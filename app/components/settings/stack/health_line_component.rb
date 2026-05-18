module Settings
  module Stack
    # Renders a single tri-state health line: `<strong>label</strong>`
    # followed by a glyph + status word colored by severity.
    #
    # Extracted from `app/views/settings/_stack_pane.html.erb` (Postgres,
    # Redis, Meilisearch, assets, notes) and
    # `app/views/settings/_voyage_section.html.erb` (Voyage AI) per
    # Beta-3 lane B candidate B10. The seven inline 7-9-line `div`
    # blocks all shared the same shape: a label + a tri-state status
    # span, only the glyph / copy / color combination changed per
    # check.
    #
    # State enum maps to glyph + copy + color class verbatim from the
    # existing source:
    #
    #   :connected      → green   "▲ connected"      (success)
    #   :disconnected   → red     "▽ disconnected"   (danger)
    #   :writable       → green   "▲ writable"       (success)
    #   :read_only      → red     "▽ read-only"      (danger)
    #   :absent         → muted   "▽ not present"    (muted)
    #   :configured     → green   "▲ configured"     (success)
    #   :not_configured → red     "▽ not configured" (danger)
    #
    # Per-consumer state expression varies. Postgres / Redis /
    # Meilisearch flip between `:connected` / `:disconnected`; assets
    # / notes flip across `:writable` / `:read_only` / `:absent`;
    # Voyage flips between `:configured` / `:not_configured`. The
    # component does not own the predicate logic — callers infer it
    # from their existing local flags.
    class HealthLineComponent < ViewComponent::Base
      STATES = {
        connected:      { glyph: "▲", copy: "connected",      severity: :success },
        disconnected:   { glyph: "▽", copy: "disconnected",   severity: :danger  },
        writable:       { glyph: "▲", copy: "writable",       severity: :success },
        read_only:      { glyph: "▽", copy: "read-only",      severity: :danger  },
        absent:         { glyph: "▽", copy: "not present",    severity: :muted   },
        configured:     { glyph: "▲", copy: "configured",     severity: :success },
        not_configured: { glyph: "▽", copy: "not configured", severity: :danger  }
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

      def glyph
        STATES.fetch(@state).fetch(:glyph)
      end

      def copy
        STATES.fetch(@state).fetch(:copy)
      end

      # @return [String] inline style / class for the status span.
      #   Matches the existing inline pattern in the source templates:
      #     success → `style="color: var(--color-success);"`
      #     danger  → `class="text-danger"`
      #     muted   → `class="text-muted"`
      def status_attrs
        case STATES.fetch(@state).fetch(:severity)
        when :success then { style: "color: var(--color-success);" }
        when :danger  then { class: "text-danger" }
        when :muted   then { class: "text-muted" }
        end
      end

      attr_reader :label, :state
    end
  end
end
