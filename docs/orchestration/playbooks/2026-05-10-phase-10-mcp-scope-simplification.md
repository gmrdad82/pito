# Manual test playbook — Phase 10: collapse MCP scope catalog from 9 scopes to dev + app

**Branch:** `main` (commit `f5b15bd`) **Spec:**
`docs/plans/beta/10-mcp-scope-simplification/specs/01-collapse-to-dev-app.md`
**ADR:** `docs/decisions/0004-mcp-scope-simplification-dev-app.md`
**Migration:**
`db/migrate/20260510110333_revoke_tokens_for_scope_simplification.rb` **Reviewer
run:** 2026-05-10 11:35

## Pipeline summary

- Code review: pass — 4 minor concerns, all non-blocking (see below)
- Simplify: pass — 2 suggestions, both opportunistic (see below)
- Test suite (`bundle exec rspec`): **1717 examples, 0 failures, 0 pending**
  (was 1673 in Phase 9; net +44 from new test files —
  `spec/requests/mcp/tool_registry_spec.rb`,
  `spec/db/migrate/revoke_tokens_for_scope_simplification_spec.rb`,
  `spec/mcp/tool_auth_spec.rb` plus updates across the existing suite)
- Lint (`bundle exec rubocop`): 425 files inspected, 0 offenses
- Security static analysis (`bundle exec brakeman -q -w2`): 0 errors, 0 warnings
  (2 obsolete ignore-file entries flagged — pre-existing, see Concerns)
- Dependency audit (`bundle exec bundler-audit check --update`): clean (1078
  advisories scanned, no vulnerabilities)
- Reviewer-spec checkpoints (per spec §"Reviewer checkpoints"):
  - `git grep -E 'Scopes::DEV_READ|Scopes::DEV_WRITE|Scopes::YT_READ|Scopes::YT_WRITE|Scopes::YT_DESTRUCTIVE|Scopes::WEBSITE_READ|Scopes::WEBSITE_WRITE|Scopes::PROJECT_READ|Scopes::PROJECT_WRITE' app/ lib/ spec/ config/ db/`
    — **zero hits.** No legacy scope constant survives anywhere.
  - `git grep -E 'dev:read|dev:write|yt:read|yt:write|yt:destructive|website:read|website:write|project:read|project:write' app/ lib/ spec/ config/ db/`
    — **only intentional hits:** the migration mapping table
    (`db/migrate/20260510110333_*.rb`), the migration's own integration spec
    (`spec/db/migrate/revoke_tokens_for_scope_simplification_spec.rb`), the
    scope-clip spec's "rejects legacy strings" examples
    (`spec/requests/oauth_scope_clip_spec.rb`), the `ApiToken` "rejects legacy
    9-scope string" boundary tests (`spec/models/api_token_spec.rb`), the
    tool_auth defense-in-depth spec (`spec/mcp/tool_auth_spec.rb`), the Phase 1
    historical-context audit comment in
    `db/migrate/20260507100002_add_user_scopes_expires_to_api_tokens.rb`, and
    the rake task help-text comment (`lib/tasks/tokens.rake:17`). All are
    intentional.
  - **Soft-clip monkey-patch unchanged on disk:**
    `git diff f5b15bd^ f5b15bd config/initializers/doorkeeper_scope_clip.rb`
    returns no changes. The patch's math is catalog-agnostic (verified by
    explicit examples in `spec/requests/oauth_scope_clip_spec.rb`).
  - **Strip-on-release boundary verified:** with `expose_dev_scope = false`
    stubbed, `Scopes::ALL == ["app"]` and `Scopes.all == ["app"]`. Confirmed via
    direct Ruby load of `app/lib/scopes.rb` against a stubbed
    `Rails.application.config.x.mcp` — see `Manual test steps` §6.
  - **Tool registry strip-on-release:** `register_tools` rejects `list_docs` /
    `read_doc` / `save_note` from the registry when the flag is `false`;
    `list_channels` and the rest of the app surface stay registered. Pinned by 7
    examples in `spec/requests/mcp/tool_registry_spec.rb`.
  - **Migration soft-revoke + scope rewrite:** new specs in
    `spec/db/migrate/revoke_tokens_for_scope_simplification_spec.rb` cover the
    `ApiToken` / `OauthAccessToken` / `OauthAccessGrant` soft-revoke and the
    `OauthApplication.scopes` rewrite (incl. dedup, already-correct passthrough,
    already-revoked preservation).
  - **Production seed skip:** `db/seeds.rb:66-68` early-returns under
    `Rails.env.production?` — no dev-token mint, no banner.
  - **Strip-on-release flag wiring:** declared in `config/application.rb`
    (`config.x.mcp.expose_dev_scope = true` default), set explicitly in
    `config/environments/{development,test}.rb` to `true`, set explicitly in
    `config/environments/production.rb` to `false`.

