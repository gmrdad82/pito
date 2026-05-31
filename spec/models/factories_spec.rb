# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Factories" do
  # ── Base factories ───────────────────────────────────────────
  describe "base factories build valid records" do
    FactoryBot.factories.each do |factory|
      context "#{factory.name}" do
        it "builds a valid instance" do
          instance = build(factory.name)
          expect(instance).to be_valid
        end
      end
    end
  end

  # ── Traits ─────────────────────────────────────────────────────
  describe "traits build valid records" do
    # Factories that have traits defined
    factories_with_traits = FactoryBot.factories.select { |f| f.definition.defined_traits.any? }

    factories_with_traits.each do |factory|
      factory.definition.defined_traits.each do |trait|
        context "#{factory.name} + :#{trait.name}" do
          it "builds a valid instance" do
            instance = build(factory.name, trait.name)
            expect(instance).to be_valid
          end
        end
      end
    end
  end

  # ── Create smoke (slower, one per factory) ──────────────────
  describe "create smoke" do
    # Sample one trait per factory to verify create path works end-to-end
    FactoryBot.factories.each do |factory|
      context "#{factory.name}" do
        it "creates successfully" do
          expect { create(factory.name) }.not_to raise_error
        end
      end
    end
  end
end
