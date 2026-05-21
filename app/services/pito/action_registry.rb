module Pito
  # ADR 0018 — Action bus + cable architecture.
  #
  # Canonical registry of every user-triggerable action in pito. Each
  # registered entry is a `Pito::Action` value object; the registry
  # indexes by symbol name (e.g. `:reindex_meilisearch`).
  #
  # Definitions live in `config/initializers/pito_actions.rb` (loaded
  # via `Rails.application.config.after_initialize` so route helpers are
  # resolvable). The registry is the single seam every consumer reads:
  # web JS dispatcher, palette, leader menu, MCP tool surface, CLI.
  module ActionRegistry
    extend self

    @registry = {}

    def define(name, path:, method: :post, confirmation: nil, i18n_key:, cable_panel: nil)
      @registry[name.to_sym] = Pito::Action.new(
        name: name.to_sym,
        path_proc: path,
        method: method,
        confirmation: confirmation,
        i18n_key: i18n_key,
        cable_panel: cable_panel
      )
    end

    def [](name)
      @registry.fetch(name.to_sym)
    end

    def all
      @registry.values
    end

    def reset!
      @registry = {}
    end
  end
end
