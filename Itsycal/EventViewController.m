//
//  EventViewController.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/25/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "EventViewController.h"
#import "EventCenter.h"
#import "MoThemeView.h"
#import "MoVFLHelper.h"

@interface HackyTextView : NSTextView
// The placeholderAttributedString property in NSTextView
// isn't exposed publicly.
// https://stackoverflow.com/a/47223845/111418
@property NSAttributedString *placeholderAttributedString;
@end

@implementation HackyTextView
- (BOOL)becomeFirstResponder
{
    // Empty NSTextView gets focus but no cursor is visible
    // https://stackoverflow.com/a/39167917
    // https://stackoverflow.com/a/77020301/111418
    BOOL result = [super becomeFirstResponder];
    if (result) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.string.length) {
                self.string = @" ";
                self.string = @"";
            }
        });
    }
    return result;
}
@end

// These values map to _alertAllDayStrings and _alertRegularStrings.
enum {
    kAlertAllDayNumOffsets = 5,
    kAlertRegularNumOffsets = 10
};
const NSTimeInterval kAlertAllDayRelativeOffsets[kAlertAllDayNumOffsets] = {
    MAXFLOAT, // None
    32400,    // On day of event (9 AM)
    -54000,   // 1 day before (9 AM)
    -140400,  // 2 days before (9 AM)
    -572400   // 1 week before
};
const NSTimeInterval kAlertRegularRelativeOffsets[kAlertRegularNumOffsets] = {
    MAXFLOAT, // None
    0,        // At time of event
    -300,     // 5 minutes before
    -600,     // 10 minutes before
    -900,     // 15 minutes before
    -1800,    // 30 minutes before
    -3600,    // 1 hour before
    -7200,    // 2 hours before
    -86400,   // 1 day before
    -172800   // 2 days before
};
// Toggling All-day converts alerts like Calendar.app (0 == no alert).
const NSInteger kAlertAllDayIndexForRegular[kAlertRegularNumOffsets] = {0, 1, 1, 1, 1, 1, 1, 1, 2, 3};
const NSInteger kAlertRegularIndexForAllDay[kAlertAllDayNumOffsets] = {0, 1, 8, 9, 0};
// Itsycal adds at most this many alerts to an event.
const NSUInteger kAlertMaxCount = 3;

static const NSInteger kCustomRepeatTag = -1;

@implementation EventViewController
{
    NSSegmentedControl *_kindControl;
    NSTextField *_title, *_location, *_url, *_startsLabel, *_endsLabel, *_repEndLabel;
    NSButton *_allDayCheckbox, *_saveButton;
    NSDatePicker *_startDate, *_endDate, *_repEndDate;
    NSPopUpButton *_repPopup, *_repEndPopup, *_alertPopup, *_calPopup;
    NSArray<NSString *> *_alertAllDayStrings, *_alertRegularStrings;
    NSMutableArray<NSTextField *> *_alertLabels;
    NSMutableArray<NSPopUpButton *> *_alertPopups;
    NSButton *_addAlertButton;
    NSLayoutConstraint *_addAlertButtonTopConstraint;
    NSInteger _defaultAlertIndex;
    BOOL _defaultAlertKept;
    BOOL _recurrenceModified;
    BOOL _alarmsModified;
    NSTimeInterval _durationSeconds;
    HackyTextView *_notes;
    NSScrollView *_notesScrollView;
    NSLayoutConstraint *_notesScrollViewHeightConstraint;
    CGFloat _notesHeightOfOneLine;
}

