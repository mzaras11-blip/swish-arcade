# Presence bridge contract (web ↔ native)

Online presence ("who is in the app right now") is split the same way as
the other S.W.I.S.H features: the web layer asks, the native shell owns
the network (Firestore). The web half shipped in v1.1; this document is
the contract the iOS and Android shells implement to light it up.

## Handler

- Name: `presence`
- Reached at: `window.webkit.messageHandlers.presence`
  (iOS: `WKScriptMessageHandler`; Android: the document-start shim maps
  the same name to the native `@JavascriptInterface`, like the existing
  `auth` / `live` / `ads` / `audio` / `haptics` handlers.)

## Web → native (`postMessage`)

### `{ "action": "heartbeat" }`

Sent by the web layer:

- as soon as sign-in state becomes known (after the `auth` state reply),
- then every 30 seconds while the page is visible,
- and again whenever the page becomes visible.

Native behavior: stamp the signed-in user's presence document —
`users/{uid}` gains `lastSeen` = Firestore server timestamp
(`FieldValue.serverTimestamp()`), keeping the existing `username` field
on the same document. No reply is expected.

### `{ "action": "friends" }`

Sent when the Friends tab opens and periodically while it is open.

Native behavior: read the current user's friend list
(`users/{uid}/friends`), fetch each friend's user document, and reply
by evaluating JavaScript in the web view:

```js
window.onPresenceResult(JSON.stringify({
  "type": "friends",
  "friends": [
    { "name": "<username>", "lastSeen": 1760000000000 }
  ]
}))
```

- `name` is the friend's username (matches the web store's friend list).
- `lastSeen` is epoch **milliseconds**. Friends with no presence stamp
  may be omitted or sent with `lastSeen: 0`.

## Web behavior

- A friend whose `lastSeen` is less than **90 seconds** old gets a green
  dot in the Friends tab ("Online now"); older gets a grey dot
  ("Offline").
- If the `presence` handler is absent, every call fails silently and
  **no dots are rendered at all** — presence is never faked. Current
  builds have no handler, so nothing changes on screen until the shells
  implement this contract.

## Native follow-on checklist

- [x] iOS: register a `presence` handler next to the existing bridges;
      heartbeat → Firestore `users/{uid}.lastSeen` server timestamp;
      friends → gather + call `window.onPresenceResult(...)`.
      (PresenceBridge in SWISH/SWISHApp.swift, v1.1 native pass.)
- [x] Android: same, via the WebView shim / `LiveManager`-style bridge.
      (PresenceManager + PresenceHandler in the Android shell, v1.1
      native pass; the shim advertises the `presence` handler name.)
- [x] Firestore rules: a signed-in user may write their own `lastSeen`
      and read their friends' user docs. Verified against
      firestore.rules in the same pass — no rules change needed: the
      users/{uid} update rule constrains only uid / username / stats /
      createdAt, so a merge-write of `lastSeen` (and `fcmTokens`) is
      already allowed, friend profiles are readable by any signed-in
      user, and the friends subcollection is owner-readable.
