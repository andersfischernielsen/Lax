# TODO


| Feature                         | Discord  | Slack    |
| ------------------------------- | -------- | -------- |
| Animated emoji                  | Never    | Never    |
| Animated images and videos      | Never    | Never    |
| Unread message marker line      | Planned  | Planned  |
| "User is typing" indicators     | OK       | Planned  |
| Set own nickname                | OK       | Planned  |
| @role or @subteam mentions      | Planned  | Planned  |
| Video calls and screen sharing  | Unlikely | Unlikely |

- [ ] Animated emoji: custom emoji show, but GIFs only show their first frame
- [ ] Animated images and videos
- [x] Unread message marker line
- [x] "User is typing" indicators (Slack)
- [x] Set own nickname (Slack): display name, from the workspace menu
- [ ] @role (Discord) or @subteam (Slack) mentions: shown in messages; no autocomplete when writing
- [ ] Video calls and screen sharing (huddles) — last


- [ ] Passkey 2FA at sign-in. macOS doesn't allow passkeys in an embedded web view
      for apps that aren't browsers, so this needs sign-in through the system browser.
- [x] Threads
- [x] Reactions, with a picker for standard and custom emoji
- [x] Images and file attachments
- [x] Bot messages: Block Kit blocks and legacy attachments
- [x] Edit and delete own messages
- [x] Message menu: reply in thread, react, copy text or link
- [x] Unread badges in the sidebar
- [x] Muted channels
- [x] Unread dot on the Dock icon (no Notification Center notifications, by choice)
- [x] Custom emoji and `:shortcodes:`
- [x] Group DM names
- [x] Search: results open the conversation, scrolled to the message (and its thread)
- [ ] Slash commands and bot buttons
- [x] Mark as unread: from the message menu (moves the read position back) and the sidebar
- [x] App icon
- [ ] Mention autocomplete (@person, #channel) in the composer
- [ ] Emoji autocomplete: typing `:` suggests shortcodes, standard and custom
- [x] Separate native views for all threads, all DMs and the base channel view:
      View ▸ Home / Direct Messages / Threads (⌘1–3), per window or tab
- [x] View → Show Tab Bar: each window and tab keeps its own conversation

- [x] ⌘K Open Quickly: jump to any channel or person by typing part of the name

- [x] Dock badge like Slack's: a dot with no number for unread channels and threads; the
      count of mentions and direct messages when there are any

- [x] Back and forward: Go ▸ Back / Forward (⌘[ / ⌘]), toolbar buttons and the mouse's
      back and forward buttons, through conversations and threads visited in a window

- [ ] New app icon: a simple hashtag on a gradient, made as a Liquid Glass icon (an Icon
      Composer `.icon` file) so macOS renders it in its glass, dark, tinted and clear styles

## Bugs

- [ ] Shift-Return and Option-Return don't start a new line in the composer
- [ ] Icons flicker when the window is closed (Lax still running) and reopened from the Dock
- [ ] No window at launch when the previous session ended with every window closed
      (restored state wins over `.defaultLaunchBehavior(.presented)`); the Dock icon opens one
- [ ] Every rebuild asks for Keychain access again: builds are signed ad hoc, so each one is a
      new identity to the Keychain. A stable signing certificate would fix it

## Apple quality

- [x] Performance pass: rows redraw only when their own data changes (split the
      workspace model), messages are formatted once and cached, avatars and emoji
      images are cached, and images reserve their space so rows don't change height
- [x] Apple guideline pass: ⌘C copies the selected message (as in Messages; selectable
      text would hide the message menu),
      a Settings window, accessibility labels, specific error messages instead of one
      generic alert, sign-out confirmation, keyboard navigation in the menus, and only
      system colors and levels (no hand-tuned opacities)
