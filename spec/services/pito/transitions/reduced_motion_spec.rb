require "rails_helper"

RSpec.describe Pito::Transitions::ReducedMotion do
  describe "CONFIG_KEY" do
    it "is the locked transitions.reduced_motion key" do
      expect(described_class::CONFIG_KEY).to eq("transitions.reduced_motion")
    end
  end

  describe "DEFAULT_VALUE" do
    it "defaults to false" do
      expect(described_class::DEFAULT_VALUE).to eq(false)
    end
  end
end
