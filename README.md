<p align="center">
  <img src="ios/Branding/logo.svg" alt="Clockwise logo" width="60">
</p>

# Clockwise

A lightweight time and attendance tracker designed to prevent accidental early clock-outs and salary shortfalls.

Clockwise notices when you arrive at the office, records that as your time in, and tells you exactly when you can time out (time in + 9 hours). It reminds you before your time out and warns you if you leave early.

## Features

- **Automatic time in:** set your office once, and your first arrival each day is recorded as your time in, even when the app is closed. Coming back from lunch doesn't overwrite it.
- **Time in delay:** entering the radius isn't the same as reaching the time clock, so the time in is recorded a few minutes after you enter. The default grows with the radius (8 min for 100 m, 13 min for 500 m); you can set your own and reset it to the default.
- **Time out countdown:** the Today screen shows your time in, time out, and a live countdown.
- **Confirming your time out:** leaving the office area is saved as an unconfirmed time out. On Today, tap **Confirm time out…** to choose when you left (it starts at the detected departure time), or **Time out now** to use the current time. You can undo it or edit the time afterwards. In History, tap a day without a time out to choose its time, or use **Select** (checkboxes, Select All) to confirm or delete several at once.
- **Reminders:** banners 30 minutes and 3 minutes before your time out.
- **Early-out warning:** if you leave the office area before your time out and stay away for 15 minutes, you get a banner. Tapping it asks whether you really timed out or just stepped out, so a quick coffee run is never recorded.
- **Office setup:** search for your office by name or address, tap the map, or use your current location, then choose the detection radius (100–500 m; smaller areas aren't detected reliably while the app is closed).
- **Reliable background detection:** iOS region monitoring wakes the app when you arrive or leave. iOS visit tracking acts as a backup with your real arrival time, and a time in that could only be noticed when you opened the app is marked as estimated.
- **Office detection from your routine:** after 3 workdays at the same place (arriving in the morning or early afternoon and staying 4+ hours), Clockwise suggests it as your office. Nothing changes until you confirm.
- **Widget:** Home Screen and Lock Screen widget showing today's time in, or "Away from office".
- **Shortfall summary:** total shortfall for this week, the last 2 weeks, the current cutoff (1st–15th or 16th–end of month), or this month, with arrows to check earlier periods. Early departures you haven't answered appear in History as the day's time out with an "Unconfirmed" badge; confirm or delete them one at a time by swiping, or several at once with Select (checkboxes and Select All). Today shows a warning when the current period has a shortfall.
- **History:** past days with time in, time out, and any shortfall.
- **Manual fallback:** "I'm in now" and "Edit time in" for days when detection misses.

## Privacy and data usage

Everything stays on your phone. There is no account, no server, and no analytics. Arrival detection uses GPS, nearby Wi-Fi and cell towers without needing mobile data or a Wi-Fi connection. Only the map and address search on the Office tab use the internet.

## Project structure

```
ios/
  project.yml            XcodeGen project definition (the .xcodeproj is generated, not committed)
  Clockwise/             iOS app (SwiftUI, SwiftData, Core Location, UserNotifications)
    Models/              WorkDay, OfficeLocation, Visit + office detection
    Services/            OfficeMonitor (geofence, visits), NotificationScheduler
    Views/               Today, Office, History tabs
  ClockwiseWidget/       WidgetKit extension
  Shared/                Data shared between the app and widget (App Group)
  ClockwiseTests/        Unit tests
  Branding/              Logo SVG and app icon renderer
```

## Getting started

Requirements: Xcode 16 or later, iOS 17+ device, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd ios
xcodegen generate
open Clockwise.xcodeproj
```

1. Select your iPhone and press **Cmd+R**. Signing uses the team in `project.yml` (`DEVELOPMENT_TEAM`); change it and the bundle ID prefix if you use a different Apple account.
2. Allow location **Always** and **Notifications** when asked.
3. Open the **Office** tab, place your office, and tap **Save office**.

Run the unit tests with **Cmd+U** (on a device or an iOS Simulator).

### Testing without going to the office

- **Reminders:** tap **Edit time in** and set it to about 8.5 hours ago; the 30-minute banner fires shortly after.
- **Early-out warning:** while running from Xcode, use **Debug > Simulate Location** to pick a far-away city, then wait 15 minutes.

### Regenerating the app icon

Edit the shapes in `ios/Branding/render-app-icon.swift` (they mirror `logo.svg`), then from `ios/` run:

```bash
swift Branding/render-app-icon.swift
```
