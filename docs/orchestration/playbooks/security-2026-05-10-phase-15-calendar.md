# Security audit — Phase 15: Calendar

**Branch:** `main` (commits `a690ca1`, `a9329aa`, `b9b22ba`) **Specs:**
`docs/plans/beta/15-calendar/specs/{01-calendar-data-model,02-calendar-views}.md`
**Reviewer playbook:**
`docs/orchestration/playbooks/2026-05-10-phase-15-calendar.md` **Audit run:**
2026-05-10

## Verdict

**CLEAR TO MERGE.** No Critical/High. 5 findings (2 Medium, 2 Low, 1
Informational), all defense-in-depth or fix-forward.

## Findings

### F1. `bypass_readonly` is whole-record, not metadata-scoped (MEDIUM)

- **Location:** `app/models/calendar_entry.rb:162-175`,
  `app/controllers/calendar/entries_controller.rb:90-101`,
  `app/controllers/deletions_controller.rb:90`
- **Description:**
  `before_save :reject_writes_to_derived_outside_user_overrides` short-circuits
  ENTIRELY when `bypass_readonly = true`. Today no live escalation (callsites
  are well-bounded), but a future controller could silently bypass the rule for
  derived/auto entries.
- **Recommendation:** Replace `bypass_readonly` flag with `bypass_readonly_for`
  allowlist (array of attribute names). Or narrow `note` controller to use
  `update_columns` directly, dropping the bypass.
- **References:** CWE-732.

### F2. `MilestoneRule#fire!` race window — duplicate `milestone_auto` entries (MEDIUM)

- **Location:** `app/models/milestone_rule.rb:43-65`,
  `app/services/calendar/milestone_evaluator.rb:18-25`
- **Description:** READ COMMITTED isolation lets two concurrent workers both see
  `fired_at: nil` and both create entries. No partial unique index on
  `milestone_auto` rows keyed by `milestone_rule_id` (unlike host-derived
  shapes).
- **Recommendation:** Partial unique index on `(milestone_rule_id)` for
  `entry_type=milestone_auto`. Then `fire!` rescues `RecordNotUnique` and
  re-reads `fired_at`.

### F3. `purchase_planned.parent_entry_id` not type-checked (LOW)

- **Location:** `app/models/calendar_entry.rb:145-149`,
  `app/validators/calendar_entry_cross_reference_validator.rb:32-36`
- **Description:** Validator only checks presence, not that parent's
  `entry_type == "game_release"`. Quick-add can attach a purchase_planned to a
  milestone_manual silently. Misclassifies data.
- **Recommendation:** Add `purchase_planned_parent_is_game_release` validation.

### F4. `metadata.user_overrides` is an unstructured jsonb sink (LOW)

- **Location:** `app/validators/calendar_entry_metadata_validator.rb:32-39`,
  `calendar/entries_controller.rb:115,126,92`
- **Description:** Strong-params permits arbitrary nested hash. Validator strips
  top-level unknown keys but never recurses into `user_overrides`. No length
  cap. Latent XSS sink when the `[note]` modal lands (Concern 6).
- **Recommendation:** Tighten metadata permit shape; length-validate
  `user_overrides.note` ≤ 5000 chars; ensure renderer escapes (default ERB
  does).

### F5. `CalendarDerivationJob` `constantize` on string argument (INFORMATIONAL)

- **Location:** `app/jobs/calendar_derivation_job.rb:9-14`
- **Description:** Arbitrary class loader if user input ever threads in. Today
  no enqueue site = no path.
- **Recommendation:** `ALLOWED_HOSTS = %w[Channel Video Game].freeze`; gate
  before constantize.

## Out-of-scope but noted

- `/sidekiq` HTTP basic auth credentials — not verified.
- No CSP header — repo-wide, not Phase 15 specific.
- `[note]` modal markup missing (Concern 6) — F4 recommendations should ride
  alongside its implementation.

## Quality gate evidence

- Brakeman strict: 5 pre-existing warnings, 0 in Phase 15.
- Bundler-audit: clean.
- Hard-rule sweeps: clean (no `alert/confirm/prompt/data-turbo-confirm`; no
  `html_safe` on user content).
- Yes/no boundary: strict rejection verified.
- SQL injection sweep: all raw fragments use bound params.
- Cross-resource FKs: DB-level FKs on all 7 cross-references prevent IDOR class.
- Race guards: 3 partial unique indexes for derived host shapes; milestone shape
  missing (F2).
- Soft-cancel state machine: state column not in any create/update permit list;
  only server-controlled writers.
- Confirmable scope filter: `where(source: :manual)` enforced.
- Auth: Sessions::AuthConcern on every calendar controller.

## Counts

- Critical: 0
- High: 0
- Medium: 2 (F1, F2)
- Low: 2 (F3, F4)
- Informational: 1 (F5)
