# LiveBuy iOS SDK

Embed live shopping experiences — live streams, replays, and shoppable VODs — directly into your iOS app.

---

## Requirements

| | Minimum |
|---|---|
| iOS | 14.0 |
| Xcode | 15.0 |
| Swift | 5.9 |

---

## Installation

### Swift Package Manager (Xcode UI)

1. In Xcode, go to **File → Add Package Dependencies…**
2. Paste the repository URL:
   ```
   https://github.com/livebuy/livebuy-ios-sdk
   ```
3. Select **Up to Next Major Version** starting from `1.0.0`
4. Add **LiveBuySDK** to your target

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/livebuy/livebuy-ios-sdk", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["LiveBuySDK"]
    )
]
```

---

## Getting Started

### 1. Configure the SDK

Call `configure` once at app launch, before any SDK feature is used.

```swift
// AppDelegate.swift
import LiveBuySDK

func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    LiveBuySDK.configure(
        apiKey: 12345,          // Int — provided by LiveBuy
        secret: "your-secret"   // String — provided by LiveBuy
    )
    return true
}
```

To attach a logged-in user so their name appears in chat:

```swift
LiveBuySDK.configure(
    apiKey: 12345,
    secret: "your-secret",
    lang: "en",                              // optional language override
    user: LBUser(displayName: "Alice", avatarUrl: nil)
)
```

### 2. Present the Player

```swift
import LiveBuySDK

let player = LiveBuyPlayerViewController()

// Handle product taps from the player
player.onProductTap = { product in
    print("Tapped:", product.name, product.goodsGpn)
    // Navigate to your product detail page
}

present(player, animated: true) {
    player.load(videoId: "abc123")
}
```

### 3. Embed a Widget

```swift
import LiveBuySDK

let widget = LiveBuyWidget(shopId: "shop-001", mode: .carousel)
widget.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(widget)

NSLayoutConstraint.activate([
    widget.leadingAnchor.constraint(equalTo: view.leadingAnchor),
    widget.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    widget.heightAnchor.constraint(equalToConstant: 300)
])
```

---

## SDK Reference

### LiveBuySDK

The main entry point. Must be configured before any other SDK call.

#### `configure(apiKey:secret:lang:user:)`

```swift
static func configure(
    apiKey: Int,
    secret: String,
    lang: String? = nil,
    user: LBUser? = nil
)
```

| Parameter | Type | Description |
|---|---|---|
| `apiKey` | `Int` | Your LiveBuy API key. Provided by LiveBuy as an integer. |
| `secret` | `String` | HMAC signing secret. Keep this value private; do not expose it in client-side code that can be extracted. |
| `lang` | `String?` | Override the display language. See [Localization](#localization) for supported codes. If `nil`, the language from the API response is used, falling back to `zh-TW`. |
| `user` | `LBUser?` | Logged-in user identity. `displayName` is shown in the live chat. If `nil`, the SDK generates a guest identity (`Guest_XXXX`). |

#### `clearUser()`

```swift
static func clearUser()
```

Clears the in-memory `displayName` and `avatarUrl`. Call this when the user logs out of your app — subsequent chat messages will appear as `Guest_XXXX` until `configure` is called again with a new user.

---

### LiveBuyPlayerViewController

A full-screen `UIViewController` that plays live streams, replays, and VODs. Handles buffering, PiP, background audio, polling, and product overlays automatically.

#### Configuration Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `showChat` | `Bool` | `true` | Show the live chat overlay |
| `showProducts` | `Bool` | `true` | Show the product list panel |
| `enablePiP` | `Bool` | `true` | Enable Picture-in-Picture when the user backgrounds the app |
| `autoDismissDelay` | `Int` | `5` | Seconds to wait on the end screen before auto-playing the next video |

#### Callbacks

Set these before calling `load(videoId:)`.

```swift
// Player state changed
player.onStateChange = { state in
    // state: LBPlayerState (.loading, .buffering, .playing, .paused, .ended, .error)
}

// User tapped a product in the overlay
player.onProductTap = { product in
    // product: LBProduct — open your product detail screen
}

// New poll data arrived (chat messages, rush events, live-end signal)
player.onPollReceived = { response in
    // response: LBPollResponse
}

// An error occurred
player.onError = { error in
    // error: LBError
}
```

#### Methods

| Method | Description |
|---|---|
| `load(videoId: String)` | Fetch channel metadata and start playback. Clears any existing video token. Safe to call multiple times to switch videos. |
| `play()` | Resume playback. |
| `pause()` | Pause playback. |
| `setMuted(_ muted: Bool)` | Mute or unmute the player. The player starts muted; the first tap unmutes. |
| `seek(seconds: Double)` | Seek to a position in seconds. Only available for replays (`liveStatus == 3`). |
| `sendChat(message: String)` | Post a chat message to the live stream. |

---

### LiveBuyWidget

An embeddable `UIView` that shows a list or carousel of LiveBuy videos. Tapping a card opens the full-screen player automatically (or calls your `onVideoTap` handler if provided).

#### Carousel / Grid

```swift
// Horizontal scrolling carousel
let carousel = LiveBuyWidget(shopId: "shop-001", mode: .carousel)

