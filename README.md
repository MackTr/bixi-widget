# BIXI Station Widget

A personal iOS home-screen widget showing live BIXI (Montréal bike share) availability
for one station, via the public GBFS feed (no API key).

Live feeds:
- Status: https://gbfs.velobixi.com/gbfs/en/station_status.json
- Info:   https://gbfs.velobixi.com/gbfs/en/station_information.json

## ⚠️ Toolchain requirement

The source uses iOS 17 / Swift 5.5+ APIs (`containerBackground`, `foregroundStyle`,
`async let`). **Update Xcode to the latest from the App Store** before building — the
Xcode 12.3 currently on this machine cannot compile or run this.

## Source files (ready to drop in)

```
Shared/BixiAPI.swift          Codable GBFS models + fetch/join service  → BOTH targets
Shared/StationSnapshot.swift  Render struct                             → BOTH targets
BixiWidget/BixiWidget.swift   @main widget + TimelineProvider + view    → widget target
BixiWidgetApp/ContentView.swift  Host-app note screen                   → app target
```

## Wiring it up in Xcode (GUI steps — can't be scripted here)

1. **New Project** → iOS → App. Name `BixiWidgetApp`, SwiftUI, Swift. Save in this folder.
2. **File → New → Target → Widget Extension**, name `BixiWidget`. Uncheck "Include
   Configuration Intent". Activate the scheme when prompted.
3. Drag the files above into the project. For the two `Shared/` files, in the File
   Inspector check **both** `BixiWidgetApp` and `BixiWidget` under Target Membership.
4. Only one `@main` per target — `BixiWidget.swift` already declares `@main`. If Xcode
   generated a `BixiWidgetBundle` with its own `@main`, delete that file (or move the
   `@main` and register `BixiWidget()` inside the bundle).
5. **Pick your station:** open `station_information.json`, find your station's
   `station_id`, and set `MY_STATION_ID` at the top of `BixiWidget.swift`.

## Run on device

- Select the host-app scheme + your iPhone → Run once.
- Signing & Capabilities → Team = your personal Apple ID; unique bundle IDs per target.
- On the phone: Settings → General → VPN & Device Management → trust your dev cert.
- Long-press home screen → + → search "BIXI Station" → add it.

> Free signing means re-running from Xcode every 7 days. AltStore/SideStore or a paid
> Apple Developer account avoids that.
