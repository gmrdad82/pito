require "rails_helper"

# Phase 20 — friendly URLs. Cross-cutting setup spec. Verifies the gem is
# wired and that the right opt-in matrix lands per resource (renameables
# get :history, identifier-style ones do NOT).
RSpec.describe "friendly_id setup" do
  describe "friendly_id_slugs table" do
    it "exists" do
      expect(ActiveRecord::Base.connection.table_exists?(:friendly_id_slugs)).to be true
    end
  end

  describe "renameable resources (Project, Bundle, MilestoneRule)" do
    [ Project, Bundle, MilestoneRule ].each do |klass|
      describe klass.name do
        it "uses the :history module" do
          expect(klass.friendly_id_config.uses?(:history)).to be true
        end

        it "uses the :slugged module" do
          expect(klass.friendly_id_config.uses?(:slugged)).to be true
        end

        it "uses the :finders module" do
          expect(klass.friendly_id_config.uses?(:finders)).to be true
        end

        it "exposes a :slug column" do
          expect(klass.column_names).to include("slug")
        end
      end
    end
  end

  describe "identifier-style resources (Video, Game)" do
    # Video and Game wire `friendly_id :<col>, use: :finders` because
    # their slug source is a real column (`youtube_video_id` / `igdb_slug`).
    # The gem's :finders module is the appropriate integration point.
    [ Video, Game ].each do |klass|
      describe klass.name do
        it "does NOT use the :history module" do
          expect(klass.friendly_id_config.uses?(:history)).to be_falsey
        end

        it "does NOT use the :slugged module" do
          expect(klass.friendly_id_config.uses?(:slugged)).to be_falsey
        end

        it "uses the :finders module" do
          expect(klass.friendly_id_config.uses?(:finders)).to be true
        end

        it "does NOT expose a :slug column" do
          expect(klass.column_names).not_to include("slug")
        end
      end
    end
  end

  describe "Channel (custom FriendlyFinder)" do
    # Channel's slug is derived from a portion of `channel_url` (the
    # UC-id), not a dedicated column. The gem's :finders module assumes
    # a 1:1 column lookup, so Channel ships a custom `FriendlyFinder`
    # instead of `extend FriendlyId`.
    it "exposes a custom Channel.friendly finder (no FriendlyId mixin)" do
      expect(Channel).to respond_to(:friendly)
      finder = Channel.friendly
      expect(finder).to respond_to(:find)
    end

    it "does NOT carry a friendly_id_config (no gem integration)" do
      expect(Channel).not_to respond_to(:friendly_id_config)
    end

    it "does NOT expose a :slug column" do
      expect(Channel.column_names).not_to include("slug")
    end
  end

  describe "Footage (custom FriendlyFinder)" do
    it "exposes a custom Footage.friendly finder (no FriendlyId mixin)" do
      expect(Footage).to respond_to(:friendly)
      finder = Footage.friendly
      expect(finder).to respond_to(:find)
    end

    it "does NOT expose a :slug column" do
      expect(Footage.column_names).not_to include("slug")
    end
  end

  describe "Pito::SlugBuilder" do
    it "transliterates accented characters" do
      expect(Pito::SlugBuilder.build("Café")).to eq("cafe")
    end

    it "lowercases and hyphenates" do
      expect(Pito::SlugBuilder.build("Hello World")).to eq("hello-world")
    end

    it "strips edge characters" do
      expect(Pito::SlugBuilder.build("  /Hello/ ")).to eq("hello")
    end

    it "collapses runs of separators" do
      expect(Pito::SlugBuilder.build("a___b---c")).to eq("a-b-c")
    end

    it "returns empty string for unhandleable input" do
      expect(Pito::SlugBuilder.build("@@@")).to eq("")
      expect(Pito::SlugBuilder.build(nil)).to eq("")
    end

    it "honors the limit kwarg and prefers a hyphen boundary" do
      input = "the-quick-brown-fox-jumps-over-the-lazy-dog-quickly-many-times-over-and-over-again"
      result = Pito::SlugBuilder.build(input, limit: 30)
      expect(result.length).to be <= 30
      expect(result).not_to end_with("-")
    end

    it "hard-truncates when no hyphen boundary fits" do
      result = Pito::SlugBuilder.build("a" * 100, limit: 10)
      expect(result.length).to eq(10)
      expect(result).to eq("a" * 10)
    end
  end
end
