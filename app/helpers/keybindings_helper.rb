module KeybindingsHelper
  # Returns the unified keybindings schema as a JSON string ready to
  # be embedded in the layout. The Stimulus `leader-menu` controller
  # parses this on connect, walks the `menus` tree in response to key
  # presses, and renders the popup card.
  #
  # The web schema filters out items tagged `surfaces: [tui]` so the
  # quit-process binding (`q`) doesn't appear in the web popup; the
  # CLI does the symmetric filter for any items tagged `surfaces:
  # [web]`. When `surfaces` is absent the item renders on both
  # surfaces.
  #
  # The output is `html_safe` because it is embedded inside a
  # `<script type="application/json">` tag whose contents are NOT
  # parsed as HTML; the browser hands the literal bytes to
  # `JSON.parse`. The schema itself is statically defined in
  # `config/keybindings.yml` and contains no user-controlled strings,
  # so there is no XSS surface here.
  def keybindings_as_json
    JSON.generate(keybindings_for_surface(:web)).html_safe
  end

  # Returns the schema as a plain Ruby hash filtered for the given
  # surface (`:web` or `:tui`). Exposed for spec assertions; the
  # layout uses the JSON wrapper above.
  def keybindings_for_surface(surface)
    # In development the initializer stores a Proc that re-parses
    # `config/keybindings.yml` on every call so YAML edits show up on
    # browser refresh without a `bin/dev` restart. In prod / test it
    # stores the deep-frozen hash itself, so this branch resolves to a
    # no-op cost on those environments.
    raw = Rails.application.config.keybindings
    schema = raw.respond_to?(:call) ? raw.call : raw
    filtered_menus = schema.fetch("menus").transform_values do |menu|
      {
        "items" => menu.fetch("items").select { |item| item_visible?(item, surface) }
      }
    end
    {
      "leader" => schema.fetch("leader"),
      "menus" => filtered_menus,
      # `page_actions:` is shipped to the web surface intact so the
      # `leader-menu` Stimulus controller can render the per-page
      # action rows in the popup's top section (2026-05-17). The TUI
      # equivalent reads the YAML directly and does not consume this
      # branch. No `surfaces:` filtering applies here — the
      # `page_actions:` block contains no per-surface keys today.
      "page_actions" => schema.fetch("page_actions", {})
    }
  end

  # Resolves the current controller#action to the YAML key under
  # `page_actions:` in `config/keybindings.yml`. Used by the layout to
  # pass `page_key:` into `KeybindingsReferenceComponent`. Returns nil
  # for pages that should render NO page-actions section (admin,
  # auth pages); returns `"default"` for pages that have no explicit
  # mapping but are still "regular" pages and should fall through to
  # the shared default actions (currently just `/ search`).
  #
  # The explicit mappings stay small and obvious — every page that
  # wants context-specific keys (sync, delete, etc.) registers its
  # own `<resource>_<action>` key here AND in the YAML. Settings
  # registers a `settings` group containing ONLY the dark-mode toggle
  # (per user direction 2026-05-17).
  def keybindings_page_key
    case "#{controller_name}##{action_name}"
    when "games#index"   then "games_index"
    when "games#show"    then "games_show"
    when "bundles#show"  then "bundles_show"
    else
      controller_path_root = controller_path.to_s.split("/").first
      return "settings" if controller_path_root == "settings"
      return nil if KeybindingsReferenceComponent::NO_PAGE_ACTIONS_PAGES.include?(controller_path_root)
      "default"
    end
  end

  private

  def item_visible?(item, surface)
    allowed = item["surfaces"]
    return true if allowed.nil?
    Array(allowed).map(&:to_s).include?(surface.to_s)
  end
end
