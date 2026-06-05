module Pito
  # ADR 0018 — Action bus + cable architecture.
  #
  # Immutable value object representing a single user-triggerable action.
  # Constructed by `Pito::ActionRegistry.define` at boot from a
  # `config/initializers/pito_actions.rb` block; consumers (web Stimulus
  # dispatcher, palette, leader menu) all read the same record.
  #
  # `path_proc` is wrapped in a Proc because Rails route helpers must be
  # resolved AFTER routes are loaded; `path` calls the proc lazily.
  #
  # `scope` declares which screen surfaces the action in the `:` palette.
  # Values: `:global` (all screens), `:home`, `:videos`, `:games`.
  # Defaults to `:global` when not provided. `Pito::ActionRegistry.for_screen`
  # uses this field to filter the catalog per screen.
  #
  # `to_h` serializes the JS-readable subset to embed in the
  # `<meta name="pito-actions">` tag at first paint.
  Action = Data.define(:name, :path_proc, :method, :confirmation, :i18n_key, :cable_panel, :scope) do
    def path
      path_proc.call
    end

    def to_h
      {
        name: name.to_s,
        path: (path rescue nil),
        method: method.to_s,
        confirmation: confirmation,
        i18n_name: I18n.t("#{i18n_key}.name"),
        i18n_hint: I18n.t("#{i18n_key}.hint"),
        cable_panel: cable_panel,
        scope: scope.to_s
      }
    end
  end
end
