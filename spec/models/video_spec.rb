require "rails_helper"

# Phase 12 — video schema expansion + edit surface + pre-publish checklist.
# Covers the full Data API v3 writable subset, the four-item pre-publish
# checklist, the Project ↔ Video direct nullable link, and the sync-back
# enqueue gating.
RSpec.describe Video, type: :model do
  subject { build(:video) }

  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to belong_to(:project).optional }
    it { is_expected.to have_many(:video_stats).dependent(:destroy) }
    it { is_expected.to have_many(:playlist_videos).dependent(:destroy) }
    it { is_expected.to have_many(:playlists).through(:playlist_videos) }
    it { is_expected.to have_one(:channel_youtube_connection).through(:channel) }

    # Phase 14 §3 — game / bundle attribution.
    it { is_expected.to have_many(:video_game_links).dependent(:destroy) }
    it { is_expected.to have_many(:linked_games).through(:video_game_links).source(:game) }
    it { is_expected.to have_many(:linked_bundles).through(:video_game_links).source(:bundle) }
  end

  # Phase 14 §3 — scoped query helpers (additive on the video model).
  describe "linked_to_game / linked_to_bundle scopes" do
    let(:channel) { create(:channel) }
    let(:game)    { create(:game) }
    let(:bundle)  { create(:bundle) }

    it "linked_to_game returns videos linked to the game" do
      v1 = create(:video, channel: channel)
      _v2 = create(:video, channel: channel)
      create(:video_game_link, video: v1, game: game)
      expect(Video.linked_to_game(game)).to contain_exactly(v1)
    end

    it "linked_to_bundle returns videos linked to the bundle" do
      v1 = create(:video, channel: channel)
      _v2 = create(:video, channel: channel)
      create(:video_game_link, :bundle, video: v1, bundle: bundle)
      expect(Video.linked_to_bundle(bundle)).to contain_exactly(v1)
    end
  end

  describe "youtube_video_id" do
    it { is_expected.to validate_presence_of(:youtube_video_id) }

    # Q12 lock — uniqueness is case-sensitive (URLs Abc / abc are
    # different videos on YouTube).
    it "validates uniqueness case-sensitively" do
      existing = create(:video, youtube_video_id: "abcDEF1234")
      duplicate = build(:video, channel: existing.channel, youtube_video_id: "abcDEF1234")
      expect(duplicate).not_to be_valid

      different_case = build(:video, channel: existing.channel, youtube_video_id: "ABCdef1234")
      expect(different_case).to be_valid
    end
  end

  describe "title validations" do
    it "allows up to 100 chars" do
      v = build(:video, title: "a" * 100)
      expect(v).to be_valid
    end

    it "rejects 101 chars" do
      v = build(:video, title: "a" * 101)
      expect(v).not_to be_valid
      expect(v.errors[:title]).to include(/too long/)
    end

    it "rejects `<` character" do
      v = build(:video, title: "hello < world")
      expect(v).not_to be_valid
      expect(v.errors[:title]).to include(/cannot contain/)
    end

    it "rejects `>` character" do
      v = build(:video, title: "hello > world")
      expect(v).not_to be_valid
    end

    it "allows unicode (emoji)" do
      v = build(:video, title: "hello \u{1F600}")
      expect(v).to be_valid
    end

    it "allows blank title for a draft (private + no publish_at)" do
      v = build(:video, title: "", privacy_status: :private, publish_at: nil)
      expect(v).to be_valid
    end

    it "requires title when transitioning to public" do
      v = create(:video, title: "set", privacy_status: :private)
      v.title = ""
      v.privacy_status = :public
      expect(v).not_to be_valid
      expect(v.errors[:title]).to be_present
    end

    it "requires title when transitioning to unlisted" do
      v = create(:video, title: "set", privacy_status: :private)
      v.title = ""
      v.privacy_status = :unlisted
      expect(v).not_to be_valid
    end
  end

  describe "description validations" do
    it "rejects descriptions over 5000 bytes (UTF-8 multibyte)" do
      v = build(:video, description: "\u{1F600}" * 1500) # 4 bytes each = 6000 bytes
      expect(v).not_to be_valid
      expect(v.errors[:description]).to include(/too long/)
    end

    it "allows exactly 5000 bytes" do
      v = build(:video, description: "a" * 5000)
      expect(v).to be_valid
    end

    it "rejects `<`" do
      v = build(:video, description: "hello < world")
      expect(v).not_to be_valid
    end

    it "rejects `>`" do
      v = build(:video, description: "hello > world")
      expect(v).not_to be_valid
    end

    it "allows blank" do
      v = build(:video, description: nil)
      expect(v).to be_valid
    end
  end

  describe "tags validations" do
    it "allows empty array" do
      v = build(:video, tags: [])
      expect(v).to be_valid
    end

    it "allows single tag" do
      v = build(:video, tags: [ "gaming" ])
      expect(v).to be_valid
    end

    it "allows multiple tags" do
      v = build(:video, tags: [ "gaming", "speedrun", "halo" ])
      expect(v).to be_valid
    end

    it "allows total API length of exactly 500" do
      tags = Array.new(50) { "a" * 8 } # 50 * 8 = 400 + 49 commas = 449
      tags << "b" * 50 # 449 + 1 comma + 50 = 500
      v = build(:video, tags: tags)
      expect(v).to be_valid
    end

    it "rejects total API length of 501" do
      v = build(:video, tags: [ "a" * 501 ])
      expect(v).not_to be_valid
      expect(v.errors[:tags]).to include(/too long/)
    end

    it "counts a tag with a space as +2 (quotes)" do
      v = build(:video, tags: [ "hello world" ]) # 11 + 2 = 13
      expect(v).to be_valid
    end

    it "rejects non-string elements" do
      v = build(:video, tags: [ "ok", 42 ])
      expect(v).not_to be_valid
      expect(v.errors[:tags]).to include(/array of strings/)
    end
  end

  describe "category_id validations" do
    it "allows nil for drafts" do
      v = build(:video, category_id: nil, privacy_status: :private)
      expect(v).to be_valid
    end

    it "rejects non-numeric `abc`" do
      v = build(:video, category_id: "abc")
      expect(v).not_to be_valid
    end

    it "rejects `12.5`" do
      v = build(:video, category_id: "12.5")
      expect(v).not_to be_valid
    end

    it "allows `20` (Gaming)" do
      v = build(:video, category_id: "20")
      expect(v).to be_valid
    end

    it "requires category_id on transition to public" do
      v = create(:video, category_id: nil, privacy_status: :private, title: "set")
      v.privacy_status = :public
      expect(v).not_to be_valid
      expect(v.errors[:category_id]).to include(/required when publishing/)
    end

    it "requires category_id on transition to unlisted" do
      v = create(:video, category_id: nil, privacy_status: :private, title: "set")
      v.privacy_status = :unlisted
      expect(v).not_to be_valid
    end

    it "requires category_id when scheduling" do
      v = create(:video, category_id: nil, privacy_status: :private)
      v.publish_at = 1.day.from_now
      expect(v).not_to be_valid
    end
  end

  describe "publish_at validations" do
    it "allows nil" do
      v = build(:video, publish_at: nil)
      expect(v).to be_valid
    end

    it "allows future timestamp" do
      v = build(:video, publish_at: 1.day.from_now, privacy_status: :private)
      expect(v).to be_valid
    end

    it "rejects past timestamp when private" do
      v = build(:video, privacy_status: :private)
      v.publish_at = 1.day.ago
      expect(v).not_to be_valid
      expect(v.errors[:publish_at]).to include(/must be in the future/)
    end

    it "rejects when privacy_status is public" do
      v = build(:video, privacy_status: :public, publish_at: 1.day.from_now,
                        published_at: 1.day.ago)
      expect(v).not_to be_valid
      expect(v.errors[:publish_at]).to include(/can only be set when privacy_status is private/)
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:privacy_status).with_values(private: 0, public: 1, unlisted: 2).with_prefix(:privacy) }

    it "exposes the privacy_private?/privacy_public?/privacy_unlisted? predicates" do
      v = build(:video)
      expect(v.privacy_private?).to be(true)
      v.privacy_status = :public
      expect(v.privacy_public?).to be(true)
    end
  end

  describe "scopes" do
    let!(:starred)  { create(:video, :starred) }
    let!(:public_v) { create(:video, :public) }
    let!(:unlisted) { create(:video, :unlisted) }
    let!(:private_draft) { create(:video, privacy_status: :private, publish_at: nil) }
    let!(:scheduled)  { create(:video, :scheduled) }
    let!(:complete)   { create(:video, :pre_publish_complete) }

    it ".starred" do
      expect(Video.starred).to contain_exactly(starred)
    end

    it ".published returns public + unlisted" do
      expect(Video.published).to include(public_v, unlisted)
      expect(Video.published).not_to include(private_draft, scheduled)
    end

    it ".draft returns private with no publish_at" do
      expect(Video.draft).to include(private_draft, starred, complete)
      expect(Video.draft).not_to include(scheduled)
    end

    it ".scheduled returns private with future publish_at" do
      expect(Video.scheduled).to contain_exactly(scheduled)
    end

    it ".pre_publish_complete returns rows with all four booleans + checked_at" do
      expect(Video.pre_publish_complete).to contain_exactly(complete)
    end
  end

  describe "#pre_publish_complete?" do
    it "returns true when all four + timestamp" do
      v = build(:video, :pre_publish_complete)
      expect(v.pre_publish_complete?).to be(true)
    end

    it "returns false when any boolean is false" do
      v = build(:video, :pre_publish_complete, pre_publish_age_ok: false)
      expect(v.pre_publish_complete?).to be(false)
    end

    it "returns false when timestamp is nil" do
      v = build(:video, :pre_publish_complete, pre_publish_checked_at: nil)
      expect(v.pre_publish_complete?).to be(false)
    end
  end

  describe "#studio_url" do
    it "returns the YouTube Studio deep link" do
      v = build(:video, youtube_video_id: "dQw4w9WgXcQ")
      expect(v.studio_url).to eq("https://studio.youtube.com/video/dQw4w9WgXcQ/edit")
    end
  end

  describe "#imported?" do
    it "true when checked_at nil + privacy_public" do
      v = build(:video, :public, pre_publish_checked_at: nil)
      expect(v.imported?).to be(true)
    end

    it "true when checked_at nil + privacy_unlisted" do
      v = build(:video, :unlisted, pre_publish_checked_at: nil)
      expect(v.imported?).to be(true)
    end

    it "false when checked_at nil + privacy_private" do
      v = build(:video, privacy_status: :private)
      expect(v.imported?).to be(false)
    end

    it "false when checked_at present + privacy_public" do
      v = build(:video, :public, pre_publish_checked_at: Time.current)
      expect(v.imported?).to be(false)
    end
  end

  describe "after_update_commit :enqueue_sync_back" do
    let!(:video) { create(:video, title: "old") }

    before { VideoSyncBack.jobs.clear }

    it "fires when title changes" do
      expect { video.update!(title: "new") }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "fires when description changes" do
      expect { video.update!(description: "new") }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "fires when tags change" do
      expect { video.update!(tags: [ "new" ]) }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "fires when category_id changes" do
      expect { video.update!(category_id: "21") }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "fires when privacy_status changes (with required fields)" do
      complete = create(:video, :pre_publish_complete, title: "ok", category_id: "20")
      VideoSyncBack.jobs.clear
      expect { complete.update!(privacy_status: :public) }
        .to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "fires when publish_at changes" do
      expect { video.update!(publish_at: 1.day.from_now) }
        .to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "fires when self_declared_made_for_kids changes" do
      expect { video.update!(self_declared_made_for_kids: true) }
        .to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "fires when contains_synthetic_media changes" do
      expect { video.update!(contains_synthetic_media: true) }
        .to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "does NOT fire when last_synced_at changes" do
      expect { video.update_columns(last_synced_at: Time.current) }
        .not_to change(VideoSyncBack.jobs, :size)
    end

    it "does NOT fire when etag changes via update_columns" do
      expect { video.update_columns(etag: "new") }
        .not_to change(VideoSyncBack.jobs, :size)
    end

    it "does NOT fire when made_for_kids_effective changes via update_columns" do
      expect { video.update_columns(made_for_kids_effective: true) }
        .not_to change(VideoSyncBack.jobs, :size)
    end

    it "does NOT fire when only pre_publish booleans change (no writable field)" do
      expect { video.update!(pre_publish_game_ok: true) }
        .not_to change(VideoSyncBack.jobs, :size)
    end
  end
end
