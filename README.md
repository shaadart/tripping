# Tripping

Offline-first road journeys and expeditions, with honest awareness of where
your companions are.

Status: early development. Journeys are stored durably on the device; the
recording, map and group features are being built in small, verified
increments.

## Development

Requires Flutter 3.38 (Dart 3.10).

```sh
flutter pub get
./tool/check.sh          # format, analyze, test: the gate for every change
```

After editing `lib/journey/schema.drift` or any drift table, regenerate code:

```sh
dart run build_runner build --force-jit
```

`--force-jit` is required: sqlite3 bundles SQLite through Dart build hooks,
which build_runner's default AOT compilation does not support.