// Infinite-scroll 2-column grid
let grid = LiveBuyWidget(shopId: "shop-001", mode: .grid)
grid.columns = 3   // optional: change column count

// Custom tap handler (overrides default player presentation)
carousel.onVideoTap = { video in
    print("Tapped:", video.id, video.title)
}
```

#### Floating Mini-Player

```swift
// Draggable floating widget anchored to a video
let floating = LiveBuyWidget(
    videoId: "abc123",
    mode: .floating,
    width: 225,    // optional, default 225 pt
    height: 400    // optional, default 400 pt
)

floating.onClose = {
    floating.removeFromSuperview()
}
```

#### Widget Modes

| Mode | Behaviour |
|---|---|
| `.carousel` | Horizontally scrolling card row with left/right arrow buttons. Suitable for embedding in a scroll view row. |
| `.grid` | Vertically scrolling grid with infinite pagination. Suitable for a dedicated video listing screen. |
| `.floating` | Draggable mini-player for a single video, anchored to a corner of its container. |

#### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `columns` | `Int` | `2` | Column count in `.grid` mode |
| `floatingWidth` | `CGFloat` | `225` | Width of the floating window in points |
| `floatingHeight` | `CGFloat` | `400` | Height of the floating window in points |

#### Callbacks

| Callback | Signature | Description |
|---|---|---|
| `onVideoTap` | `((LBVideoItem) -> Void)?` | Called when a card is tapped. If `nil`, the SDK presents `LiveBuyPlayerViewController` automatically. |
| `onClose` | `(() -> Void)?` | Called when the user closes a `.floating` widget. |

---

### Data Models

#### `LBUser`

```swift
LBUser(displayName: "Alice", avatarUrl: "https://…/avatar.png")
```

| Property | Type | Description |
|---|---|---|
| `displayName` | `String?` | Name shown in live chat |
| `avatarUrl` | `String?` | URL of the user's avatar image |

#### `LBPlayerState`

| Case | Description |
|---|---|
| `.loading` | Fetching channel metadata from the API |
| `.buffering` | Metadata received; waiting for enough stream data to begin |
| `.playing` | Stream is playing |
| `.paused` | Playback is paused |
| `.ended` | Stream ended; end screen is shown |
| `.error` | Unrecoverable error; `onError` is also fired |

#### `LBProduct` (key fields)

| Property | Type | Description |
|---|---|---|
| `id` | `Int` | Internal product ID |
| `goodsGpn` | `String` | Global product number (e.g. `"P456"`) — use this as the identifier to look up products in your catalogue |
| `name` | `String` | Display name |
| `price` | `Double` | Current price |
| `priceShow` | `String` | Formatted price string for display (e.g. `"NT$299"`) |
| `soldOut` | `Int` | `1` if sold out, `0` otherwise |
| `stock` | `Int` | Remaining stock count |
| `pic` | `String` | Primary image URL |

---

## Error Handling

```swift
player.onError = { error in
    switch error {
    case .invalidSignature:
        // The HMAC signature was rejected by the server.
        // Check that apiKey and secret are correct and that the device clock is accurate.
    case .signatureExpired:
        // The request timestamp is older than 600 seconds.
        // Ensure the device time is synchronised (NTP).
    case .videoNotFound:
        // The videoId does not exist or is not accessible with your API key.
    case .restricted:
        // The video is geo-restricted or the viewer does not meet access requirements.
        // Show an appropriate message and dismiss the player.
    case .chatRateLimited:
        // The user is sending chat messages too quickly.
        // Throttle your sendChat calls to at most one per second.
    case .networkError(let underlying):
        // A network-layer error occurred (no connectivity, timeout, etc.).
        // Inspect `underlying` for details; retry when connectivity is restored.
    case .serverError(let code, let message):
        // The API returned an unexpected error code.
        // Log `code` and `message` for debugging; display a generic error to the user.
    }
}
```

---

## Localization

The SDK UI is fully localised. The active language is resolved in this priority order:

1. **`lang` parameter** passed to `LiveBuySDK.configure(lang:)` — highest priority
2. **`lang` field** returned by the API for the current video/shop
3. **Fallback:** `zh-TW`

| Code | Language |
|---|---|
| `zh-TW` | Traditional Chinese (default) |
| `zh-CN` | Simplified Chinese |
| `en` | English |
| `ms-MY` | Malay |
| `id-ID` | Indonesian |

---

## Info.plist Requirements

### Background Audio

To allow the player to continue playing audio when the user backgrounds your app, add `audio` to `UIBackgroundModes`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

Or in Xcode: **Target → Signing & Capabilities → Background Modes → Audio, AirPlay, and Picture in Picture**.

### Picture in Picture

PiP works on iOS 14+ with no additional Info.plist entry. It is enabled by default (`enablePiP = true`). To disable it, set `player.enablePiP = false` before calling `load(videoId:)`.

> **Note:** PiP requires that Background Modes → Audio is also enabled, otherwise PiP will be silently unavailable.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

Copyright © LiveBuy. All rights reserved.