- (void)loadView
{
    // View controller content view
    NSView *v = [NSView new];

    // Kind segmented control (Event vs Reminder, shown when creating a new item)
    _kindControl = [NSSegmentedControl segmentedControlWithLabels:@[
        NSLocalizedString(@"Event", @""),
        NSLocalizedString(@"Reminder", @"")
    ] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(kindChanged:)];
    _kindControl.selectedSegment = 0;
    _kindControl.segmentDistribution = NSSegmentDistributionFillEqually;
    [v addSubview:_kindControl];

    // TextField maker
    NSTextField* (^txt)(NSString*, BOOL) = ^NSTextField* (NSString *stringValue, BOOL isEditable) {
        NSTextField *txt;
        if (isEditable) {
            txt = [NSTextField textFieldWithString:@""];
            txt.placeholderString = stringValue;
            txt.bezeled = NO;
            txt.focusRingType = NSFocusRingTypeNone;
            txt.drawsBackground = NO;
        }
        else {
            txt = [NSTextField labelWithString:stringValue];
            txt.alignment = NSTextAlignmentRight;
        }
        [v addSubview:txt];
        return txt;
    };

    // DatePicker maker
    NSDatePicker* (^picker)(void) = ^NSDatePicker* () {
        NSDatePicker *picker = [NSDatePicker new];
        picker.datePickerStyle = NSDatePickerStyleTextField;
        picker.locale = NSLocale.currentLocale;
        picker.bezeled  = NO;
        picker.bordered = NO;
        picker.drawsBackground = NO;
        picker.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
        [v addSubview:picker];
        return picker;
    };

    // PopUpButton maker
    NSPopUpButton* (^popup)(SEL) = ^NSPopUpButton* (SEL action) {
        NSPopUpButton *pop = [NSPopUpButton new];
        pop.target = self;
        pop.action = action;
        pop.menu.autoenablesItems = NO;
        [v addSubview:pop];
        return pop;
    };

    // Button maker
    NSButton* (^btn)(NSString*, id, SEL) = ^NSButton* (NSString *title, id target, SEL action) {
        NSButton *btn = [NSButton buttonWithTitle:title target:target action:action];
        [v addSubview:btn];
        return btn;
    };

    // Title, location, and URL text fields
    _title = txt(NSLocalizedString(@"New Event", @""), YES);
    _title.delegate = self;
    _title.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
    _location = txt(NSLocalizedString(@"Add Location or Video Call", @""), YES);
    _url = txt(NSLocalizedString(@"Add URL", @""), YES);

    // All-day checkbox
    _allDayCheckbox = [NSButton new];
    _allDayCheckbox.title = @"";
    _allDayCheckbox.target = self;
    _allDayCheckbox.action = @selector(allDayClicked:);
    [_allDayCheckbox setButtonType:NSButtonTypeSwitch];
    [v addSubview:_allDayCheckbox];

    // Static labels
    NSTextField *allDayLabel = txt(NSLocalizedString(@"All-day:", @""), NO);
    _startsLabel             = txt(NSLocalizedString(@"Starts:", @""), NO);
    _endsLabel               = txt(NSLocalizedString(@"Ends:", @""), NO);
    NSTextField *repLabel    = txt(NSLocalizedString(@"Repeat:", @""), NO);
                _repEndLabel = txt(NSLocalizedString(@"End Repeat:", @""), NO);
    NSTextField *alertLabel  = txt(NSLocalizedString(@"Alert:", @""), NO);

    // Date pickers
    _startDate = picker();
    _startDate.target = self;
    _startDate.action = @selector(startDateChanged:);
    _endDate = picker();
    _endDate.target = self;
    _endDate.action = @selector(endDateChanged:);
    _repEndDate = picker();
    _repEndDate.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    _repEndDate.target = self;
    _repEndDate.action = @selector(repEndDateChanged:);

    // Popups
    _repPopup = popup(@selector(repPopupChanged:));
    [self resetRepPopupItemsWithCustom:NO];

    _repEndPopup = popup(@selector(repEndPopupChanged:));
    [_repEndPopup addItemsWithTitles:@[NSLocalizedString(@"Never", @"Repeat ends never"),
                                       NSLocalizedString(@"On Date", @"")]];

    _alertPopup = popup(@selector(alertPopupChanged:));
    _alertAllDayStrings = @[
        NSLocalizedString(@"None", @"Alert none"),
        NSLocalizedString(@"On day of event (9 AM)", @""),
        NSLocalizedString(@"1 day before (9 AM)", @""),
        NSLocalizedString(@"2 days before (9 AM)", @""),
        NSLocalizedString(@"1 week before", @"")];
    _alertRegularStrings = @[
        NSLocalizedString(@"None", @"Alert none"),
        NSLocalizedString(@"At time of event", @""),
        NSLocalizedString(@"5 minutes before", @""),
        NSLocalizedString(@"10 minutes before", @""),
        NSLocalizedString(@"15 minutes before", @""),
        NSLocalizedString(@"30 minutes before", @""),
        NSLocalizedString(@"1 hour before", @""),
        NSLocalizedString(@"2 hours before", @""),
        NSLocalizedString(@"1 day before", @""),
        NSLocalizedString(@"2 days before", @"")];
    // Populate the alert with all possible values so Autolayout can
    // calculate the maximum width of the button.
    [_alertPopup addItemsWithTitles:_alertAllDayStrings];
    [_alertPopup addItemsWithTitles:_alertRegularStrings];
    _alertLabels = [NSMutableArray arrayWithObject:alertLabel];
    _alertPopups = [NSMutableArray arrayWithObject:_alertPopup];
    NSImage *plus = [[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:nil] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular]];
    NSImage *plusImage = [NSImage imageWithSize:plus.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [plus drawInRect:dstRect];
        return YES;
    }];
    plusImage.template = YES;
    plusImage.accessibilityDescription = plus.accessibilityDescription;
    _addAlertButton = [NSButton buttonWithImage:plusImage target:self action:@selector(addAlertClicked:)];
    [v addSubview:_addAlertButton];

    // Notes (NSTextView embedded in NSScrollView)
    _notesScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 44)];
    _notesScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _notesScrollView.focusRingType = NSFocusRingTypeExterior;
    _notesScrollView.borderType = NSNoBorder;
    _notesScrollView.verticalScrollElasticity = NSScrollElasticityNone;
    _notesScrollView.drawsBackground = NO;
    _notesScrollView.hasVerticalScroller = NO; // see -textDidChange:
    [v addSubview:_notesScrollView];

    NSSize noteContentSize = _notesScrollView.contentSize;
    _notes = [[HackyTextView alloc] initWithFrame:NSMakeRect(0, 0, noteContentSize.width, noteContentSize.height)];
    _notes.delegate = self;
    _notes.font = _location.font; // _title.font is too big
    _notes.placeholderAttributedString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Add Notes", @"") attributes:@{NSFontAttributeName: _notes.font, NSForegroundColorAttributeName: NSColor.disabledControlTextColor}];
    _notes.allowsUndo = YES;
    _notes.drawsBackground = NO;
    _notes.richText = NO;
    _notes.focusRingType = NSFocusRingTypeNone;
    _notes.minSize = NSMakeSize(0, noteContentSize.height);
    _notes.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _notes.verticallyResizable = YES;
    _notes.horizontallyResizable = NO;
    _notes.autoresizingMask = NSViewWidthSizable;
    _notes.textContainer.widthTracksTextView = YES;
    [_notes.textContainer setLineFragmentPadding:0];
    [_notes.textContainer setContainerSize:NSMakeSize(noteContentSize.width, FLT_MAX)];

    _notesScrollView.documentView = _notes;

    _calPopup = popup(@selector(calPopupChanged:));
    _calPopup.imagePosition = NSImageOnly;

    NSMenuItem *calItem = [NSMenuItem new];
    calItem.image = [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect dstRect) { return YES; }];
    calItem.preferredImageVisibility = NSMenuItemImageVisibilityVisible;
    [_calPopup.menu addItem:calItem];

    // Save and Cancel buttons
    _saveButton = btn(NSLocalizedString(@"Save Event", @""), self, @selector(saveEvent:));
    _saveButton.enabled = NO;
    NSButton *cancelButton = btn(NSLocalizedString(@"Cancel", @""), self, @selector(cancelOperation:));

    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:nil views:NSDictionaryOfVariableBindings(_kindControl, _title, _calPopup, _location, _allDayCheckbox, allDayLabel, _startsLabel, _endsLabel, _startDate, _endDate, repLabel, alertLabel, _repPopup, _repEndLabel, _repEndPopup, _repEndDate, _alertPopup, _addAlertButton, _notesScrollView, _url, cancelButton, _saveButton)];

    [vfl :@"V:|-[_kindControl]-10-[_title]-[_location]-15-[_allDayCheckbox]"];
    [vfl :@"V:[_allDayCheckbox]-[_startDate]-[_endDate]-[_repPopup]-[_repEndPopup]-[_alertPopup]" :NSLayoutFormatAlignAllLeading];
    [vfl :@"V:[_addAlertButton(==_alertPopup)]-20-[_notesScrollView]-10-[_url]-15-[_saveButton]-|"];
    [vfl :@"H:|-[_kindControl]-|"];
    [vfl :@"H:|-[_title]-[_calPopup]-|" :NSLayoutFormatAlignAllCenterY];
    [vfl :@"H:|-[_location]-|"];
    [vfl :@"H:|-[allDayLabel]-[_allDayCheckbox]-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-[_startsLabel]-[_startDate]-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-[_endsLabel]-[_endDate]-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-[repLabel]-[_repPopup]" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-[_repEndLabel]-[_repEndPopup]-[_repEndDate]-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-[alertLabel]-[_alertPopup]" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:[_alertPopup]-[_addAlertButton]-|"];
    [vfl :@"H:|-[_notesScrollView(>=200)]-|"];
    [vfl :@"H:|-[_url]-|"];
    [vfl :@"H:[cancelButton]-[_saveButton]-|" :NSLayoutFormatAlignAllCenterY];
    [_addAlertButton.widthAnchor constraintEqualToAnchor:_addAlertButton.heightAnchor].active = YES;
    [_repPopup.trailingAnchor constraintEqualToAnchor:_alertPopup.trailingAnchor].active = YES;
    [self updateAddAlertButton];

    // Get height of one line in _notes
    [_notes.layoutManager ensureLayoutForTextContainer:_notes.textContainer];
    _notesHeightOfOneLine = [_notes.layoutManager usedRectForTextContainer:_notes.textContainer].size.height;

    _notesScrollViewHeightConstraint = [_notesScrollView.heightAnchor constraintEqualToConstant:_notesHeightOfOneLine];
    _notesScrollViewHeightConstraint.active = YES;

    [_allDayCheckbox setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationVertical];
    [_startDate setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_endDate   setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    v.translatesAutoresizingMaskIntoConstraints = NO;
    MoThemeView *view = [MoThemeView new];
    [view addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor],
        [v.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor],
        [v.leftAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.leftAnchor],
        [v.rightAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.rightAnchor],
    ]];
    self.view = view;
}