## Blockers

None. Ship-ready.

## Concerns and suggestions

All flagged as **minor / nitpick** (non-blocking). The diff is exactly the
spec-prescribed shape; the items below are opportunistic notes, not corrections
required before validation.

1. **(minor / housekeeping) — `Scopes.dev_exposed?` and
   `Mcp::PitoServer.dev_scope_exposed?` duplicate the same flag-resolution
   logic.** Both methods do the same `respond_to?(:mcp)` guard, safe-navigate
   `expose_dev_scope`, and default-to-`true` fallback. The bodies are identical;
   only the names differ (`app/lib/scopes.rb:43-47` vs
   `app/mcp/pito_server.rb:61-65`). A future tightening could route
   `Mcp::PitoServer` through `Scopes.dev_exposed?` to keep one source of truth —
   but the duplication is intentional during boot when Scopes is loaded by
   Doorkeeper's initializer ahead of the MCP server. /simplify suggestion only;
   no behavior change.

2. **(minor / pre-existing, NOT introduced by Phase 10) — Two obsolete entries
   in `config/brakeman.ignore`** (fingerprints
   `4d586370565ad858623ed4e34fae39e1c97703ae2505563f20e37f124f373ba5` and
   `050af47121b0c4251d18c5b722e529807edb8a9852128f6fa384c768d47e0317`). Already
   noted as a non-blocking follow-up by Phase 9's reviewer pass. No new findings
   introduced by this phase.

3. **(minor / pre-existing) — `RAILS_ENV=production bin/rails runner …` crashes
   on `solid_queue` / `solid_cache` configuration before reaching
   `Scopes::ALL`.** `config/environments/production.rb:50,53,54` sets
   `config.cache_store = :solid_cache_store`,
   `config.active_job.queue_adapter = :solid_queue`, and
   `config.solid_queue.connects_to = ...`, but neither gem is in the `Gemfile`.
   This blocks the spec's recommended manual-validation step (the
   `bin/rails runner 'puts Scopes::ALL.inspect'` dry-run). It is NOT a Phase 10
   regression — same code shape existed pre-Phase 10. The playbook's User
   Validation section uses an alternative direct-load probe instead. Flag for a
   future infra hygiene pass.

4. **(minor / nitpick) — Migration body uses the rocket hash style
   (`"dev:read" => "dev"`).** Rubocop accepts this because every key is
   non-symbol, but the rest of the codebase prefers the modern shorthand.
   Cosmetic only — rubocop is green and the table is highly readable in its
   current form. Probably leave alone.

5. **(simplify suggestion / nitpick) — `db/migrate/20260510110333_*.rb`
   `rewrite_scopes` falls back to `[ "app" ]` when the mapped set is empty.**
   The defensive fallback is meant to keep an OauthApplication usable
   post-migration. Realistically, no application in pito's history has only
   legacy scope strings that all map to `nil` (the mapping table is exhaustive).
   The fallback is dead code in practice. Keep it as a defensive edge case;
   document the assumption is fine. /simplify flag.

6. **(observation only) — `WellKnownController#oauth_authorization_server` and
   `#oauth_protected_resource` advertise `Scopes::ALL` as the
   `scopes_supported`.** Under `expose_dev_scope = false`, the `.well-known`
   metadata correctly drops `dev` from the advertised list. This is the desired
   behavior — production discovery documents truthfully advertise what the
   server will issue. No action needed; just calling out that this is one of the
   visible cross-cutting effects of the strip-on-release flag.

## Manual test steps

This is the command-level setup walkthrough. After this section, the **User
Validation** section walks through the browser-only smoke test the user can
follow without leaving the UI.

