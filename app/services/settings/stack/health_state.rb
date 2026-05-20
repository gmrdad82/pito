module Settings
  module Stack
    # Pure-data lookup table mapping a semantic health state symbol to
    # the chip label + chip variant the stack pane renders inline.
    #
    # FB-82 (2026-05-20) — extracted from the now-deleted
    # `Settings::Stack::HealthLineComponent`. After FB-63-V4 moved the
    # status chip into the sub-panel header's right-cluster, no view
    # rendered the component itself; only its `STATES` hash was
    # consulted inline by `_stack_pane.html.erb`. The component carried
    # an ERB template + initializer + accessors that nothing exercised,
    # so the constant migrated here and the component was deleted.
    #
    # FB-6 collapsed the variant cascade from 4 colors
    # (success / info / warn / danger) to 2 (success / danger): every
    # "healthy" state reads green, every "unhealthy" state reads danger
    # pink. `:absent` lives on the danger side because the notes /
    # storage volume being absent is operationally a failure.
    #
    # Per-consumer state expression varies. Postgres / Redis /
    # Meilisearch flip between `:connected` / `:disconnected`; assets
    # / notes flip across `:writable` / `:read_only` / `:absent`;
    # Voyage flips between `:configured` / `:not_configured`. The
    # module does not own the predicate logic — callers infer it from
    # their existing local flags and `fetch` the matching chip metadata.
    module HealthState
      STATES = {
        connected:      { chip_label: "connected",      chip_variant: :success },
        disconnected:   { chip_label: "disconnected",   chip_variant: :danger  },
        writable:       { chip_label: "writable",       chip_variant: :success },
        read_only:      { chip_label: "read-only",      chip_variant: :danger  },
        absent:         { chip_label: "not present",    chip_variant: :danger  },
        configured:     { chip_label: "configured",     chip_variant: :success },
        not_configured: { chip_label: "not configured", chip_variant: :danger  }
      }.freeze
    end
  end
end