- (BOOL)isReminderMode
{
    if (self.editingItem) return self.editingItem.reminder != nil;
    return _kindControl.selectedSegment == 1;
}

- (void)resetRepPopupItemsWithCustom:(BOOL)includeCustom
{
    [_repPopup removeAllItems];
    NSArray<NSString *> *titles = @[
        NSLocalizedString(@"None", @"Repeat none"),
        NSLocalizedString(@"Every Day", @""),
        NSLocalizedString(@"Every Week", @""),
        [NSString stringWithFormat:NSLocalizedString(@"Every %zd Weeks", nil), (NSInteger)2],
        NSLocalizedString(@"Every Month", @""),
        NSLocalizedString(@"Every Year", @"")
    ];
    for (NSInteger i = 0; i < titles.count; i++) {
        [_repPopup addItemWithTitle:titles[i]];
        [_repPopup itemAtIndex:i].tag = i;
    }
    if (includeCustom) {
        [_repPopup addItemWithTitle:NSLocalizedString(@"Custom", @"")];
        _repPopup.lastItem.tag = kCustomRepeatTag;
    }
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    self.view.window.defaultButtonCell = _saveButton.cell;
    self.view.window.autorecalculatesKeyViewLoop = YES;

    _recurrenceModified = NO;
    _alarmsModified = NO;
    _kindControl.hidden = (self.editingItem != nil);
    if (!self.editingItem) {
        _kindControl.selectedSegment = 0;
    }

    if (self.editingItem) {
        [self populateFormForEditingItem:self.editingItem];
    } else {
        [self populateFormForNewItem];
    }
    [self updateModeVisibility];
}

- (void)updateModeVisibility
{
    BOOL reminder = [self isReminderMode];
    _location.hidden = reminder;
    _endsLabel.hidden = reminder;
    _endDate.hidden = reminder;
    _startsLabel.stringValue = reminder ? NSLocalizedString(@"Due:", @"") : NSLocalizedString(@"Starts:", @"");
    _title.placeholderString = reminder ? NSLocalizedString(@"New Reminder", @"") : NSLocalizedString(@"New Event", @"");
    if (self.editingItem) {
        _saveButton.title = NSLocalizedString(@"Save", @"");
    } else {
        _saveButton.title = reminder ? NSLocalizedString(@"Save Reminder", @"") : NSLocalizedString(@"Save Event", @"");
    }
}

- (void)kindChanged:(NSSegmentedControl *)sender
{
    if (sender.selectedSegment == 1 && self.ec.remindersAuthorizationStatus != EKAuthorizationStatusFullAccess) {
        __weak typeof(self) weakSelf = self;
        [self.ec requestRemindersAccessWithCompletion:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (strongSelf.ec.remindersAuthorizationStatus != EKAuthorizationStatusFullAccess || ![strongSelf populateCalendarPopupForEntityMask:EKEntityMaskReminder selectedCalendarID:nil]) {
                strongSelf->_kindControl.selectedSegment = 0;
                [strongSelf populateCalendarPopupForEntityMask:EKEntityMaskEvent selectedCalendarID:nil];
                [strongSelf updateModeVisibility];
                return;
            }
            [strongSelf updateModeVisibility];
            [strongSelf populateAlertPopup];
        }];
        return;
    }
    EKEntityMask mask = [self isReminderMode] ? EKEntityMaskReminder : EKEntityMaskEvent;
    if (![self populateCalendarPopupForEntityMask:mask selectedCalendarID:nil] && [self isReminderMode]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = NSLocalizedString(@"No modifiable reminder list found. Enable Reminders in Settings › Events.", @"");
        [alert runModal];
        _kindControl.selectedSegment = 0;
        [self populateCalendarPopupForEntityMask:EKEntityMaskEvent selectedCalendarID:nil];
    }
    [self updateModeVisibility];
    [self populateAlertPopup];
}