### Setup preamble

1. **Confirm Phase 9 is on `main`.** The `YoutubeConnection` rename and the
   sign-in-with-Google drop are prerequisites; the seed in this phase assumes
   the post-Phase-9 shape. If `git log --oneline | head -3` does not show
   `f5b15bd Phase 10` followed by `9ea8896 Phase 9`, stop and re-route.

2. **Reseed the database.**

   ```bash
   bin/rails db:drop db:create db:migrate db:seed
   ```

   - **Expected:** seed completes;
     `Dev token minted (save this now — cannot be shown again):` banner prints
     exactly once. Capture the plaintext if you want to test the bearer flow
     over curl directly.

3. **Verify the seeded scope set.**

   ```bash
   bin/rails runner 'puts ApiToken.where(name: "dev").pluck(:scopes).inspect'
   ```

   - **Expected:** `[["dev", "app"]]`.

4. **Verify the migration soft-revoked any pre-existing tokens.** (Optional —
   the freshly-reseeded DB above will not have any rows older than the
   migration. To check the migration body itself, the integration spec in
   `spec/db/migrate/revoke_tokens_for_scope_simplification_spec.rb` is the
   authoritative coverage and is already green.)

5. **Quality gates.** All four are green at commit `f5b15bd`; reproduce if you
   want a fresh confirmation:

   ```bash
   bundle exec rspec
   bundle exec rubocop
   bundle exec brakeman -q -w2
   bundle exec bundler-audit check --update
   ```

6. **Strip-on-release dry-run (alternative path).** The spec recommends
   `RAILS_ENV=production bin/rails runner 'puts Scopes::ALL.inspect'` →
   `["app"]`. That exact command is currently blocked by the pre-existing
   `solid_queue` / `solid_cache` configuration gap (Concerns §3). To verify the
   strip-on-release boundary directly without booting the full production
   environment, run this minimal probe from the repo root:

   ```bash
   ruby -e '
   module Rails
     def self.application
       @app ||= begin
         a = Object.new
         def a.config
           @c ||= begin
             c = Object.new
             def c.x
               @x ||= begin
                 x = Object.new
                 def x.respond_to?(s); s == :mcp; end
                 def x.mcp
                   m = Object.new
                   def m.expose_dev_scope; false; end
                   m
                 end
                 x
               end
             end
             c
           end
         end
         a
       end
     end
   end
   load "app/lib/scopes.rb"
   puts "Scopes::ALL = #{Scopes::ALL.inspect}"
   puts "Scopes.all  = #{Scopes.all.inspect}"
   puts "dev_exposed? = #{Scopes.dev_exposed?}"
   '
   ```

   - **Expected:**

     ```
     Scopes::ALL = ["app"]
     Scopes.all  = ["app"]
     dev_exposed? = false
     ```

   This is the same outcome the spec calls for — the only difference is the
   probe path avoids the `solid_queue` boot crash.

7. **Start the dev server.**

   ```bash
   bin/dev
   ```

   - **Expected:** Puma listens on `app.pitomd.com` (cookie + admin),
     `mcp.pitomd.com` (MCP rack-app), Sidekiq is up, Tailwind is in watch mode.
     No errors during boot.

## User Validation

Walk through the browser-only smoke test. Each step is observable from the UI —
no shell required after the setup preamble above. Cross off as you go.

[ ] 1. **Sign in.** Visit `https://app.pitomd.com/login` → enter the seeded
`:owner` email + password from credentials → land on the channels page.
Expected: dashboard renders; no flash error.

[ ] 2. **Open the tokens admin page.** Click the gear icon (top-right) →
`[ tokens ]` → land on `/settings/tokens`. Expected: the page lists exactly one
row labelled `dev` with the scope chips `[ dev ]` and `[ app ]` (and
`last used: never` on the right).

[ ] 3. **Visit the new-token form.** Click `[ new token ]` → land on
`/settings/tokens/new`. Expected: the **scopes** section renders a flat
two-checkbox list, NOT a nested namespace tree. Visible labels: -
`dev — read and capture developer docs.` -
`app — application access. manage channels, videos, projects, and the calendar.`

       Both checkboxes are unchecked by default (the new form starts blank).
       The legacy 9-scope namespace `<fieldset>` grouping is gone.

