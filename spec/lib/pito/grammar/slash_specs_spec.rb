# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pito::Grammar slash specs" do
  before { Pito::Grammar::Registry.reset! }
  after  { Pito::Grammar::Registry.reset! }

  before do
    Pito::Grammar::Registry.register_all!
  end

  describe "/config spec (from config)" do
    subject(:spec) { Pito::Grammar::Registry.spec(namespace: :slash, name: :config) }

    it "is registered" do
      expect(spec).not_to be_nil
    end

    it "has a :provider literal slot sourced from :config_providers" do
      slot = spec.slot(:provider)
      expect(slot).not_to be_nil
      expect(slot.kind).to eq(:literal)
      expect(slot.source).to eq(:config_providers)
    end

    it "has a :settings kv slot that is repeatable and optional" do
      slot = spec.slot(:settings)
      expect(slot).not_to be_nil
      expect(slot.kind).to eq(:kv)
      expect(slot.repeatable?).to be(true)
      expect(slot.optional?).to be(true)
    end

    it "no longer has an :effect enum slot (fx provider removed — item 18)" do
      expect(spec.slot(:effect)).to be_nil
    end

    it "has auth :authenticated_only" do
      expect(spec.auth).to eq(:authenticated_only)
    end
  end

  describe "/disconnect spec (from config)" do
    subject(:spec) { Pito::Grammar::Registry.spec(namespace: :slash, name: :disconnect) }

    it "is registered" do
      expect(spec).not_to be_nil
    end

    it "has a :channel enum slot sourced from :channels that is optional" do
      slot = spec.slot(:channel)
      expect(slot).not_to be_nil
      expect(slot.kind).to eq(:enum)
      expect(slot.source).to eq(:channels)
      expect(slot.optional?).to be(true)
    end

    it "has auth :authenticated_only" do
      expect(spec.auth).to eq(:authenticated_only)
    end
  end

  describe "/help spec (from config)" do
    subject(:spec) { Pito::Grammar::Registry.spec(namespace: :slash, name: :help) }

    it "is registered" do
      expect(spec).not_to be_nil
    end

    it "has auth :any" do
      expect(spec.auth).to eq(:any)
    end
  end

  describe "/login spec (from config)" do
    subject(:spec) { Pito::Grammar::Registry.spec(namespace: :slash, name: :login) }

    it "is registered" do
      expect(spec).not_to be_nil
    end

    it "has a :code free slot" do
      slot = spec.slot(:code)
      expect(slot).not_to be_nil
      expect(slot.kind).to eq(:free)
    end

    it "has auth :unauthenticated_only" do
      expect(spec.auth).to eq(:unauthenticated_only)
    end
  end

  describe "/logout spec (from config)" do
    subject(:spec) { Pito::Grammar::Registry.spec(namespace: :slash, name: :logout) }

    it "is registered" do
      expect(spec).not_to be_nil
    end

    it "has auth :authenticated_only" do
      expect(spec.auth).to eq(:authenticated_only)
    end
  end

  describe "/connect spec (from config)" do
    subject(:spec) { Pito::Grammar::Registry.spec(namespace: :slash, name: :connect) }

    it "is registered" do
      expect(spec).not_to be_nil
    end

    it "has auth :authenticated_only" do
      expect(spec.auth).to eq(:authenticated_only)
    end
  end

  describe "i18n description keys" do
    let(:all_specs) do
      slash_specs  = Pito::Grammar::Registry.specs(namespace: :slash)
      chat_specs   = Pito::Grammar::Registry.specs(namespace: :chat)
      hashtag_specs = Pito::Grammar::Registry.specs(namespace: :hashtag)
      slash_specs + chat_specs + hashtag_specs
    end

    it "every spec's description_key resolves without MissingTranslation" do
      all_specs.each do |spec|
        next if spec.description_key.nil?

        expect {
          I18n.t(spec.description_key, raise: true)
        }.not_to raise_error,
          "Expected #{spec.description_key} to resolve, but got MissingTranslation"
      end
    end
  end
end
