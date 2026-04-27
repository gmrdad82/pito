require "rails_helper"

RSpec.describe Search do
  after { described_class.reset_engine! }

  describe ".engine" do
    it "returns a MeilisearchEngine by default" do
      expect(described_class.engine).to be_a(Search::MeilisearchEngine)
    end

    it "caches the engine instance" do
      engine1 = described_class.engine
      engine2 = described_class.engine
      expect(engine1).to equal(engine2)
    end

    it "respects the search_engine AppSetting" do
      AppSetting.set("search_engine", "meilisearch")
      described_class.reset_engine!
      expect(described_class.engine).to be_a(Search::MeilisearchEngine)
    end

    it "raises for unknown engines" do
      AppSetting.set("search_engine", "solr")
      described_class.reset_engine!
      expect { described_class.engine }.to raise_error("Unknown search engine: solr")
    end
  end

  describe ".reset_engine!" do
    it "clears cached engine" do
      engine1 = described_class.engine
      described_class.reset_engine!
      engine2 = described_class.engine
      expect(engine1).not_to equal(engine2)
    end
  end
end
