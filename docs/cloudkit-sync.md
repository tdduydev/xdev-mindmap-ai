# iCloud sync

Status: planned for Phase 6. The schema is already CloudKit-ready (see [data-model.md](data-model.md)); sync is switched off in `PersistenceController` until then.

## Goals

- Maps sync between the user's own iPhone and iPad through their private iCloud database.
- No xDev account and no sync button.
- Editing never waits for sync. The device is always fully usable on its own.

## Plan

1. Add the iCloud capability with a CloudKit container (`iCloud.asia.xdev.mindmapai`) and background remote notifications.
2. Set `cloudKitDatabase: .private(...)` in `PersistenceController`; keep a local-only store when the user is signed out or has disabled iCloud for the app.
3. Observe remote changes and reload open maps through `GraphRepair` before showing them.
4. Show sync state quietly (`CloudSyncState`: on, off, signed out, waiting, error) in Settings and as a small status line, never as a blocking alert. Being offline is not an error.

## Conflicts

Sync merges per record, last writer wins per field set. The design keeps that safe:

| Case | Outcome |
| --- | --- |
| Two devices edit different nodes | Both edits survive (one record each). |
| Two devices edit the same node | Last writer wins for that node only. |
| A node arrives before its parent | Stored as is; shown under the root until the parent arrives (repair). |
| One device deletes a branch, another adds under it | The added nodes hang under the root; nothing is silently lost. |
| Two devices move nodes under each other | A loop; repair cuts it at the most recently edited node. |
| The same record arrives twice | The newest `updatedAt` wins on load; the repository folds duplicates on save. |

Repair is deterministic, so devices reach the same result independently.

## Open questions for Phase 6

- Undo history after a remote change: decided 2026-10-02, drop the undo steps that touch the topics the remote change touched and keep the rest.
- Whether the map record's `updatedAt` should come from the server's modification time, so "Recent" ordering agrees across devices.
- Test plan for account changes and storage-full errors on real devices.
