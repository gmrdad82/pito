# frozen_string_literal: true

require "rails_helper"

RSpec.describe Video, type: :model do
  subject(:video) { build(:video) }

  # ── Associations ─────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:channel).required }
    it { is_expected.to have_many(:video_game_links).dependent(:destroy) }
    it { is_expected.to have_many(:linked_games).through(:video_game_links).source(:game) }
  end

  # ── Validations ──────────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:youtube_video_id) }

    it "requires uniqueness of youtube_video_id" do
      create(:video, youtube_video_id: "dup_yt_id")
      dup = build(:video, youtube_video_id: "dup_yt_id")
      expect(dup).not_to be_valid
      expect(dup.errors[:youtube_video_id]).to be_present
    end
  end

  # ── Enum: privacy_status ─────────────────────────────────────────
  describe "enum :privacy_status" do
    it "defaults to private (0)" do
      v = Video.new
      expect(v.privacy_status).to eq("private")
    end

    it "defines private, public, unlisted" do
      expect(described_class.privacy_statuses.keys).to contain_exactly("private", "public", "unlisted")
    end

    it "stores public as integer 1 in the database" do
      v = create(:video, privacy_status: :public)
      raw = ActiveRecord::Base.connection.execute(
        "SELECT privacy_status FROM videos WHERE id = #{v.id}"
      ).first["privacy_status"]
      expect(raw).to eq(1)
    end

    it "defines prefix-scoped predicate #privacy_status_public?" do
      v = build(:video, privacy_status: :public)
      expect(v).to be_privacy_status_public
    end

    it "defines #privacy_status_private?" do
      v = build(:video, privacy_status: :private)
      expect(v).to be_privacy_status_private
    end

    it "defines #privacy_status_unlisted?" do
      v = build(:video, privacy_status: :unlisted)
      expect(v).to be_privacy_status_unlisted
    end

    it "transitions privacy_status between values" do
      v = create(:video, :private)
      v.update!(privacy_status: :public)
      expect(v.reload.privacy_status).to eq("public")
    end
  end

  # ── stat readers (Pito::Stats-backed) ────────────────────────────
  describe "stat readers" do
    let(:saved) { create(:video) }

    it "reads like_count / comment_count from Pito::Stats" do
      Pito::Stats.set(saved, :likes, 42)
      Pito::Stats.set(saved, :comments, 7)
      expect(saved.like_count).to eq(42)
      expect(saved.comment_count).to eq(7)
    end

    it "returns nil when a stat has no row" do
      expect(saved.like_count).to be_nil
      expect(saved.comment_count).to be_nil
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────
  describe ".scheduled" do
    it "includes a video whose publish_at is in the future" do
      future = create(:video, publish_at: 1.hour.from_now)
      expect(described_class.scheduled).to include(future)
    end

    it "excludes a video whose publish_at is in the past" do
      past = create(:video, publish_at: 1.hour.ago)
      expect(described_class.scheduled).not_to include(past)
    end

    it "excludes a video whose publish_at is nil" do
      no_date = create(:video, publish_at: nil)
      expect(described_class.scheduled).not_to include(no_date)
    end
  end

  # D2 rule: private = privacy_status private AND NOT scheduled (publish_at
  # NULL or past). A future-dated scheduled upload is privacy-private on
  # YouTube too but must be excluded — it belongs to the `scheduled`
  # filter/slate, never `private`.
  describe ".private_unscheduled" do
    it "excludes a private video with a future publish_at (scheduled)" do
      scheduled = create(:video, :scheduled)
      expect(described_class.private_unscheduled).not_to include(scheduled)
    end

    it "includes a private video with a past publish_at" do
      past_private = create(:video, :private, publish_at: 1.hour.ago)
      expect(described_class.private_unscheduled).to include(past_private)
    end

    it "includes a private video with a NULL publish_at" do
      nil_private = create(:video, :private, publish_at: nil)
      expect(described_class.private_unscheduled).to include(nil_private)
    end

    it "excludes a public video" do
      public_vid = create(:video, :public)
      expect(described_class.private_unscheduled).not_to include(public_vid)
    end

    it "excludes an unlisted video" do
      unlisted_vid = create(:video, :unlisted)
      expect(described_class.private_unscheduled).not_to include(unlisted_vid)
    end
  end

  # ── publish_spacing_within_channel (:schedule context, WP2) ───────
  # 60-min ROLLING per-channel spacing between scheduled publishes. Only the
  # chat `schedule` tool's stage-time dry-run and confirm-time save opt into
  # the :schedule validation context — see Video#publish_spacing_within_channel.
  describe "publish_spacing_within_channel (:schedule context)" do
    let!(:spacing_channel) { create(:channel) }
    let!(:other_channel)   { create(:channel) }

    it "default context (plain save): a colliding publish_at is VALID — the validation never runs" do
      create(:video, channel: spacing_channel, publish_at: 10.days.from_now)
      colliding = build(:video, channel: spacing_channel, publish_at: 10.days.from_now + 10.minutes)
      expect(colliding).to be_valid
      expect { colliding.save! }.not_to raise_error
    end

    it ":schedule context: invalid when within 60 minutes of another scheduled video on the SAME channel" do
      create(:video, channel: spacing_channel, title: "First Video", publish_at: 10.days.from_now)
      colliding = build(:video, channel: spacing_channel, publish_at: 10.days.from_now + 30.minutes)
      expect(colliding.valid?(:schedule)).to be false
      expect(colliding.errors[:publish_at]).to be_present
    end

    it ":schedule context: valid at exactly 60 minutes away (the boundary is allowed, not caught by the range)" do
      anchor = 10.days.from_now
      create(:video, channel: spacing_channel, publish_at: anchor)
      exactly_60 = build(:video, channel: spacing_channel, publish_at: anchor + 60.minutes)
      expect(exactly_60.valid?(:schedule)).to be true
    end

    it ":schedule context: a colliding time on a DIFFERENT channel is valid (spacing is per-channel)" do
      create(:video, channel: other_channel, publish_at: 10.days.from_now)
      cross_channel = build(:video, channel: spacing_channel, publish_at: 10.days.from_now + 10.minutes)
      expect(cross_channel.valid?(:schedule)).to be true
    end

    it ":schedule context: a video with a PAST publish_at never counts as a collision, even within the window" do
      # Video.scheduled excludes publish_at <= Time.current, so a past publish
      # is never a candidate — even though the gap here is well under 60 min.
      create(:video, channel: spacing_channel, publish_at: 5.minutes.ago)
      candidate = build(:video, channel: spacing_channel, publish_at: 10.minutes.from_now)
      expect(candidate.valid?(:schedule)).to be true
    end

    it ":schedule context: self-excluded — a persisted video does not collide with its own publish_at" do
      video = create(:video, channel: spacing_channel, publish_at: 10.days.from_now)
      expect(video.valid?(:schedule)).to be true
    end
  end

  # ── #publish_spacing_collision ─────────────────────────────────────
  describe "#publish_spacing_collision" do
    let!(:pc_channel) { create(:channel) }

    it "returns the colliding video when one exists within the window" do
      other = create(:video, channel: pc_channel, title: "Anchor Video", publish_at: 10.days.from_now)
      candidate = build(:video, channel: pc_channel, publish_at: other.publish_at + 15.minutes)
      expect(candidate.publish_spacing_collision).to eq(other)
    end

    it "returns nil when there is no collision" do
      candidate = build(:video, channel: pc_channel, publish_at: 10.days.from_now)
      expect(candidate.publish_spacing_collision).to be_nil
    end

    it "returns nil when publish_at is blank" do
      candidate = build(:video, channel: pc_channel, publish_at: nil)
      expect(candidate.publish_spacing_collision).to be_nil
    end
  end

  # ── already_published? / publish_at_requires_never_published (:schedule
  # context) — root cause of the 2026-07-19 invalidPublishAt production
  # incident: YouTube's status.publishAt is settable only on a vid that is
  # private AND has never gone public. See Video#already_published?.
  describe "#already_published? and publish_at_requires_never_published (:schedule context)" do
    let!(:ap_channel) { create(:channel) }

    it "already_published? is true for a currently-public video (no pending change)" do
      video = create(:video, channel: ap_channel, privacy_status: :public)
      expect(video.already_published?).to be true
    end

    it "already_published? is false for a currently-private video (no pending change)" do
      video = create(:video, channel: ap_channel, privacy_status: :private)
      expect(video.already_published?).to be false
    end

    it "already_published? is false for a currently-unlisted video" do
      video = create(:video, channel: ap_channel, privacy_status: :unlisted)
      expect(video.already_published?).to be false
    end

    it "already_published? reads the PRE-assignment state via privacy_status_was, even after assign_attributes flips it to private" do
      video = create(:video, channel: ap_channel, privacy_status: :public)
      video.assign_attributes(privacy_status: :private, publish_at: 10.days.from_now)
      expect(video.privacy_status).to eq("private") # the assignment did happen
      expect(video.already_published?).to be true    # but it WAS public
    end

    it "default context (plain save): scheduling an already-public video is VALID — the validation never runs" do
      video = create(:video, channel: ap_channel, privacy_status: :public)
      video.assign_attributes(privacy_status: :private, publish_at: 10.days.from_now)
      expect(video).to be_valid
      expect { video.save! }.not_to raise_error
    end

    it ":schedule context: invalid when the video was already public before this assignment" do
      video = create(:video, channel: ap_channel, privacy_status: :public)
      video.assign_attributes(privacy_status: :private, publish_at: 10.days.from_now)
      expect(video.valid?(:schedule)).to be false
      expect(video.errors[:privacy_status]).to be_present
    end

    it ":schedule context: valid when the video was already private before this assignment (a re-schedule)" do
      video = create(:video, channel: ap_channel, privacy_status: :private, publish_at: 3.days.from_now)
      video.assign_attributes(privacy_status: :private, publish_at: 10.days.from_now)
      expect(video.valid?(:schedule)).to be true
    end

    it ":schedule context: valid when the video was already unlisted before this assignment" do
      video = create(:video, channel: ap_channel, privacy_status: :unlisted)
      video.assign_attributes(privacy_status: :private, publish_at: 10.days.from_now)
      expect(video.valid?(:schedule)).to be true
    end
  end

  # ── #thumbnail_variant_url ───────────────────────────────────────
  describe "#thumbnail_variant_url" do
    let(:saved) { create(:video) }

    it "returns nil when no thumbnail is attached" do
      expect(saved.thumbnail_variant_url).to be_nil
    end

    it "returns a host-less ActiveStorage proxy path when a thumbnail is attached" do
      saved.thumbnail.attach(
        io:           StringIO.new("fake-bytes"),
        filename:     "thumbnail-#{saved.id}.jpg",
        content_type: "image/jpeg"
      )
      url = saved.thumbnail_variant_url
      expect(url).to be_a(String)
      expect(url).to start_with("/rails/active_storage")
    end
  end

  # ── #category_name ───────────────────────────────────────────────
  describe "#category_name" do
    it "maps a known YouTube category id to its name" do
      expect(build(:video, category_id: "20").category_name).to eq("Gaming")
      expect(build(:video, category_id: "22").category_name).to eq("People & Blogs")
    end

    it "returns nil for an unknown or blank id" do
      expect(build(:video, category_id: "99999").category_name).to be_nil
      expect(build(:video, category_id: nil).category_name).to be_nil
    end
  end

  describe ".picker_page" do
    it "pages by PICKER_PAGE_SIZE, case-stable, zero overlap, exact continuity" do
      stub_const("Video::PICKER_PAGE_SIZE", 3)
      %w[apple Banana cherry Delta echo].each { |t| create(:video, title: t) }

      p1, c1 = Video.picker_page
      expect(p1.size).to eq(3)
      expect(c1).to be_present

      p2, c2 = Video.picker_page(after: c1)
      expect(p2.size).to eq(2)
      expect(c2).to be_nil

      expect((p1 + p2).map(&:title).map(&:downcase))
        .to eq(%w[apple banana cherry delta echo])
      expect((p1.map(&:id) & p2.map(&:id))).to be_empty
    end

    it "treats a malformed cursor as the first page" do
      create(:video, title: "Solo")
      rows, = Video.picker_page(after: "garbage!!")
      expect(rows).not_to be_empty
    end
  end
end
