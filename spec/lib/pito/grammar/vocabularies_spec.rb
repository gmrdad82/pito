# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::Vocabularies do
  # Helper: look up a vocab from the .all collection by name.
  def vocab(name)
    described_class.all.find { |v| v.name == name.to_sym }
  end

  describe ".all" do
    it "returns an Array of Pito::Grammar::Vocabulary objects" do
      expect(described_class.all).to be_an(Array)
      expect(described_class.all).to all(be_a(Pito::Grammar::Vocabulary))
    end

    it "includes all expected vocabulary names" do
      names = described_class.all.map(&:name)
      expect(names).to include(
        :slash_tools, :config_providers, :config_keys, :on_off, :genres, :platforms,
        :release_status, :metrics, :hashtag_tools, :fillers, :connectives,
        :channels, :conversations, :game_titles
      )
    end
  end

  describe ".register_all!" do
    before { Pito::Grammar::Registry.reset! }
    after  { Pito::Grammar::Registry.reset! }

    it "registers every vocabulary into the given registry" do
      described_class.register_all!(Pito::Grammar::Registry)
      registered_names = Pito::Grammar::Registry.vocabularies.map(&:name)
      described_class.all.each do |v|
        expect(registered_names).to include(v.name)
      end
    end

    it "makes vocabularies retrievable by name" do
      described_class.register_all!(Pito::Grammar::Registry)
      expect(Pito::Grammar::Registry.vocabulary(:genres)).to eq(vocab(:genres))
    end
  end

  describe "MASKED_CONFIG_KEYS" do
    it "contains client_id, client_secret, and api_key" do
      expect(described_class::MASKED_CONFIG_KEYS).to include("client_id", "client_secret", "api_key")
    end
  end

  # ── Static vocab: :config_providers ──────────────────────────────────────────
  describe ":config_providers" do
    subject(:config_providers) { vocab(:config_providers) }

    it "includes the sound toggle" do
      expect(config_providers.canonical).to include("sound")
    end

    it "no longer includes the removed motion/fx providers (item 18)" do
      expect(config_providers.canonical).not_to include("motion", "fx")
    end

    it "still includes the credential providers" do
      expect(config_providers.canonical).to include("google", "igdb", "webhook")
    end
  end

  # ── Static vocab: :on_off ──────────────────────────────────────────────────
  describe ":on_off" do
    subject(:on_off) { vocab(:on_off) }

    it "is not dynamic" do
      expect(on_off.dynamic?).to be false
    end

    it "has canonical values on and off" do
      expect(on_off.canonical).to contain_exactly("on", "off")
    end

    it 'resolves "true" to "on"' do
      expect(on_off.resolve("true")).to eq("on")
    end

    it 'resolves "false" to "off"' do
      expect(on_off.resolve("false")).to eq("off")
    end

    it 'resolves "enable" to "on"' do
      expect(on_off.resolve("enable")).to eq("on")
    end

    it 'resolves "disable" to "off"' do
      expect(on_off.resolve("disable")).to eq("off")
    end

    it 'resolves "yes" to "on"' do
      expect(on_off.resolve("yes")).to eq("on")
    end

    it 'resolves "no" to "off"' do
      expect(on_off.resolve("no")).to eq("off")
    end

    it 'resolves "enabled" to "on"' do
      expect(on_off.resolve("enabled")).to eq("on")
    end

    it 'resolves "disabled" to "off"' do
      expect(on_off.resolve("disabled")).to eq("off")
    end
  end

  # ── Static vocab: :genres ──────────────────────────────────────────────────
  describe ":genres" do
    subject(:genres) { vocab(:genres) }

    it "is not dynamic" do
      expect(genres.dynamic?).to be false
    end

    it 'resolves "fps" to "Shooter"' do
      expect(genres.resolve("fps")).to eq("Shooter")
    end

    it 'resolves "sim" to "Simulation"' do
      expect(genres.resolve("sim")).to eq("Simulation")
    end

    it 'resolves "rpg" to "RPG"' do
      expect(genres.resolve("rpg")).to eq("RPG")
    end

    it 'resolves "racing" to "Racing"' do
      expect(genres.resolve("racing")).to eq("Racing")
    end

    it "includes canonical members Shooter, Simulation, RPG, Racing" do
      expect(genres.canonical).to include("Shooter", "Simulation", "RPG", "Racing")
    end
  end

  # ── Static vocab: :platforms ───────────────────────────────────────────────
  describe ":platforms" do
    subject(:platforms) { vocab(:platforms) }

    it "is not dynamic" do
      expect(platforms.dynamic?).to be false
    end

    it 'resolves "ps5" to "PlayStation 5"' do
      expect(platforms.resolve("ps5")).to eq("PlayStation 5")
    end

    it 'resolves "playstation" to the bare PlayStation family (matches PS4 + PS5 by substring)' do
      expect(platforms.resolve("playstation")).to eq("PlayStation")
    end

    it 'resolves "ps" to the PlayStation family' do
      expect(platforms.resolve("ps")).to eq("PlayStation")
    end

    it 'resolves "sony" to the PlayStation family' do
      expect(platforms.resolve("sony")).to eq("PlayStation")
    end

    it 'resolves "switch" to "Nintendo Switch"' do
      expect(platforms.resolve("switch")).to eq("Nintendo Switch")
    end

    it 'resolves "steam" to "PC"' do
      expect(platforms.resolve("steam")).to eq("PC")
    end

    it 'resolves "pc" to "PC"' do
      expect(platforms.resolve("pc")).to eq("PC")
    end

    it 'resolves "xbox" to the bare Xbox family (matches every Xbox platform by substring)' do
      expect(platforms.resolve("xbox")).to eq("Xbox")
    end
  end

  # ── Static vocab: :metrics ─────────────────────────────────────────────────
  describe ":metrics" do
    subject(:metrics) { vocab(:metrics) }

    it "is not dynamic" do
      expect(metrics.dynamic?).to be false
    end

    it 'has "subs" as the canonical metric (not "subscribers")' do
      expect(metrics.canonical).to include("subs")
      expect(metrics.canonical).not_to include("subscribers")
    end

    it 'resolves canonical "subs" to "subs"' do
      expect(metrics.resolve("subs")).to eq("subs")
    end

    it 'resolves alias "subscribers" to "subs"' do
      expect(metrics.resolve("subscribers")).to eq("subs")
    end

    it 'resolves alias "subscriber" to "subs"' do
      expect(metrics.resolve("subscriber")).to eq("subs")
    end

    it 'filler? is true for "count"' do
      expect(metrics.filler?("count")).to be true
    end

    it 'filler? is true for "ratio"' do
      expect(metrics.filler?("ratio")).to be true
    end

    it 'filler? is false for "subs"' do
      expect(metrics.filler?("subs")).to be false
    end
  end

  # ── Static vocab: :nouns ───────────────────────────────────────────────────
  describe ":nouns" do
    subject(:nouns) { vocab(:nouns) }

    it 'has "vids" as the canonical video noun (not "videos")' do
      expect(nouns.canonical).to include("vids")
      expect(nouns.canonical).not_to include("videos")
    end

    it 'resolves canonical "vids" to "vids"' do
      expect(nouns.resolve("vids")).to eq("vids")
    end

    it 'resolves alias "videos" to "vids"' do
      expect(nouns.resolve("videos")).to eq("vids")
    end

    it 'resolves alias "video" to "vids"' do
      expect(nouns.resolve("video")).to eq("vids")
    end

    it 'resolves alias "vid" to "vids"' do
      expect(nouns.resolve("vid")).to eq("vids")
    end

    it "keeps channels and games canonical" do
      expect(nouns.canonical).to include("channels", "games")
    end
  end

  # ── Static vocab: :sync_targets ────────────────────────────────────────────
  describe ":sync_targets" do
    subject(:sync_targets) { vocab(:sync_targets) }

    it 'has "vids" as the canonical video target (not "videos")' do
      expect(sync_targets.canonical).to include("vids")
      expect(sync_targets.canonical).not_to include("videos")
    end

    it 'resolves canonical "vids" to "vids"' do
      expect(sync_targets.resolve("vids")).to eq("vids")
    end

    it 'resolves alias "videos" to "vids"' do
      expect(sync_targets.resolve("videos")).to eq("vids")
    end

    it 'resolves alias "vid" to "vids"' do
      expect(sync_targets.resolve("vid")).to eq("vids")
    end

    it "keeps channels canonical" do
      expect(sync_targets.canonical).to include("channels")
    end
  end

  # ── Static vocab: :schedule_whens ──────────────────────────────────────────
  describe ":schedule_whens" do
    subject(:schedule_whens) { vocab(:schedule_whens) }

    it "is registered" do
      expect(schedule_whens).not_to be_nil
    end

    it 'offers "slate" as the canonical keyword' do
      expect(schedule_whens.canonical).to include("slate")
    end

    it 'resolves "slate" to "slate"' do
      expect(schedule_whens.resolve("slate")).to eq("slate")
    end
  end

  # ── Static vocab: :hashtag_tools ───────────────────────────────────────────
  describe ":hashtag_tools" do
    subject(:hashtag_tools) { vocab(:hashtag_tools) }

    it "is not dynamic" do
      expect(hashtag_tools.dynamic?).to be false
    end

    it 'resolves "drop" to "without"' do
      expect(hashtag_tools.resolve("drop")).to eq("without")
    end

    it 'resolves "delete" to "without"' do
      expect(hashtag_tools.resolve("delete")).to eq("without")
    end

    it 'resolves "include" to "with"' do
      expect(hashtag_tools.resolve("include")).to eq("with")
    end
  end

  # ── Static vocab: :release_status ─────────────────────────────────────────
  describe ":release_status" do
    subject(:release_status) { vocab(:release_status) }

    it 'resolves "unreleased" to "upcoming"' do
      expect(release_status.resolve("unreleased")).to eq("upcoming")
    end

    it 'resolves "tbd" to "tba"' do
      expect(release_status.resolve("tbd")).to eq("tba")
    end
  end

  # ── Static vocab: :fillers ─────────────────────────────────────────────────
  describe ":fillers" do
    subject(:fillers) { vocab(:fillers) }

    it 'filler? is true for "the"' do
      expect(fillers.filler?("the")).to be true
    end

    it 'filler? is true for "games"' do
      expect(fillers.filler?("games")).to be true
    end

    it 'filler? is false for "RPG"' do
      expect(fillers.filler?("RPG")).to be false
    end
  end

  # ── Static vocab: :slash_tools ─────────────────────────────────────────────
  describe ":slash_tools" do
    subject(:slash_tools) { vocab(:slash_tools) }

    it "is not dynamic" do
      expect(slash_tools.dynamic?).to be false
    end

    it "includes the implemented slash tools" do
      expect(slash_tools.canonical).to include("config", "disconnect", "help")
    end
  end

  # ── Static vocab: :connectives ─────────────────────────────────────────────
  describe ":connectives" do
    subject(:connectives) { vocab(:connectives) }

    it 'includes "and" and "for"' do
      expect(connectives.canonical).to include("and", "for")
    end
  end

  # ── Dynamic vocabs ─────────────────────────────────────────────────────────
  describe "dynamic vocabularies" do
    %i[channels conversations game_titles].each do |name|
      describe ":#{name}" do
        subject(:dyn) { vocab(name) }

        it "is dynamic" do
          expect(dyn.dynamic?).to be true
        end

        it "has a callable resolver" do
          expect(dyn.resolver).to respond_to(:call)
        end

        it "omits :canonical from to_h" do
          expect(dyn.to_h).not_to have_key(:canonical)
        end
      end
    end
  end
end