- (void)populateFormForNewItem
{
    NSDate *initialStart, *initialEnd, *today = [NSDate new];
    if ([self.cal isDate:self.calSelectedDate inSameDayAsDate:today]) {
        NSInteger hour;
        [self.cal getHour:&hour minute:NULL second:NULL nanosecond:NULL fromDate:today];
        hour = (hour == 23) ? 0 : hour + 1;
        initialStart = [self.cal nextDateAfterDate:today matchingUnit:NSCalendarUnitHour value:hour options:NSCalendarMatchNextTimePreservingSmallerUnits];
    }
    else {
        initialStart = [self.cal dateBySettingHour:8 minute:0 second:0 ofDate:self.calSelectedDate options:0];
    }
    NSInteger newEventDuration = [self defaultDurationInMinutesForNewEvent];
    _durationSeconds = newEventDuration * 60.0;
    initialEnd = [self.cal dateByAddingUnit:NSCalendarUnitMinute
                                      value:newEventDuration
                                     toDate:initialStart
                                    options:0];

    _title.stringValue = @"";
    _location.stringValue = @"";
    _url.stringValue = @"";
    _notes.string = @"";
    [self textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:_notes]];
    _allDayCheckbox.state = NSControlStateValueOff;
    _startDate.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
    _endDate.datePickerElements   = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
    _startDate.dateValue = initialStart;
    _endDate.minDate     = initialStart;
    _endDate.dateValue   = initialEnd;
    _repEndLabel.hidden  = YES;
    _repEndPopup.hidden  = YES;
    _repEndDate.hidden   = YES;
    _repEndDate.minDate  = initialStart;
    _repEndDate.dateValue = initialEnd;
    [self resetRepPopupItemsWithCustom:NO];
    [_repPopup selectItemAtIndex:0];
    [_repEndPopup selectItemAtIndex:0];
    [_alertPopup selectItemAtIndex:0];
    _defaultAlertKept = YES;
    _saveButton.enabled = NO;

    [self populateCalendarPopupForEntityMask:EKEntityMaskEvent selectedCalendarID:[self.ec defaultCalendarIdentifier]];
    [self populateAlertPopup];
}

- (void)populateFormForEditingItem:(EventInfo *)info
{
    EKCalendarItem *item = info.item;
    BOOL isAllDay = info.isRealAllDay;
    NSDate *start = info.startDate ?: [NSDate new];
    NSDate *end = info.endDate ?: start;
    if ([end compare:start] == NSOrderedAscending) end = start;
    _durationSeconds = [end timeIntervalSinceDate:start];

    _title.stringValue = item.title ?: @"";
    _location.stringValue = info.location ?: @"";
    _url.stringValue = item.URL.absoluteString ?: @"";
    _notes.string = item.notes ?: @"";
    [self textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:_notes]];

    _allDayCheckbox.state = isAllDay ? NSControlStateValueOn : NSControlStateValueOff;
    NSDatePickerElementFlags flags = isAllDay
        ? NSDatePickerElementFlagYearMonthDay
        : (NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute);
    _startDate.datePickerElements = flags;
    _endDate.datePickerElements   = flags;
    _startDate.dateValue = start;
    _endDate.minDate     = start;
    _endDate.dateValue   = end;
    _repEndDate.minDate  = start;
    _repEndDate.dateValue = end;

    EKEntityMask mask = info.reminder ? EKEntityMaskReminder : EKEntityMaskEvent;
    [self populateCalendarPopupForEntityMask:mask selectedCalendarID:item.calendar.calendarIdentifier];

    // Recurrence
    EKRecurrenceRule *rule = item.recurrenceRules.firstObject;
    NSInteger repTag = [self repeatTagForRule:rule];
    [self resetRepPopupItemsWithCustom:(repTag == kCustomRepeatTag)];
    [_repPopup selectItemWithTag:repTag];
    if (repTag == 0 || repTag == kCustomRepeatTag) {
        [_repEndPopup selectItemAtIndex:0];
        _repEndLabel.hidden = YES;
        _repEndPopup.hidden = YES;
        _repEndDate.hidden  = YES;
    } else {
        _repEndLabel.hidden = NO;
        _repEndPopup.hidden = NO;
        if (rule.recurrenceEnd.endDate != nil) {
            [_repEndPopup selectItemAtIndex:1];
            _repEndDate.dateValue = rule.recurrenceEnd.endDate;
            _repEndDate.hidden = NO;
        } else {
            [_repEndPopup selectItemAtIndex:0];
            _repEndDate.hidden = YES;
        }
    }

    // Alerts
    [self populateAlertPopup];
    _defaultAlertIndex = 0;
    _defaultAlertKept = NO;
    NSMutableArray<NSNumber *> *matchedIndexes = [NSMutableArray new];
    NSInteger numOffsets = isAllDay ? kAlertAllDayNumOffsets : kAlertRegularNumOffsets;
    const NSTimeInterval *offsets = isAllDay ? kAlertAllDayRelativeOffsets : kAlertRegularRelativeOffsets;
    for (EKAlarm *alarm in item.alarms) {
        NSTimeInterval offset = alarm.relativeOffset;
        if (alarm.absoluteDate != nil) {
            offset = [alarm.absoluteDate timeIntervalSinceDate:start];
        }
        for (NSInteger i = 1; i < numOffsets; i++) {
            if (fabs(offset - offsets[i]) < 1.0 && ![matchedIndexes containsObject:@(i)]) {
                [matchedIndexes addObject:@(i)];
                break;
            }
        }
    }
    [self showAlertIndexes:matchedIndexes.count > 0 ? matchedIndexes : @[@0]];
    _alarmsModified = NO;

    NSString *trimmedTitle = [_title.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _saveButton.enabled = trimmedTitle.length > 0;
}

