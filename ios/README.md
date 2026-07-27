# Ground to Growth Connect iOS App

Native SwiftUI iPhone app for privacy-first location tracking, connecting to the Ground to Growth Connect backend.

## Requirements

- Xcode 16+ (full Xcode app, not Command Line Tools only)
- iOS 17+ device or simulator
- Backend running (see root `README.md`)

## Open in Xcode

```bash
open "ios/Ground to Growth Connect.xcodeproj"
```

1. Select your **Development Team** in Signing & Capabilities (Target → Ground to Growth Connect → Signing)
2. Choose an iPhone simulator or connected device
3. Press **Run** (⌘R)

## Backend URL

| Environment | API URL |
|-------------|---------|
| Simulator | `http://127.0.0.1:3001` (default) |
| Physical device | `http://YOUR_MAC_LAN_IP:3001` |

Set this in the app under **Settings → API base URL**. Your Mac and iPhone must be on the same network.

## Features

- **Keychain storage** — auth token encrypted at rest on device (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **Consent flow** — full disclosure, grant/revoke, audit log synced to SQL backend
- **15-minute reports** — Core Location with ~100m accuracy, rate-limited client-side
- **Background location** — enable "Always" in iOS Settings for reports when app is backgrounded
- **Map tab** — MapKit view of latest consented user locations

## Privacy permissions

The app requests location only **after** you tap "Grant consent". Info.plist includes:

- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- Background mode: `location`

## App Store notes (future)

Before App Store submission you'll need:

- App icon (1024×1024) in `Assets.xcassets/AppIcon`
- Privacy nutrition labels describing location collection
- HTTPS backend (ATS will block plain HTTP in production)
- Apple Developer Program membership for device testing beyond personal team limits
