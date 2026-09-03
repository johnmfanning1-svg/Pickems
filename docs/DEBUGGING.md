# Debugging Pickems

## Console.app

1. Run the app from Xcode on a device or simulator.
2. Open **Console.app** → select the device → start streaming.
3. Filter:
   - Subsystem: `FannypackInc.Pickems` (or the app bundle id)
   - Category: `auth`, `onboarding`, `session`, `events`, `firestore`, `network`, `notifications`, `picks`

## Instant launch crash (TestFlight)

A healthy cold launch always logs `app.launch` before any auth work. If the process dies with **no** `app.launch` line:

1. Firebase never finished configuring — confirm `GoogleService-Info.plist` is in the app bundle (Target → Build Phases → Copy Bundle Resources).
2. `Messaging.messaging()` must not run before `FirebaseApp.configure()`. Auth / Messaging / Firestore clients are started from `AppState.configure()` after bootstrap.
3. `UNUserNotificationCenter` delegates must use the **completion-handler** APIs. The `async` variants trap under Swift 6 / `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` when UserNotifications calls back off-main.
4. Watch companion must declare `WKApplication = YES` (see `PickemsWatch/Info.plist`).

Delete + reinstall does **not** clear the Firebase Auth keychain for the same team/bundle. A “fresh” install can still restore a session and run `onAuthStateReady` immediately.

## Auth / onboarding trail

A healthy first-run sequence looks like:

```
app.launch
auth.state_changed { signed_in=true }
auth.sign_up_succeeded | auth.sign_in_succeeded | auth.apple_succeeded
auth.profile_loaded
session.bootstrap_ready { needs_onboarding=true }
root.destination_changed { to=onboarding }
onboarding.join_succeeded | onboarding.create_succeeded
onboarding.marked_complete
root.destination_changed { to=main }
favorite_team.prompt_presented
```

If the UI stays on Sign In after a “successful” tap, look for:

- Missing `root.destination_changed` after `auth.*_succeeded` → observation / `isSignedIn` issue
- `auth.*_failed` with no on-screen message → UI not binding `errorMessage`
- `auth.epoch_stale_ignored` → race between sign-out and profile load

## Repeated crashes after login

Device Crashlytics is not readable from this cloud environment without Firebase Console auth. On device:

1. Filter Console.app for `session.on_auth_ready_begin` / `session.on_auth_ready_complete`.
2. A begin without a matching complete (and without `superseded`) means setup stalled or the process died mid-bootstrap.
3. Look for `auth.*_failed`, `groups.listener_error`, `session.bootstrap_failed`, or Crashlytics non-fatals with `pickems_code`.
4. Custom Crashlytics keys set after login: `is_signed_in`, `needs_onboarding`, `favorite_team_id`, `group_count`.

Overlapping login callbacks (Sign In button + `isSignedIn` onChange) are serialized with an `authReadyGeneration` counter / single-flight task so stale work cannot finish out of order.

## Favorite team contrast

Team palettes no longer use raw primary colors as accents. `ThemePalette.from(team:)` picks the primary/secondary with the best WCAG contrast on the dark background (and lightens if needed). Auburn therefore accents with orange (`#E87722`) instead of navy (`#0C2340`). Solid fills use `theme.onAccent` for label color.

When a theme applies you should see:

```
theme applied { team=AUB, accent_hex=#E87722, accent_contrast=… }
```

## Crashlytics

Non-fatal errors are recorded with a `pickems_code` matching the `AppEvent` raw value (for example `auth.sign_in_failed`). Breadcrumbs mirror the same event stream.

Enable Crashlytics in Firebase Console and ensure the Xcode target links **FirebaseCrashlytics** (already added to the Pickems target). The Pickems target runs `Crashlytics/run` after linking so Release/Archive dSYMs upload for symbolication. `ENABLE_USER_SCRIPT_SANDBOXING` is on; the phase lists `GoogleService-Info.plist` and the dSYM paths as inputs.
