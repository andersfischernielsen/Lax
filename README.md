# Lax

A native macOS Slack client. Targets macOS 27 or later.

- `Sources/LaxKit`: the Slack layer (credentials, Web API, WebSocket, cache). No UI.
- `Sources/Lax`: the SwiftUI app.

## Build

Needs Xcode 27 (the Command Line Tools lack SwiftUI's macro plugin).

```sh
swift build          # debug build
swift test           # run tests
swift run Lax        # run the app without bundling
scripts/bundle.sh    # release build, wrapped as build/Lax.app
```
