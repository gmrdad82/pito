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
  #
  # Label resolution (2026-05-18): items in the YAML carry a
  # `label_i18n:` reference (e.g. `keybindings.page_actions.games_index.search`)
  # rather than an inline `label:` string. The helper resolves the i18n
  # key into the actual translated string and injects it as `label` in
  # the payload so the Stimulus controller (which only reads `item.label`)
  # keeps working without any JS-side change. Items still carrying a
  # raw `label:` fall through as-is for safety / back-compat.
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
        "items" => menu.fetch("items")
                       .select { |item| item_visible?(item, surface) }
                       .map { |item| resolve_label(item) }
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
      "page_actions" => resolve_section_labels(schema.fetch("page_actions", {})),
      # `modal_actions:` is the modal-as-page parallel to
      # `page_actions:` (A2, 2026-05-17). When a `<dialog open>` on
      # the page carries `data-modal-actions-key="<key>"`, the
      # `leader-menu` Stimulus controller resolves
      # `schema.modal_actions[<key>].items` instead of the page-actions
      # list (and suppresses navigation + logout entirely). Defaults to
      # an empty hash until Phase B starts populating modal entries.
      # Same "no surfaces filtering" rule applies as page_actions.
      "modal_actions" => resolve_modal_actions_labels(schema.fetch("modal_actions", {}) || {}),
      # `flat:` is the leader-less entry-point block (`/` opens
      # omnisearch, `g` / `q` open the leader popup in compact mode
      # seeded with that prefix). Consumed by the `flat-key` Stimulus
      # controller; see `flat_key_controller.js`. The block has no
      # `surfaces:` keys today so no per-surface filtering applies.
      "flat" => resolve_flat_labels(schema.fetch("flat", {}) || {})
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

  # Resolve `label_i18n` (preferred) into a literal `label` string so
  # the Stimulus controller can read `item.label` directly. Divider
  # rows and rows already carrying a literal `label:` are returned
  # untouched. The original hash is never mutated — a shallow dup is
  # produced when we need to write back the resolved label.
  def resolve_label(item)
    return item unless item.is_a?(Hash)
    return item if item["divider"]
    key = item["label_i18n"]
    return item if key.blank?
    item.merge("label" => I18n.t(key))
  end

  # Walk a `page_actions:` block (`{ <page_key> => [rows, ...] }`) and
  # resolve labels in every row.
  def resolve_section_labels(section)
    section.transform_values do |rows|
      rows.map { |row| resolve_label(row) }
    end
  end

  # Walk a `modal_actions:` block (`{ <modal_key> => { items: [rows] } }`)
  # and resolve labels in every modal's items list.
  def resolve_modal_actions_labels(modal_actions)
    modal_actions.transform_values do |entry|
      next entry unless entry.is_a?(Hash)
      items = entry["items"]
      next entry unless items.is_a?(Array)
      entry.merge("items" => items.map { |row| resolve_label(row) })
    end
  end

  # Walk a `flat:` block (`{ items: [rows] }`) and resolve labels on
  # every row. Same shape as a single `modal_actions` entry — one
  # `items` array of `{ key, label_i18n, action }` hashes. Returns
  # `{}` when the block is missing entirely (defensive: schemas
  # without `flat:` still parse cleanly).
  def resolve_flat_labels(flat)
    return flat unless flat.is_a?(Hash)
    items = flat["items"]
    return flat unless items.is_a?(Array)
    flat.merge("items" => items.map { |row| resolve_label(row) })
  end
end
