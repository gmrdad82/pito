# Beta-3 Lane B (B3) — Game::MetaTableComponent.
#
# Extracts the inline `meta_rows = []` builder + `<table class="kv-table">`
# markup block from `app/views/games/show.html.erb` (LEFT pane, between the
# genres line + hairline above and the rating heat-bar below) into a focused
# ViewComponent.
#
# Business rule (Phase 14 §1 + 2026-05-11 Fix 3 + 2026-05-18 sync row):
#   - Row order is fixed: date, dev, pub, sync.
#   - The `date` row is OMITTED entirely when `game.release_date` is blank
#     (no "—" placeholder).
#   - The `dev` row is OMITTED entirely when `game.developers` is empty.
#   - The `pub` row is OMITTED entirely when `game.publishers` is empty.
#   - The `sync` row is ALWAYS present. While a resync is in flight
#     (`game.resyncing?` true) the value renders as `---` so the row
#     visibly signals "stale, refreshing". Otherwise it renders
#     `helpers.compact_time_ago(game.igdb_synced_at)` (which returns
#     "never" for nil — games that have never synced still show the row).
#   - Date value is formatted via `strftime("%m-%d-%Y")` (Fix 3).
#   - Each rendered row's value cell carries a `title` attribute equal to
#     the value string — the standard truncation tooltip affordance.
#
# 2026-05-19 (Bug A3 fix) — the sync row now carries:
#   - A stable DOM id (`game_meta_sync_row_<id>`) so Turbo's `morph`
#     refresh (the page-level `auto-refresh` controller's 5s reload
#     into `Turbo.visit(..., { action: "replace" })` interacts with
#     a morph-method `<meta>` tag at the layout level) identifies
#     the same row across renders and reliably swaps its inner text
#     from `~Xm ago` → `---` (and back). Without a stable id, morph
#     was free to reuse the surrounding `<td>` shells and leave the
#     stale time-ago string in the value cell.
#   - A `kv-table__row--syncing` modifier class on the `<tr>` when
#     `resyncing?` is true — the muted-text treatment that visually
#     ties the row to the breadcrumb [sync] / [delete] muted spans
#     and the ownership-matrix "syncing…" placeholder. The class is
#     a CSS hook only (no inline style) so the design surface owns
#     the actual color rule.
#   - A `data-resyncing="yes"` / `"no"` attribute on the `<tr>`
#     (project-wide yes/no boundary contract) so future Stimulus /
#     CSS hooks can target the row without re-checking the model.
#
# 2026-05-19 (Wave B) — when `resyncing?` is true, the date / dev / pub
# rows also render their value cells as `sync-indicator` dot-loaders
# (same `=---` cycling frames as the genre line) at phase offsets
# 1 / 2 / 3 respectively so the four-zone stagger reads as a wave:
#     genre  (offset 0)  =---  →  -=--  →  --=-  →  ---=
#     date   (offset 1)  -=--  →  --=-  →  ---=  →  =---
#     dev    (offset 2)  --=-  →  ---=  →  =---  →  -=--
#     pub    (offset 3)  ---=  →  =---  →  -=--  →  --=-
#     summary(offset 0)  =---  →  -=--  →  --=-  →  ---=
# The sync row's value stays the static `---` string (the underlying
# row itself dims via `kv-table__row--syncing`, and its semantic
# meaning is "when did the last sync land" not "this is loading").
# Both the row's `kv-table__row--syncing` modifier and the per-cell
# loader stay live in parallel — the row dim layers the muted-stale
# treatment while the loader inside the value cell carries the actual
# animation.
class Game::MetaTableComponent < ViewComponent::Base
  SYNC_ROW_KEY = "sync".freeze

  # Canonical 4-frame cycle for sync-indicator across /games/:id.
  # Mirrors Game::GenresLineComponent::SYNC_INDICATOR_FRAMES — the
  # canonical frame array lives here too so the kv-table row template
  # doesn't reach into a sibling component for a literal. Phase
  # offsets are assigned per-row (date=1, dev=2, pub=3) so the four
  # zones in the LEFT pane stagger.
  SYNC_INDICATOR_FRAMES = [ "=---", "-=--", "--=-", "---=" ].freeze
  SYNC_INDICATOR_PHASE_OFFSETS = {
    "date" => 1,
    "dev"  => 2,
    "pub"  => 3
  }.freeze

  def initialize(game:)
    @game = game
  end

  attr_reader :game

  # Memoized row hashes in the fixed render order. Conditional rows
  # are simply omitted from the array (no `nil` slots). Each row is:
  #   { key:, label:, value: }
  # where `key` distinguishes the always-rendered sync row from the
  # conditional date/dev/pub rows so the template can target it for
  # the stable id + modifier-class treatment.
  #
  # 2026-05-19 (Wave B) — during a resync the date / dev / pub rows
  # are FORCE-RENDERED even when the underlying value is currently
  # blank, so the per-cell dot-loader has a row to live in. Without
  # this, a freshly-created game (no developers / publishers yet) in
  # mid-sync would render only the sync row + no loaders at all —
  # the "stale, refreshing" signal would collapse. The value is set
  # to `nil` in that branch; the template branches on `resyncing?`
  # and renders the loader cell instead of the static value.
  def meta_rows
    @meta_rows ||= begin
      rows = []
      if game.release_date.present?
        rows << { key: "date", label: "date", value: game.release_date.strftime("%m-%d-%Y") }
      elsif resyncing?
        rows << { key: "date", label: "date", value: nil }
      end
      developer_names = game.developers.map(&:name)
      if developer_names.any?
        rows << { key: "dev", label: "dev", value: developer_names.join(", ") }
      elsif resyncing?
        rows << { key: "dev", label: "dev", value: nil }
      end
      publisher_names = game.publishers.map(&:name)
      if publisher_names.any?
        rows << { key: "pub", label: "pub", value: publisher_names.join(", ") }
      elsif resyncing?
        rows << { key: "pub", label: "pub", value: nil }
      end
      rows << { key: SYNC_ROW_KEY, label: "sync", value: sync_value }
      rows
    end
  end

  def sync_row_id
    "game_meta_sync_row_#{game.id}"
  end

  def resyncing?
    game.resyncing?
  end

  # Returns the phase offset for a non-sync row (date / dev / pub) per
  # SYNC_INDICATOR_PHASE_OFFSETS. Unknown keys (defensive) get 0.
  def phase_offset_for(key)
    SYNC_INDICATOR_PHASE_OFFSETS.fetch(key, 0)
  end

  private

  def sync_value
    return "---" if game.resyncing?

    helpers.compact_time_ago(game.igdb_synced_at)
  end
end
