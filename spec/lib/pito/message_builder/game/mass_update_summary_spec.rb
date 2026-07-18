# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::MassUpdateSummary do
  describe ".call" do
    subject(:payload) { described_class.call(field: "footage", rows: rows) }

    context "a mix of applied and skipped rows, in typed order" do
      let(:rows) do
        [
          { applied: true, ref: "#5", title: "Elden Ring", value: "8.5h" },
          { applied: false, ref: "#42", reason: "not found" },
          { applied: false, ref: "#7", reason: "couldn't read 'abc' as a footage value" }
        ]
      end

      it "returns a Hash" do
        expect(payload).to be_a(Hash)
      end

      it "has html false" do
        expect(payload["html"]).to be false
      end

      it "carries no follow-up handle — a report, not a prompt" do
        expect(Pito::FollowUp.followupable?(payload)).to be false
      end

      it "the header names the field and BOTH counts" do
        expect(payload["body"]).to eq("Update game footage — 1 applied, 2 skipped")
      end

      it "expand_detail has exactly one line per row, IN TYPED ORDER" do
        expect(payload["expand_detail"].size).to eq(3)
      end

      it "an applied row renders '#id title → value'" do
        expect(payload["expand_detail"][0]).to eq("#5 Elden Ring → 8.5h")
      end

      it "a skipped row renders '#id — reason' (no 'skipped:' prefix — that's the vid mass card's shape)" do
        expect(payload["expand_detail"][1]).to eq("#42 — not found")
        expect(payload["expand_detail"][2]).to eq("#7 — couldn't read 'abc' as a footage value")
      end
    end

    context "every row applied" do
      let(:rows) do
        [
          { applied: true, ref: "#1", title: "Hollow Knight", value: "€12.99" },
          { applied: true, ref: "#2", title: "Silksong", value: "€0.00" }
        ]
      end

      it "the header reads 0 skipped" do
        expect(payload["body"]).to eq("Update game footage — 2 applied, 0 skipped")
      end
    end

    context "every row skipped" do
      let(:rows) { [ { applied: false, ref: "#9", reason: "not found" } ] }

      it "the header reads 0 applied" do
        expect(payload["body"]).to eq("Update game footage — 0 applied, 1 skipped")
      end
    end

    context "a row with no parseable id (quoted raw segment ref)" do
      let(:rows) { [ { applied: false, ref: "'nonsense'", reason: "couldn't find an id and a value there" } ] }

      it "renders the quoted segment in place of an id" do
        expect(payload["expand_detail"].first).to eq("'nonsense' — couldn't find an id and a value there")
      end
    end

    context "empty batch" do
      let(:rows) { [] }

      it "renders a zero/zero header and an empty expand_detail" do
        expect(payload["body"]).to eq("Update game footage — 0 applied, 0 skipped")
        expect(payload["expand_detail"]).to eq([])
      end
    end
  end
end
