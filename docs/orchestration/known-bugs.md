# Known bugs — accepted / not fixing

Living list of small bugs we know about and have explicitly accepted as
"not worth fixing right now" (or possibly ever). Each entry: the bug,
why it's not worth fixing, and any condition that would change that
assessment.

Convention: keep entries TERSE. If a bug grows beyond a couple lines
of context, promote it to a real follow-up in
`docs/orchestration/follow-ups.md`.

---

## KB-1. Released-on filter still includes user-toggled platforms after un-toggle

**Date logged:** 2026-05-18

**Symptom.** User clicks `[owned] PS` on a game where IGDB doesn't list PS
→ FN2 adds a `GamePlatform` row with `source: "user"` and `platforms_available`
now includes PS5. User then un-clicks `[owned] PS` → the owned state goes off
but the `platforms_available` row (`source: "user"`) **stays**. Effect: the
game still surfaces under the `released` axis on the `ps` platform filter even
though the user no longer owns it on PS.

**Why not fixing.** Edge case. The intent of `source: "user"` is to preserve
user-authored truth across IGDB syncs — auto-removing on un-toggle would
introduce a 3rd state ("temporarily owned then unowned") that doesn't carry
useful signal. The current behavior is "platforms_available is sticky once a
user has asserted it."

**Would change if.** Multiple users complain (n/a — single-user install) OR a
future "purge unused user-source rows" action ships as a separate flow.

---
