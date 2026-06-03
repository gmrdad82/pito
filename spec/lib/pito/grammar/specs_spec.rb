# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::Specs do
  before { Pito::Grammar::Registry.reset! }
  after  { Pito::Grammar::Registry.reset! }

  describe ".all" do
    subject(:all_specs) { described_class.all }

    it "includes the :list chat spec" do
      expect(all_specs.map(&:name)).to include(:list)
    end

    it "includes the :show chat spec" do
      expect(all_specs.map(&:name)).to include(:show)
    end

    it "includes the :find chat spec" do
      expect(all_specs.map(&:name)).to include(:find)
    end

    it "includes the :add hashtag spec" do
      expect(all_specs.map(&:name)).to include(:add)
    end

    it "includes the :remove hashtag spec" do
      expect(all_specs.map(&:name)).to include(:remove)
    end

    it "assigns the :chat namespace to :list, :show, :find" do
      chat_names = all_specs.select { |s| s.namespace == :chat }.map(&:name)
      expect(chat_names).to include(:list, :show, :find)
    end

    it "assigns the :hashtag namespace to :add, :remove" do
      hashtag_names = all_specs.select { |s| s.namespace == :hashtag }.map(&:name)
      expect(hashtag_names).to include(:add, :remove)
    end

    it "does not share the same slot array objects across chat specs (mutable state isolation)" do
      list_slots = all_specs.find { |s| s.name == :list && s.namespace == :chat }.slots
      show_slots = all_specs.find { |s| s.name == :show && s.namespace == :chat }.slots
      expect(list_slots).not_to equal(show_slots)
    end
  end

  describe ".register_all!" do
    before { described_class.register_all!(Pito::Grammar::Registry) }

    describe "chat namespace" do
      it "registers the :list spec with 3 slots" do
        spec = Pito::Grammar::Registry.spec(namespace: :chat, name: :list)
        expect(spec).not_to be_nil
        expect(spec.slots.length).to eq(3)
      end

      it "registers :show and :find specs" do
        names = Pito::Grammar::Registry.specs(namespace: :chat).map(&:name)
        expect(names).to include(:list, :show, :find)
      end
    end

    describe "hashtag namespace" do
      it "resolves :drop alias to the :remove spec" do
        result = Pito::Grammar::Registry.specs_for_alias(namespace: :hashtag, token: :drop)
        expect(result&.name).to eq(:remove)
      end

      it "resolves :delete alias to the :remove spec" do
        result = Pito::Grammar::Registry.specs_for_alias(namespace: :hashtag, token: :delete)
        expect(result&.name).to eq(:remove)
      end

      it "resolves :include alias to the :add spec" do
        result = Pito::Grammar::Registry.specs_for_alias(namespace: :hashtag, token: :include)
        expect(result&.name).to eq(:add)
      end
    end

    describe "shared chat slot set details" do
      let(:list_spec) { Pito::Grammar::Registry.spec(namespace: :chat, name: :list) }

      it "has :platform slot with introducer :for" do
        expect(list_spec.slot(:platform).introducer).to eq(:for)
      end

      it "has :genre slot with repeatable? true" do
        expect(list_spec.slot(:genre).repeatable?).to be(true)
      end

      it "has :status slot that is optional" do
        expect(list_spec.slot(:status).optional?).to be(true)
      end
    end
  end
end
