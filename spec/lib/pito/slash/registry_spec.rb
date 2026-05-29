# frozen_string_literal: true

require "rails_helper"

class RegistryTestHandler < Pito::Slash::Handler
  self.verb = :testcmd
  self.description_key = "pito.slash.help.descriptions.testcmd"

  def call
    Pito::Slash::Result::Ok.new(events: [ { kind: "assistant_text", payload: { text: "ok" } } ])
  end
end

RSpec.describe Pito::Slash::Registry do
  around do |example|
    old_registry = described_class.instance_variable_get(:@registry)&.dup || {}
    described_class.instance_variable_set(:@registry, {})
    example.run
    described_class.instance_variable_set(:@registry, old_registry)
  end

  describe ".register" do
    it "registers a handler by its verb" do
      described_class.register(RegistryTestHandler)
      expect(described_class.lookup(:testcmd)).to eq(RegistryTestHandler)
    end
  end

  describe ".lookup" do
    before { described_class.register(RegistryTestHandler) }

    it "returns the handler class for a registered verb" do
      expect(described_class.lookup(:testcmd)).to eq(RegistryTestHandler)
    end

    it "returns nil for an unknown verb" do
      expect(described_class.lookup(:nonexistent)).to be_nil
    end

    it "accepts a string and converts to symbol" do
      expect(described_class.lookup("testcmd")).to eq(RegistryTestHandler)
    end
  end

  describe ".size" do
    it "returns the number of registered handlers" do
      expect { described_class.register(RegistryTestHandler) }.to change(described_class, :size).by(1)
    end
  end
end
