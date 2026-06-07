# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Theme::List do
  let(:conversation) { create(:conversation) }

  describe ".call" do
    let(:grouped)      { Pito::Themes::Registry.grouped }
    let(:current_slug) { "dracula" }

    subject(:payload) do
      described_class.call(grouped: grouped, current_slug: current_slug, conversation: conversation)
    end

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "includes a body" do
      expect(payload["body"]).to be_present
    end

    it "includes sections with Dark and Light" do
      titles = payload["sections"].map { |s| s[:title] }
      expect(titles).to include("Dark", "Light")
    end

    it "marks the current theme with value2" do
      rows = payload["sections"].flat_map { |s| s[:rows] }
      current = rows.find { |r| r[:key] == "dracula" }
      expect(current[:value2]).to be_present
    end

    it "does not mark other themes" do
      rows = payload["sections"].flat_map { |s| s[:rows] }
      non_current = rows.reject { |r| r[:key] == "dracula" }
      expect(non_current.none? { |r| r[:value2].present? }).to be true
    end

    it "is follow-up-able with target theme_list" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
      expect(payload["reply_target"]).to eq("theme_list")
    end

    it "has a reply_handle in the payload" do
      expect(payload["reply_handle"]).to be_present
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
