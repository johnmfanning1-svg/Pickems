# Debugging Pickems

## Console.app

1. Run the app from Xcode on a device or simulator.
2. Open **Console.app** → select the device → start streaming.
3. Filter:
   - Subsystem: `FannypackInc.Pickems` (or the app bundle id)
   - Category: `auth`, `onboarding`, `session`, `events`, `firestore`, `network`, `notifications`, `picks`

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

## Crashlytics

Non-fatal errors are recorded with a `pickems_code` matching the `AppEvent` raw value (for example `auth.sign_in_failed`). Breadcrumbs mirror the same event stream.

Enable Crashlytics in Firebase Console and ensure the Xcode target links **FirebaseCrashlytics** (already added to the Pickems target). Add the Crashlytics run script build phase for dSYM upload before shipping release builds.
