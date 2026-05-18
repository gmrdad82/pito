# Beta-3 Lane B (B3) — Games::MetaTableComponent.
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
class Games::MetaTableComponent < ViewComponent::Base
  def initialize(game:)
    @game = game
  end

  attr_reader :game

  # Memoized [label, value] pairs in the fixed render order. Conditional
  # rows are simply omitted from the array (no `nil` slots).
  def meta_rows
    @meta_rows ||= begin
      rows = []
      rows << [ "date", game.release_date.strftime("%m-%d-%Y") ] if game.release_date.present?
      developer_names = game.developers.map(&:name)
      rows << [ "dev", developer_names.join(", ") ] if developer_names.any?
      publisher_names = game.publishers.map(&:name)
      rows << [ "pub", publisher_names.join(", ") ] if publisher_names.any?
      rows << [ "sync", sync_value ]
      rows
    end
  end

  private

  def sync_value
    return "---" if game.resyncing?

    helpers.compact_time_ago(game.igdb_synced_at)
  end
end
