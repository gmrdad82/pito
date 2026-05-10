require "rails_helper"

RSpec.describe Igdb::Apicalypse do
  describe "#to_s" do
    it "produces a fields-only body" do
      body = described_class.new.fields("a", "b").to_s
      expect(body).to eq("fields a, b;")
    end

    it "includes a where clause when provided" do
      body = described_class.new.fields("a").where("id = 1").to_s
      expect(body).to include("where id = 1;")
    end

    it "ANDs multiple where clauses with `&`" do
      body = described_class.new.fields("a").where("a > 1").where("b < 2").to_s
      expect(body).to include("where a > 1 & b < 2;")
    end

    it "includes a limit when provided" do
      body = described_class.new.fields("a").limit(10).to_s
      expect(body).to include("limit 10;")
    end

    it "wraps a search query in double quotes" do
      body = described_class.new.search("zelda").fields("a").to_s
      expect(body).to include('search "zelda";')
    end

    it "escapes embedded double quotes in a search query" do
      body = described_class.new.search('he said "hi"').fields("a").to_s
      expect(body).to include('search "he said \\"hi\\"";')
    end

    it "raises when search is blank" do
      expect { described_class.new.search("") }.to raise_error(ArgumentError)
      expect { described_class.new.search(nil) }.to raise_error(ArgumentError)
    end

    it "raises when limit is non-integer" do
      expect { described_class.new.limit("ten") }.to raise_error(ArgumentError)
      expect { described_class.new.limit(0) }.to raise_error(ArgumentError)
    end

    it "raises when fields() is empty" do
      expect { described_class.new.fields }.to raise_error(ArgumentError)
    end

    it "raises when to_s called without fields" do
      expect { described_class.new.where("id = 1").to_s }.to raise_error(ArgumentError)
    end
  end
end
