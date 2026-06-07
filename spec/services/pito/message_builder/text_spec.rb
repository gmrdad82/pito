# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Text do
  describe ".call" do
    context "with a copy key and args" do
      it "renders the copy key and returns a text payload" do
        payload = described_class.call("pito.copy.games.not_found", ref: "foo")
        expect(payload).to be_a(Hash)
        expect(payload["text"]).to be_present
        expect(payload["text"]).to include("foo")
      end
    end

    context "with a copy key and no args" do
      it "renders the copy key" do
        payload = described_class.call("pito.copy.games.list_empty")
        expect(payload).to be_a(Hash)
        expect(payload["text"]).to be_present
      end
    end

    context "with a plain text string" do
      it "returns the text as-is" do
        payload = described_class.call("Something went wrong")
        expect(payload["text"]).to eq("Something went wrong")
      end
    end

    it "renders without raising" do
      expect { described_class.call("pito.copy.games.list_empty") }.not_to raise_error
    end
  end
end
