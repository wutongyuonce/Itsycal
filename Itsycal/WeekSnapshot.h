#import <Foundation/Foundation.h>

@class EventCenter;

// Two complete weeks beginning at the app's configured first day, independent
// of the menu-bar selection. weekStartDOW: 0=Sunday ... 6=Saturday.
NSDateInterval *WeekSnapshotInterval(NSDate *date, NSInteger weekStartDOW);
void PublishWeekSnapshot(NSDictionary *eventsForDate, EventCenter *center,
                         NSDateInterval *interval, NSInteger weekStartDOW);
