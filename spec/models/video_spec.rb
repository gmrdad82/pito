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

  # D2 (docs/claude/2.2.0.md): private = privacy_status private AND NOT
  # scheduled (publish_at NULL or past). A future-dated scheduled upload is
  # privacy-private on YouTube too but must be excluded — it belongs to the
  # `scheduled` filter/slate, never `private`.
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
