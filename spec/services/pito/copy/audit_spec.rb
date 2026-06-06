# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Copy::Audit, type: :service do
  # We store fixture translations directly into the I18n backend so the specs
  # are fully isolated from the real locale files.
  around do |example|
    I18n.backend.store_translations(:en,
      pito: {
        copy: {
          greeting:  "Hello!",
          farewell:  [ "See you.", "Later." ],
          tagged:    [ "Hey %{name}!", "Hi there, %{name}." ],
          dual_var:  [ "From %{sender} to %{receiver}." ]
        },
        legacy_array:   [ "old one", "old two", "old three" ],
        nested_legacy: {
          inner: [ "A %{foo} entry", "Another %{foo} entry" ]
        },
        plain_string: "I am NOT an array"
      }
    )
    example.run
  end

  describe ".call" do
    subject(:result) { described_class.call }

    # ── Result shape ──────────────────────────────────────────────────────

    it "returns a Result with :registered and :legacy_candidates lists" do
      expect(result).to respond_to(:registered, :legacy_candidates)
    end

    # ── Registered (pito.copy.*) ──────────────────────────────────────────

    describe "registered keys" do
      subject(:registered) { described_class.call.registered }

      it "includes every leaf under pito.copy.*" do
        keys = registered.map { |r| r[:key] }
        expect(keys).to include(
          "pito.copy.greeting",
          "pito.copy.farewell",
          "pito.copy.tagged",
          "pito.copy.dual_var"
        )
      end

      it "does NOT include namespace keys (Hash nodes)" do
        keys = registered.map { |r| r[:key] }
        expect(keys).not_to include("pito.copy")
      end

      context "with a single-string entry (greeting)" do
        subject(:entry) { registered.find { |r| r[:key] == "pito.copy.greeting" } }

        it "reports variants: 1" do
          expect(entry[:variants]).to eq(1)
        end

        it "marks it as single: true" do
          expect(entry[:single]).to be(true)
        end

        it "reports no placeholders" do
          expect(entry[:placeholders]).to be_empty
        end
      end

      context "with a multi-variant entry (farewell)" do
        subject(:entry) { registered.find { |r| r[:key] == "pito.copy.farewell" } }

        it "reports the correct variant count" do
          expect(entry[:variants]).to eq(2)
        end

        it "marks it as single: false" do
          expect(entry[:single]).to be(false)
        end

        it "reports no placeholders" do
          expect(entry[:placeholders]).to be_empty
        end
      end

      context "with placeholders (tagged)" do
        subject(:entry) { registered.find { |r| r[:key] == "pito.copy.tagged" } }

        it "extracts the placeholder names" do
          expect(entry[:placeholders]).to eq([ "name" ])
        end
      end

      context "with multiple placeholders (dual_var)" do
        subject(:entry) { registered.find { |r| r[:key] == "pito.copy.dual_var" } }

        it "extracts all unique placeholder names sorted" do
          expect(entry[:placeholders]).to eq(%w[receiver sender])
        end
      end
    end

    # ── Legacy candidates (pito.* outside pito.copy.*) ────────────────────

    describe "legacy_candidates" do
      subject(:candidates) { described_class.call.legacy_candidates }

      it "includes array-valued leaves under pito.* but outside pito.copy.*" do
        keys = candidates.map { |c| c[:key] }
        expect(keys).to include(
          "pito.legacy_array",
          "pito.nested_legacy.inner"
        )
      end

      it "does NOT include pito.copy.* entries" do
        keys = candidates.map { |c| c[:key] }
        expect(keys).not_to include(
          "pito.copy.greeting",
          "pito.copy.farewell",
          "pito.copy.tagged"
        )
      end

      it "does NOT include plain string leaves (only arrays are candidates)" do
        keys = candidates.map { |c| c[:key] }
        expect(keys).not_to include("pito.plain_string")
      end

      context "with pito.legacy_array" do
        subject(:entry) { candidates.find { |c| c[:key] == "pito.legacy_array" } }

        it "reports the correct variant count" do
          expect(entry[:variants]).to eq(3)
        end

        it "reports no placeholders" do
          expect(entry[:placeholders]).to be_empty
        end
      end

      context "with pito.nested_legacy.inner (has placeholder)" do
        subject(:entry) { candidates.find { |c| c[:key] == "pito.nested_legacy.inner" } }

        it "extracts the placeholder" do
          expect(entry[:placeholders]).to eq([ "foo" ])
        end
      end
    end

    # ── Placeholder extraction ────────────────────────────────────────────

    describe "placeholder extraction" do
      it "extracts unique placeholder names from all variants" do
        entry = result.registered.find { |r| r[:key] == "pito.copy.tagged" }
        # Both variants use %{name} → only one unique entry
        expect(entry[:placeholders]).to eq([ "name" ])
      end

      it "sorts placeholder names alphabetically" do
        entry = result.registered.find { |r| r[:key] == "pito.copy.dual_var" }
        expect(entry[:placeholders]).to eq(%w[receiver sender])
      end
    end
  end
end
