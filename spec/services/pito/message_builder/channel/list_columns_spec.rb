# frozen_string_literal: true

require "rails_helper"

# G26.2 — channels joined the with/without mechanism: the fixed kv-table
# (handle/title/subs/views/vids) is always sortable, while addable columns
# (likes) sort only while visible.
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

    it "does not include the fixed columns (they are not with/without-able)" do
      %w[handle title subs views vids].each do |fixed|
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

    it "returns a proc for every fixed column regardless of selected_columns" do
      %w[handle title subs views vids].each do |token|
        expect(described_class.sort_key_for(token, selected_columns: []))
          .to be_a(Proc), "expected #{token} to always sort"
      end
    end

    it "keys the 'title' sort on the downcased title" do
      key = described_class.sort_key_for("title", selected_columns: [])
      expect(key.call(channel)).to eq("alpha tube")
    end

    it "resolves the canonical-noun aliases (subscribers→subs, videos→vids)" do
      expect(described_class.sort_key_for("subscribers", selected_columns: [])).to be_a(Proc)
      expect(described_class.sort_key_for("videos",      selected_columns: [])).to be_a(Proc)
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
    it "lists the fixed columns when nothing is selected" do
      expect(described_class.sortable_tokens(selected_columns: []))
        .to eq(%w[handle title subs views vids])
    end

    it "appends the visible addable columns" do
      expect(described_class.sortable_tokens(selected_columns: [ :likes ]))
        .to eq(%w[handle title subs views vids likes])
    end
  end
end
