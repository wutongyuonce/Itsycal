#import <AppKit/AppKit.h>
#import "EventCenter.h"
#import "WeekSnapshot.h"

// Exercise the real grouping/cache code with an in-memory store. No permission
// prompt or personal calendar query occurs, and no widget snapshot is written.
NSDateInterval *WeekSnapshotInterval(NSDate *date) { return nil; }
void PublishWeekSnapshot(NSDictionary *events, EventCenter *center, NSDateInterval *interval) {}

@interface MemoryStore : EKEventStore
@property NSArray<EKEvent *> *fixtures;
@property NSDate *queryStart;
@property NSDate *queryEnd;
@end
@implementation MemoryStore
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
@end

@interface TestEventCenter : EventCenter @end
@implementation TestEventCenter
- (BOOL)calendarAccessGranted { return YES; }
@end

@interface EventCenter (Check)
- (void)_fetchEventsWithStartDate:(MoDate)start endDate:(MoDate)end refetch:(BOOL)refetch;
@end

int main(void) {
    @autoreleasepool {
        NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        cal.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
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
        [center setValue:dispatch_queue_create("test.calendars", DISPATCH_QUEUE_SERIAL) forKey:@"queueIsol2"];
        CalendarInfo *info = [CalendarInfo new]; info.calendar = calendar;
        [center setValue:@[info] forKey:@"sourcesAndCalendars"];
        [center _fetchEventsWithStartDate:MakeDate(2026, 9, 19) endDate:MakeDate(2026, 9, 23) refetch:NO];
        [center _fetchEventsWithStartDate:MakeDate(2026, 9, 19) endDate:MakeDate(2026, 9, 26) refetch:NO];
        NSDictionary *grouped = [center valueForKey:@"eventsForDate"];
        NSCAssert([grouped[date(20, 0)] count] == 1, @"Overnight event starts Tuesday");
        NSCAssert([grouped[date(21, 0)] count] == 2, @"Overnight ending and next event coexist Wednesday");
        NSCAssert(grouped[date(22, 0)] == nil, @"Midnight end must not occupy Thursday");
        NSCAssert([grouped[date(23, 0)] count] == 1, @"Zero-duration midnight event must be retained");
        NSCAssert([grouped[date(25, 0)] count] == 1, @"Overlapping cache query must include its final day");
        NSCAssert([grouped[date(21, 0)] count] == 2, @"Overlapping query must not duplicate rows");
        puts("EventCenter checks passed: overlap, final day, cross-midnight and zero-duration grouping");
    }
}
