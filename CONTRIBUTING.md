# Contributing to Itsycal

Thank you for your interest in contributing!

## Setting Up Code Signing

Itsycal uses a local xcconfig file to manage code signing so that your
personal signing settings are never committed to the repository.

Before opening `Itsycal.xcodeproj`, copy the example config:

```
cp Local.xcconfig.example Local.xcconfig
```

`Local.xcconfig` is gitignored and should never be committed.

### Option 1 — No Apple Developer account

For compilation checks, leave the defaults as-is and build with
`CODE_SIGNING_ALLOWED=NO`. Running this fork's native widget also requires
working development signing and a shared App Group; see
[widget setup](docs/WEEK_WIDGET_SETUP.md).

### Option 2 — Your own Apple Developer account

Edit `Local.xcconfig` and set your 10-character team ID (found under
Membership at developer.apple.com):

```
DEVELOPMENT_TEAM = XXXXXXXXXX
CODE_SIGN_IDENTITY = Apple Development
CODE_SIGN_STYLE = Automatic
ENABLE_HARDENED_RUNTIME = YES
WEEK_APP_GROUP = XXXXXXXXXX.com.wutongyuonce.Itsycal
```

## Submitting a Pull Request

Make sure your PR does not include changes to `DEVELOPMENT_TEAM`,
`DevelopmentTeam`, or `ProvisioningStyle` in
`Itsycal.xcodeproj/project.pbxproj`. If you see those in your diff,
revert them — they are the result of Xcode writing your local signing
settings into the project file. Setting up `Local.xcconfig` as described
above will prevent this from happening.
