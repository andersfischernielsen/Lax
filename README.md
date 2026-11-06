# Lax

A native macOS Slack client. Targets macOS 27 or later.

- `Sources/LaxKit`: the Slack layer (credentials, Web API, WebSocket, cache). No UI.
- `Sources/Lax`: the SwiftUI app.

## Build

Needs Swift 6.4 (the Command Line Tools are enough).

```sh
swift build          # debug build
scripts/test.sh      # run tests (wraps `swift test`, see the script)
swift run Lax        # run the app without bundling
scripts/bundle.sh    # release build, wrapped as build/Lax.app
```
