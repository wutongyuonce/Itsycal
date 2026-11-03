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

Set your team, bundle ID and App Group in `Local.xcconfig` as described in
[widget setup](docs/WEEK_WIDGET_SETUP.md#配置签名).

## Submitting a Pull Request

Make sure your PR does not include changes to `DEVELOPMENT_TEAM`,
`DevelopmentTeam`, `ProvisioningStyle` or `PRODUCT_BUNDLE_IDENTIFIER` in
`Itsycal.xcodeproj/project.pbxproj`. If you see those in your diff,
revert them — they are the result of Xcode writing your local signing
settings into the project file. Setting up `Local.xcconfig` as described
above will prevent this from happening.
