//
//  PrefsAIVC.m
//  Itsycal
//

#import "PrefsAIVC.h"
#import "MoVFLHelper.h"
#import "Itsycal-Swift.h"

@implementation PrefsAIVC
{
    NSPopUpButton *_protocolPopup;
    NSTextField *_baseURLField;
    NSTextField *_modelField;
    NSSecureTextField *_apiKeyField;
    NSTextField *_instructionsField;
    NSButton *_clearCacheBtn;
    NSTextField *_cacheInfoLabel;
    NSTextField *_statusLabel;
}

- (void)loadView
{
    NSView *v = [NSView new];

    NSTextField* (^label)(NSString *) = ^NSTextField* (NSString *stringValue) {
        NSTextField *txt = [NSTextField labelWithString:stringValue];
        txt.alignment = NSTextAlignmentRight;
        [v addSubview:txt];
        return txt;
    };

    NSTextField *heading = [NSTextField labelWithString:NSLocalizedString(@"AI Assistant", @"")];
    heading.font = [NSFont boldSystemFontOfSize:heading.font.pointSize - 1];
    [v addSubview:heading];

    NSBox *separator = [NSBox new];
    separator.boxType = NSBoxSeparator;
    [v addSubview:separator];

    NSTextField *protocolLabel = label(NSLocalizedString(@"Protocol:", @""));
    _protocolPopup = [NSPopUpButton new];
    [_protocolPopup addItemsWithTitles:@[
        @"OpenAI Compatible",
        @"Anthropic (Claude)",
        @"Google Gemini"
    ]];
    _protocolPopup.target = self;
    _protocolPopup.action = @selector(protocolChanged:);
    [v addSubview:_protocolPopup];

    NSTextField *urlLabel = label(NSLocalizedString(@"API URL:", @""));
    _baseURLField = [NSTextField textFieldWithString:@""];
    _baseURLField.placeholderString = @"https://api.openai.com/v1";
    _baseURLField.bezelStyle = NSTextFieldRoundedBezel;
    _baseURLField.usesSingleLineMode = YES;
    _baseURLField.delegate = self;
    [v addSubview:_baseURLField];

    NSTextField *modelLabel = label(NSLocalizedString(@"Model:", @""));
    _modelField = [NSTextField textFieldWithString:@""];
    _modelField.placeholderString = @"gpt-4o-mini";
    _modelField.bezelStyle = NSTextFieldRoundedBezel;
    _modelField.usesSingleLineMode = YES;
    _modelField.delegate = self;
    [v addSubview:_modelField];

    NSTextField *keyLabel = label(NSLocalizedString(@"API Key:", @""));
    _apiKeyField = [NSSecureTextField new];
    _apiKeyField.placeholderString = @"sk-...";
    _apiKeyField.bezelStyle = NSTextFieldRoundedBezel;
    _apiKeyField.usesSingleLineMode = YES;
    _apiKeyField.delegate = self;
    [v addSubview:_apiKeyField];

    NSTextField *instructionsLabel = label(NSLocalizedString(@"Preferences:", @""));
    _instructionsField = [NSTextField textFieldWithString:@""];
    _instructionsField.placeholderString = NSLocalizedString(@"Optional: e.g. Default 30m meetings", @"");
    _instructionsField.bezelStyle = NSTextFieldRoundedBezel;
    _instructionsField.usesSingleLineMode = YES;
    _instructionsField.delegate = self;
    [v addSubview:_instructionsField];

    NSTextField *cacheLabel = label(NSLocalizedString(@"History:", @""));
    _clearCacheBtn = [NSButton buttonWithTitle:NSLocalizedString(@"Clear Session & Cache", @"") target:self action:@selector(clearCacheClicked:)];
    [v addSubview:_clearCacheBtn];

    _cacheInfoLabel = [NSTextField labelWithString:@"0 KB"];
    _cacheInfoLabel.font = [NSFont systemFontOfSize:11];
    _cacheInfoLabel.textColor = NSColor.secondaryLabelColor;
    [v addSubview:_cacheInfoLabel];

    _statusLabel = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Use ⌘K or the ✨ button in Itsycal to create or delete events and reminders with natural language.", @"")];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = NSColor.secondaryLabelColor;
    [v addSubview:_statusLabel];

    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:@{@"m": @20} views:NSDictionaryOfVariableBindings(heading, separator, protocolLabel, _protocolPopup, urlLabel, _baseURLField, modelLabel, _modelField, keyLabel, _apiKeyField, instructionsLabel, _instructionsField, cacheLabel, _clearCacheBtn, _cacheInfoLabel, _statusLabel)];
    [vfl :@"V:|-m-[heading]-12-[_protocolPopup]-10-[_baseURLField]-10-[_modelField]-10-[_apiKeyField]-10-[_instructionsField]-12-[_clearCacheBtn]-14-[_statusLabel]-m-|"];
    [vfl :@"H:|-m-[heading]-[separator]-m-|" :NSLayoutFormatAlignAllCenterY];
    [vfl :@"H:|-m-[protocolLabel(80)]-[_protocolPopup(>=210)]-m-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-m-[urlLabel(80)]-[_baseURLField(>=210)]-m-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-m-[modelLabel(80)]-[_modelField(>=210)]-m-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-m-[keyLabel(80)]-[_apiKeyField(>=210)]-m-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-m-[instructionsLabel(80)]-[_instructionsField(>=210)]-m-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-m-[cacheLabel(80)]-[_clearCacheBtn]-8-[_cacheInfoLabel]-(>=m)-|" :NSLayoutFormatAlignAllFirstBaseline];
    [vfl :@"H:|-m-[_statusLabel]-m-|"];

    self.view = v;
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    [self reloadFromStore];
}

- (void)viewWillDisappear
{
    [super viewWillDisappear];
    [self saveToStore];
}

- (void)reloadFromStore
{
    [_protocolPopup selectItemAtIndex:[AIAssistantBridge currentProtocolIndex]];
    _baseURLField.stringValue = [AIAssistantBridge currentBaseURL];
    _modelField.stringValue = [AIAssistantBridge currentModel];
    _apiKeyField.stringValue = [AIAssistantBridge currentAPIKey];
    _instructionsField.stringValue = [AIAssistantBridge currentCustomInstructions];
    _baseURLField.placeholderString = [AIAssistantBridge defaultBaseURLForProtocolIndex:_protocolPopup.indexOfSelectedItem];
    _modelField.placeholderString = [AIAssistantBridge defaultModelForProtocolIndex:_protocolPopup.indexOfSelectedItem];
    _cacheInfoLabel.stringValue = [AIAssistantBridge cacheSizeDescription];
}

- (void)protocolChanged:(id)sender
{
    [self saveToStore];
    NSInteger newIdx = _protocolPopup.indexOfSelectedItem;
    [AIAssistantBridge switchProtocolIndex:newIdx];
    [self reloadFromStore];
}

- (void)clearCacheClicked:(id)sender
{
    [AIAssistantBridge clearSessionAndCache];
    _cacheInfoLabel.stringValue = NSLocalizedString(@"Cleared (0 KB)", @"");
}

- (void)controlTextDidChange:(NSNotification *)obj
{
    [self saveToStore];
}

- (void)saveToStore
{
    [AIAssistantBridge saveConfigWithProtocolIndex:_protocolPopup.indexOfSelectedItem
                                           baseURL:_baseURLField.stringValue
                                             model:_modelField.stringValue
                                            apiKey:_apiKeyField.stringValue
                                customInstructions:_instructionsField.stringValue];
}

@end
