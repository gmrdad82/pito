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

  # ─────────────────────────────────────────────────────────────────
  # Phase 23 §23a — Video Sync with Diff Dialog.
  # ─────────────────────────────────────────────────────────────────
  describe "Phase 23 — diff associations" do
    it { is_expected.to have_many(:video_change_logs).dependent(:delete_all) }
    it { is_expected.to have_many(:video_diffs).dependent(:destroy) }

    it "exposes the single open diff via has_one :open_diff" do
      video = create(:video)
      open_diff = create(:video_diff, video: video)
      _resolved = create(:video_diff, video: video, resolved_at: 1.day.ago,
                                       resolution_payload: { "title" => "youtube" })

      expect(video.reload.open_diff).to eq(open_diff)
    end

    it "returns nil from open_diff when none is open" do
      video = create(:video)
      expect(video.open_diff).to be_nil
    end
  end

  describe "Phase 23 — display-only counter validations" do
    it "rejects a negative view_count" do
      video = build(:video, view_count: -1)
      expect(video).not_to be_valid
      expect(video.errors[:view_count]).to be_present
    end

    it "accepts a large view_count" do
      video = build(:video, view_count: 12_345_678)
      expect(video).to be_valid
    end

    it "rejects a non-http thumbnail_url" do
      video = build(:video, thumbnail_url: "not a url")
      expect(video).not_to be_valid
      expect(video.errors[:thumbnail_url]).to be_present
    end

    it "accepts an https thumbnail_url" do
      video = build(:video, thumbnail_url: "https://i.ytimg.com/vi/abc/maxres.jpg")
      expect(video).to be_valid
    end

    it "rejects a negative duration_seconds" do
      video = build(:video, duration_seconds: -10)
      expect(video).not_to be_valid
    end
  end

  describe "Phase 23 — title_locked? helpers (Q1 inert)" do
    it "always returns false for title_locked? — videos have no 14-day cooldown" do
      video = build(:video, title_changed_at: 1.hour.ago)
      expect(video.title_locked?).to be(false)
    end

    it "returns nil for title_unlock_at" do
      video = build(:video, title_changed_at: 1.hour.ago)
      expect(video.title_unlock_at).to be_nil
    end
  end

  # Phase 11 §01a — Video edit page polish.
  describe "Phase 11 §01a — thumbnail / chapters / end-screens" do
    describe "associations" do
      it { is_expected.to have_many(:video_chapters).dependent(:destroy) }
      it { is_expected.to have_many(:video_end_screens).dependent(:destroy) }
    end

    describe "thumbnail attachment" do
      it "is not attached on a fresh video" do
        video = create(:video)
        expect(video.thumbnail).not_to be_attached
      end

      it "attaches a valid PNG" do
        video = create(:video, :with_thumbnail)
        expect(video.thumbnail).to be_attached
        expect(video).to be_valid
      end

      it "rejects non-PNG / non-JPEG content types" do
        video = create(:video)
        video.thumbnail.attach(
          io: StringIO.new("this is a text file"),
          filename: "thumb.txt",
          content_type: "text/plain"
        )
        expect(video).not_to be_valid
        expect(video.errors[:thumbnail]).to include(/PNG or JPEG/)
      end

      it "rejects files larger than 2 MB" do
        video = create(:video)
        big = "x" * (Video::THUMBNAIL_MAX_BYTES + 1)
        video.thumbnail.attach(
          io: StringIO.new(big),
          filename: "huge.png",
          content_type: "image/png"
        )
        expect(video).not_to be_valid
        expect(video.errors[:thumbnail]).to include(/too large/)
      end

      it "exposes a preview variant when attached" do
        video = create(:video, :with_thumbnail)
        expect(video.thumbnail_preview).not_to be_nil
      end

      it "thumbnail_preview returns nil when not attached" do
        video = create(:video)
        expect(video.thumbnail_preview).to be_nil
      end
    end

    describe "nested-attributes — video_chapters" do
      it "accepts a chapter nested-attributes payload" do
        video = create(:video)
        video.update!(video_chapters_attributes: [
          { start_seconds: 0, label: "intro" },
          { start_seconds: 120, label: "setup" }
        ])
        expect(video.video_chapters.ordered.pluck(:label)).to eq([ "intro", "setup" ])
      end

      it "destroys a chapter when _destroy is set" do
        video = create(:video)
        chapter = create(:video_chapter, video: video, start_seconds: 0, label: "intro")
        video.update!(video_chapters_attributes: [
          { id: chapter.id, _destroy: "1" }
        ])
        expect(video.video_chapters.count).to eq(0)
      end

      it "rejects an all-blank chapter row (reject_if: :all_blank)" do
        video = create(:video)
        expect {
          video.update!(video_chapters_attributes: [
            { start_seconds: "", label: "" }
          ])
        }.not_to change { video.video_chapters.count }
      end

      it "surfaces a duplicate start_seconds error on save" do
        video = create(:video)
        create(:video_chapter, video: video, start_seconds: 0, label: "intro")
        video.video_chapters_attributes = [
          { start_seconds: 0, label: "duplicate" }
        ]
        expect(video.save).to be(false)
        nested_errs = video.video_chapters.flat_map { |c| c.errors[:start_seconds] }
        expect(nested_errs).to include(/unique/)
      end
    end

    describe "nested-attributes — video_end_screens" do
      it "accepts an end-screen nested-attributes payload" do
        video = create(:video)
        video.update!(video_end_screens_attributes: [
          { kind: "related_video", target_id: "yt_abc", target_label: "watch next", position: 0 }
        ])
        expect(video.video_end_screens.count).to eq(1)
        expect(video.video_end_screens.first.kind_related_video?).to be(true)
      end

      it "destroys an end-screen when _destroy is set" do
        video = create(:video)
        es = create(:video_end_screen, video: video, kind: :related_video, target_id: "yt_a")
        video.update!(video_end_screens_attributes: [
          { id: es.id, _destroy: "1" }
        ])
        expect(video.video_end_screens.count).to eq(0)
      end

      it "rejects 5 simultaneous non-none rows on save" do
        video = create(:video)
        rows = (0..4).map do |i|
          { kind: "related_video", target_id: "yt_#{i}", target_label: "l#{i}", position: i }
        end
        video.video_end_screens_attributes = rows
        expect(video.save).to be(false)
      end

      it "rejects mixing a none row with a non-none row" do
        video = create(:video)
        video.video_end_screens_attributes = [
          { kind: "none", position: 0 },
          { kind: "related_video", target_id: "yt_a", target_label: "x", position: 1 }
        ]
        expect(video.save).to be(false)
      end
    end
  end
end