[ ] 4. **Mint a dev-only token.** Type `mobile-dev-test` in the name field →
tick `[ dev ]` only → leave `expires` blank → click `[ create ]`. Expected:
redirected back to `/settings/tokens` with the one-time plaintext banner at the
top; the new row shows scope chip `[ dev ]` only.

[ ] 5. **Mint an app-only token.** Repeat with name `cli-app-test` and only
`[ app ]` ticked. Expected: success banner + new row with `[ app ]` only.

[ ] 6. **Open the OAuth applications admin page.** Settings cog →
`[ oauth applications ]` → land on `/settings/oauth_applications`. Click
`[ new application ]`. Expected: the **scopes** section renders the same flat
2-checkbox list (`dev` / `app`) with the same locked prose. No legacy `dev:read`
/ `yt:read` / `project:write` checkboxes.

[ ] 7. **Re-pair Claude Mobile (MCP).** Open the Claude Mobile MCP connector
configuration → revoke the existing `pito` connection → re-add
`https://mcp.pitomd.com` (or your tunnel URL). Walk the OAuth consent flow.
Expected: the consent screen displays exactly two scope rows: - `dev` —
`read and capture developer docs.` - `app` —
`application access. manage channels, videos, projects, and the calendar.`

       The legacy 9-scope checkbox tree is gone. After approval, return
       to Claude Mobile; the connection shows green / connected.

[ ] 8. **Smoke a `dev` MCP tool from Claude Mobile.** In Claude Mobile, prompt:
`list developer docs` (or call the `list_docs` tool directly via the connector
debugger). Expected: returns a JSON list of markdown filenames under `docs/`.

[ ] 9. **Smoke an `app` MCP tool from Claude Mobile.** Prompt:
`list pito channels`. Expected: returns the seeded 100 channels (or a paginated
subset, depending on tool defaults).

[ ] 10. **Re-pair Claude.ai Web MCP.** Open Claude.ai → Settings → Connectors →
revoke any existing pito connection → re-add `https://mcp.pitomd.com`. Walk the
consent flow. Expected: same 2-scope consent screen as step 7 (Claude.ai
auto-walks every advertised scope, so both `dev` and `app` are pre-checked).

[ ] 11. **Smoke an `app` tool from Claude.ai Web.** From Claude.ai, prompt:
`list pito channels`. Expected: returns the seeded list.

[ ] 12. **Soft-clip happy path.** From a browser, visit (replace
`<APPLICATION_UID>` with the `client_id` of one of the apps from step 6 that has
both scopes whitelisted):

        ```
        https://app.pitomd.com/oauth/authorize?response_type=code&client_id=<APPLICATION_UID>&redirect_uri=<URI>&scope=dev+app&code_challenge=<CHALLENGE>&code_challenge_method=S256
        ```

        Expected: the consent screen renders with the `[ authorize ]` link
        visible and both scope rows shown.

[ ] 13. **Soft-clip legacy rejection.** Same URL as step 12 but with
`scope=dev:read+app:write` (legacy strings). Expected: the request is rejected;
the consent screen does NOT render — instead the URL redirects back to the
application's `redirect_uri` carrying `?error=invalid_scope&...`. (If the
redirect_uri is loopback the browser will fail to load it; the URL bar still
shows the `error=invalid_scope` query string.)

[ ] 14. **Tokens-list housekeeping.** Return to `/settings/tokens` and revoke
the two test tokens you minted in steps 4-5 (`mobile-dev-test` and
`cli-app-test`) so the install ends in the same state it started. Expected:
revoked rows show `(revoked)` status and the chip list dim.

## Cleanup

If anything in the validation goes sideways and you want to reset:

```bash
# Roll back to a clean state from the seed:
bin/rails db:drop db:create db:migrate db:seed

# Or just revoke the test tokens you minted:
bin/rails runner 'ApiToken.where(name: %w[mobile-dev-test cli-app-test]).each(&:revoke!)'

# Reset the Claude Mobile / Claude.ai connector pairings if a stale
# token is wedged client-side: revoke from the connector UI, then re-pair.
```

To sanity-check the diff again:

```bash
git diff f5b15bd^ f5b15bd --stat | tail -10
git log --oneline -1 f5b15bd
```
