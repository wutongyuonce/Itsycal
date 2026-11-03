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
        [center setValue:dispatch_queue_create("test.calendars", DISPATCH_QUEUE_SERIAL) forKey:@"queueIsol2"];
        CalendarInfo *info = [CalendarInfo new]; info.calendar = calendar;
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
        puts("EventCenter checks passed: snapshot interval, partial-cache range, cross-midnight and zero-duration grouping");
    }
}
