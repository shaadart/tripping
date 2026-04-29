# Identity screen and native marker probe

Use a separate scratch copy and applicationId
`com.shaadart.tripping.identitycheck`, labelled `Tripping Identity Test`.
Do not copy personal databases, signing configuration or Firebase client files.
Never install this entrypoint over a personal Tripping app.

Use the scratch-only receiver setup in [PAUSE_PROBE.md](PAUSE_PROBE.md), but
build `--target tool/identity_probe.dart`. No Firebase emulators, native sensor
probe or location permission are needed: positions are generated at a public
park, participants are fictional and the relay is in memory. Sharing on a live
server is not demonstrated by this fixture.

Complete the actual welcome screen, e.g. Ravi Mehta / River / Gate. Use the
person button on the map to reopen the same editor. The scratch receiver takes
commands through `tripping/pause_probe`:

```sh
adb shell am broadcast --receiver-foreground \
  -n com.shaadart.tripping.identitycheck/com.shaadart.tripping.PauseProbeReceiver \
  --es command start
```

Commands: `start`, `pause`, `resume`, `end`, `sample`, `companions` (while
recording), `light`, `dark`, `sun`, `largeText`, `normalText`, `offline`.
`companions` reuses its synthetic membership and places Asha, Meera, Noor and
Tom around the newest simulated fix. Ages include live, aging and stale data.
`largeText` applies 200% scaling only inside the test app, preserving global
phone preferences. Native marker PNGs must use the actual device pixel ratio.

Check the foreground app, floating/PiP windows and active audio/calls before
EVERY tap/capture; stop immediately if private content could be captured.
Use only fictional identities and synthetic positions. On a personal phone,
obtain availability confirmation before interactive checks. Force-stop/reopen
only the test package to verify identity and paused-journey recovery. End the
synthetic journey, uninstall only this package, and remove its temporary UI
dumps after verification. The diagnostic receiver is never declared in the
production manifest. Do not commit test databases or private screenshots.
