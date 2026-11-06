# Lax

A native macOS Slack client. Targets macOS 27 or later.

- `Sources/LaxKit`: the Slack layer (credentials, Web API, WebSocket, cache). No UI.
- `Sources/Lax`: the SwiftUI app.

## Build

Needs Xcode 27 (the Command Line Tools lack SwiftUI's macro plugin).

```sh
swift build          # debug build
swift test           # run LaxKit's tests (Swift Testing)
swift run Lax        # run the app without bundling
scripts/bundle.sh    # release build, wrapped as build/Lax.app
scripts/uitest.sh    # run the UI tests (XCUIAutomation, via Lax.xcodeproj)
```

The UI tests launch Lax with `-ui-testing`, which signs in to a fixture workspace answered
in-process (`Sources/Lax/UITesting`) instead of the Keychain and Slack. They find elements by
accessibility identifier and drive the real mouse and keyboard, so leave the Mac alone while
they run.
