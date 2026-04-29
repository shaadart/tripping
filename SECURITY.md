# Security and private data

Tripping records private journeys. Publish source and synthetic demonstrations;
keep personal journeys, invitation links and service state outside Git.

## Local configuration

Recording, history, maps and routing build without Firebase. Group sharing
needs your own Firebase project; see [configuration](docs/CONFIGURATION.md).
Firebase client API keys, project IDs, Android package IDs and service URLs
identify public clients. They are not administrative credentials or an access
control boundary. The repository keeps per-developer client configuration
local so a checkout does not accidentally use somebody else's service.

Never commit service-account private keys, authentication/refresh tokens,
signing keystores/passwords, invitations or their derived encryption keys.
An invitation grants access to the group. Anyone receiving it can forward it.
Use a new group/invitation if a link is disclosed; deleting a historical copy
does not revoke an invitation or credential.

## Group trust model

The invite has 128 random bits. HKDF-SHA256 derives the relay room and
AES-256-GCM key with separate labels. The room name is a bearer join
capability, distinct from the decryption key. The server can observe room
names, membership, timing and traffic, but receives sealed names/positions.
Knowing the room name alone does not reveal the encryption key.

Firebase Authentication and [database rules](firebase/database.rules.json)
control membership reads and writes to each anonymous UID's own slot.
Ciphertext associated data includes the sender UID, so copying a box to a
different slot fails authentication. Members share one encryption key: this
does not provide independent cryptographic identity against another group
member who knows that key. Source code and derivation labels are public;
security depends on secret key material and deployed rules.

Use only the documented rule test/deployment procedure. Passing local tests
does not deploy rules or prove the currently running server has them. A
connection is not proof that another phone received or saw a position.

## Data on the phone

The app's private SQLite database contains tracks, destinations, recent
places, waypoints and group invitation secrets. It is not an encrypted
application database; access relies on Android's app sandbox and device
storage protection. Debug builds also write a raw-fix log. Do not publish
database copies, WAL/SHM files, logs, map-cache databases or personal GPX.

Android backup is disabled. Android 12+ extraction rules explicitly exclude
all app storage domains from cloud backups and device transfer; older
versions use `allowBackup=false` and `fullBackupContent=false`. This policy
instructs supported automatic backup/transfer paths to exclude journey and
invite data. Host checks validate the manifest and exclusion XML; actual
device/OEM transfer behaviour has not been verified. It does not protect a
rooted phone or a debug build accessed with
`run-as`, and it does not recall backups made by older builds. See
[Android's backup documentation](https://developer.android.com/identity/data/autobackup)
for the distinction between cloud backup and device transfer.

Existing journeys are not deleted or migrated by this policy. Export wanted
journeys yourself before uninstalling or replacing the phone; GPX exports
contain location history. iOS backup, linking and group setup are not yet
verified and are not covered by Android's policy.

## Before publication

Run `./tool/check.sh`. It includes the disclosure guard and synthetic
regressions. The guard checks both the Git index and tracked/nonignored
working files, so cleaning a working file cannot hide an older staged secret.
Use `python3 tool/disclosure_check.py --staged` before committing, or
`python3 tool/disclosure_check.py --tree HEAD` for a committed snapshot.
The guard reports category/path/line without printing matched contents.

The guard blocks databases/location exports, local configuration, signing
artifacts, private directories, unreviewed binaries, recognisable private
key/token forms and literal invitations. Known image directories are allowed
so actual app screenshots can be published after review. Manually inspect
every image, metadata and synthetic fixture's provenance: pattern matching
cannot identify every secret or tell a fictional coordinate from a real one.
Ignore rules do not remove already tracked files or historical copies.

If private data was tracked, preserve the owner's original privately, remove
the publication copy, rotate/revoke affected credentials, and verify an
isolated history rewrite before changing references. Published references
need explicit owner authorization before replacement. Remote clones,
downloaded artifacts, caches and backups cannot be recalled by a Git rewrite.

## Current external follow-up

A repository audit found unrelated PocketBase database state in an earlier
snapshot. Its authentication material must be treated as disclosed if that
snapshot left a trusted machine. The affected service owner should change
the superuser password and revoke/rotate its session/token material, then
review access. The local originals are preserved. No service credential was
rotated by editing this repository, and no secret values belong in an issue,
PR, report or chat. The Android upload key was not identified in tracked
history; do not rotate it merely because public client configuration exists.
