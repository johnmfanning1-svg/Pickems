---
name: ship-ios
description: >-
  Ships Pickems to TestFlight and App Store review, and raises the
  Firestore minimumBuild force-update gate. Use when the user asks to bump a
  TestFlight build, archive, upload, submit for App Review, App Store Connect,
  ship an iOS release, force a minimum build, or force-update users.
---

# Ship Pickems (TestFlight, App Store, force-update)

Read the matching SOP before acting (repo root):

- TestFlight bump / archive / upload → `docs/TESTFLIGHT.md`
- App Review submit → `docs/APP_STORE.md`
- Force-update / `minimumBuild` → `docs/MINIMUM_BUILD.md`

## Gates

| User said | Do | Do not |
|--|--|--|
| bump / TestFlight / new build | Follow TESTFLIGHT.md | Submit for App Review or raise `minimumBuild` |
| submit / App Store review / Apple | Follow APP_STORE.md | Raise `minimumBuild` |
| force update / minimum build / force users onto a build | Follow MINIMUM_BUILD.md | Set it above the live App Store build |
| none of the above | Stop and ask | Ship or change the gate |

Never raise `appConfig/live.minimumBuild` unless the user explicitly asked. Ceiling is the **App Store** build (not TestFlight-only). Never set `resetRatingsRequest`. Never commit demo passwords. Never leave review credentials in `/tmp` JS files.

## Identity (do not rediscover)

| | |
|--|--|
| Bundle | `FannypackInc.Pickems` |
| Apple ID | `6785697079` |
| Team | `22A943P8SJ` |
| Firebase | `pickems-fb` |
| Connect | [iOS version](https://appstoreconnect.apple.com/apps/6785697079/distribution/ios/version/deliverable) |

App Store Connect work uses **Google Chrome** (logged-in iris). Cursor's browser cannot complete Apple login.

## Version numbers

Shipping targets (Pickems, PickemsWidget, PickemsWatch Debug+Release) share marketing + build. Convention: `3.2.3` ↔ `323`. Leave PickemsTests / PickemsUITests at `1.0`.
