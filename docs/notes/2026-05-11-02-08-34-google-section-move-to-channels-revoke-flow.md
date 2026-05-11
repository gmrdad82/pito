# Move Google section out of Settings → Channels only

## Scope
- Remove the Google section from Settings entirely. It lives only in `/channels`.
- Each channel row/page gets a `[revoke]` action.

## Revoke flow
- `[revoke]` opens a confirmation modal.
- Modal must state how many videos will also be affected, since revoking a channel deletes its videos.
- On confirm: enqueue a Sidekiq `DeleteChannelDataJob` (or similarly-named) that cascades the deletion.

## What the job deletes
- The channel record.
- All videos belonging to that channel.
- Associated assets: thumbnails, stats, and any other dependent records (notes/links/diffs/etc. — audit before implementing).

## Requirements
- Spec coverage must be exhaustive:
  - Modal renders correct video count.
  - Confirm vs cancel paths.
  - Job enqueues with correct args.
  - Job deletes channel, videos, and all assets/dependents.
  - No orphaned records left behind (verify with DB checks in tests).
  - Idempotency / re-run safety.
  - Authorization (only owner can revoke).
- Tests should cover both the controller/UI path and the Sidekiq job in isolation.
