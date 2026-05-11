module KeyboardNavigationHelper
  # Hjkl-on-every-surface helper (2026-05-10).
  #
  # The global keyboard controller (`app/javascript/controllers/keyboard_controller.js`)
  # binds `h` / `l` to "previous / next sibling in the current sort order"
  # on detail (show) pages. Detail templates emit the two URLs as data
  # attributes (`data-keyboard-detail-prev-url`, `data-keyboard-detail-next-url`)
  # on a container the controller looks up via `document.querySelector`.
  # This helper centralizes the lookup so every show template uses the
  # same scope semantics (and so we can spec the computation once).
  #
  # Scope order is the model's natural ID order (ascending). That choice
  # is deliberate:
  #
  #   * It is stable — every record has an id and they never collide.
  #   * It is decoupled from the per-page URL sort params that drive the
  #     index list. The helper doesn't see the user's index sort and we
  #     don't want a brittle "remember the last index sort in a cookie"
  #     dance for sibling navigation. The CLI follows the same convention.
  #   * On most surfaces (channels, videos, games, ...) created_at order
  #     matches id order anyway, so the user-visible sibling order is the
  #     same as on the index page's default view.
  #
  # `record` is the current model instance. `scope` is any ActiveRecord
  # relation; usually `Model` (all records) or `record.class` is fine,
  # but parent-scoped lists pass the parent's association (e.g. a Note
  # belongs_to a Project and the sibling set is "notes in this project").
  # `path_helper` is a callable (proc / lambda / method object) that
  # turns a record into its show URL — pass `method(:foo_path)` so the
  # helper resolves slug-aware URLs through Rails' URL helpers.
  #
  # Returns:
  #
  #   * `keyboard_detail_nav_attrs` — a hash like
  #     `{ "data-keyboard-detail-prev-url" => "/foo/1",
  #        "data-keyboard-detail-next-url" => "/foo/3" }` that callers
  #     splat into a `tag.div` or interpolate via the companion
  #     `keyboard_detail_nav_data_attributes` method below. Empty hash
  #     when there are no siblings.
  #   * `keyboard_detail_nav_data_attributes` — an `html_safe` string of
  #     `key="value" key2="value2"` pairs for direct interpolation
  #     inside a raw `<div ...>` tag. Empty string when no siblings.
  def keyboard_detail_nav_attrs(record, scope:, path_helper:)
    return {} if record.nil? || record.id.nil?

    relation = scope.respond_to?(:reorder) ? scope.reorder(:id) : scope.order(:id)

    prev_record = relation.where("#{record.class.table_name}.id < ?", record.id).last
    next_record = relation.where("#{record.class.table_name}.id > ?", record.id).first

    attrs = {}
    attrs["data-keyboard-detail-prev-url"] = path_helper.call(prev_record) if prev_record
    attrs["data-keyboard-detail-next-url"] = path_helper.call(next_record) if next_record
    attrs
  end

  # Renders the prev/next URL pair as inline HTML attribute pairs,
  # safe for interpolation inside a `<div ...>` tag. Empty string (also
  # html_safe) when the record has no sibling on either side, so the
  # template can render `<div ... <%= ... %>>` unconditionally without
  # leaving stray whitespace or attribute fragments.
  def keyboard_detail_nav_data_attributes(record, scope:, path_helper:)
    attrs = keyboard_detail_nav_attrs(record, scope: scope, path_helper: path_helper)
    return "".html_safe if attrs.empty?

    attrs.map { |k, v| %(#{k}="#{ERB::Util.html_escape(v)}") }.join(" ").html_safe
  end
end
