# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pito::Copy shinies", type: :service do
  SHINIES_THRESHOLDS = [
    1, 2, 5, 10, 20, 50, 100, 200, 500,
    1_000, 2_000, 5_000, 10_000, 20_000, 50_000,
    100_000, 200_000, 500_000,
    1_000_000, 2_000_000, 5_000_000, 10_000_000
  ].freeze

  describe "pito.copy.shinies.heading" do
    it "resolves to 'Shinies'" do
      expect(Pito::Copy.render("pito.copy.shinies.heading")).to eq("Shinies")
    end
  end

  describe "pito.copy.shinies.singular" do
    it "resolves to 'shiny'" do
      expect(Pito::Copy.render("pito.copy.shinies.singular")).to eq("shiny")
    end
  end

  describe "step names (general)" do
    SHINIES_THRESHOLDS.each do |threshold|
      context "threshold #{threshold}" do
        subject(:name) { Pito::Copy.render("pito.copy.shinies.steps.#{threshold}") }

        it "resolves to a non-blank string" do
          expect(name).to be_a(String).and(satisfy("be non-blank") { |s| s.present? })
        end

        it "contains neither 'milestone' nor 'achievement'" do
          expect(name).not_to match(/milestone|achievement/i)
        end
      end
    end
  end

  describe "step names (game / ROI flavor)" do
    SHINIES_THRESHOLDS.each do |threshold|
      context "threshold #{threshold}" do
        subject(:name) { Pito::Copy.render("pito.copy.shinies.steps_game.#{threshold}") }

        it "resolves to a non-blank string" do
          expect(name).to be_a(String).and(satisfy("be non-blank") { |s| s.present? })
        end

        it "contains neither 'milestone' nor 'achievement'" do
          expect(name).not_to match(/milestone|achievement/i)
        end
      end
    end
  end
end
