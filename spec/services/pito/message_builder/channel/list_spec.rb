# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Channel::List do
  let(:conversation) { create(:conversation) }
  let!(:alpha) { create(:channel, title: "Alpha Tube", handle: "@alpha", youtube_channel_id: "UCa") }
  let!(:beta)  { create(:channel, title: "Beta Cast", handle: "@beta", youtube_channel_id: "UCb") }

  describe ".call" do
    let(:channels) { ::Channel.order(:title) }

    subject(:payload) { described_class.call(channels, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html true" do
      expect(payload["html"]).to be true
    end

    # The kv-table (Phase LS): titles/handles live in table_rows cells now —
    # the body carries only the intro line.
    it "renders the table heading Avatar(blank)/Handle/Title/Subs/Views/Vids" do
      texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      expect(texts).to eq([ "", "Handle", "Title", "Subs", "Views", "Vids" ])
    end

    it "right-aligns the count headings" do
      right = payload["table_heading"].select { |h| h.is_a?(Hash) }
      expect(right.map { |h| h["class"] }).to all(include("text-right"))
    end

    it "includes channel titles as Title cells" do
      titles = payload["table_rows"].map { |r| r[:cells][2][:text] }
      expect(titles).to contain_exactly("Alpha Tube", "Beta Cast")
    end

    it "renders the Handle cell as the click-to-open seam (show channel prefill)" do
      handle_cell = payload["table_rows"].first[:cells][1]
      expect(handle_cell[:text]).to eq("@alpha")
      expect(handle_cell[:data].to_h.values.join(" ")).to include("show channel @alpha")
    end

    it "renders the Avatar cell as html with the tiny ringed avatar class" do
      avatar_cell = payload["table_rows"].first[:cells][0]
      expect(avatar_cell[:html]).to be true
      expect(avatar_cell[:text]).to include("pito-channel-tiny-avatar")
    end

    it "renders compact right-aligned count cells" do
      subs_cell = payload["table_rows"].first[:cells][3]
      expect(subs_cell[:class]).to include("text-right")
    end

    it "stamps channel_ids in listed order" do
      expect(payload["channel_ids"]).to eq(channels.map(&:id))
    end

    it "wraps the intro count in a subject-shimmer span" do
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">2</span>})
    end

    it "wraps the channels noun in a subject-shimmer span" do
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">channels</span>})
    end

    context "when there is exactly 1 channel" do
      let(:channels) { ::Channel.where(id: alpha.id) }

      it "uses the singular noun 'channel'" do
        expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">channel</span>})
      end

      it "does not use the plural noun 'channels'" do
        expect(payload["body"]).not_to match(%r{<span class="pito-subject-shimmer[^"]*">channels</span>})
      end
    end

    it "is follow-up-able with target channel_list" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
      expect(payload["reply_target"]).to eq("channel_list")
    end

    it "has a reply_handle in the payload" do
      expect(payload["reply_handle"]).to be_present
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end

    # Channel list is sort-only: addable and removable are both empty (no with/without),
    # so only the sort line is rendered. The footer mentions sort keys (handle, subs, vids)
    # but contains no column-add/remove instructions (no `with` / `without` clauses).
    it "payload list_footer mentions sort keys but no column-manipulation instructions" do
      expect(payload["list_footer"]).to be_a(String)
      expect(payload["list_footer"]).to include("subs")
      expect(payload["list_footer"]).to include("vids")
      expect(payload["list_footer"]).not_to include("`with")
    end
  end
end
