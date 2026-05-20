module Settings
  module Stack
    # Renders a single tri-state health line: `<strong>label</strong>`
    # followed by a `Tui::ChipComponent` whose label + variant encode
    # the current state.
    #
    # Beta 4 F3-D — switched the status surface from a colored glyph +
    # word span to the canonical `[ label ]` chip primitive (ADR 0016
    # TUI design system). The component still owns the label-to-state
    # mapping, so consumers do not pass chip variants directly — they
    # pass a semantic state (`:connected`, `:writable`, `:configured`,
    # …) and the component resolves the chip copy + variant.
    #
    # State enum maps to chip label + chip variant verbatim:
    #
    #   :connected      → `[connected]`      success
    #   :disconnected   → `[disconnected]`   danger
    #   :writable       → `[writable]`       info
    #   :read_only      → `[read-only]`      danger
    #   :absent         → `[not present]`    warn
    #   :configured     → `[configured]`     info
    #   :not_configured → `[not configured]` danger
    #
    # Per-consumer state expression varies. Postgres / Redis /
    # Meilisearch flip between `:connected` / `:disconnected`; assets
    # / notes flip across `:writable` / `:read_only` / `:absent`;
    # Voyage flips between `:configured` / `:not_configured`. The
    # component does not own the predicate logic — callers infer it
    # from their existing local flags.
    class HealthLineComponent < ViewComponent::Base
      STATES = {
        connected:      { chip_label: "connected",      chip_variant: :success },
        disconnected:   { chip_label: "disconnected",   chip_variant: :danger  },
        writable:       { chip_label: "writable",       chip_variant: :info    },
        read_only:      { chip_label: "read-only",      chip_variant: :danger  },
        absent:         { chip_label: "not present",    chip_variant: :warn    },
        configured:     { chip_label: "configured",     chip_variant: :info    },
        not_configured: { chip_label: "not configured", chip_variant: :danger  }
      }.freeze

      # @param label [String] the bolded check name, e.g. "Postgres".
      # @param state [Symbol] one of {STATES} keys. Anything else
      #   raises `ArgumentError` so a typo at the call site never
      #   silently renders a blank status.
      def initialize(label:, state:)
        unless STATES.key?(state)
          raise ArgumentError, "unknown state #{state.inspect} (expected one of #{STATES.keys.inspect})"
        end

        @label = label
        @state = state
      end

      def chip_label
        STATES.fetch(@state).fetch(:chip_label)
      end

      def chip_variant
        STATES.fetch(@state).fetch(:chip_variant)
      end

      attr_reader :label, :state
    end
  end
end
