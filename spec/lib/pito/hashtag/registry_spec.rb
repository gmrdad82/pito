# frozen_string_literal: true

require "rails_helper"

class HashtagRegistryTestHandler < Pito::Hashtag::Handler
  self.handle = :testhandle

  def call
    Pito::Hashtag::Result::Ok.new(events: [ { kind: :system, payload: { text: "ok" } } ])
  end
end

RSpec.describe Pito::Hashtag::Registry do
  around do |example|
    old_registry = described_class.instance_variable_get(:@registry)&.dup || {}
    described_class.instance_variable_set(:@registry, {})
    example.run
    described_class.instance_variable_set(:@registry, old_registry)
  end

  describe ".register" do
    it "registers a handler by its handle" do
      described_class.register(HashtagRegistryTestHandler)
      expect(described_class.lookup(:testhandle)).to eq(HashtagRegistryTestHandler)
    end
  end

  describe ".lookup" do
    before { described_class.register(HashtagRegistryTestHandler) }

    it "returns the handler class for a registered handle" do
      expect(described_class.lookup(:testhandle)).to eq(HashtagRegistryTestHandler)
    end

    it "returns nil for an unknown handle" do
      expect(described_class.lookup(:nonexistent)).to be_nil
    end

    it "accepts a string and converts to symbol" do
      expect(described_class.lookup("testhandle")).to eq(HashtagRegistryTestHandler)
    end
  end

  describe ".size" do
    it "returns the number of registered handlers" do
      expect { described_class.register(HashtagRegistryTestHandler) }.to change(described_class, :size).by(1)
    end
  end

  describe ".registered_handles" do
    it "returns the list of registered handle symbols" do
      described_class.register(HashtagRegistryTestHandler)
      expect(described_class.registered_handles).to include(:testhandle)
    end
  end

  describe ".register_all!" do
    it "discovers and registers handlers under Pito::Hashtag::Handlers" do
      stub_const("Pito::Hashtag::Handlers::TestAll", Class.new(Pito::Hashtag::Handler) do
        self.handle = :testall

        def call
          Pito::Hashtag::Result::Ok.new(events: [])
        end
      end)

      expect { described_class.register_all! }.to change(described_class, :size).by_at_least(1)
      expect(described_class.lookup(:testall)).to be_a(Class)
    end
  end
end
