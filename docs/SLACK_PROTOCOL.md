# How Lax talks to Slack

Lax uses the same interface as Slack's own web client at `app.slack.com`: a
browser session (an `xoxc-` token plus the `d` cookie), the Web API, and a
real-time WebSocket. Nothing here needs a Slack app, a bot token or admin
approval. Slack doesn't document this interface for third parties and may
change it; this file records what Lax relies on.

## Signing in

1. Lax opens `https://app.slack.com/` in a `WKWebView` with a non-persistent
   website data store, so the user signs in exactly as in a browser, SSO and
   2FA included. Pop-ups (some SSO providers) open as sheets.
2. Slack's desktop hand-off page (`/ssb/redirect`) is replaced by the web
   client (`app.slack.com/client`), so sign-in finishes in the web view.
3. Once the page is the signed-in client, Lax reads
   `localStorage.localConfig_v2`: one entry per workspace with its `token`
   (`xoxc-…`), `url`, team and user IDs.
4. It reads the `d` cookie (and `d-s`) for `.slack.com` from the web view's
   cookie store.
5. For each workspace it calls `auth.test` to confirm the session, then saves
   the token, cookies and IDs to the Keychain. The web view's data is
   discarded.

The cookie is only ever sent to hosts under `slack.com`, `slack-edge.com` and
`slack-files.com`, over HTTPS.

## Web API

Requests are form-encoded POSTs to `https://<workspace>.slack.com/api/<method>`
with `token` in the body and the cookies in the `Cookie` header. Every
response has `ok`; failures carry `error`. Lists page with
`response_metadata.next_cursor`.

| Method | Lax uses it for |
| ------ | --------------- |
| `auth.test` | Checking a session at sign-in |
| `rtm.connect` | The WebSocket URL |
| `client.counts` | Unread state, mention counts and latest activity per conversation, and followed threads (`thread_counts_by_channel=true`) |
| `users.conversations` | Channels, private channels, DMs and group DMs (`types=public_channel,private_channel,mpim,im`) |
| `conversations.history` | Messages, newest first, paged with `latest` |
| `conversations.replies` | A whole thread |
| `conversations.info` | The read position (`last_read`) when opening a conversation |
| `conversations.mark` | Moving the read position, forward or back (mark as unread) |
| `conversations.members` | Members of group DMs, to name them |
| `users.info` | Names and avatars |
| `usergroups.list` | `@group` handles |
| `users.prefs.get` / `users.prefs.setNotifications` | Muted conversations (`muted_channels`, `all_notifications_prefs`) |
| `users.profile.set` | Display name |
| `emoji.list` | Custom emoji; aliases are `alias:<name>` |
| `chat.postMessage` | Sending, with `thread_ts` for replies |
| `chat.update` / `chat.delete` | Editing and deleting own messages |
| `chat.getPermalink` | Copy Link |
| `chat.command` | Slash commands: `command`, `text`, `disp`, `client_token` |
| `blocks.actions` | Pressing a bot's button: `actions`, `container`, `service_id`, `bot_user_id`, `client_token` |
| `reactions.add` / `reactions.remove` | Reactions |
| `search.messages` | Search |
| `subscriptions.thread.getView` | Followed threads, newest first, paged with `current_ts` |
| `subscriptions.thread.mark` | Marking a followed thread read |

### Button presses

`actions` is a JSON array with the pressed button, and `container` says where
it is:

```json
[{"action_id":"approve","block_id":"b2","type":"button",
  "text":{"type":"plain_text","text":"Approve"},"value":"yes"}]
```

```json
{"type":"message","message_ts":"1700000000.000100","channel_id":"C1","is_ephemeral":false}
```

`service_id` is the message's `bot_id`, and `bot_user_id` its `user`.
`client_token` is any unique string; Lax uses `web-<milliseconds>`.

## Real time

`rtm.connect` returns a `wss://` URL. Lax sends `{"type":"ping","id":N}` every
30 seconds and `{"type":"typing","id":N,"channel":"…"}` while the user types,
reconnects with back-off, and treats `invalid_auth`, `not_authed`,
`account_inactive` and `token_revoked` as signed out.

Events Lax handles:

- `hello`, `goodbye`
- `message`, with subtypes `message_changed`, `message_deleted` and
  `message_replied`; shown subtypes include `bot_message`, `me_message`,
  `thread_broadcast`, `file_share`, `channel_join`, `channel_leave`,
  `channel_topic`, `channel_purpose` and `channel_name`
- `user_typing`
- `channel_marked`, `group_marked`, `im_marked`, `mpim_marked`
  (`unread_count_display`, `mention_count_display`)
- `reaction_added`, `reaction_removed`
- `pref_change` (muting)
- `emoji_changed`

## Messages

A message's text is Slack markup ("mrkdwn"): `*bold*`, `_italic_`,
`~strike~`, `` `code` ``, ```` ```blocks``` ````, `> quotes`, `:emoji:`, and
tokens like `<@U1>`, `<#C1|name>`, `<!subteam^S1>`, `<!here>` and
`<https://…|label>`. `&`, `<` and `>` are escaped as entities.

Bots often send layout `blocks` (Block Kit) and legacy `attachments` instead
of, or as well as, `text`; Lax renders `section`, `header`, `context`,
`rich_text` and `divider` blocks, `button` elements, and attachment titles,
text, fields and colours.

Files carry thumbnails (`thumb_720`, `thumb_360`), animated GIF thumbnails
(`thumb_480_gif`, `thumb_360_gif`, with `original_w`/`original_h`), and for
videos `mp4` and a poster (`thumb_video`). All of them need the cookie.
