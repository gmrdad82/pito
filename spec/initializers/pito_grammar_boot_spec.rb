# frozen_string_literal: true

require "rails_helper"

# Verifies that the boot sequence wired in config/initializers/pito.rb correctly
# populates the grammar registry before the slash/chat/hashtag runtime registries.
RSpec.describe "Grammar registry boot sequence" do
  before do
    # Mirror the exact order from config/initializers/pito.rb to be deterministic
    # regardless of what other specs may have called reset! on.
    Pito::Grammar::Registry.register_all!
    Pito::Slash::Registry.register_all!
    Pito::Chat::Registry.register_all!
    Pito::Hashtag::Registry.register_all!
  end

  after { Pito::Grammar::Registry.reset! }

  # ── Grammar registry ─────────────────────────────────────────────────────────

  describe "Pito::Grammar::Registry" do
    it "is populated with vocabularies" do
      expect(Pito::Grammar::Registry.vocabularies).not_to be_empty
    end

    it "includes the :genres vocabulary" do
      vocab_names = Pito::Grammar::Registry.vocabularies.map(&:name)
      expect(vocab_names).to include(:genres)
    end

    it "registers the :list chat spec" do
      names = Pito::Grammar::Registry.specs(namespace: :chat).map(&:name)
      expect(names).to include(:list)
    end

    it "registers the :add hashtag spec" do
      names = Pito::Grammar::Registry.specs(namespace: :hashtag).map(&:name)
      expect(names).to include(:add)
    end

    it "registers the :config slash spec" do
      names = Pito::Grammar::Registry.specs(namespace: :slash).map(&:name)
      expect(names).to include(:config)
    end

    it "registers the :login slash spec" do
      names = Pito::Grammar::Registry.specs(namespace: :slash).map(&:name)
      expect(names).to include(:login)
    end
  end

  # ── Runtime registries unaffected ────────────────────────────────────────────

  describe "Pito::Slash::Registry" do
    it "has registered handlers (size > 0)" do
      expect(Pito::Slash::Registry.size).to be > 0
    end

    it "resolves the :config handler to a non-nil class" do
      expect(Pito::Slash::Registry.lookup(:config)).not_to be_nil
    end
  end
end
