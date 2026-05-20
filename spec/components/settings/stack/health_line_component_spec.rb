require "rails_helper"

# Beta 4 F3-D — `HealthLineComponent` now renders a label + a
# `Tui::ChipComponent` whose label + variant encode the current state.
# The previous glyph + colored word span surface is gone (replaced by
# the canonical `[ label ]` bracket grammar from ADR 0016).
RSpec.describe Settings::Stack::HealthLineComponent, type: :component do
  # Each state maps to a chip label + chip variant verbatim from
  # `STATES`. The matrix below is the single behavioral surface — one
  # `it` per state asserts the chip label appears and the chip carries
  # the expected variant class.
  STATE_EXPECTATIONS = {
    connected:      { label: "connected",      variant: :success },
    disconnected:   { label: "disconnected",   variant: :danger  },
    writable:       { label: "writable",       variant: :info    },
    read_only:      { label: "read-only",      variant: :danger  },
    absent:         { label: "not present",    variant: :warn    },
    configured:     { label: "configured",     variant: :info    },
    not_configured: { label: "not configured", variant: :danger  }
  }.freeze

  STATE_EXPECTATIONS.each do |state, expected|
    it "renders a `Tui::ChipComponent` " \
       "`[#{expected[:label]}]` with variant :#{expected[:variant]} " \
       "for state :#{state}" do
      render_inline(described_class.new(label: "Postgres", state: state))

      expect(page).to have_css(
        ".tui-chip.tui-chip--#{expected[:variant]}",
        text: "[#{expected[:label]}]"
      )
    end
  end

  it "renders the label inside a <strong> tag" do
    render_inline(described_class.new(label: "Voyage AI", state: :configured))

    expect(page).to have_css("strong", text: "Voyage AI")
  end

  it "raises ArgumentError when given an unknown state" do
    expect {
      described_class.new(label: "Postgres", state: :on_fire)
    }.to raise_error(ArgumentError, /unknown state/)
  end

  it "lays out the label and the chip on a single flex row " \
     "(label flush left, chip flush right)" do
    render_inline(described_class.new(label: "Postgres", state: :connected))

    # Inline flex container — single row, two children (label span +
    # chip span). `justify-content: space-between` keeps the chip flush
    # right.
    expect(page).to have_css(
      'div[style*="display: flex"][style*="justify-content: space-between"]'
    )
  end

  it "exposes `chip_label` + `chip_variant` accessors keyed off STATES" do
    component = described_class.new(label: "Redis", state: :disconnected)

    expect(component.chip_label).to eq("disconnected")
    expect(component.chip_variant).to eq(:danger)
  end
end
