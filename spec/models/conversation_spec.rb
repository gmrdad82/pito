# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conversation, type: :model do
  subject(:conversation) { build(:conversation) }

  describe "validations" do
    it { is_expected.to validate_uniqueness_of(:uuid).ignoring_case_sensitivity }

    it "validates uniqueness of uuid" do
      first = create(:conversation)
      second = build(:conversation, uuid: first.uuid)
      expect(second).not_to be_valid
      expect(second.errors[:uuid]).to include("has already been taken")
    end
  end

  describe "uuid generation" do
    it "sets a uuid before creation" do
      conv = create(:conversation)
      expect(conv.uuid).to be_present
      expect(conv.uuid).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "preserves an explicitly assigned lowercase uuid" do
      custom_uuid = "550e8400-e29b-41d4-a716-446655440000"
      conv = create(:conversation, uuid: custom_uuid)
      expect(conv.uuid).to eq(custom_uuid)
    end

    it "downcases an uppercased uuid" do
      upper = "550E8400-E29B-41D4-A716-446655440000"
      conv  = create(:conversation, uuid: upper)
      expect(conv.uuid).to eq(upper.downcase)
    end
  end

  describe "#to_param" do
    it "returns the uuid" do
      conv = create(:conversation)
      expect(conv.to_param).to eq(conv.uuid)
    end
  end

  describe "#display_name" do
    it "returns the title when present" do
      conv = build(:conversation, title: "My Chat")
      expect(conv.display_name).to eq("My Chat")
    end

    it "falls back to 'Unnamed <id>' for an in-memory record that skipped before_create" do
      # Build (not create) so before_create callbacks don't run; title stays nil.
      conv = build(:conversation, title: nil)
      # Simulate a saved-but-titleless record by stubbing id.
      allow(conv).to receive(:id).and_return(99)
      expect(conv.display_name).to eq("Unnamed 99")
    end
  end

  describe "#set_default_title (before_create)" do
    it "sets a default 'Unnamed N' title on create when title is nil" do
      conv = create(:conversation)
      expect(conv.title).to match(/\AUnnamed \d+\z/)
    end

    it "numbers new conversations sequentially starting at 1" do
      Conversation.delete_all
      first  = create(:conversation)
      second = create(:conversation)
      expect(first.title).to eq("Unnamed 1")
      expect(second.title).to eq("Unnamed 2")
    end

    it "does not overwrite an explicitly provided title" do
      conv = create(:conversation, title: "My Chat")
      expect(conv.title).to eq("My Chat")
    end
  end

  describe "#named?" do
    it "returns false for an auto-generated 'Unnamed N' title" do
      conv = build(:conversation, title: "Unnamed 3")
      expect(conv.named?).to be false
    end

    it "returns false when title is nil" do
      conv = build(:conversation, title: nil)
      expect(conv.named?).to be false
    end

    it "returns true when the title is user-chosen (not 'Unnamed …')" do
      conv = build(:conversation, title: "My Gaming Session")
      expect(conv.named?).to be true
    end

    it "returns false for a title starting with 'Unnamed ' (word boundary)" do
      conv = build(:conversation, title: "Unnamed but extended title")
      expect(conv.named?).to be false
    end

    it "returns false for a blank title" do
      conv = build(:conversation, title: "")
      expect(conv.named?).to be false
    end
  end

  describe "#default_title? (stricter than !named?, for auto-purge)" do
    it "is true for the literal auto-default 'Unnamed N'" do
      expect(build(:conversation, title: "Unnamed 17").default_title?).to be true
    end

    it "is true for a blank/nil title" do
      expect(build(:conversation, title: "").default_title?).to be true
      expect(build(:conversation, title: nil).default_title?).to be true
    end

    it "is FALSE for a user title that merely starts with 'Unnamed' (protected)" do
      expect(build(:conversation, title: "Unnamed thoughts").default_title?).to be false
    end

    it "is false for any user-chosen title" do
      expect(build(:conversation, title: "My Gaming Session").default_title?).to be false
    end
  end

  describe ".singleton" do
    it "creates a conversation when none exists" do
      expect { Conversation.singleton }.to change(described_class, :count).by(1)
    end

    it "returns the same record across calls" do
      first = Conversation.singleton
      second = Conversation.singleton
      expect(first).to eq(second)
    end

    it "does not create a new record when one already exists" do
      Conversation.singleton
      expect { Conversation.singleton }.not_to change(described_class, :count)
    end
  end

  describe ".by_recent_activity" do
    it "returns conversations ordered most-recently-active first" do
      old_conv  = create(:conversation)
      new_conv  = create(:conversation)
      turn      = create(:turn, conversation: new_conv)
      # Give the old conversation an older event and new_conv a recent one
      create(:event, conversation: old_conv, turn: turn, created_at: 3.hours.ago)
      # new_conv has no events — falls back to its created_at which was just now
      results = described_class.by_recent_activity.to_a
      expect(results.first.id).to eq(new_conv.id)
      expect(results.last.id).to eq(old_conv.id)
    end

    it "uses the most recent event's created_at as last_activity_at" do
      conv  = create(:conversation)
      turn  = create(:turn, conversation: conv)
      early = create(:event, conversation: conv, turn: turn, created_at: 10.days.ago)
      late  = create(:event, conversation: conv, turn: turn, created_at: 1.hour.ago,
                             position: early.position + 1)
      result = described_class.by_recent_activity.find { |c| c.id == conv.id }
      expect(result.last_activity_at).to be_within(5.seconds).of(late.created_at)
    end

    it "falls back to conversation created_at when no events exist" do
      conv   = create(:conversation)
      result = described_class.by_recent_activity.find { |c| c.id == conv.id }
      expect(result.last_activity_at).to be_within(5.seconds).of(conv.created_at)
    end

    it "exposes last_activity_at on each record" do
      create(:conversation)
      results = described_class.by_recent_activity.to_a
      expect(results).to all(respond_to(:last_activity_at))
    end
  end

  describe "#context_event_count" do
    it "counts only :system, :enhanced, :confirmation messages (not thinking/echo/follow-ups)" do
      conv = create(:conversation)
      turn = create(:turn, conversation: conv)
      %i[system enhanced confirmation].each { |k| create(:event, conversation: conv, turn: turn, kind: k) }
      %i[thinking echo error theme_diff system_follow_up enhanced_follow_up confirmation_follow_up]
        .each { |k| create(:event, conversation: conv, turn: turn, kind: k) }
      expect(conv.context_event_count).to eq(3)
    end
  end

  describe ".purgeable" do
    # An UNNAMED conversation (default "Unnamed N" title) made "old" via a 40-day-old event.
    def old_unnamed
      c = create(:conversation)
      t = create(:turn, conversation: c)
      create(:event, conversation: c, turn: t, created_at: 40.days.ago)
      c
    end

    it "selects unnamed conversations with no activity in 30 days" do
      c = old_unnamed
      expect(described_class.purgeable.map(&:id)).to include(c.id)
    end

    it "NEVER selects a named conversation, even when old" do
      c = create(:conversation, :named)
      t = create(:turn, conversation: c)
      create(:event, conversation: c, turn: t, created_at: 40.days.ago)
      expect(c.named?).to be true
      expect(described_class.purgeable.map(&:id)).not_to include(c.id)
    end

    it "protects a user title that merely starts with 'Unnamed' (not the literal default)" do
      c = create(:conversation, title: "Unnamed thoughts")
      t = create(:turn, conversation: c)
      create(:event, conversation: c, turn: t, created_at: 40.days.ago)
      expect(described_class.purgeable.map(&:id)).not_to include(c.id)
    end

    it "does not select a recently-active unnamed conversation" do
      c = create(:conversation) # no events → last_activity = created_at (now)
      expect(described_class.purgeable.map(&:id)).not_to include(c.id)
    end

    it "treats the default 'Unnamed' title as unnamed (selectable when old)" do
      c = old_unnamed
      expect(c.named?).to be false
      expect(described_class.purgeable.map(&:id)).to include(c.id)
    end

    it "respects the older_than boundary" do
      c = create(:conversation)
      t = create(:turn, conversation: c)
      create(:event, conversation: c, turn: t, created_at: 20.days.ago)
      expect(described_class.purgeable.map(&:id)).not_to include(c.id)
      expect(described_class.purgeable(older_than: 10.days.ago).map(&:id)).to include(c.id)
    end
  end

  describe ".recency_groups" do
    context "when there are no conversations" do
      it "returns empty recent and older buckets" do
        groups = described_class.recency_groups
        expect(groups[:recent]).to be_empty
        expect(groups[:older]).to be_empty
      end
    end

    context "when there is a single conversation" do
      it "places it in recent and leaves older empty" do
        create(:conversation)
        groups = described_class.recency_groups
        expect(groups[:recent].size).to eq(1)
        expect(groups[:older]).to be_empty
      end
    end

    context "when all conversations are within 24h of the newest" do
      it "places all in recent and leaves older empty" do
        # Create two conversations whose activity is within 1h of each other
        conv1 = create(:conversation)
        conv2 = create(:conversation)
        turn1 = create(:turn, conversation: conv1)
        turn2 = create(:turn, conversation: conv2)
        create(:event, conversation: conv1, turn: turn1, created_at: 23.hours.ago)
        create(:event, conversation: conv2, turn: turn2, created_at: 22.hours.ago)
        groups = described_class.recency_groups
        expect(groups[:recent].size).to eq(2)
        expect(groups[:older]).to be_empty
      end
    end

    context "when some conversations are older than 24h from the newest" do
      it "splits correctly into recent and older buckets" do
        newest = create(:conversation)
        old    = create(:conversation)
        turn_n = create(:turn, conversation: newest)
        turn_o = create(:turn, conversation: old)
        create(:event, conversation: newest, turn: turn_n, created_at: 1.hour.ago)
        create(:event, conversation: old,    turn: turn_o, created_at: 30.hours.ago)
        groups = described_class.recency_groups
        expect(groups[:recent].map(&:id)).to include(newest.id)
        expect(groups[:older].map(&:id)).to include(old.id)
      end
    end

    it "orders recent by last_activity_at descending" do
      conv_a = create(:conversation)
      conv_b = create(:conversation)
      turn_a = create(:turn, conversation: conv_a)
      turn_b = create(:turn, conversation: conv_b)
      create(:event, conversation: conv_a, turn: turn_a, created_at: 5.hours.ago)
      create(:event, conversation: conv_b, turn: turn_b, created_at: 1.hour.ago)
      groups = described_class.recency_groups
      ids = groups[:recent].map(&:id)
      expect(ids.index(conv_b.id)).to be < ids.index(conv_a.id)
    end
  end

  describe ".find_by_title_ci" do
    it "returns nil when given nil" do
      expect(described_class.find_by_title_ci(nil)).to be_nil
    end

    it "returns nil when given a blank string" do
      expect(described_class.find_by_title_ci("")).to be_nil
    end

    it "returns nil when given a whitespace-only string" do
      expect(described_class.find_by_title_ci("   ")).to be_nil
    end

    it "returns nil when no conversation title matches" do
      create(:conversation, title: "Elden Ring")
      expect(described_class.find_by_title_ci("Dark Souls")).to be_nil
    end

    it "returns the conversation on an exact same-case match" do
      conv = create(:conversation, title: "My Chat")
      expect(described_class.find_by_title_ci("My Chat")).to eq(conv)
    end

    it "matches regardless of case" do
      conv = create(:conversation, title: "My Chat")
      expect(described_class.find_by_title_ci("my chat")).to eq(conv)
      expect(described_class.find_by_title_ci("MY CHAT")).to eq(conv)
      expect(described_class.find_by_title_ci("mY cHaT")).to eq(conv)
    end

    it "strips leading/trailing whitespace from the query before matching" do
      conv = create(:conversation, title: "Hollow Knight")
      expect(described_class.find_by_title_ci("  Hollow Knight  ")).to eq(conv)
    end
  end

  describe ".similar_titles" do
    it "returns [] when given nil" do
      expect(described_class.similar_titles(nil)).to eq([])
    end

    it "returns [] when given a blank string" do
      expect(described_class.similar_titles("")).to eq([])
      expect(described_class.similar_titles("  ")).to eq([])
    end

    it "returns [] when nothing is within the edit-distance threshold" do
      create(:conversation, title: "Alpha")
      # "omega" vs "alpha": distance 4, threshold max(5/3=1, 2) = 2 → excluded
      expect(described_class.similar_titles("omega")).to eq([])
    end

    it "excludes an exact case-insensitive match" do
      create(:conversation, title: "Elden Ring")
      expect(described_class.similar_titles("Elden Ring")).to eq([])
      expect(described_class.similar_titles("elden ring")).to eq([])
    end

    it "includes a title within the threshold (single-char typo)" do
      conv = create(:conversation, title: "Elden Ring")
      # "elden rink" vs "elden ring": distance 1 (g→k)
      # threshold = max(max(10,10)/3=3, 2) = 3; 1 ≤ 3 → included
      result = described_class.similar_titles("elden rink")
      expect(result).to include(conv)
    end

    it "excludes a title that is too far away" do
      create(:conversation, title: "hello")
      # "world" vs "hello": distance 4, threshold max(5/3=1, 2) = 2 → excluded
      expect(described_class.similar_titles("world")).to be_empty
    end

    it "respects the default limit of 5" do
      # Six titles each 1 edit from "hello" (single substitution)
      %w[aello hbllo heclo heldo hellx zello].each { |t| create(:conversation, title: t) }
      result = described_class.similar_titles("hello")
      expect(result.size).to eq(5)
    end

    it "respects a custom limit" do
      %w[aello hbllo heclo].each { |t| create(:conversation, title: t) }
      result = described_class.similar_titles("hello", limit: 2)
      expect(result.size).to eq(2)
    end

    it "orders by edit distance — closer match comes first" do
      # "helxo" vs "hello": differ at pos 4 (x≠l) → distance 1
      # "helox" vs "hello": two-position shift (l,o → o,x) → distance 2
      closer  = create(:conversation, title: "helxo")
      farther = create(:conversation, title: "helox")
      result  = described_class.similar_titles("hello")
      expect(result).to eq([ closer, farther ])
    end

    it "breaks distance ties by recency — most-recently-active first" do
      # Both titles are 1 edit from "hello" (h→a and h→z respectively)
      older  = create(:conversation, title: "aello", created_at: 5.hours.ago)
      recent = create(:conversation, title: "zello", created_at: 1.hour.ago)
      result = described_class.similar_titles("hello")
      expect(result.first).to eq(recent)
      expect(result.last).to  eq(older)
    end
  end

  describe "#deleting? + .deleting (async-delete in-flight state)" do
    it "deleting? is true when deleting_at is set, false otherwise" do
      expect(create(:conversation, deleting_at: Time.current)).to be_deleting
      expect(create(:conversation)).not_to be_deleting
    end

    it ".deleting returns only conversations with an in-flight delete" do
      d = create(:conversation, deleting_at: Time.current)
      create(:conversation)
      expect(described_class.deleting).to contain_exactly(d)
    end
  end
end
