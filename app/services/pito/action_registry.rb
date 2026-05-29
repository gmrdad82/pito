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
  #
  # Scope system (2026-05-25) — every action carries a `scope:` symbol:
  #   :global  — surfaces in the `:` palette on every screen (default)
  #   :home    — only visible on the home screen (dashboard / system panels)
  #   :videos  — only visible on the videos screen
  #   :games   — only visible on the games screen
  #
  # `for_screen(screen)` returns the subset of actions scoped to `:global`
  # OR the given screen. The layout helper `pito_screen_actions_json` uses
  # this to embed the screen-filtered catalog at first paint so the palette
  # does not show irrelevant commands (e.g. "reindex Meilisearch" must not
  # appear when browsing /videos).
  module ActionRegistry
    extend self

    VALID_SCOPES = %i[global home videos games].freeze

    @registry = {}

    # Define a new action and add it to the registry.
    #
    # @param name [Symbol, String] canonical action key
    # @param path [Proc] lazy route helper lambda
    # @param method [Symbol] HTTP method (:get, :post, :patch, :delete)
    # @param confirmation [Hash, nil] optional confirmation dialog descriptor
    # @param i18n_key [String] dotted I18n key prefix (`.name` + `.hint` appended)
    # @param cable_panel [String, nil] cable channel this action broadcasts to
    # @param scope [Symbol] palette visibility scope — :global (default), :home,
    #   :videos, or :games. Use :home for actions that ONLY make sense on the
    #   home screen (reindex, stack health). Use :global for navigation and
    #   universal commands.
    def define(name, path:, method: :post, confirmation: nil, i18n_key:, cable_panel: nil, scope: :global)
      resolved_scope = scope.to_sym
      unless VALID_SCOPES.include?(resolved_scope)
        raise ArgumentError, "Pito::ActionRegistry.define: unknown scope #{resolved_scope.inspect}. " \
                             "Valid: #{VALID_SCOPES.map(&:inspect).join(', ')}"
      end

      @registry[name.to_sym] = Pito::Action.new(
        name: name.to_sym,
        path_proc: path,
        method: method,
        confirmation: confirmation,
        i18n_key: i18n_key,
        cable_panel: cable_panel,
        scope: resolved_scope
      )
    end

    def [](name)
      @registry.fetch(name.to_sym)
    end

    def all
      @registry.values
    end

    # Returns all actions whose scope is :global OR matches `screen`.
    #
    # @param screen [Symbol, String] one of :home, :videos, :games (or "home",
    #   "videos", "games"). Passing :global / "global" returns only the
    #   global-scoped actions (useful for MCP / CLI surfaces that don't have
    #   a screen concept).
    # @return [Array<Pito::Action>]
    def for_screen(screen)
      s = screen.to_sym
      @registry.values.select { |action| action.scope == :global || action.scope == s }
    end

    def reset!
      @registry = {}
    end
  end
end
