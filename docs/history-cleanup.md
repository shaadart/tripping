# Prepare clean publication history

Older commits can restore a database removed from today's source. The
identified private artifacts are under `pb_data/`, introduced in `a4ec9fb`.
The original files belong to an unrelated service and must stay intact.

The current checkout has no configured remote, remote-tracking branches or
tags. That does not establish that it has never been shared. A connected
GitHub repository lookup found no matching repository in the current account;
other accounts, deleted repositories, archives and private copies remain
unknown. Treat publication status as unresolved until the owner confirms it.

## Before publication

The database contains authentication state. If it belongs to an active
PocketBase service, its owner must reset the affected superuser credential,
invalidate its tokens/sessions, and review service/API/storage/mail secrets
that were configured in any exposed copy. No credential values belong in
issues, logs, this document or AI context. Historical removal cannot revoke
credentials or erase copies someone already obtained. If the database is an
unused local development instance, record that closure/rotation decision
privately; do not overwrite the preserved original to simulate remediation.

Keep the protected backup until recovery is no longer needed. It contains
the original private data and must never be pushed, attached to a report or
included in an ordinary source archive. Copy it to a private encrypted backup
outside this machine before making any eventual destructive source rewrite.

## Isolated preparation

`tool/prepare_publication.py` is read-only by default:

```sh
python3 tool/prepare_publication.py
```

After committing and checking the source cleanup, create a new ignored
private directory. Supply the full reviewed source commit explicitly:

```sh
python3 tool/prepare_publication.py \
  --expected-head <full-reviewed-clean-commit> \
  --prepare .publication-private/reviewed-publication \
  --publication-ref refs/heads/main
```

The procedure refuses a dirty tracked tree/index, an unexpected HEAD, an
existing output, a shallow/alternate-object source, or an unignored output
inside the source. It never rewrites, prunes or moves source references and
does not contact a remote. It does the following within the private output:

1. Copies the complete Git directory independently, verifies every copied
   file by SHA-256, saves all original refs, and runs `git fsck`.
2. Creates and verifies an all-ref bundle, restores it independently and
   checks the restored refs. The full Git copy also retains reflogs and
   unreachable local objects that a reachable-ref bundle need not include.
3. Creates `candidate.git` with only selected publication refs. Internal
   Codex refs are excluded; some are direct tree refs rather than commits
   and can retain private artifacts outside branch history. Originals stay
   in the protected backup.
4. Uses Git's index-filter rewrite in the isolated candidate to remove
   `pb_data/` from every selected commit, retaining commit graph shape and
   unrelated content. Old candidate refs/reflogs/index and unreachable
   objects are discarded only after the original backup verifies.
5. Checks all candidate refs/objects, confirms excluded objects are physically
   absent, compares every rewritten commit tree against its original minus
   the excluded path, and runs `git fsck` again. `commit-map.json` and
   `verification.json` record the result without secret values.

Do not add branches or tags to publication without repeating preparation
and verification for those refs. This repository currently has no signed
commits or tags; future rewrites invalidate commit signatures, and annotated
or signed tags need a separately reviewed procedure. The helper currently
accepts commit-valued publication heads/tags and fails on other tag types.

Clone `candidate.git` into a separate clean directory to run the disclosure
guard, `./tool/check.sh`, rules emulator suite and Android build without local
Firebase/signing configuration. Compare its tree to the reviewed clean
source. Host checks are build/source evidence, not device or deployed-rule
evidence. A final source commit made after preparation requires a new output
and a repeated verification; do not silently publish a stale candidate.

The generated verification deliberately records credential rotation and
publication authorization as unconfirmed. Local preparation does not resolve
those external gates.

## Authorization and collaborator recovery

Obtain explicit authorization before changing any references already
published, force-pushing, or deleting remote references. First show the
concrete old/new reference map, verified candidate, backup location and
credential-remediation status. No push or remote deletion is part of the
helper or the current preparation work.

For an eventual approved replacement, agree a short write freeze with
collaborators. The least error-prone recovery is a fresh clone of the clean
publication. Keep unfinished work privately, inspect it for excluded data,
then reapply reviewed patches onto the clean clone. Do not merge an old
branch into the new history or push old tags/branches; that can restore the
removed objects. Retire old CI workspaces/caches and rebuild from the clean
refs. If recovery is needed before publication, restore into a separate
private directory from `all-refs.bundle` or `original.git`, verify it and
compare the saved refs; leave the source working tree alone.

Old clones, forks, downloaded source/APKs, hosting caches, PR diffs, backups
and other external copies cannot be recalled by a Git rewrite. Request
host-side cache cleanup where available and revoke exposed credentials
regardless of whether those copies can be removed.
