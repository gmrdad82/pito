require "rails_helper"

RSpec.describe CalendarEntryCrossReferenceValidator do
  describe "channel_published" do
    it "happy with channel_id only" do
      entry = build(:calendar_entry, :channel_published)
      expect(entry).to be_valid
    end

    it "rejects video_id" do
      entry = build(:calendar_entry, :channel_published)
      entry.video = create(:video)
      expect(entry).not_to be_valid
    end

    it "rejects game_id" do
      entry = build(:calendar_entry, :channel_published)
      entry.game = create(:game)
      expect(entry).not_to be_valid
    end

    it "rejects parent_entry_id" do
      parent = create(:calendar_entry, :game_release)
      entry = build(:calendar_entry, :channel_published)
      entry.parent_entry = parent
      expect(entry).not_to be_valid
    end

    it "rejects milestone_rule_id" do
      rule = create(:milestone_rule)
      entry = build(:calendar_entry, :channel_published)
      entry.milestone_rule = rule
      expect(entry).not_to be_valid
    end
  end

  describe "video_published" do
    it "requires video_id" do
      entry = build(:calendar_entry, :video_published)
      entry.video = nil
      entry.source_ref = nil
      expect(entry).not_to be_valid
      expect(entry.errors[:video_id]).to be_present
    end

    it "rejects channel_id" do
      entry = build(:calendar_entry, :video_published)
      entry.channel = create(:channel)
      expect(entry).not_to be_valid
    end
  end

  describe "video_scheduled" do
    it "requires video_id" do
      entry = build(:calendar_entry, :video_scheduled)
      entry.video = nil
      entry.source_ref = nil
      expect(entry).not_to be_valid
    end
  end

  describe "game_release" do
    it "happy with game_id" do
      entry = build(:calendar_entry, :game_release)
      expect(entry).to be_valid
    end

    it "happy with game_id nil (pre-IGDB)" do
      entry = build(:calendar_entry, :game_release)
      entry.game = nil
      expect(entry).to be_valid
    end

    it "rejects channel_id" do
      entry = build(:calendar_entry, :game_release)
      entry.channel = create(:channel)
      expect(entry).not_to be_valid
    end
  end

  describe "purchase_planned" do
    it "happy with parent_entry + optional game_id" do
      entry = build(:calendar_entry, :purchase_planned)
      entry.game = create(:game)
      expect(entry).to be_valid
    end

    it "rejects channel_id" do
      entry = build(:calendar_entry, :purchase_planned)
      entry.channel = create(:channel)
      expect(entry).not_to be_valid
    end
  end

  describe "milestone_manual" do
    it "happy with no FKs" do
      entry = build(:calendar_entry, :milestone_manual)
      expect(entry).to be_valid
    end

    it "happy with project_id only" do
      entry = build(:calendar_entry, :milestone_manual)
      entry.project = create(:project)
      expect(entry).to be_valid
    end

    it "rejects channel_id" do
      entry = build(:calendar_entry, :milestone_manual)
      entry.channel = create(:channel)
      expect(entry).not_to be_valid
    end
  end

  describe "milestone_auto" do
    it "happy with milestone_rule_id" do
      entry = build(:calendar_entry, :milestone_auto)
      expect(entry).to be_valid
    end

    it "rejects channel_id" do
      entry = build(:calendar_entry, :milestone_auto)
      entry.channel = create(:channel)
      expect(entry).not_to be_valid
    end
  end

  describe "custom" do
    it "happy with no FKs" do
      entry = build(:calendar_entry, :custom)
      expect(entry).to be_valid
    end

    it "rejects video_id" do
      entry = build(:calendar_entry, :custom)
      entry.video = create(:video)
      expect(entry).not_to be_valid
    end
  end
end