- (NSInteger)repeatTagForRule:(EKRecurrenceRule *)rule
{
    if (rule == nil) return 0;
    if (rule.daysOfTheWeek.count > 1 ||
        rule.daysOfTheMonth.count > 0 ||
        rule.monthsOfTheYear.count > 0 ||
        rule.weeksOfTheYear.count > 0 ||
        rule.daysOfTheYear.count > 0 ||
        rule.setPositions.count > 0 ||
        rule.recurrenceEnd.occurrenceCount > 0) {
        return kCustomRepeatTag;
    }
    if (rule.frequency == EKRecurrenceFrequencyDaily && rule.interval == 1) return 1;
    if (rule.frequency == EKRecurrenceFrequencyWeekly && rule.interval == 1) return 2;
    if (rule.frequency == EKRecurrenceFrequencyWeekly && rule.interval == 2) return 3;
    if (rule.frequency == EKRecurrenceFrequencyMonthly && rule.interval == 1) return 4;
    if (rule.frequency == EKRecurrenceFrequencyYearly && rule.interval == 1) return 5;
    return kCustomRepeatTag;
}

- (BOOL)populateCalendarPopupForEntityMask:(EKEntityMask)entityMask selectedCalendarID:(NSString *)selectedID
{
    if (selectedID == nil) {
        selectedID = (entityMask == EKEntityMaskReminder)
            ? [self.ec defaultReminderCalendarIdentifier]
            : [self.ec defaultCalendarIdentifier];
    }
    NSImage* (^coloredDot)(NSColor *) = ^NSImage* (NSColor *color) {
        return [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
            [color set];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, 8, 8)] fill];
            return YES;
        }];
    };

    NSArray *sourcesAndCalendars = [self.ec sourcesAndCalendars];
    EKSource *currentSource = nil;
    [_calPopup.menu removeAllItems];
    NSInteger firstTag = NSNotFound;
    BOOL matchedSelected = NO;
    for (id obj in sourcesAndCalendars) {
        if ([obj isKindOfClass:[NSString class]]) continue;
        CalendarInfo *calInfo = obj;
        if (calInfo.calendar.allowsContentModifications &&
            (calInfo.calendar.allowedEntityTypes & entityMask)) {
            if (![calInfo.calendar.source isEqualTo:currentSource]) {
                if (_calPopup.menu.itemArray.count != 0) {
                    [_calPopup.menu addItem:[NSMenuItem separatorItem]];
                }
                NSMenuItem *sourceItem = [NSMenuItem new];
                sourceItem.title   = calInfo.calendar.source.title ?: @"???";
                sourceItem.enabled = NO;
                [_calPopup.menu addItem:sourceItem];
                currentSource = calInfo.calendar.source;
            }
            NSMenuItem *calItem = [NSMenuItem new];
            calItem.title = calInfo.calendar.title;
            calItem.image = coloredDot(calInfo.calendar.color);
            calItem.tag   = [sourcesAndCalendars indexOfObject:obj];
            calItem.preferredImageVisibility = NSMenuItemImageVisibilityVisible;
            [_calPopup.menu addItem:calItem];
            if (firstTag == NSNotFound) firstTag = calItem.tag;
            if (selectedID && [calInfo.calendar.calendarIdentifier isEqualToString:selectedID]) {
                [_calPopup selectItemWithTag:calItem.tag];
                matchedSelected = YES;
            }
        }
    }
    if (!matchedSelected && firstTag != NSNotFound) {
        [_calPopup selectItemWithTag:firstTag];
    }
    return firstTag != NSNotFound;
}

- (NSInteger)defaultDurationInMinutesForNewEvent {
    NSUserDefaults *calendarDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.iCal"];
    NSNumber *durationMinutes = [calendarDefaults objectForKey:@"Default duration in minutes for new event"];
    if (durationMinutes != nil) {
        return [durationMinutes longValue];
    }
    return 60;
}

