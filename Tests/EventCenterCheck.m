#import <AppKit/AppKit.h>
#import "EventCenter.h"
#import "WeekSnapshot.h"
#import "Itsycal-Swift.h"

// Exercise the real grouping and week-interval code with an in-memory store.
// No permission prompt or personal calendar query occurs, and no snapshot is written.
@implementation WidgetReloader
+ (void)reload {}
@end

@interface MemoryStore : EKEventStore
@property NSArray<EKEvent *> *fixtures;
@property NSDate *queryStart;
@property NSDate *queryEnd;
@property NSMutableDictionary<NSString *, EKEvent *> *savedEvents;
@property NSMutableDictionary<NSString *, EKReminder *> *savedReminders;
@property NSMutableDictionary<NSString *, EKCalendar *> *calendarsByID;
@property NSInteger commitCount;
@property BOOL failOnCommit;
@property BOOL didReset;
@end
@implementation MemoryStore
- (instancetype)init {
    self = [super init];
    if (self) {
        _savedEvents = [NSMutableDictionary new];
        _savedReminders = [NSMutableDictionary new];
        _calendarsByID = [NSMutableDictionary new];
    }
    return self;
}
- (NSPredicate *)predicateForEventsWithStartDate:(NSDate *)start endDate:(NSDate *)end calendars:(NSArray *)calendars {
    self.queryStart = start;
    self.queryEnd = end;
    return [NSPredicate predicateWithValue:YES];
}
- (NSArray<EKEvent *> *)eventsMatchingPredicate:(NSPredicate *)predicate {
    NSMutableArray *result = [NSMutableArray new];
    for (EKEvent *event in self.fixtures) {
        if ([event.startDate compare:self.queryEnd] == NSOrderedAscending &&
            [event.endDate compare:self.queryStart] != NSOrderedAscending) [result addObject:event];
    }
    return result;
}
- (EKCalendar *)calendarWithIdentifier:(NSString *)identifier {
    return self.calendarsByID[identifier];
}
- (EKEvent *)eventWithIdentifier:(NSString *)identifier {
    return self.savedEvents[identifier];
}
- (EKCalendarItem *)calendarItemWithIdentifier:(NSString *)identifier {
    return self.savedReminders[identifier] ?: self.savedEvents[identifier];
}
- (BOOL)saveEvent:(EKEvent *)event span:(EKSpan)span commit:(BOOL)commit error:(NSError **)error {
    NSString *key = event.eventIdentifier ?: event.calendarItemIdentifier;
    self.savedEvents[key] = event;
    if (commit) return [self commit:error];
    return YES;
}
- (BOOL)removeEvent:(EKEvent *)event span:(EKSpan)span commit:(BOOL)commit error:(NSError **)error {
    NSString *key = event.eventIdentifier ?: event.calendarItemIdentifier;
    if (key) [self.savedEvents removeObjectForKey:key];
    if (commit) return [self commit:error];
    return YES;
}
- (BOOL)saveReminder:(EKReminder *)reminder commit:(BOOL)commit error:(NSError **)error {
    self.savedReminders[reminder.calendarItemIdentifier] = reminder;
    if (commit) return [self commit:error];
    return YES;
}
- (BOOL)removeReminder:(EKReminder *)reminder commit:(BOOL)commit error:(NSError **)error {
    if (reminder.calendarItemIdentifier) [self.savedReminders removeObjectForKey:reminder.calendarItemIdentifier];
    if (commit) return [self commit:error];
    return YES;
}
- (BOOL)commit:(NSError **)error {
    if (self.failOnCommit) {
        if (error) *error = [NSError errorWithDomain:@"TestError" code:1 userInfo:nil];
        return NO;
    }
    self.commitCount += 1;
    return YES;
}
- (void)reset {
    self.didReset = YES;
    [self.savedEvents removeAllObjects];
    [self.savedReminders removeAllObjects];
}
@end

@interface TestEventCenter : EventCenter @end
@implementation TestEventCenter
- (BOOL)calendarAccessGranted { return YES; }
@end

@interface EventCenter (Check)
- (BOOL)_fetchEventsWithStartDate:(MoDate)start endDate:(MoDate)end refetch:(BOOL)refetch;
@end

