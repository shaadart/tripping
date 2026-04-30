# Map presentation probe

Build `tool/map_probe.dart` in a separate scratch copy with applicationId
`com.shaadart.tripping.mapcheck`, label `Tripping Map Test`. Use the test-only
receiver setup in [PAUSE_PROBE.md](PAUSE_PROBE.md). Never install this fixture
over a personal Tripping app. Do not copy private configuration or databases.

The fixture uses the actual RecordScreen, JourneyMap, TrackMap, Settings and
Recorder with existing store APIs. All points and routes are authored synthetic
geometry around a public park, and Ravi Mehta / Cedar Camp / Rest stop / Lookout
are fictional. A FakeLocation stream and fake system facts replace sensors and
notification settings; these screens do not establish real GPS, service or
notification behavior. No Firebase, search, routing service or live group is
used. Native basemap/terrain tiles can download while the fixture is online.

Send scratch receiver commands as in the identity/pause probe:

```sh
adb shell am broadcast --receiver-foreground \
  -n com.shaadart.tripping.mapcheck/com.shaadart.tripping.PauseProbeReceiver \
  --es command dark
```

Commands: `road`, `expedition`, `light`, `dark`, `sun`, `precise`, `approximate`,
`history` (ends the selected synthetic journey), `straight`, `pause`,
`largeText`, `offline`, `end`. `precise`/`approximate` deliver one synthetic fix;
they are not a continuous native location feed. Ages continue to advance.

Inspect shared route/track sections, a self-crossing, out-and-back ground, two
separate recorded segments, all point symbols, actual sprite density and map
key. History uses a real ended fixture and distinguishes finish from intended
destination. After history use the other mode for remaining live checks.
`offline` deliberately replaces only this test app's local style files with an
empty basemap, disables its map networking and recreates the recording view.
Wait for the actual blank-map note. This injects missing tiles; it is not proof
of an actual radio/network outage. Reinstall this test package to restore maps.

Check foreground package, floating/PiP windows and call/audio mode before every
tap/capture. Stop if the phone becomes occupied. Do not capture other apps or
personal journeys. End synthetic journeys with `end`, uninstall only this test
package and delete its temporary UI dump. Never declare the exported diagnostic
receiver in the production manifest. Host tests and these seeded renderings do
not replace outdoor sunlight, real GPS, long battery or TalkBack checks.
