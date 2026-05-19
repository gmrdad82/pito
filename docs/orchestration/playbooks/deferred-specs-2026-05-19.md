# Deferred specs playbook — 2026-05-19

This playbook is the input for the eventual RSpec consolidation phase ("the look
'n feel is validated, now we lock the behavior").

Every iteration-mode dispatch in the 2026-05-19 session shipped code without
specs (per CLAUDE.md "Iteration vs consolidation" rule). This playbook catalogs
the debt so the consolidation pass has a complete checklist.

## How to use this playbook

1. User signals "start spec consolidation" or similar.
2. Master dispatches RSpec agents to work through this list section by section.
3. Each agent writes specs for one section, runs `bin/test <files>`, marks
   complete by appending an entry to "Section completion log" at the bottom.
4. Existing specs that went RED due to mid-session refactors get rewritten first
   (see section 6) so the suite returns to a stable baseline before new coverage
   lands.
5. New behavior gets new specs (`build_stubbed` where possible, fast-loop
   discipline, per the project's testing.md).

## 1. NEW ViewComponents needing specs

The 2026-05-19 session shipped these components without specs. Path is the `.rb`
file; the matching `.html.erb` ships in the same dispatch.

### /channels Wave A1 — title bar + filter row + ID card shelf

- `app/components/channels/title_bar_component.rb` — title row, `[ + add ]` /
  `[ - remove ]` brackets, conditional rendering rules
- `app/components/channels/avatar_chip_component.rb` — circular avatar +
  checkbox; `1.4em + 4px` sizing; `-3px` vertical nudge; href generation per
  channel
- `app/components/channels/avatar_shelf_component.rb` — composes N avatar chips,
  scrolls horizontally
- `app/components/channels/id_card_component.rb` — landscape `314x158` card;
  circular avatar; landscape stats grid; YouTube Studio footer; optional
  `score:` arg renders `[NN]` top-right badge overlay

NOTE: there is no separate `id_card_shelf_component` — the canonical top-level
`ShelfComponent` is reused for the ID card row.

### /channels Wave A2-A10 variant gallery

Each section below ships 2–3 visual variants that render side-by-side on
`/channels`. The user picks one variant per section during validation
(`docs/orchestration/playbooks/channels-wave-a-validation-2026-05-19.md`); the
rejected variants get deleted in the cleanup pass that follows.

**Spec coverage targets ONLY the surviving variant per section.** Rejected
variants are deleted, not spec'd.

- `app/components/channels/basics_section_inline_component.rb` (V1)
- `app/components/channels/basics_section_card_component.rb` (V2)
- `app/components/channels/basics_section_separator_component.rb` (V3)
- `app/components/channels/top_content_list_component.rb` (V1)
- `app/components/channels/top_content_grid_component.rb` (V2)
- `app/components/channels/top_content_table_component.rb` (V3)
- `app/components/channels/window_summaries_tabs_component.rb` (V1)
- `app/components/channels/window_summaries_grid_component.rb` (V2)
- `app/components/channels/geography_list_component.rb` (V1)
- `app/components/channels/geography_bar_component.rb` (V2)
- `app/components/channels/geography_treemap_component.rb` (V3)
- `app/components/channels/demographics_pyramid_component.rb` (V1)
- `app/components/channels/demographics_grouped_component.rb` (V2)
- `app/components/channels/device_types_donut_component.rb` (V1)
- `app/components/channels/device_types_bars_component.rb` (V2)
- `app/components/channels/heatmap_grid_component.rb` (V1)
- `app/components/channels/heatmap_sparkline_component.rb` (V2)
- `app/components/channels/traffic_sources_list_component.rb` (V1)
- `app/components/channels/traffic_sources_split_component.rb` (V2)

### Shared / chrome

- `app/components/shelf_component.rb` — top-level rename of the former
  `Games::ShelfComponent`, with headless heading mode added and the scrollbar
  CSS encapsulated. `app/components/games/shelf_component.rb` is now a one-line
  `Games::ShelfComponent = ::ShelfComponent` alias — spec the canonical class;
  the alias only needs a `constantize` smoke.
- `app/components/about_modal_component.rb` — logo + K-V definition list
  (version / revision / env) + centered copyright + `[close]` bracketed link
- `app/components/search/everywhere_modal_component.rb` — mount, focus trap,
  context detection
- `app/components/search/everywhere_results_component.rb` — context-aware
  section ordering (games on /games, channels on /channels, etc.)
- `app/components/search/everywhere_section_component.rb` — thin wrapper after
  section-heading drop; verify it still renders the heading-less shape
- `app/components/search/everywhere_row_component.rb` — three kinds (game /
  bundle / channel) + type label aligned right + cover-less IGDB filter (drops
  rows with no cover)

NOTE: the user's brief mentioned `Games::RecommendedChannelsSectionComponent`
and `Games::ChannelRecommendationRowComponent` as "orphan, built but not wired"
— verification 2026-05-19 shows neither file exists under
`app/components/games/`. The recommendation **service**
(`app/services/games/channel_recommendation.rb`) shipped, but the view
components did not. Treat as out of scope for consolidation until the wiring
lands.

## 2. NEW services needing specs

- `app/services/channels/mock_data.rb` — 6 channels with all extended fields
  (`video_count`, `top_content`, `window_summaries`, `geography`,
  `demographics`, `device_types`, `viewer_time_heatmap`, `traffic_sources`,
  `yt_search_terms`); spec the shape contract
- `app/services/channels/demographics_mock.rb` — split out of `mock_data` due to
  a parallel-edit race during Wave A; spec the demographic buckets shape
  independently
- `app/services/channels/aggregator.rb` — 4+ aggregation methods
  (`subscribers_total`, `views_total`, `videos_total`, `watch_hours_total`,
  `window_summary`)
- `app/services/channels/voyage_indexer.rb` — composite text builder + Voyage
  embed + `update_columns(summary_embedding:)` upsert
- `app/services/meilisearch/channel_indexer.rb` — title / handle / description /
  keywords searchable; `add_documents` shape
- `app/services/games/channel_recommendation.rb` — `nearest_neighbors` on Voyage
  channel embeddings + 0–100 score mapping + threshold filter
- `app/services/search/everywhere.rb` — multi-source orchestrator + context
  ordering + per-source error isolation (one indexer down does not blank the
  modal)
- `app/services/formatting/compact_count.rb` — K / M / B tier transitions
- `app/services/formatting/compact_hours.rb` — European thousands separator, no
  K-compression
- `app/services/formatting/current_channel_filter_chips.rb` — dynamic year /
  month chip set derived from per-channel data

## 3. NEW jobs needing specs

- `app/jobs/channel_index_job.rb` — invokes `Meilisearch::ChannelIndexer` on a
  single channel id
- `app/jobs/channel_remove_index_job.rb` — removes a channel from Meilisearch on
  destroy
- `app/jobs/channel_voyage_index_job.rb` — invokes `Channels::VoyageIndexer` on
  a single channel id; respects the global Voyage enable toggle

## 4. NEW controllers needing specs

- `app/controllers/everywhere_search_controller.rb` — `#show` action (HTML for
  the modal mount + JSON branch for the autocomplete payload); context param
  wire-format; empty-query short-circuit; per-source failure tolerance assertion

## 5. NEW model behavior needing specs

- `Channel` — `has_neighbors :summary_embedding` configuration +
  `after_save_commit` Voyage callback enqueueing `ChannelVoyageIndexJob`
- `Channel` — `after_save_commit` Meilisearch sync via `ChannelIndexJob` +
  `after_destroy_commit` cleanup via `ChannelRemoveIndexJob`
- `Game` — `after_*_commit` ActionCable broadcasts driving live refresh on
  /games (verify the channel name + payload shape; gate that `silent: true`
  updates do not broadcast)

## 6. EXISTING specs that went RED (need rewriting)

These specs were not edited in the 2026-05-19 session but reference methods /
classes / file paths that the session refactored away. Each needs a rewrite
against the new shape before any new coverage lands.

- `spec/components/games/rating_heat_bar_component_spec.rb` — V3 method / class
  renames (`bubble_text` gone, `fill_glyphs` gone); rewrite against the current
  `RatingHeatBarComponent` public surface
- `spec/components/games/time_to_beat_component_spec.rb` — V3 method renames
  (`HEAT_THRESHOLDS` gone, `PILLAR_COLOR` gone, `gradient_stops` gone,
  `pillar_cell_index` gone); rewrite against the adaptive-gradient
  - per-pillar-color surface
- `spec/requests/favicon_spec.rb` — `/favicon.ico` now serves the direct PNG (no
  redirect); also tracked in `docs/orchestration/follow-ups.md` "favicon_spec.rb
  redirect target update"
- `spec/components/games/shelf_component_spec.rb` — uses the old
  `Games::ShelfComponent` name; the canonical class is now top-level
  `::ShelfComponent` with `Games::ShelfComponent` as a one-line alias. Rewrite
  the spec against the canonical class; optionally add a one-liner
  `expect(Games::ShelfComponent).to eq(::ShelfComponent)`
- `spec/javascript/leader_menu_controller_spec.rb` — compact-mode prefix
  filtering + dead-end dismiss + lazy schema getter need positive coverage
  (already tracked in follow-ups.md "Deferred specs" section)
- `spec/system/games_index_spec.rb` — 2 TODO-skipped examples referencing genre
  nested-shelf headings; revisit alongside the surviving channels variants since
  the genre shelves reuse `ShelfComponent`
- `spec/views/shared/_igdb_cover.html.erb_spec.rb` — `_light.svg` references
  gone after theme removal; verify the spec still asserts the single-dark
  fallback path post-edit (the edit was made; this is a green-confirm pass)
- `spec/components/games/cover_component_spec.rb` — `fallback_light_path` was
  renamed / removed; verify the spec edit already applied during theme-removal
  is still green

## 7. /channels Wave A1 + ID card iteration history

The `Channels::IdCardComponent` dimensions iterated multiple times during the
session:

1. `226 x 358` portrait first pass
2. `206 x 130` shrink
3. `217 x 344` taller variant
4. `232 x 146` short variant
5. `314 x 158` landscape with circular avatar + landscape stats grid + YouTube
   Studio footer (current locked state)

Plus the avatar chip received a `-3px` vertical nudge after the first visual
review.

**Spec the FINAL state only** (`314 x 158`, circular avatar, score badge
top-right when `score:` arg present). Intermediate states are git history, not
test surface.

## 8. SPEC files already touched by theme removal (verify still pass)

These files were edited during the theme-removal dispatch and the consolidation
pass simply runs them to confirm green. No further rewrite expected unless a
regression is found.

- `spec/javascript/theme_controller_spec.rb` (DELETED)
- `spec/javascript/leader_menu_controller_spec.rb` (themeToggle examples
  replaced with negative guards)
- `spec/system/settings_refactor_spec.rb` (`pito-theme` localStorage references
  swapped to negative guard)
- `spec/components/games/cover_component_spec.rb` (single-dark fallback)
- `spec/views/shared/_igdb_cover.html.erb_spec.rb` (single-dark fallback)
- `spec/components/games/game_tile_component_spec.rb` (single-dark fallback)
- `spec/components/games/genre_tile_component_spec.rb` (single-dark fallback)
- `spec/components/bundles/empty_cover_placeholder_component_spec.rb`
  (single-dark)
- `spec/components/games/bundle_tile_component_spec.rb` (single-dark)
- `spec/assets/tailwind/cover_border_css_spec.rb` (single-theme)
- `spec/assets/tailwind/games_polish_css_spec.rb` (single-theme)

## 9. MCP-cut spec changes (already applied)

The MCP scope simplification cut shipped during this session removed the entire
MCP tool surface and the MCP server. Spec files touched by that cut:

- `spec/lib/scopes_spec.rb` (`Scopes::ALL == ["app"]`)
- `spec/models/api_token_spec.rb` (`Scopes::APP`)
- `spec/factories/api_tokens.rb` + `spec/factories/oauth_applications.rb`
  (`Scopes::APP`)
- `spec/lib/api/token_authenticator_spec.rb` (`Scopes::APP`)
- `spec/lib/tasks/tokens_rake_spec.rb` (single-scope)
- `spec/requests/oauth_authorization_spec.rb` (`Scopes::APP`)
- `spec/requests/api/auth_concern_spec.rb` (no-scope simulation rewrites)
- `spec/requests/api/footages_spec.rb` (no-scope simulation rewrites)
- `spec/requests/api/footages/frames_spec.rb` (no-scope simulation rewrites)

DELETED (gone with the MCP surface):

- `spec/javascript/theme_controller_spec.rb`
- `spec/services/notification_formatter/mcp_spec.rb`
- `spec/mcp/**` (all tool specs + server / resources / tool_auth specs)
- `spec/requests/mcp/**` (rack_app_auth, tool_registry, oauth_token acceptance,
  mcp_http)
- `spec/requests/oauth_scope_clip_spec.rb`
- `spec/support/api_token_context.rb`

These were all green per the cut dispatches at the time they landed. The
consolidation pass runs them as a green-confirm and removes any straggling
reference in support files / shared examples.

## 10. Behavior rules to add as regression guards

Each rule below was established or reinforced during the 2026-05-19 session and
benefits from a spec that guards it against future drift.

- **Modal footer left-align** (`docs/design.md` rule) — spec that confirm-modal
  footer renders no `margin-left: auto` and that the cancel / confirm bracketed
  links sit flush left
- **Channel avatar circular** (`border-radius: 50%`) — spec the
  `Channels::AvatarChipComponent` and `Channels::IdCardComponent` avatar
  elements render with the circle border-radius token
- **Trend glyphs `▲ – ▼`** — spec the sortable header markup +
  `RatingHeatBarComponent` + `Channels::IdCardComponent` stat row trend cells
- **Filter chip canonical primitive** — every chip surface uses
  `FilterChipComponent`; consider a structural test that fails when a view
  renders a `[ ... ]` chip without going through the component (grep-as-spec or
  a Rubocop cop)
- **Compact menu prefix dead-end dismiss** — `leader_menu_controller.js` closes
  the popup when the accumulated prefix has zero matches (already listed in
  follow-ups.md as a deferred spec)
- **Flat-key controller Turbo-nav lazy schema** — `flat_key_controller.js`
  resolves the keybinding schema lazily after Turbo navigation so a fresh page
  doesn't capture the stale schema
- **Section accent inheritance** — `body[data-section]` accent inheritance falls
  through into modals; spec that an opened modal on /channels inherits the
  section accent token (and is overridden by the modal's own narrow rule when
  present)
- **Score badge on `IdCardComponent`** — when the `score:` arg is present, the
  `[NN]` badge renders top-right with the correct heat-bar tier color; when
  `score:` is absent, the badge slot is empty
- **About modal copy contract** — version + revision + env K-V keys rendered
  exactly once, copyright line centered, `[close]` link bracketed (not
  `[ cancel ]`, per the close-vs-cancel rule in CLAUDE.md / design.md)

## 11. Open questions to resolve before / during consolidation

- /channels variant winners (user picks; rejected variants and their files get
  deleted before specs land)
- Whether to ship `Games::RecommendedChannelsSectionComponent` +
  `Games::ChannelRecommendationRowComponent` (the service exists but the view
  components do not). If yes, both ship as new components and enter section 1.
  If no, fold the service into a different consumer or drop it.
- DRACULA-SWATCHES-V2 PS-blue final pick (currently locked to Pale Cobalt
  `#7eb6ff`); if it changes, every chip / badge that consumes the token needs a
  re-snapshot
- Manual `pito:voyage:reindex_channels` cadence and a green-path spec for the
  rake task once channels are populated

## 12. Cross-references

- Wave A visual validation playbook —
  `docs/orchestration/playbooks/channels-wave-a-validation-2026-05-19.md`
- Theme-base-color refactor playbook —
  `docs/orchestration/playbooks/theme-base-color-refactor-2026-05-19.md`
- System-spec debt sweep —
  `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md`
- Channels + Live Updates handoff —
  `docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md`
- Follow-ups deferred-specs section — `docs/orchestration/follow-ups.md`
  "Deferred specs (spec consolidation phase)"
- Phase plans — `docs/plans/beta/37-channels-revamp/plan.md` and
  `docs/plans/beta/38-games-channel-recommendations/specs/01-recommendation-system.md`
- Design tokens — `docs/design.md`

## Append-only convention

Future iteration-mode dispatches MUST append their deferred items here. Dispatch
prompts include: "before reporting done, append your deferred spec items to
`docs/orchestration/playbooks/deferred-specs-2026-05-19.md` per the existing
convention."

The master agent audits the playbook before kicking off the RSpec consolidation
phase and resolves all open questions in section 11 with the user first.

## Section completion log

Entries added by the RSpec consolidation agents as they work through this list.
Format: `- YYYY-MM-DD — section N — <one-line note> — <commit SHA or pending>`.

- (none yet — consolidation has not started)
