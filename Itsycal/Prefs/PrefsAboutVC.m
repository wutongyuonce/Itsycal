//
//  Created by Sanjay Madan on 1/11/17.
//  Copyright © 2017 mowglii.com. All rights reserved.
//

#import "PrefsAboutVC.h"
#import "Itsycal.h"
#import "MoTextField.h"
#import "MoVFLHelper.h"
#import "MoLoginItem.h"
#import "Itsycal-Swift.h"

@implementation PrefsAboutVC

#pragma mark -
#pragma mark View lifecycle

- (void)loadView
{
    NSView *v = [NSView new];

    // The content goes in a box that hugs it. The box is centered
    // so the content stays centered when the Settings window is
    // wider than the content (see PrefsVC).
    NSView *box = [NSView new];
    [v addSubview:box];

    // Convenience function for making labels.
    MoTextField* (^label)(NSString*, BOOL) = ^MoTextField* (NSString *stringValue, BOOL isLink) {
        MoTextField *txt = [MoTextField labelWithString:stringValue];
        if (isLink) {
            txt.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            txt.linkEnabled = YES;
        }
        [box addSubview:txt];
        return txt;
    };

    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString *displayName = infoDict[@"CFBundleDisplayName"] ?: @"Itsycal";
    NSTextField *appName = label(displayName, NO);
    appName.font = [NSFont systemFontOfSize:16 weight:NSFontWeightBold];

    NSTextField *version = label([NSString stringWithFormat:@"%@ (%@)", infoDict[@"CFBundleShortVersionString"], infoDict[@"CFBundleVersion"]], NO);
    version.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    version.textColor = [NSColor secondaryLabelColor];

    MoTextField *repo = label(@"GitHub", YES);
    repo.urlString = @"https://github.com/wutongyuonce/Itsycal";

    MoTextField *upstream = label(@"Upstream Itsycal", YES);
    upstream.urlString = @"https://github.com/sfsam/Itsycal";

    NSTextField *forkNote = label(@"Forked from Itsycal by Sanjay Madan", NO);

    NSTextField *copyright1 = label(@"© 2026 wutongyuonce", NO);
    NSTextField *copyright2 = label(@"Itsycal © 2012–2026 mowglii.com", NO);
    copyright1.textColor = [NSColor secondaryLabelColor];
    copyright2.textColor = [NSColor secondaryLabelColor];

    NSButton *uninstallBtn = [NSButton buttonWithTitle:NSLocalizedString(@"Clean Uninstall Itsycal…", @"") target:self action:@selector(cleanUninstallClicked:)];
    uninstallBtn.contentTintColor = NSColor.systemRedColor;
    [box addSubview:uninstallBtn];

    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:box metrics:@{@"m": @25} views:NSDictionaryOfVariableBindings(appName, version, repo, upstream, forkNote, copyright1, copyright2, uninstallBtn)];
    [vfl :@"V:|[appName]-m-[repo]-8-[upstream]-m-[forkNote]-6-[copyright1]-2-[copyright2]-18-[uninstallBtn]|"];
    [vfl :@"H:|[appName]-4-[version]-(>=0)-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|[repo]-(>=0)-|"];
    [vfl :@"H:|[upstream]-(>=0)-|"];
    [vfl :@"H:|[forkNote]-(>=0)-|"];
    [vfl :@"H:|[copyright1]-(>=0)-|"];
    [vfl :@"H:|[copyright2]-(>=0)-|"];
    [vfl :@"H:|[uninstallBtn]-(>=0)-|"];

    MoVFLHelper *outer = [[MoVFLHelper alloc] initWithSuperview:v metrics:@{@"m": @25} views:NSDictionaryOfVariableBindings(box)];
    [outer :@"V:|-m-[box]-m-|"];
    [outer :@"H:|-(>=m)-[box]-(>=m)-|"];
    [box.centerXAnchor constraintEqualToAnchor:v.centerXAnchor].active = YES;

    // Make the box as narrow as its content allows.
    NSLayoutConstraint *hug = [box.widthAnchor constraintEqualToConstant:0];
    hug.priority = 1;
    hug.active = YES;

    self.view = v;
}

- (void)cleanUninstallClicked:(id)sender
{
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = NSLocalizedString(@"Clean Uninstall Itsycal?", @"");
    alert.informativeText = NSLocalizedString(@"This will remove Itsycal's login item, preferences, Keychain API key, AI session cache, and widget container, then move Itsycal.app to the Trash and quit.", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"Uninstall & Move to Trash", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    alert.buttons.firstObject.hasDestructiveAction = YES;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    MOEnableLoginItem(NO);
    [AIAssistantBridge removeAllAppResidues];

    NSURL *bundleURL = [[NSBundle mainBundle] bundleURL];
    [[NSWorkspace sharedWorkspace] recycleURLs:@[bundleURL] completionHandler:^(NSDictionary<NSURL *,NSURL *> * _Nonnull newURLs, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
    }];
}

@end
