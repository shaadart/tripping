# Android pause probe

`pause_probe.dart` is a test-only Flutter entrypoint, using the actual recorder,
record screen, map and Firebase relay. It saves synthetic Cubbon Park positions
and the fictional name Ravi. With `PAUSE_PROBE_NATIVE=true`, it additionally
opens the real native location service but **discards every native fix**; those
fixes never enter the journey, sharing or logs. It does not use `RawFixLog`.

Use a separate scratch checkout with applicationId
`com.shaadart.tripping.pausecheck` and label `Tripping Pause Test`. Never install
this over a personal Tripping installation. Do not copy owner Firebase config,
signing configuration or databases. Obtain permission before interrupting an
owner's phone or rebooting it.

For the scratch build only:

1. Copy `tool/android/PauseProbeReceiver.kt` into the Kotlin source directory.
   Add this receiver inside the scratch main manifest's application:
   `<receiver android:name="com.shaadart.tripping.PauseProbeReceiver" android:exported="true" />`.
   This exported diagnostic receiver must never enter a production manifest.
2. Use the existing network security config: it already permits 127.0.0.1
   for the offline-map style server, so local emulators need no production
   network-policy change. The probe disables automatic Android emulator host
   mapping; USB forwards connect to 127.0.0.1, not 10.0.2.2.
3. Start Auth (9099) and Database (9000) emulators with project
   `demo-tripping-rules`, using `firebase/database.rules.json`. Both listen on
   127.0.0.1. Forward each with `adb reverse tcp:PORT tcp:PORT`.
4. Build with `flutter build apk --debug --target-platform android-arm64
   --target tool/pause_probe.dart --dart-define=PAUSE_PROBE_NATIVE=true`.
   Install only the distinct test package; grant its location and notification
   permissions. Open its activity **before** sending a start/resume command.
   Android refuses background foreground-service startup; restart the test
   process after such a refusal.

Send commands with:

```sh
adb shell am broadcast --receiver-foreground \
  -n com.shaadart.tripping.pausecheck/com.shaadart.tripping.PauseProbeReceiver \
  --es command sample
```

Commands: `start`, `pause`, `resume`, `pauseSharing`, `resumeSharing`, `end`,
`sample`. Samples contain only the test process CPU/network counters, foreground
service count, journey UUID/status, segment count and saved fix count, plus Auth identity-presence/equality booleans.
The diagnostic receiver inspects Auth 25.0.0's task fields to report whether a
refresh Runnable is pending. This **test-only** reflection never reads tokens,
never enters production code and returns null if the SDK layout is unknown;
null is not evidence that a task stopped. Production GroupAuth uses only
public user-transfer/sign-out APIs and Firebase private persistence. Native
system dumps must be filtered in memory to this test UID/package; never save or
print a raw location dump. Distinguish current registrations from historical
location events, and current wake locks from power-service history.

Verify recording activity first, then sharing-only pause, then full pause.
Also send Home and reopen the paused app: native background detectors can
re-arm work on foreground return. Both Auth refresh counters must stay false.
Allow outstanding traffic to drain before measuring full pause. Compare UID
RX/TX bytes, CPU milliseconds, current location registrations, foreground
services, wake locks, saved fixes and emulator presence sequence/timestamp over
an explicitly measured interval. Sampling itself causes some CPU activity.

Force-stop only the test package, reopen its activity and confirm the same
paused UUID/fixes/segments. After an authorised reboot, recreate USB forwards,
open the activity and check again. Explicit resume must add one segment without
changing UUID. Restore original Location settings, remove only these forwards
and this test package, and stop the local emulators. A short device soak does
not establish two, three or five actual days of suspension or battery life;
`test/recording/paused_recovery_test.dart` covers those durations with an
injected clock and real host subprocess SIGKILL.
