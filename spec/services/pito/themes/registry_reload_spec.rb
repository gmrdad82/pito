# frozen_string_literal: true

require "rails_helper"

# Regression: in dev, Zeitwerk reloads Registry (clearing @definitions) while
# the definitions/ dir is Zeitwerk-ignored. `load` (not `require`) must
# re-register them, or every theme lookup + the sidebar break after a reload.
RSpec.describe Pito::Themes::Registry, type: :service do
  it "repopulates after a simulated code reload" do
    original = described_class.all.size
    expect(original).to be >= 18

    described_class.instance_variable_set(:@definitions, [])
    described_class.instance_variable_set(:@loaded, false)

    expect(described_class.all.size).to eq(original)
    expect(described_class.find("ayu-dark")).to be_present
    expect(described_class.default.slug).to eq("tokyo-night")
  ensure
    described_class.instance_variable_set(:@loaded, false)
    described_class.all
  end
end
