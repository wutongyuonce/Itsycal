#import "WeekSnapshot.h"
#import "EventCenter.h"
#import <AppKit/AppKit.h>
#import <os/log.h>
#import "Itsycal-Swift.h"

NSDateInterval *WeekSnapshotInterval(NSDate *date, NSInteger weekStartDOW)
{
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = NSTimeZone.localTimeZone;
    NSDate *today = [calendar startOfDayForDate:date];
    weekStartDOW = MIN(MAX(weekStartDOW, 0), 6);
    NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:today] - 1;
    NSInteger offset = (weekday - weekStartDOW + 7) % 7;
    NSDate *start = [calendar dateByAddingUnit:NSCalendarUnitDay value:-offset toDate:today options:0];
    NSDate *end = [calendar dateByAddingUnit:NSCalendarUnitDay value:14 toDate:start options:0];
    return [[NSDateInterval alloc] initWithStartDate:start endDate:end];
}

void PublishWeekSnapshot(NSDictionary *eventsForDate, EventCenter *center,
                         NSDateInterval *interval, NSInteger weekStartDOW)
{
    NSString *group = [NSBundle.mainBundle objectForInfoDictionaryKey:@"WeekAppGroup"];
    NSURL *container = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
    if (!container) {
        os_log_error(OS_LOG_DEFAULT, "Week widget shared container is unavailable");
        return;
    }

    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = NSTimeZone.localTimeZone;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.calendar = calendar;
    formatter.timeZone = calendar.timeZone;
    formatter.dateFormat = @"yyyy-MM-dd";

    BOOL selected = NO;
    for (id entry in [center sourcesAndCalendars]) {
        if ([entry isKindOfClass:CalendarInfo.class] && [entry selected]) selected = YES;
    }
    NSString *status = !center.calendarAccessGranted ? @"permission" : (!selected ? @"calendars" : @"ready");
    NSMutableDictionary *days = [NSMutableDictionary new];
    if ([status isEqualToString:@"ready"]) {
        for (NSDate *date = interval.startDate; [date compare:interval.endDate] == NSOrderedAscending;
             date = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:date options:0]) {
            NSMutableArray *items = [NSMutableArray new];
            for (EventInfo *info in eventsForDate[date]) {
                EKEvent *event = info.event;
                NSColor *color = [[NSColor colorWithCGColor:event.calendar.CGColor] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                [items addObject:@{
                    @"id": [NSString stringWithFormat:@"%@/%.0f", event.eventIdentifier ?: @"", event.startDate.timeIntervalSince1970],
                    @"title": event.title.length ? event.title : @"无标题日程",
                    @"start": @(event.startDate.timeIntervalSince1970),
                    @"end": @(event.endDate.timeIntervalSince1970),
                    @"allDay": @(event.allDay),
                    @"spansDay": @(info.isAllDay),
                    @"startsHere": @([calendar isDate:date inSameDayAsDate:event.startDate]),
                    @"endsHere": @(info.isEndDate),
                    @"continues": @(info.isStartDate),
                    @"color": @[@(color ? color.redComponent : 0.3), @(color ? color.greenComponent : 0.5), @(color ? color.blueComponent : 0.8)]
                }];
            }
            days[[formatter stringFromDate:date]] = items;
        }
    }
    NSDictionary *snapshot = @{
        @"version": @2,
        @"generatedAt": @(NSDate.date.timeIntervalSince1970),
        @"timeZone": calendar.timeZone.name,
        @"start": @(interval.startDate.timeIntervalSince1970),
        @"end": @(interval.endDate.timeIntervalSince1970),
        @"status": status,
        @"weekStart": @(MIN(MAX(weekStartDOW, 0), 6)),
        @"days": days
    };
    NSError *error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&error];
    if (!data || ![data writeToURL:[container URLByAppendingPathComponent:@"week.json"] options:NSDataWritingAtomic error:&error]) {
        os_log_error(OS_LOG_DEFAULT, "Unable to publish week widget: %{public}@", error.localizedDescription);
        return;
    }
    [WeekWidgetReloader reload];
}
