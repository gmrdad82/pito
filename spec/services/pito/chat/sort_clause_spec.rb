# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::SortClause do
  describe ".parse" do
    it "returns nil when there is no sort clause" do
      expect(described_class.parse("list games")).to be_nil
    end

    it "returns nil for an empty string" do
      expect(described_class.parse("")).to be_nil
    end

    it "returns nil for a with clause without a sort clause" do
      expect(described_class.parse("list games with platform")).to be_nil
    end

    it "parses 'sorted by year' with implicit asc direction" do
      result = described_class.parse("list games sorted by year")
      expect(result).to eq({ token: "year", direction: :asc })
    end

    it "parses 'ordered by release date desc'" do
      result = described_class.parse("list games ordered by release date desc")
      expect(result).to eq({ token: "release date", direction: :desc })
    end

    it "parses 'sorted by Title ASC' (case-insensitive token and direction)" do
      result = described_class.parse("list games sorted by Title ASC")
      expect(result).to eq({ token: "title", direction: :asc })
    end

    it "parses 'SORTED BY year DESC' (fully uppercase)" do
      result = described_class.parse("list games SORTED BY year DESC")
      expect(result).to eq({ token: "year", direction: :desc })
    end

    it "parses 'ordered by title' with implicit asc direction" do
      result = described_class.parse("list games ordered by title")
      expect(result).to eq({ token: "title", direction: :asc })
    end

    it "strips leading/trailing whitespace from the token" do
      result = described_class.parse("list games sorted by  title  ")
      expect(result[:token]).to eq("title")
    end

    it "composes with a with clause — parses sort after 'with platform'" do
      result = described_class.parse("list games with platform sorted by year desc")
      expect(result).to eq({ token: "year", direction: :desc })
    end

    it "downcases a mixed-case token" do
      result = described_class.parse("list games sorted by Release Date")
      expect(result).to eq({ token: "release date", direction: :asc })
    end
  end
end
