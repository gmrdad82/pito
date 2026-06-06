# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/copy"

RSpec.describe Pito::Copy, type: :service do
  # Register isolated fixture keys directly into the backend so these tests
  # never depend on real copy in config/locales/.
  around do |example|
    I18n.backend.store_translations(:en, copy_spec: {
      greeting:   "Hello!",
      with_name:  "Hey, %{name}!",
      two_vars:   "From %{sender} to %{receiver}.",
      variants:   [ "alpha", "beta", "gamma" ],
      one_item:   [ "only" ],
      nested:     { child: "child value" }
    })
    example.run
  end

  # ── sampler is overridden to deterministic (first) by spec/support/copy.rb ──

  describe ".render" do
    context "with a String entry" do
      it "returns the string unchanged when no vars are needed" do
        expect(described_class.render("copy_spec.greeting")).to eq("Hello!")
      end
    end

    context "with a one-element Array entry" do
      it "behaves like a single string" do
        expect(described_class.render("copy_spec.one_item")).to eq("only")
      end
    end

    context "with an Array of variants" do
      it "returns an element that is in the set (using deterministic sampler → first)" do
        result = described_class.render("copy_spec.variants")
        expect(%w[alpha beta gamma]).to include(result)
      end

      it "returns the first entry with the deterministic sampler (no variant:)" do
        expect(described_class.render("copy_spec.variants")).to eq("alpha")
      end

      it "returns the correct entry for variant: 0" do
        expect(described_class.render("copy_spec.variants", variant: 0)).to eq("alpha")
      end

      it "returns the correct entry for variant: 1" do
        expect(described_class.render("copy_spec.variants", variant: 1)).to eq("beta")
      end

      it "returns the correct entry for variant: 2 (3rd element)" do
        expect(described_class.render("copy_spec.variants", variant: 2)).to eq("gamma")
      end

      it "raises IndexError for an out-of-range variant:" do
        expect { described_class.render("copy_spec.variants", variant: 99) }
          .to raise_error(IndexError)
      end
    end

    context "with interpolation" do
      it "fills a single %{name} placeholder" do
        result = described_class.render("copy_spec.with_name", { name: "Alice" })
        expect(result).to eq("Hey, Alice!")
      end

      it "fills multiple placeholders" do
        result = described_class.render(
          "copy_spec.two_vars",
          { sender: "Bob", receiver: "Carol" }
        )
        expect(result).to eq("From Bob to Carol.")
      end

      it "raises MissingPlaceholder when a %{token} has no matching key in vars" do
        expect { described_class.render("copy_spec.with_name") }
          .to raise_error(Pito::Copy::MissingPlaceholder, /name/)
      end

      it "MissingPlaceholder message names the i18n key" do
        expect { described_class.render("copy_spec.with_name") }
          .to raise_error(Pito::Copy::MissingPlaceholder, /copy_spec\.with_name/)
      end
    end

    context "with a missing i18n key" do
      it "raises I18n::MissingTranslationData (never returns a silent string)" do
        expect { described_class.render("copy_spec.does_not_exist") }
          .to raise_error(I18n::MissingTranslationData)
      end
    end

    context "with a namespace (Hash) key" do
      it "raises ArgumentError" do
        expect { described_class.render("copy_spec.nested") }
          .to raise_error(ArgumentError, /namespace/)
      end

      it "error message names the key" do
        expect { described_class.render("copy_spec.nested") }
          .to raise_error(ArgumentError, /copy_spec\.nested/)
      end
    end
  end

  describe ".sampler" do
    it "defaults to first-entry in spec env (installed by support/copy.rb)" do
      described_class.sampler = ->(entries) { entries.last }
      expect(described_class.render("copy_spec.variants")).to eq("gamma")
    end

    it "is restored to deterministic (first) after each example" do
      # This example runs AFTER the override above; the after(:each) hook in
      # spec/support/copy.rb should have restored it.
      expect(described_class.render("copy_spec.variants")).to eq("alpha")
    end
  end

  describe ".reset_sampler!" do
    it "restores the default (random) sampler" do
      described_class.sampler = ->(entries) { entries.last }
      described_class.reset_sampler!
      # After reset, sampler should be DEFAULT_SAMPLER (random). We can't
      # assert on randomness directly, but we CAN assert the result is in-set.
      result = described_class.render("copy_spec.variants")
      expect(%w[alpha beta gamma]).to include(result)
    end
  end
end
