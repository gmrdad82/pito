# Renders the keybindings reference card as TWO sections:
#
#   1. Page actions  — keys specific to the current route (search,
#      sync, delete, etc.). Rendered FIRST so the user sees the
#      immediate context-specific affordances at the top of the card.
#   2. Navigation    — the always-true leader-menu hierarchy.
#
# Per spec 09 (docs/plans/beta/27-games-listing-shelves-filters-display-modes/
# specs-v2/09-keybindings-page-actions.md) §"Two-section UI" +
# §"Per-page contracts", with the user-confirmed §25.3 ordering
# decision (page actions FIRST).
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
# page-actions section and the hairline separator are BOTH omitted —
# the card renders the navigation section only, cleanly.
class KeybindingsReferenceComponent < ViewComponent::Base
  # Pages that intentionally render NO page-actions section. Used to
  # short-circuit before consulting the YAML `default:` fallback so
  # /settings, /admin and similar utility surfaces stay clean. Per
  # spec 09 §"Per-page contracts": "/settings is INTENTIONALLY
  # ABSENT — no page-actions section renders on /settings".
  NO_PAGE_ACTIONS_PAGES = %w[settings admin].freeze

  def initialize(page_key: nil)
    @page_key = page_key
  end

  # Resolved page-actions rows for the current page. Returns [] when:
  #   * page_key is nil (caller did not provide one)
  #   * page_key is in the deny-list NO_PAGE_ACTIONS_PAGES
  #   * the YAML has no entry for page_key AND no `default:` fallback
  # The deny-list check happens BEFORE the `default:` fallback so
  # /settings does not accidentally inherit the global `/ search`
  # default entry.
  def page_actions
    return [] if @page_key.nil?
    return [] if NO_PAGE_ACTIONS_PAGES.include?(@page_key)

    config.fetch("page_actions", {})[@page_key] ||
      config.fetch("page_actions", {})["default"] ||
      []
  end

  # The leader-menu navigation hierarchy (root + submenus). Unchanged
  # by this spec — the existing `menus:` block in
  # `config/keybindings.yml` is the source.
  def navigation_menus
    config.fetch("menus", {})
  end

  private

  # Reads the parsed schema from the boot-time initializer
  # (`config/initializers/keybindings.rb`) when available so we don't
  # re-parse the YAML on every render. Falls back to a direct
  # `YAML.load_file` for contexts where the initializer hasn't run
  # (e.g. an isolated component spec without Rails boot).
  def config
    @config ||= Rails.application.config.try(:keybindings) ||
                YAML.load_file(Rails.root.join("config", "keybindings.yml"))
  end
end
