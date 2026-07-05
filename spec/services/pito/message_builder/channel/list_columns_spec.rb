# frozen_string_literal: true

require "rails_helper"

# G26.2/G82 — channels' with/without columns: identity (handle/title) is fixed
# and always sortable; every counter (subs/views/vids/likes) is a selectable
# column that sorts only while visible. DEFAULT_COLUMNS ships subs/views/vids.
RSpec.describe Pito::MessageBuilder::Channel::ListColumns do
  # ── vocabulary ──────────────────────────────────────────────────────────────

  describe ".vocabulary" do
    subject(:vocab) { described_class.vocabulary }

    it "returns a Hash" do
      expect(vocab).to be_a(Hash)
    end

    it "maps 'likes' to :likes" do
      expect(vocab["likes"]).to eq(:likes)
    end

    it "maps every counter alias to its canonical token (G82)" do
      expect(vocab["subs"]).to eq(:subs)
      expect(vocab["subscribers"]).to eq(:subs)
      expect(vocab["views"]).to eq(:views)
      expect(vocab["vids"]).to eq(:vids)
      expect(vocab["videos"]).to eq(:vids)
    end

    it "does not include the identity columns (they are not with/without-able)" do
      %w[handle title].each do |fixed|
        expect(vocab.key?(fixed)).to be(false), "expected #{fixed} not to be addable"
      end
    end

    it "does not include unknown tokens" do
      expect(vocab.key?("unknown_token")).to be(false)
    end
  end

  # ── sort_key_for ─────────────────────────────────────────────────────────────

  describe ".sort_key_for" do
    let(:channel) { create(:channel, title: "Alpha Tube", handle: "@alpha") }

    it "returns a proc for the identity columns regardless of selected_columns" do
      %w[handle title].each do |token|
        expect(described_class.sort_key_for(token, selected_columns: []))
          .to be_a(Proc), "expected #{token} to always sort"
      end
    end

    it "sorts a counter only while visible (G82 — subs/views/vids joined likes)" do
      %w[subs views vids].each do |token|
        expect(described_class.sort_key_for(token, selected_columns: [])).to be_nil
        expect(described_class.sort_key_for(token, selected_columns: %i[subs views vids]))
          .to be_a(Proc), "expected visible #{token} to sort"
      end
    end

    it "keys the 'title' sort on the downcased title" do
      key = described_class.sort_key_for("title", selected_columns: [])
      expect(key.call(channel)).to eq("alpha tube")
    end

    it "resolves the canonical-noun aliases while visible (subscribers→subs, videos→vids)" do
      selected = %i[subs vids]
      expect(described_class.sort_key_for("subscribers", selected_columns: selected)).to be_a(Proc)
      expect(described_class.sort_key_for("videos",      selected_columns: selected)).to be_a(Proc)
    end

    it "returns nil for 'likes' when :likes is not in selected_columns" do
      expect(described_class.sort_key_for("likes", selected_columns: [])).to be_nil
    end

    it "returns a proc for 'likes' when :likes IS in selected_columns" do
      key = described_class.sort_key_for("likes", selected_columns: [ :likes ])
      expect(key).to be_a(Proc)
    end

    it "keys the 'likes' sort on the channel's materialized likes row (G28)" do
      Pito::Stats.set(channel, :likes, 700)
      key = described_class.sort_key_for("likes", selected_columns: [ :likes ])
      expect(key.call(channel)).to eq(700)
    end

    it "returns nil for an unknown token" do
      expect(described_class.sort_key_for("bogus", selected_columns: [ :likes ])).to be_nil
    end

    it "is case-insensitive for the token" do
      expect(described_class.sort_key_for("TITLE", selected_columns: [])).to be_a(Proc)
    end
  end

  # ── sortable_tokens ──────────────────────────────────────────────────────────

  describe ".sortable_tokens" do
    it "lists only the identity columns when nothing is selected" do
      expect(described_class.sortable_tokens(selected_columns: []))
        .to eq(%w[handle title])
    end

    it "appends the visible counters in canonical order (the default table)" do
      expect(described_class.sortable_tokens(selected_columns: described_class::DEFAULT_COLUMNS))
        .to eq(%w[handle title subs views vids])
    end

    it "includes likes while selected" do
      expect(described_class.sortable_tokens(selected_columns: %i[likes subs]))
        .to eq(%w[handle title subs likes])
    end
  end
end