- (void)cancelOperation:(id)sender
{
    [self.enclosingPopover close];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
    NSString *trimmedTitle = [_title.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _saveButton.enabled = ![trimmedTitle isEqualToString:@""];
}

- (void)allDayClicked:(NSButton *)allDayCheckbox
{
    _alarmsModified = YES;
    if (allDayCheckbox.state == NSControlStateValueOn) {
        _startDate.datePickerElements = NSDatePickerElementFlagYearMonthDay;
        _endDate.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    }
    else {
        _startDate.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
        _endDate.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
    }

    const NSInteger *indexes = allDayCheckbox.state == NSControlStateValueOn ? kAlertAllDayIndexForRegular : kAlertRegularIndexForAllDay;
    NSMutableOrderedSet<NSNumber *> *alertIndexes = [NSMutableOrderedSet new];
    for (NSNumber *alertIndex in [self alertIndexesWithoutDefault]) {
        [alertIndexes addObject:@(indexes[alertIndex.integerValue])];
    }
    [alertIndexes removeObject:@0];
    [self populateAlertPopup];
    [self showAlertIndexesWithDefault:alertIndexes.array];
}

- (void)startDateChanged:(NSDatePicker *)startPicker
{
    _endDate.minDate    = _startDate.dateValue;
    _repEndDate.minDate = _startDate.dateValue;
    _endDate.dateValue  = [_startDate.dateValue dateByAddingTimeInterval:MAX(0, _durationSeconds)];
}

- (void)endDateChanged:(NSDatePicker *)endPicker
{
    _durationSeconds = MAX(0, [_endDate.dateValue timeIntervalSinceDate:_startDate.dateValue]);
}

- (void)repEndDateChanged:(NSDatePicker *)repEndPicker
{
    _recurrenceModified = YES;
}

- (void)repPopupChanged:(id)sender
{
    _recurrenceModified = YES;
    NSInteger repTag = _repPopup.selectedItem.tag;
    NSInteger repEndIndex = [_repEndPopup indexOfItem:_repEndPopup.selectedItem];
    if (repTag == 0 || repTag == kCustomRepeatTag) {
        [_repEndPopup selectItemAtIndex:0];
    }
    BOOL showEnd = (repTag > 0);
    _repEndLabel.hidden = !showEnd;
    _repEndPopup.hidden = !showEnd;
    _repEndDate.hidden  = !showEnd || repEndIndex == 0;
}

- (void)repEndPopupChanged:(id)sender
{
    _recurrenceModified = YES;
    NSInteger repEndIndex = [_repEndPopup indexOfItem:_repEndPopup.selectedItem];
    _repEndDate.hidden = repEndIndex == 0;
}

- (void)calPopupChanged:(id)sender
{
    _alarmsModified = YES;
    NSArray<NSNumber *> *alertIndexes = [self alertIndexesWithoutDefault];
    [self populateAlertPopup];
    [self showAlertIndexesWithDefault:alertIndexes];
}

- (void)populateAlertPopup
{
    [_alertPopup removeAllItems];

    NSInteger numOffsets = 0;
    const NSTimeInterval *offsets = nil;

    if (_allDayCheckbox.state == NSControlStateValueOn) {
        [_alertPopup addItemsWithTitles:_alertAllDayStrings];
        numOffsets = kAlertAllDayNumOffsets;
        offsets = kAlertAllDayRelativeOffsets;
    } else {
        [_alertPopup addItemsWithTitles:_alertRegularStrings];
        numOffsets = kAlertRegularNumOffsets;
        offsets = kAlertRegularRelativeOffsets;
    }

    [_alertPopup selectItemAtIndex:0];

    if (_calPopup.selectedItem == nil || [self isReminderMode]) {
        _defaultAlertIndex = 0;
        [self showAlertIndexes:@[@0]];
        return;
    }

    NSInteger index = _calPopup.selectedItem.tag;
    NSArray *sourcesAndCalendars = [self.ec sourcesAndCalendars];
    if (index < 0 || index >= (NSInteger)sourcesAndCalendars.count || ![sourcesAndCalendars[index] isKindOfClass:[CalendarInfo class]]) {
        _defaultAlertIndex = 0;
        [self showAlertIndexes:@[@0]];
        return;
    }
    CalendarInfo *calInfo = sourcesAndCalendars[index];

    EKEvent *dummyEvent  = [self.ec newEvent];
    dummyEvent.calendar  = calInfo.calendar;
    dummyEvent.allDay    = _allDayCheckbox.state == NSControlStateValueOn;

    if (dummyEvent.alarms.count > 0) {
        for (NSInteger i = 0; i < numOffsets; i++) {
            if (dummyEvent.alarms.firstObject.relativeOffset == offsets[i]) {
                [_alertPopup selectItemAtIndex:i];
                break;
            }
        }
    }
    _defaultAlertIndex = [_alertPopup indexOfItem:_alertPopup.selectedItem];
    [self showAlertIndexes:@[@(_defaultAlertIndex)]];
}

- (void)showAlertIndexes:(NSArray<NSNumber *> *)alertIndexes
{
    NSUInteger count = MIN(MAX(alertIndexes.count, 1), kAlertMaxCount);
    while (_alertPopups.count > count) {
        [_alertLabels.lastObject removeFromSuperview];
        [_alertPopups.lastObject removeFromSuperview];
        [_alertLabels removeLastObject];
        [_alertPopups removeLastObject];
    }
    while (_alertPopups.count < count) {
        [self addAlertRow];
    }
    for (NSUInteger i = 0; i < _alertPopups.count; i++) {
        [_alertPopups[i] selectItemAtIndex:i < alertIndexes.count ? alertIndexes[i].integerValue : 0];
    }
    [self updateAlertItems];
    [self updateAddAlertButton];
}

- (void)updateAlertItems
{
    NSArray<NSNumber *> *alertIndexes = [self alertIndexes];
    for (NSPopUpButton *alertPopup in _alertPopups) {
        NSInteger selectedIndex = [alertPopup indexOfItem:alertPopup.selectedItem];
        for (NSInteger i = 0; i < alertPopup.numberOfItems; i++) {
            [alertPopup itemAtIndex:i].enabled = i == selectedIndex || ![alertIndexes containsObject:@(i)];
        }
    }
}

- (void)addAlertClicked:(id)sender
{
    _alarmsModified = YES;
    [self showAlertIndexes:[[self alertIndexes] arrayByAddingObject:@0]];
}

- (void)addAlertRow
{
    NSView *v = _alertPopup.superview;
    NSPopUpButton *lastPopup = _alertPopups.lastObject;
    NSTextField *alertLabel = [NSTextField labelWithString:NSLocalizedString(@"Alert:", @"")];
    alertLabel.alignment = NSTextAlignmentRight;
    NSPopUpButton *alertPopup = [NSPopUpButton new];
    alertPopup.target = self;
    alertPopup.action = @selector(alertPopupChanged:);
    alertPopup.menu.autoenablesItems = NO;
    [alertPopup addItemsWithTitles:_alertPopup.itemTitles];
    [v addSubview:alertLabel];
    [v addSubview:alertPopup];
    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:nil views:NSDictionaryOfVariableBindings(lastPopup, alertLabel, alertPopup)];
    [vfl :@"V:[lastPopup]-[alertPopup]" :NSLayoutFormatAlignAllLeading | NSLayoutFormatAlignAllTrailing];
    [vfl :@"H:|-[alertLabel]-[alertPopup]" :NSLayoutFormatAlignAllBaseline];
    [_alertLabels addObject:alertLabel];
    [_alertPopups addObject:alertPopup];
}

- (void)alertPopupChanged:(id)sender
{
    _alarmsModified = YES;
    NSMutableArray<NSNumber *> *alertIndexes = [self alertIndexes];
    [alertIndexes sortUsingSelector:@selector(compare:)];
    if (alertIndexes.count < _alertPopups.count) {
        [alertIndexes addObject:@0];
    }
    if (_defaultAlertIndex > 0 && ![alertIndexes containsObject:@(_defaultAlertIndex)]) {
        _defaultAlertKept = NO;
    }
    [self showAlertIndexes:alertIndexes];
}

