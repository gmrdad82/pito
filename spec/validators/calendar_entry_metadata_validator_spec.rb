require "rails_helper"

RSpec.describe CalendarEntryMetadataValidator do
  describe "key allowlist per entry_type" do
    it "strips unknown keys for game_release" do
      entry = build(:calendar_entry, :game_release,
                    metadata: { "platforms" => %w[PC], "evil" => 1 })
      entry.valid?
      expect(entry.metadata).to eq("platforms" => %w[PC])
    end

    it "preserves user_overrides on every type" do
      %i[
        channel_published video_published video_scheduled
        game_release purchase_planned milestone_manual
        milestone_auto custom
      ].each do |trait|
        entry = build(:calendar_entry, trait,
                      metadata: { "user_overrides" => { "k" => "v" } })
        entry.valid?
        expect(entry.metadata["user_overrides"]).to eq("k" => "v"), "trait #{trait}"
      end
    end

    it "keeps purchase_planned-specific keys" do
      parent = create(:calendar_entry, :game_release)
      entry = build(:calendar_entry, :purchase_planned,
                    parent_entry: parent,
                    metadata: {
                      "purchase_kind" => "preorder",
                      "storefront" => "Steam",
                      "amount" => "39.99",
                      "currency" => "EUR",
                      "intruder" => "x"
                    })
      entry.valid?
      expect(entry.metadata).to include(
        "purchase_kind" => "preorder",
        "storefront" => "Steam",
        "amount" => "39.99",
        "currency" => "EUR"
      )
      expect(entry.metadata).not_to include("intruder")
    end

    it "keeps milestone_auto's metric_value_at_fire" do
      rule = create(:milestone_rule)
      entry = build(:calendar_entry, :milestone_auto,
                    milestone_rule: rule,
                    metadata: { "metric_value_at_fire" => 100, "extra" => "x" })
      entry.valid?
      expect(entry.metadata).to eq("metric_value_at_fire" => 100)
    end

    it "keeps custom's tags array" do
      entry = build(:calendar_entry, :custom,
                    metadata: { "tags" => %w[a b], "huh" => 1 })
      entry.valid?
      expect(entry.metadata).to eq("tags" => %w[a b])
    end
  end
end
