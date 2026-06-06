# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::WebhookUrlMask do
  describe ".call" do
    context "known brands" do
      it "returns the Discord mask for :discord" do
        expect(described_class.call(:discord)).to eq("https://discord.com/***")
      end

      it "returns the Slack mask for :slack" do
        expect(described_class.call(:slack)).to eq("https://hooks.slack.com/***")
      end

      it "accepts string 'discord' (coerces via to_sym)" do
        expect(described_class.call("discord")).to eq("https://discord.com/***")
      end

      it "accepts string 'slack' (coerces via to_sym)" do
        expect(described_class.call("slack")).to eq("https://hooks.slack.com/***")
      end
    end

    context "unknown brand" do
      it "raises ArgumentError for an unknown symbol" do
        expect { described_class.call(:twitch) }.to raise_error(ArgumentError, /unknown brand/)
      end

      it "raises ArgumentError for an unknown string" do
        expect { described_class.call("unknown") }.to raise_error(ArgumentError, /unknown brand/)
      end

      it "includes the offending brand name in the message" do
        expect { described_class.call(:twitch) }.to raise_error(ArgumentError, /twitch/)
      end
    end

    context "edge cases" do
      it "raises ArgumentError for nil (nil.to_sym raises — no silent failure)" do
        expect { described_class.call(nil) }.to raise_error(NoMethodError)
      end

      it "does not include the actual webhook secret in the output" do
        %i[discord slack].each do |brand|
          mask = described_class.call(brand)
          expect(mask).to end_with("***")
          expect(mask).not_to match(%r{/api/webhooks/|/services/})
        end
      end
    end
  end
end
