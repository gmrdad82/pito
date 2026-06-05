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
        :slash_verbs, :config_providers, :config_keys, :on_off, :genres, :platforms,
        :release_status, :metrics, :hashtag_verbs, :fillers, :connectives,
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

    it "includes sound and fx" do
      expect(config_providers.canonical).to include("sound", "fx")
    end

    it "still includes the credential providers" do
      expect(config_providers.canonical).to include("google", "voyage", "igdb", "webhook")
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

    it 'resolves "playstation" to "PlayStation 5"' do
      expect(platforms.resolve("playstation")).to eq("PlayStation 5")
    end

    it 'resolves "ps" to "PlayStation 5"' do
      expect(platforms.resolve("ps")).to eq("PlayStation 5")
    end

    it 'resolves "sony" to "PlayStation 5"' do
      expect(platforms.resolve("sony")).to eq("PlayStation 5")
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

    it 'resolves "xbox" to "Xbox Series X"' do
      expect(platforms.resolve("xbox")).to eq("Xbox Series X")
    end
  end

  # ── Static vocab: :metrics ─────────────────────────────────────────────────
  describe ":metrics" do
    subject(:metrics) { vocab(:metrics) }

    it "is not dynamic" do
      expect(metrics.dynamic?).to be false
    end

    it 'resolves "subs" to "subscribers"' do
      expect(metrics.resolve("subs")).to eq("subscribers")
    end

    it 'filler? is true for "count"' do
      expect(metrics.filler?("count")).to be true
    end

    it 'filler? is true for "ratio"' do
      expect(metrics.filler?("ratio")).to be true
    end

    it 'filler? is false for "subscribers"' do
      expect(metrics.filler?("subscribers")).to be false
    end
  end

  # ── Static vocab: :hashtag_verbs ───────────────────────────────────────────
  describe ":hashtag_verbs" do
    subject(:hashtag_verbs) { vocab(:hashtag_verbs) }

    it "is not dynamic" do
      expect(hashtag_verbs.dynamic?).to be false
    end

    it 'resolves "drop" to "remove"' do
      expect(hashtag_verbs.resolve("drop")).to eq("remove")
    end

    it 'resolves "delete" to "remove"' do
      expect(hashtag_verbs.resolve("delete")).to eq("remove")
    end

    it 'resolves "include" to "add"' do
      expect(hashtag_verbs.resolve("include")).to eq("add")
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

  # ── Static vocab: :slash_verbs ─────────────────────────────────────────────
  describe ":slash_verbs" do
    subject(:slash_verbs) { vocab(:slash_verbs) }

    it "is not dynamic" do
      expect(slash_verbs.dynamic?).to be false
    end

    it "includes the implemented slash verbs" do
      expect(slash_verbs.canonical).to include("config", "disconnect", "help")
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
