require_relative "definition"

module Pito
  module Themes
    # Theme registry — discovers and stores all Definition objects.
    #
    # Auto-discovery / self-registration contract
    # --------------------------------------------
    # Each file under `definitions/` calls `Registry.register(<raw_hash>)`
    # when loaded. The Registry auto-requires the glob once (at first access),
    # so callers never need to manually require individual definition files.
    #
    # Adding a new theme = dropping a file in `definitions/` that ends with
    # a `Registry.register(...)` call. No other wiring is required.
    #
    # Public API
    # ----------
    #   Registry.all        → Array<Definition> in stable registration order
    #   Registry.find(slug) → Definition | nil
    #   Registry.names      → Array<String> of slugs
    #   Registry.grouped    → { dark: [...], light: [...] }
    #   Registry.default    → the "tokyo-night" Definition
    module Registry
      DEFAULT_SLUG = "tokyo-night"

      @definitions = []
      @loaded      = false

      class << self
        # Called by each definition file to self-register.
        # @param raw [Hash] the raw theme hash accepted by Definition.from_raw
        def register(raw)
          @definitions << Definition.from_raw(raw)
        end

        # @return [Array<Definition>] all registered themes, stable order
        def all
          load_definitions
          @definitions
        end

        # @param slug [String]
        # @return [Definition, nil]
        def find(slug)
          all.find { |d| d.slug == slug }
        end

        # @return [Array<String>] all registered slugs
        def names
          all.map(&:slug)
        end

        # @return [Hash{ Symbol => Array<Definition> }]
        def grouped
          all.group_by(&:mode)
        end

        # @return [Definition] the default theme (tokyo-night)
        def default
          find(DEFAULT_SLUG) or raise "Default theme '#{DEFAULT_SLUG}' not found in registry"
        end

        # Resolves a slug OR the token "default" to a Definition.
        # "default" is a special alias that always resolves to Registry.default.
        # Returns nil when the token matches no registered slug and is not "default".
        #
        # @param token [String, Symbol]
        # @return [Definition, nil]
        def resolve_target(token)
          slug = token.to_s.strip.downcase
          return default if slug == "default"

          find(slug)
        end

        private

        def load_definitions
          return if @loaded

          @loaded = true
          glob = File.join(__dir__, "definitions", "*.rb")
          Dir.glob(glob).sort.each { |f| require f }
        end
      end
    end
  end
end
