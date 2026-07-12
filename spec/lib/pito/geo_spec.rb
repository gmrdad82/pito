# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Geo do
  describe ".country_name" do
    it "resolves an alpha-2 code to a friendly name" do
      expect(described_class.country_name("US")).to eq("United States")
      expect(described_class.country_name("GB")).to eq("United Kingdom")
    end

    it "is case-insensitive on the code" do
      expect(described_class.country_name("kr")).to eq("South Korea")
    end

    it "falls back to the upcased code for an unknown code" do
      expect(described_class.country_name("zz")).to eq("ZZ")
    end

    it "handles nil/blank without raising" do
      expect(described_class.country_name(nil)).to eq("")
    end
  end
end
