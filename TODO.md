# Roadmap

## Planned

- [ ] Huddles: calls and screen sharing
- [ ] Passkey sign-in. macOS doesn't allow passkeys in an embedded web view for apps
      that aren't browsers, so this needs sign-in through the system browser.
- [ ] Bot select menus and modal dialogs (buttons work)
- [ ] Notarized releases, signed with a Developer ID

## Known issues

- [ ] Icons in the sidebar may flicker once when a closed window is reopened from the Dock
- [ ] Local builds signed ad hoc ask for Keychain access after every rebuild; signing with
      a stable certificate (`scripts/bundle.sh` uses "Lax Local Code Signing" when present)
      avoids it

## Done

- [x] File and image uploads by paste, drag and drop or ⌘U, in conversations and threads
- [x] Sign-in with the usual Slack login, SSO and 2FA codes included; several workspaces
- [x] Channels, direct messages and group DMs, each view in its own window or tab
      (View ▸ Channels / Direct Messages / Threads, ⌘1–3)
- [x] Threads beside the conversation, and a view of followed threads
- [x] Rich text composer: ⌘B bold, ⌘I italic, ⇧⌘X strikethrough, ⇧⌘C code, sent as
      Slack markup; Shift- or Option-Return for a new line
- [x] Autocomplete for `@people`, `@groups`, `#channels` and `:emoji:`
- [x] Slash commands and Block Kit buttons
- [x] Reactions, with a picker for standard and custom emoji
- [x] Custom emoji, animated ones included, in text, reactions and emoji-only messages
- [x] Images, GIFs and videos, opening in a viewer tab
- [x] Bot messages: Block Kit blocks and legacy attachments
- [x] Edit, delete, copy and link to messages; mark as unread
- [x] Read state: messages count as read once scrolled past; unread messages are marked
      with a red bar; conversations open at the first unread message
- [x] Unread badges, muted conversations, and a Slack-style Dock badge instead of
      notifications
- [x] Search, opening the result in place
- [x] Open Quickly (⌘K), back and forward (⌘[ / ⌘]), and a Go menu
- [x] Keyboard shortcuts for everything in the message and conversation menus
- [x] Settings, VoiceOver labels, and a Liquid Glass app icon