int main(void) {
    @autoreleasepool {
        NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        cal.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        // October 2026 starts on a Thursday; November ends on a Monday.
        NSDate *thursday = [cal dateWithEra:1 year:2026 month:10 day:22 hour:12 minute:0 second:0 nanosecond:0];
        NSDate *(^dayStart)(NSInteger, NSInteger) = ^NSDate *(NSInteger month, NSInteger day) {
            return [cal dateWithEra:1 year:2026 month:month day:day hour:0 minute:0 second:0 nanosecond:0];
        };
        NSDateInterval *wednesday = WeekSnapshotInterval(thursday, 3);
        NSCAssert([wednesday.startDate isEqualToDate:dayStart(9, 30)], @"Grid starts on the Wednesday on or before Oct 1");
        NSCAssert([wednesday.endDate isEqualToDate:dayStart(12, 2)], @"Grid ends after the week containing Nov 30");
        NSDateInterval *sunday = WeekSnapshotInterval(thursday, 0);
        NSCAssert([sunday.startDate isEqualToDate:dayStart(9, 27)], @"Sunday start must follow the app preference");
        NSCAssert([sunday.endDate isEqualToDate:dayStart(12, 6)], @"Sunday grid ends after the week containing Nov 30");

        NSDate *(^date)(NSInteger, NSInteger) = ^NSDate *(NSInteger day, NSInteger hour) {
            return [cal dateWithEra:1 year:2026 month:10 day:day hour:hour minute:0 second:0 nanosecond:0];
        };
        MemoryStore *store = [MemoryStore new];
        EKCalendar *calendar = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:store];
        EKEvent *(^event)(NSString *, NSDate *, NSDate *) = ^EKEvent *(NSString *title, NSDate *start, NSDate *end) {
            EKEvent *e = [EKEvent eventWithEventStore:store];
            e.calendar = calendar; e.title = title; e.startDate = start; e.endDate = end;
            return e;
        };
        EKEvent *overnight = event(@"Overnight", date(20, 22), date(21, 2));
        EKEvent *midnight = event(@"Midnight end", date(21, 22), date(22, 0));
        EKEvent *point = event(@"Point at midnight", date(23, 0), date(23, 0));
        EKEvent *last = event(@"Last uncovered day", date(25, 15), date(25, 16));
        store.fixtures = @[overnight, midnight, point, last];

        EventCenter *center = [TestEventCenter new]; // Deliberately bypass access-request initializer.
        [center setValue:store forKey:@"store"];
        [center setValue:cal forKey:@"cal"];
        [center setValue:[NSMutableDictionary new] forKey:@"eventsForDate"];
        [center setValue:[NSMutableIndexSet new] forKey:@"previouslyFetchedDates"];
        [center setValue:dispatch_queue_create("test.work", DISPATCH_QUEUE_SERIAL) forKey:@"queueWork"];
        [center setValue:dispatch_queue_create("test.isol", DISPATCH_QUEUE_SERIAL) forKey:@"queueIsol"];
        [center setValue:dispatch_queue_create("test.calendars", DISPATCH_QUEUE_SERIAL) forKey:@"queueIsol2"];
        CalendarInfo *info = [CalendarInfo new]; info.calendar = calendar;
        store.calendarsByID[calendar.calendarIdentifier] = calendar;
        [center setValue:@[info] forKey:@"sourcesAndCalendars"];
        // Cache the tail first, then request a range whose head is missing:
        // the last missing day (21st) must still be queried.
        [center _fetchEventsWithStartDate:MakeDate(2026, 9, 22) endDate:MakeDate(2026, 9, 30) refetch:NO];
        [center _fetchEventsWithStartDate:MakeDate(2026, 9, 19) endDate:MakeDate(2026, 9, 26) refetch:NO];
        NSCAssert(![center _fetchEventsWithStartDate:MakeDate(2026, 9, 20) endDate:MakeDate(2026, 9, 26) refetch:NO],
                  @"A fully cached range must not query or republish");
        NSDictionary *grouped = [center valueForKey:@"eventsForDate"];
        NSCAssert([grouped[date(20, 0)] count] == 1, @"Overnight event starts Tuesday");
        NSCAssert([grouped[date(21, 0)] count] == 2, @"Last missing day before a cached range must be fetched");
        NSCAssert(grouped[date(22, 0)] == nil, @"Midnight end must not occupy Thursday");
        NSCAssert([grouped[date(23, 0)] count] == 1, @"Zero-duration midnight event must be retained");
        NSCAssert([grouped[date(25, 0)] count] == 1, @"Re-queried cached days are replaced, not duplicated");

        // Batch save events + reminders with atomic commit and single Undo/Redo.
        NSUndoManager *undoManager = [NSUndoManager new];
        undoManager.groupsByEvent = NO;
        EKEvent *batchEvent1 = event(@"AI Review 1", date(26, 14), date(26, 15));
        EKEvent *batchEvent2 = event(@"AI Review 2", date(27, 14), date(27, 15));
        EKReminder *batchReminder = [center newReminder];
        batchReminder.calendar = calendar;
        batchReminder.title = @"Prepare slides";
        NSDateComponents *dueComp = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:date(26, 10)];
        dueComp.calendar = cal;
        batchReminder.dueDateComponents = dueComp;

        [undoManager beginUndoGrouping];
        NSError *saveError = nil;
        BOOL saved = [center applyBatchChangesWithAddedEvents:@[batchEvent1, batchEvent2]
                                               addedReminders:@[batchReminder]
                                                deletedEvents:@[]
                                            deletedEventSpans:@[]
                                             deletedReminders:@[]
                                                  undoManager:undoManager
                                                        error:&saveError];
        [undoManager endUndoGrouping];
        NSCAssert(saved && saveError == nil, @"Batch save must succeed");
        NSCAssert(store.commitCount == 1, @"Batch save must commit once atomically");
        NSCAssert(store.savedEvents.count == 2 && store.savedReminders.count == 1, @"All batch items must be stored");

        [undoManager undo];
        NSCAssert(store.savedEvents.count == 0 && store.savedReminders.count == 0, @"Single undo must remove all batch events and reminders");
        NSCAssert(store.commitCount == 2, @"Batch undo must commit once atomically");

        [undoManager redo];
        NSCAssert(store.savedEvents.count == 2 && store.savedReminders.count == 1, @"Single redo must recreate all batch events and reminders");
        NSCAssert(store.commitCount == 3, @"Batch redo must commit once atomically");

        // Batch delete + undo/redo restoration.
        EKEvent *existingToDelete = store.savedEvents.allValues.firstObject;
        EKReminder *existingRemToDelete = store.savedReminders.allValues.firstObject;
        [undoManager beginUndoGrouping];
        BOOL deleted = [center applyBatchChangesWithAddedEvents:@[]
                                                 addedReminders:@[]
                                                  deletedEvents:@[existingToDelete]
                                              deletedEventSpans:@[@(EKSpanThisEvent)]
                                               deletedReminders:@[existingRemToDelete]
                                                    undoManager:undoManager
                                                          error:&saveError];
        [undoManager endUndoGrouping];
        NSCAssert(deleted && store.savedEvents.count == 1 && store.savedReminders.count == 0, @"Batch delete must remove target event and reminder");

        [undoManager undo];
        NSCAssert(store.savedEvents.count == 2 && store.savedReminders.count == 1, @"Undo of batch delete must restore deleted event and reminder");

        [undoManager redo];
        NSCAssert(store.savedEvents.count == 1 && store.savedReminders.count == 0, @"Redo of batch delete must delete restored items again");

        // Edit existing event + undo/redo restoration.
        EKEvent *editableEvent = store.savedEvents.allValues.firstObject;
        NSString *originalTitle = editableEvent.title;
        [undoManager beginUndoGrouping];
        BOOL updated = [center updateItem:editableEvent span:EKSpanThisEvent changes:^(EKCalendarItem *target) {
            target.title = @"Updated Title";
        } undoManager:undoManager error:&saveError];
        [undoManager endUndoGrouping];
        NSCAssert(updated && [editableEvent.title isEqualToString:@"Updated Title"], @"updateItem must modify event title");

        [undoManager undo];
        NSCAssert([editableEvent.title isEqualToString:originalTitle], @"Undo of updateItem must restore previous title");

        [undoManager redo];
        NSCAssert([editableEvent.title isEqualToString:@"Updated Title"], @"Redo of updateItem must reapply updated title");

        // No-op edit (unchanged fields) must not commit or register an undo action.
        NSUndoManager *noopUndoManager = [NSUndoManager new];
        NSInteger commitsBeforeNoop = store.commitCount;
        BOOL noopUpdated = [center updateItem:editableEvent span:EKSpanThisEvent changes:^(EKCalendarItem *target) {
            target.title = @"Updated Title";
        } undoManager:noopUndoManager error:&saveError];
        NSCAssert(noopUpdated && store.commitCount == commitsBeforeNoop && !noopUndoManager.canUndo,
                  @"No-op updateItem must not commit or push an undo entry");

        // Failed commit rolls back via store reset.
        store.failOnCommit = YES;
        store.didReset = NO;
        EKEvent *failEvent = event(@"Should Rollback", date(28, 9), date(28, 10));
        BOOL failedSave = [center applyBatchChangesWithAddedEvents:@[failEvent]
                                                    addedReminders:@[]
                                                     deletedEvents:@[]
                                                 deletedEventSpans:@[]
                                                  deletedReminders:@[]
                                                       undoManager:undoManager
                                                             error:&saveError];
        NSCAssert(!failedSave && store.didReset, @"Failed batch commit must reset uncommitted changes");

        puts("EventCenter checks passed: snapshot interval, partial-cache range, cross-midnight, zero-duration, and batch save/undo/redo");
    }
}
