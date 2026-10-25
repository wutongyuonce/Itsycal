#import <Foundation/Foundation.h>

@class EventCenter;

// Two complete Monday-based weeks, independent of the menu-bar selection.
NSDateInterval *WeekSnapshotInterval(NSDate *date);
void PublishWeekSnapshot(NSDictionary *eventsForDate, EventCenter *center, NSDateInterval *interval);
