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
    schema = Rails.application.config.keybindings
    filtered_menus = schema.fetch("menus").transform_values do |menu|
      {
        "items" => menu.fetch("items").select { |item| item_visible?(item, surface) }
      }
    end
    {
      "leader" => schema.fetch("leader"),
      "menus" => filtered_menus
    }
  end

  private

  def item_visible?(item, surface)
    allowed = item["surfaces"]
    return true if allowed.nil?
    Array(allowed).map(&:to_s).include?(surface.to_s)
  end
end