- (NSMutableArray<NSNumber *> *)alertIndexes
{
    NSMutableOrderedSet<NSNumber *> *alertIndexes = [NSMutableOrderedSet new];
    for (NSPopUpButton *alertPopup in _alertPopups) {
        [alertIndexes addObject:@([alertPopup indexOfItem:alertPopup.selectedItem])];
    }
    [alertIndexes removeObject:@0];
    return [alertIndexes.array mutableCopy];
}

- (NSArray<NSNumber *> *)alertIndexesWithoutDefault
{
    NSMutableArray<NSNumber *> *alertIndexes = [self alertIndexes];
    NSUInteger defaultRow = [alertIndexes indexOfObject:@(_defaultAlertIndex)];
    if (_defaultAlertKept && defaultRow != NSNotFound) {
        [alertIndexes removeObjectAtIndex:defaultRow];
    }
    return alertIndexes;
}

- (void)showAlertIndexesWithDefault:(NSArray<NSNumber *> *)alertIndexes
{
    if (_defaultAlertKept && _defaultAlertIndex > 0) {
        if (alertIndexes.count < kAlertMaxCount && ![alertIndexes containsObject:@(_defaultAlertIndex)]) {
            alertIndexes = [alertIndexes arrayByAddingObject:@(_defaultAlertIndex)];
        }
        else {
            _defaultAlertIndex = 0;
        }
    }
    [self showAlertIndexes:[alertIndexes sortedArrayUsingSelector:@selector(compare:)]];
}

- (void)updateAddAlertButton
{
    NSPopUpButton *lastPopup = _alertPopups.lastObject;
    _addAlertButtonTopConstraint.active = NO;
    _addAlertButtonTopConstraint = [_addAlertButton.topAnchor constraintEqualToAnchor:lastPopup.topAnchor];
    _addAlertButtonTopConstraint.active = YES;
    BOOL hidden = _alertPopups.count >= kAlertMaxCount || [lastPopup indexOfItem:lastPopup.selectedItem] == 0;
    if (hidden && _addAlertButton.window.firstResponder == _addAlertButton) {
        [_addAlertButton.window makeFirstResponder:lastPopup];
    }
    _addAlertButton.hidden = hidden;
}

- (EKRecurrenceRule *)selectedRecurrenceRule
{
    NSInteger repTag = _repPopup.selectedItem.tag;
    if (repTag <= 0) return nil;
    EKRecurrenceFrequency frequency = EKRecurrenceFrequencyDaily;
    NSInteger interval = 1;
    switch (repTag) {
        case 1: frequency = EKRecurrenceFrequencyDaily; break;
        case 2: frequency = EKRecurrenceFrequencyWeekly; break;
        case 3: frequency = EKRecurrenceFrequencyWeekly; interval = 2; break;
        case 4: frequency = EKRecurrenceFrequencyMonthly; break;
        case 5: frequency = EKRecurrenceFrequencyYearly; break;
        default: return nil;
    }
    EKRecurrenceEnd *recurrenceEnd = nil;
    if ([_repEndPopup indexOfItem:_repEndPopup.selectedItem] != 0) {
        recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithEndDate:_repEndDate.dateValue];
    }
    return [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:frequency interval:interval end:recurrenceEnd];
}

- (void)fillItem:(EKCalendarItem *)item updateRecurrence:(BOOL)updateRecurrence updateAlarms:(BOOL)updateAlarms
{
    NSDate *startDate = _startDate.dateValue;
    NSDate *endDate   = _endDate.dateValue;
    BOOL isAllDay     = _allDayCheckbox.state == NSControlStateValueOn;

    NSInteger index = _calPopup.selectedItem.tag;
    NSArray *sourcesAndCalendars = [self.ec sourcesAndCalendars];
    CalendarInfo *calInfo = (index >= 0 && index < (NSInteger)sourcesAndCalendars.count && [sourcesAndCalendars[index] isKindOfClass:[CalendarInfo class]])
        ? sourcesAndCalendars[index]
        : nil;

    NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    item.title = [_title.stringValue stringByTrimmingCharactersInSet:whitespaceSet];
    if (calInfo.calendar) item.calendar = calInfo.calendar;
    NSString *urlText = [_url.stringValue stringByTrimmingCharactersInSet:whitespaceSet];
    item.URL = urlText.length > 0 ? [NSURL URLWithString:urlText] : nil;
    NSString *notes = [_notes.string stringByTrimmingCharactersInSet:whitespaceSet];
    item.notes = notes.length > 0 ? notes : nil;

    if ([item isKindOfClass:[EKEvent class]]) {
        EKEvent *event = (EKEvent *)item;
        NSString *loc = [_location.stringValue stringByTrimmingCharactersInSet:whitespaceSet];
        event.location  = loc.length > 0 ? loc : nil;
        event.allDay    = isAllDay;
        event.startDate = startDate;
        event.endDate   = [endDate compare:startDate] == NSOrderedAscending ? startDate : endDate;
        event.timeZone  = isAllDay ? nil : (event.timeZone ?: [NSTimeZone localTimeZone]);
    }
    else if ([item isKindOfClass:[EKReminder class]]) {
        EKReminder *reminder = (EKReminder *)item;
        NSCalendarUnit units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
        if (!isAllDay) {
            units |= (NSCalendarUnitHour | NSCalendarUnitMinute);
        }
        NSDateComponents *dueComp = [self.cal components:units fromDate:startDate];
        dueComp.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        if (!isAllDay) dueComp.timeZone = [NSTimeZone localTimeZone];
        reminder.dueDateComponents = dueComp;
        if (updateRecurrence && [self selectedRecurrenceRule] != nil) {
            reminder.startDateComponents = [dueComp copy];
        }
    }

    if (updateRecurrence && _repPopup.selectedItem.tag != kCustomRepeatTag) {
        EKRecurrenceRule *rule = [self selectedRecurrenceRule];
        item.recurrenceRules = rule ? @[rule] : nil;
    }

    if ([item isKindOfClass:[EKReminder class]]) {
        EKReminder *reminder = (EKReminder *)item;
        reminder.startDateComponents = reminder.hasRecurrenceRules ? [reminder.dueDateComponents copy] : nil;
    }

    if (updateAlarms) {
        for (EKAlarm *alarm in [item.alarms copy]) {
            [item removeAlarm:alarm];
        }
        for (NSNumber *alertIndexNumber in [self alertIndexes]) {
            NSInteger alertIndex = alertIndexNumber.integerValue;
            NSTimeInterval offset = MAXFLOAT;
            if (isAllDay && alertIndex < kAlertAllDayNumOffsets) {
                offset = kAlertAllDayRelativeOffsets[alertIndex];
            }
            else if (!isAllDay && alertIndex < kAlertRegularNumOffsets) {
                offset = kAlertRegularRelativeOffsets[alertIndex];
            }
            if (offset != MAXFLOAT) {
                if ([item isKindOfClass:[EKReminder class]]) {
                    NSDate *base = isAllDay ? [self.cal startOfDayForDate:startDate] : startDate;
                    [item addAlarm:[EKAlarm alarmWithAbsoluteDate:[base dateByAddingTimeInterval:offset]]];
                } else {
                    [item addAlarm:[EKAlarm alarmWithRelativeOffset:offset]];
                }
            }
        }
    }
}

