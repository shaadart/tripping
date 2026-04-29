# Build and configuration

## Standalone Android build

Install Flutter 3.38 / Dart 3.10, the Android SDK and a JDK 21 discoverable by
Gradle. Python 3.10+ is used by the repository's disclosure checks. From a
fresh checkout:

```sh
flutter pub get
./tool/check.sh
flutter build apk --debug
```

Flutter generates local SDK configuration. No Firebase, signing key,
database dump or personal journey is required. Recording, history and maps
work without group configuration; sharing reports that it is not set up.
Map tiles, place search and new routes require their respective networks.
Before public distribution, arrange suitable Photon/Valhalla hosting and
review map-provider terms. Override endpoints at build time:

```sh
flutter run --dart-define=TRIPPING_SEARCH_URL=https://search.example.invalid \
  --dart-define=TRIPPING_ROUTING_URL=https://routing.example.invalid
```

The `.invalid` addresses are placeholders, not working public services.
Do not put service credentials in endpoint query strings or build flags.

## Optional Firebase group relay

1. Create/select your own Firebase project and register the Android package
   `com.shaadart.tripping`.
2. Enable anonymous Authentication and create a Realtime Database. Keep
   initial database access denied while configuring it.
3. Download that Android app's client configuration as
   `android/app/google-services.json`. The tracked
   [example](../config/firebase.example.json) documents its shape only; use
   the console's actual download, not placeholder values. The real file is
   ignored.
4. Run `./tool/check_firebase_rules.sh` with Node.js/npm and JDK 21 on PATH.
   It uses a demo project and local emulators, without your live project or
   credentials. Follow [the rule test/deployment instructions](../firebase/README.md)
   to deploy [the checked-in rules](../firebase/database.rules.json) to your
   own project. Verify denial and member-only access before sharing a build.
   A local rule edit does not change the hosted database.
5. Rebuild. Do not supply a service-account key to a mobile application.

Review Firebase client-key API/application restrictions and project abuse
controls for your deployment. A client API key is public identification;
database rules and authenticated membership enforce authorisation. Service
accounts and private signing keys belong only on trusted infrastructure.

The supplied platform project is Android-first. iOS has no equivalent
Firebase/link/background verification yet; a Mac and iPhone are required
before claiming parity.

## Optional release signing

Debug builds need no signing setup. Keep your upload keystore outside the
checkout. Copy [key.properties.example](../android/key.properties.example)
to ignored `android/key.properties`, replace its placeholders locally and
restrict both files to the owner:

```sh
chmod 600 android/key.properties /absolute/path/outside/repository/upload.jks
```

Back up the keystore/passwords securely outside Git. With no `key.properties`,
the current Gradle setup signs a release build with the development debug
key so a clean checkout remains buildable; that build is not a store release.
Inspect the actual signing certificate before uploading a release artifact.

## Publication checks

`./tool/check.sh` runs disclosure regressions, scans the index and working
publication candidates, checks Dart formatting, analyses the app and runs
host tests. Device GPS, background operation, services, wake locks, battery
and native map rendering require separate device evidence.

Use fictional participants and in-app synthetic location builds for demos.
Keep `pb_data/`, private backups, journey databases, exports and raw logs
outside the publication set. See [SECURITY.md](../SECURITY.md) for the trust
model, storage limits, manual image review and exposed-credential follow-up.
