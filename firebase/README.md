# Group relay rules

Group sharing is optional. Recording, history and maps work without Firebase.
See [configuration](../docs/CONFIGURATION.md) to connect your own project.

## Test locally

Install Node/npm, Python 3 and Java 21, with Java 21's `java` on PATH. Run:

```sh
./tool/check_firebase_rules.sh
```

The runner downloads the pinned Firebase CLI and emulator binaries on first
use. It copies the checked-in rules to a temporary directory and starts only
the Authentication and Realtime Database emulators, bound to loopback, under
the fixed `demo-tripping-rules` project. The tests refuse nonlocal emulator
addresses. They never read your Firebase configuration or use a production
account. The CLI receives a minimal environment and a separate XDG config
directory; temporary logs are removed when the command exits.

The suite exercises unauthenticated/nonmember denial, room listing denial,
own-UID membership and publication, shape/size/timestamp/sequence validation,
the server's two-second write interval, creator departure, stale-entry cleanup
and legacy closed rooms. Age-expiry tests seed old synthetic records in the
emulator; they do not demonstrate a real day passing.

## Deploy deliberately

Local tests do not update a deployed database. In your Firebase project:

1. Enable Authentication's Anonymous provider and create a Realtime Database.
2. Open that database's **Rules** tab. Review and paste the complete contents
   of [database.rules.json](database.rules.json), then publish them.
3. Confirm you selected the database used by your own client configuration.
   Review its deployed rules again; local files cannot prove remote state.
4. Run a synthetic group between test devices to check the application's
   authentication, membership and publication after deployment. Do not use
   a personal journey or share an invitation in logs or issue reports.

Only a known room's capability name permits self-joining; anonymous sign-in
alone never lists rooms or reads a room before joining. Room names and message
encryption keys are separately derived from the invitation secret. The rules
enforce member reads and own-UID writes; authenticated encryption binds a box
to the UID slot and encrypts the name and saved position. No cryptographic
security depends on hiding these source files.

The old `s1` measurement namespace is denied by this ruleset. To repeat the
historical transport spike, use a separate test project and intentionally
reviewed temporary rules rather than opening a production namespace.

## Limits

- A leaked invite or room name is a bearer join capability. A room name alone
  does not reveal the decryption key, but it must still be kept private.
- A shared group key and UID-associated data do not establish independent
  identity against another key holder. Firebase authorization is the
  boundary that prevents a member writing in another UID's slot.
- Sequence values must be positive safe integers. They are not required to
  increase across process restarts, and the relay's `seq` and `at` are not
  trusted for ordering. Each sealed message carries a random per-run session
  and a counter, plus the sender's send time; receivers accept a higher
  counter in the same session, or a new session sent later by the sender's
  own clock, and refuse unsessioned messages once a sender has used
  sessions. A replayed old box is therefore ignored even with a new relay
  timestamp. A sender whose clock is set back is not heard until it passes
  its previous send time.
- Position age is measured on the sender with one clock (when the fix
  reached the phone to when it was sent), so a disagreement between the
  phone's wall clock and GNSS time does not change it.
- The current retention sweep runs on members' phones; there is no server
  expiry task. An unopened room can remain stored.
- Rules and per-UID write spacing do not prevent all anonymous-account or
  quota abuse. Review API restrictions, project quotas and App Check for a
  public deployment, without assuming that a hidden client API key grants
  authorization.

Firebase's [API-key guidance](https://firebase.google.com/docs/projects/api-keys)
distinguishes client project identifiers from administrative credentials.
The [Realtime Database rule language](https://firebase.google.com/docs/database/security/core-syntax)
and [emulator documentation](https://firebase.google.com/docs/emulator-suite/connect_rtdb)
describe the authorization and local-testing boundaries used here.
