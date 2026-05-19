# Renders the keybindings reference card as TWO sections:
#
#   1. local   — keys specific to the current page (formerly "page
#                actions"). Renders FIRST so the user sees the
#                immediate context-specific affordances at the top.
#   2. global  — the always-true navigation surface (formerly
#                "navigation"). Trimmed 2026-05-18 to /games + /settings
#                + logout only.
#
# Layout markers — divider rows in `page_actions` may carry
# `layout: grid_2col` to open a 2-column grid that closes at the next
# plain divider OR end-of-list. The grid lays items out COLUMN-FIRST
# (CSS `grid-auto-flow: column` + `grid-template-rows: repeat(half,
# auto)`) so a group of 8 items renders 5 left / 3 right and a group
# of 2 renders 1 left / 1 right. See `app/assets/tailwind/application.css`
# for the `.keybindings-grid--two-col` rule.
#
# The component is page-aware via the `page_key:` initialize arg. The
# layout passes `keybindings_page_key` (see
# `app/helpers/keybindings_helper.rb`) which maps the current
# controller#action to a YAML key under `page_actions:` in
# `config/keybindings.yml`.
#
# Empty-page-actions handling: when the resolved `page_actions` list
# is empty (either because the page is on the deny-list or because no
# entry exists in YAML and no `default` fallback applies), the
# "local" section and the hairline separator are BOTH omitted — the
# card renders the "global" section only, cleanly.
class KeybindingsReferenceComponent < ViewComponent::Base
  # Pages that intentionally render NO page-actions section. Used to
  # short-circuit before consulting the YAML `default:` fallback so
  # /admin and similar utility surfaces stay clean.
  NO_PAGE_ACTIONS_PAGES = %w[admin].freeze

  # Section group representation. Each group is either a single-column
  # run of rows OR a 2-column grid run, opened by a divider carrying
  # `layout: grid_2col` and closed at the next divider OR end-of-list.
  # The template iterates these groups; dividers between groups paint
  # as visible hairlines but never themselves render as a binding row.
  Group = Struct.new(:layout, :items, keyword_init: true)

  def initialize(page_key: nil)
    @page_key = page_key
  end

  # Raw page_actions rows (compat surface for specs + callers that walk
  # the flat list). Returns [] when:
  #   * page_key is nil
  #   * page_key is in NO_PAGE_ACTIONS_PAGES
  #   * the YAML has no entry for page_key AND no `default:` fallback
  #
  # Rows carrying `label_i18n:` get a resolved `label:` field injected
  # (the original hash is not mutated) so callers walking the flat
  # list see human-readable labels without re-doing the lookup. Rows
  # already carrying a raw `label:` pass through unchanged.
  def page_actions
    return [] if @page_key.nil?
    return [] if NO_PAGE_ACTIONS_PAGES.include?(@page_key)

    rows = config.fetch("page_actions", {})[@page_key] ||
           config.fetch("page_actions", {})["default"] ||
           []
    rows.map { |row| resolve_row_label(row) }
  end

  # Grouped representation of the "local" section. Walks `page_actions`
  # and folds runs of items between dividers into Group structs. A
  # divider carrying `layout: grid_2col` opens a grid group; a plain
  # divider opens a regular single-column group; the first run (before
  # any divider) is always single-column.
  def local_groups
    build_groups(page_actions)
  end

  # The "global" section — the flat root-menu list. Each row is either
  # a binding (`key`, `label`, `action`) or a divider
  # (`{ "divider" => true }`).
  #
  # 2026-05-18 the surface was trimmed to /games + /settings + logout
  # only; the legacy submenu indices and the calendar / channels /
  # videos / projects / notifications bindings were dropped entirely.
  def navigation_items
    config.fetch("menus", {}).fetch("root", {}).fetch("items", [])
          .map { |row| resolve_row_label(row) }
  end

  # Grouped representation of the "global" section. Same Group struct
  # as `local_groups`; the root menu does not yet use grid layouts so
  # every group falls through as single-column today.
  def global_groups
    build_groups(navigation_items)
  end

  # Render a sequence of Group structs as HTML, painting visible
  # hairlines BETWEEN groups (never at the very top or bottom). Each
  # group renders as either a `<div class="keybindings-grid
  # keybindings-grid--two-col">` (for `:grid_2col`) or a plain run of
  # `<div class="keybindings-row">` rows. The 2-col grid carries an
  # inline `grid-template-rows: repeat(<half>, auto)` so the CSS
  # `grid-auto-flow: column` rule (in application.css) fills items
  # column-first (5 left / 3 right for 8 items, 1 left / 1 right for 2).
  def render_groups(groups)
    safe_join(
      groups.each_with_index.flat_map do |group, idx|
        chunks = []
        if idx.positive?
          chunks << tag.hr(class: "hairline keybindings-divider")
        end
        chunks << render_group(group)
        chunks
      end
    )
  end

  def render_group(group)
    if group.layout == :grid_2col
      half = (group.items.size / 2.0).ceil
      tag.div(
        class: "keybindings-grid keybindings-grid--two-col",
        style: "grid-template-rows: repeat(#{half}, auto);"
      ) do
        safe_join(group.items.map { |item| render_row(item) })
      end
    else
      safe_join(group.items.map { |item| render_row(item) })
    end
  end

  def render_row(item)
    tag.div(class: "keybindings-row") do
      safe_join([
        tag.kbd(item["key"]),
        tag.span(row_label(item))
      ])
    end
  end

  # Resolve a row's user-visible label. Prefers the i18n key under
  # `label_i18n:` (the canonical surface after the 2026-05-18
  # externalization sweep); falls through to a raw `label:` field for
  # safety / back-compat with any future row that has not yet been
  # migrated. Returns an empty string when neither is present so the
  # rendered span stays well-formed.
  def row_label(item)
    key = item["label_i18n"]
    return I18n.t(key) if key.present?
    item["label"].to_s
  end

  # Return a shallow-copied row with `label` injected (resolved from
  # `label_i18n`) so flat-list consumers (specs, JSON serializers,
  # whatever walks the rows directly) see the same label the renderer
  # paints. Dividers and rows already carrying `label:` pass through
  # untouched.
  def resolve_row_label(item)
    return item unless item.is_a?(Hash)
    return item if item["divider"]
    key = item["label_i18n"]
    return item if key.blank?
    item.merge("label" => I18n.t(key))
  end

  private

  # Folds a flat list of rows into a sequence of Group structs.
  # Dividers act as group separators; a divider carrying
  # `layout: grid_2col` opens a 2-col grid group; any other divider
  # (or the implicit start before the first divider) opens a single-
  # column group. Empty groups (consecutive dividers, leading divider
  # with no preceding items) are skipped so the rendered output stays
  # clean.
  def build_groups(rows)
    groups = []
    current_layout = :single
    current_items = []
    flush = lambda do
      groups << Group.new(layout: current_layout, items: current_items) if current_items.any?
      current_items = []
    end

    rows.each do |row|
      if row["divider"]
        flush.call
        current_layout = row["layout"] == "grid_2col" ? :grid_2col : :single
      else
        current_items << row
      end
    end
    flush.call
    groups
  end

  # Reads the parsed schema from the boot-time initializer
  # (`config/initializers/keybindings.rb`) when available so we don't
  # re-parse the YAML on every render. Falls back to a direct
  # `YAML.load_file` for contexts where the initializer hasn't run
  # (e.g. an isolated component spec without Rails boot).
  #
  # The initializer stores either a frozen Hash (prod/test) OR a Proc
  # that re-parses YAML on each call (development — so edits become
  # visible without restarting `bin/dev`). Unwrap the Proc here so
  # downstream accessors uniformly see a Hash.
  def config
    @config ||= begin
      raw = Rails.application.config.try(:keybindings)
      raw = raw.call if raw.respond_to?(:call)
      raw || YAML.load_file(Rails.root.join("config", "keybindings.yml"))
    end
  end
end
