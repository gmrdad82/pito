require "rails_helper"

RSpec.describe Settings::Stack::HealthLineComponent, type: :component do
  # Each state maps to a glyph + copy + severity tuple verbatim from
  # the source templates `_stack_pane.html.erb` +
  # `_voyage_section.html.erb`. The matrix below is the single
  # behavioral surface — one `it` per state asserts the glyph + copy.
  STATE_EXPECTATIONS = {
    connected:      "▲ connected",
    disconnected:   "▽ disconnected",
    writable:       "▲ writable",
    read_only:      "▽ read-only",
    absent:         "▽ not present",
    configured:     "▲ configured",
    not_configured: "▽ not configured"
  }.freeze

  STATE_EXPECTATIONS.each do |state, expected_text|
    it "renders glyph + copy '#{expected_text}' for state :#{state}" do
      render_inline(described_class.new(label: "Postgres", state: state))
      expect(page).to have_text(expected_text)
    end
  end

  it "renders the label inside a <strong> tag" do
    render_inline(described_class.new(label: "Voyage AI", state: :configured))
    expect(page).to have_css("strong", text: "Voyage AI")
  end

  it "applies the success color style to success-severity states" do
    render_inline(described_class.new(label: "Redis", state: :connected))
    expect(page).to have_css('span[style*="--color-success"]', text: "▲ connected")
  end

  it "applies the text-danger class to danger-severity states" do
    render_inline(described_class.new(label: "Redis", state: :disconnected))
    expect(page).to have_css("span.text-danger", text: "▽ disconnected")
  end

  it "applies the text-muted class to the absent state" do
    render_inline(described_class.new(label: "notes", state: :absent))
    expect(page).to have_css("span.text-muted", text: "▽ not present")
  end

  it "raises ArgumentError when given an unknown state" do
    expect {
      described_class.new(label: "Postgres", state: :on_fire)
    }.to raise_error(ArgumentError, /unknown state/)
  end
end