- (void)saveEvent:(id)sender
{
    NSError *error = nil;
    BOOL saved = NO;

    if (self.editingItem != nil) {
        EKCalendarItem *target = self.editingItem.item;
        if (target == nil || ![target refresh]) {
            [self.enclosingPopover close];
            return;
        }
        EKSpan span = EKSpanThisEvent;
        if (self.editingItem.event != nil && self.editingItem.event.hasRecurrenceRules) {
            if (_recurrenceModified) {
                span = EKSpanFutureEvents;
            } else {
                NSAlert *alert = [NSAlert new];
                alert.messageText = NSLocalizedString(@"You’re changing a repeating event.", @"");
                alert.informativeText = NSLocalizedString(@"Do you want to save the changes for this event only, or for all future events?", @"");
                [alert addButtonWithTitle:NSLocalizedString(@"Save for This Event Only", @"")];
                [alert addButtonWithTitle:NSLocalizedString(@"Save for Future Events", @"")];
                [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
                NSModalResponse response = [alert runModal];
                if (response == NSAlertThirdButtonReturn) return;
                span = (response == NSAlertSecondButtonReturn) ? EKSpanFutureEvents : EKSpanThisEvent;
            }
        }
        saved = [self.ec updateItem:target span:span changes:^(EKCalendarItem *item) {
            [self fillItem:item updateRecurrence:self->_recurrenceModified updateAlarms:self->_alarmsModified];
        } undoManager:self.eventUndoManager error:&error];
    }
    else if ([self isReminderMode]) {
        EKReminder *reminder = [self.ec newReminder];
        [self fillItem:reminder updateRecurrence:YES updateAlarms:YES];
        saved = [self.ec applyBatchChangesWithAddedEvents:@[]
                                           addedReminders:@[reminder]
                                            deletedEvents:@[]
                                        deletedEventSpans:@[]
                                         deletedReminders:@[]
                                              undoManager:self.eventUndoManager
                                                    error:&error];
        if (saved && reminder.calendar.calendarIdentifier) {
            [self.ec updateSelectedCalendarsForIdentifier:reminder.calendar.calendarIdentifier selected:YES];
        }
    }
    else {
        EKEvent *event = [self.ec newEvent];
        [self fillItem:event updateRecurrence:YES updateAlarms:YES];
        saved = [self.ec applyBatchChangesWithAddedEvents:@[event]
                                           addedReminders:@[]
                                            deletedEvents:@[]
                                        deletedEventSpans:@[]
                                         deletedReminders:@[]
                                              undoManager:self.eventUndoManager
                                                    error:&error];
        if (saved && event.calendar.calendarIdentifier) {
            [self.ec updateSelectedCalendarsForIdentifier:event.calendar.calendarIdentifier selected:YES];
        }
    }

    if (saved == NO && error != nil) {
        [[NSAlert alertWithError:error] runModal];
    }
    else {
        [self.enclosingPopover close];
    }
}

#pragma mark -
#pragma mark NSTextViewDelegate

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
    if (aTextView != _notes) return NO;
    if (aSelector == @selector(insertTab:)) {
        [_notes.window makeFirstResponder:_url];
        return YES;
    }
    else if (aSelector == @selector(insertBacktab:)) {
        [_notes.window selectKeyViewPrecedingView:_notes];
        return YES;
    }
    return NO;
}

- (void)textDidChange:(NSNotification *)notification
{
    if (notification.object != _notes) return;

    NSInteger maxVisibleLines = 16;

    [_notes.layoutManager ensureLayoutForTextContainer:_notes.textContainer];
    CGFloat height = [_notes.layoutManager usedRectForTextContainer:_notes.textContainer].size.height;

    height = MIN(height, maxVisibleLines * _notesHeightOfOneLine);
    _notesScrollViewHeightConstraint.constant = MAX(height, _notesHeightOfOneLine);

    NSInteger numberOfLines, idx, numberOfGlyphs = [_notes.layoutManager numberOfGlyphs];
    NSRange lineRange;
    for (numberOfLines = 0, idx = 0; idx < numberOfGlyphs; numberOfLines++) {
        (void)[_notes.layoutManager lineFragmentRectForGlyphAtIndex:idx effectiveRange:&lineRange];
        idx = NSMaxRange(lineRange);
    }

    BOOL scrolls = numberOfLines > maxVisibleLines;
    _notesScrollView.verticalScrollElasticity = scrolls ? NSScrollElasticityAutomatic : NSScrollElasticityNone;
    if (_notesScrollView.hasVerticalScroller != scrolls) {
        _notesScrollView.hasVerticalScroller = scrolls;
        [self textDidChange:notification];
    }
}

@end
