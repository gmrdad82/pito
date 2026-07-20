# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Confirmation::Executor, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:connection) { create(:youtube_connection) }
  let!(:channel)   { create(:channel, handle: "@pito", youtube_connection: connection) }
  let!(:video1)    { create(:video, channel:) }
  let!(:video2)    { create(:video, channel:) }

  let(:payload) do
    { "command" => "disconnect", "channel_id" => channel.id }
  end

  # ── confirm / disconnect ──────────────────────────────────────────────────

  describe ".confirm — disconnect" do
    it "destroys the channel" do
      expect { described_class.confirm("disconnect", payload) }
        .to change(Channel, :count).by(-1)
    end

    it "destroys all videos via cascade" do
      expect { described_class.confirm("disconnect", payload) }
        .to change(Video, :count).by(-2)
    end

    it "destroys the YoutubeConnection when it was the last channel" do
      expect { described_class.confirm("disconnect", payload) }
        .to change(YoutubeConnection, :count).by(-1)
    end

    it "keeps the YoutubeConnection when other channels remain" do
      create(:channel, youtube_connection: connection)
      expect { described_class.confirm("disconnect", payload) }
        .not_to change(YoutubeConnection, :count)
    end

    it "returns outcome_text mentioning the handle and video count" do
      text = described_class.confirm("disconnect", payload)
      expect(text).to include("@pito")
      expect(text).to include("2")
    end

    it "appends a themed ascii-art <pre> block to the outcome" do
      text = described_class.confirm("disconnect", payload)
      expect(text).to include("<pre>")
      expect(text).to include("</pre>")
    end

    context "when the channel is already gone" do
      before { channel.destroy! }

      it "does not raise" do
        expect { described_class.confirm("disconnect", payload) }.not_to raise_error
      end

      it "returns the already_gone message" do
        text = described_class.confirm("disconnect", payload)
        expect(text).to be_present
      end
    end
  end

  # ── cancel / disconnect ───────────────────────────────────────────────────

  describe ".cancel — disconnect" do
    it "does NOT destroy the channel" do
      expect { described_class.cancel("disconnect", payload) }
        .not_to change(Channel, :count)
    end

    it "returns outcome_text mentioning the channel handle" do
      text = described_class.cancel("disconnect", payload)
      expect(text).to include("@pito")
    end
  end

  # ── unknown command fallbacks ─────────────────────────────────────────────

  describe ".confirm — unknown command" do
    it "returns the default confirmed text" do
      text = described_class.confirm("unknown_cmd", {})
      expect(text).to be_present
    end
  end

  describe ".cancel — unknown command" do
    it "returns the default cancelled text" do
      text = described_class.cancel("unknown_cmd", {})
      expect(text).to be_present
    end
  end

  describe ".confirm — game_delete" do
    it "destroys the game and returns outcome text with the title" do
      game = create(:game, title: "Lies of P")
      text = nil
      expect {
        text = described_class.confirm("game_delete", { "game_id" => game.id, "game_title" => "Lies of P" })
      }.to change(Game, :count).by(-1)
      expect(text).to include("Lies of P")
    end

    it "is a no-op (still returns text) when the game is already gone" do
      text = described_class.confirm("game_delete", { "game_id" => 0, "game_title" => "Gone" })
      expect(text).to include("Gone")
    end
  end

  # ── confirm / video_delete ───────────────────────────────────────────────

  describe ".confirm — video_delete" do
    let(:del_connection) { create(:youtube_connection) }
    let!(:v_channel)     { create(:channel, youtube_connection: del_connection) }
    let!(:video)         { create(:video, channel: v_channel, title: "My Let's Play") }

    before { allow(VideoRemoteDelete).to receive(:perform_later) }

    it "destroys the video and returns outcome text with the title" do
      text = nil
      expect {
        text = described_class.confirm("video_delete", { "video_id" => video.id, "video_title" => "My Let's Play" })
      }.to change(Video, :count).by(-1)
      expect(text).to include("My Let's Play")
    end

    it "enqueues VideoRemoteDelete with the youtube id and connection id" do
      yt_id   = video.youtube_video_id
      conn_id = del_connection.id
      described_class.confirm("video_delete", { "video_id" => video.id, "video_title" => "My Let's Play" })
      expect(VideoRemoteDelete).to have_received(:perform_later).with(yt_id, conn_id)
    end

    it "is a no-op (still returns text) when the video is already gone" do
      text = described_class.confirm("video_delete", { "video_id" => 0, "video_title" => "Vanished" })
      expect(text).to include("Vanished")
      expect(VideoRemoteDelete).not_to have_received(:perform_later)
    end

    it "does NOT enqueue VideoRemoteDelete when the channel has no connection" do
      no_conn_video = create(:video, channel: create(:channel, :orphan), title: "Orphan Clip")
      described_class.confirm("video_delete", { "video_id" => no_conn_video.id, "video_title" => "Orphan Clip" })
      expect(VideoRemoteDelete).not_to have_received(:perform_later)
    end
  end

  # ── cancel / video_delete ───────────────────────────────────────────────

  describe ".cancel — video_delete" do
    let!(:v_channel) { create(:channel) }
    let!(:video)     { create(:video, channel: v_channel, title: "Cancelled Video") }

    it "does NOT destroy the video" do
      expect {
        described_class.cancel("video_delete", { "video_id" => video.id, "video_title" => "Cancelled Video" })
      }.not_to change(Video, :count)
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("video_delete", { "video_id" => video.id, "video_title" => "Cancelled Video" })
      expect(text).to be_present
    end
  end

  # ── confirm / game_reindex ────────────────────────────────────────────────

  describe ".confirm — game_reindex" do
    let!(:game) { create(:game, title: "Bloodborne") }

    it "calls Game::EmbeddingIndexer with force: true and returns outcome text" do
      allow(::Game::EmbeddingIndexer).to receive(:call)
      text = described_class.confirm("game_reindex", { "game_id" => game.id, "game_title" => "Bloodborne" })
      expect(::Game::EmbeddingIndexer).to have_received(:call).with(game, force: true)
      expect(text).to include("Bloodborne")
    end

    it "returns a not-found text when the game does not exist" do
      text = described_class.confirm("game_reindex", { "game_id" => 0, "game_title" => "Vanished" })
      expect(text).to be_present
    end
  end

  # ── cancel / game_delete ──────────────────────────────────────────────────

  describe ".cancel — game_delete" do
    let!(:game) { create(:game, title: "Cancelled Game") }

    it "does NOT destroy the game" do
      expect {
        described_class.cancel("game_delete", { "game_id" => game.id, "game_title" => "Cancelled Game" })
      }.not_to change(Game, :count)
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("game_delete", { "game_id" => game.id, "game_title" => "Cancelled Game" })
      expect(text).to be_present
    end
  end

  # ── cancel / game_reindex ─────────────────────────────────────────────────

  describe ".cancel — game_reindex" do
    let!(:game) { create(:game, title: "Reindex Target") }

    it "does NOT call Game::EmbeddingIndexer" do
      expect(::Game::EmbeddingIndexer).not_to receive(:call)
      described_class.cancel("game_reindex", { "game_id" => game.id, "game_title" => "Reindex Target" })
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("game_reindex", { "game_id" => game.id, "game_title" => "Reindex Target" })
      expect(text).to be_present
    end
  end

  # ── confirm / video_reindex ───────────────────────────────────────────────

  describe ".confirm — video_reindex" do
    let!(:v_channel) { create(:channel) }
    let!(:video)     { create(:video, channel: v_channel, title: "Let's Play Bloodborne") }

    it "calls Video::EmbeddingIndexer with force: true and returns outcome text" do
      allow(::Video::EmbeddingIndexer).to receive(:call)
      text = described_class.confirm("video_reindex", { "video_id" => video.id, "video_title" => "Let's Play Bloodborne" })
      expect(::Video::EmbeddingIndexer).to have_received(:call).with(video, force: true)
      expect(text).to include("Let's Play Bloodborne")
    end

    it "returns a not-found text when the video does not exist" do
      text = described_class.confirm("video_reindex", { "video_id" => 0, "video_title" => "Vanished Video" })
      expect(text).to be_present
    end
  end

  # ── cancel / video_reindex ────────────────────────────────────────────────

  describe ".cancel — video_reindex" do
    let!(:v_channel) { create(:channel) }
    let!(:video)     { create(:video, channel: v_channel, title: "Video Reindex Target") }

    it "does NOT call Video::EmbeddingIndexer" do
      expect(::Video::EmbeddingIndexer).not_to receive(:call)
      described_class.cancel("video_reindex", { "video_id" => video.id, "video_title" => "Video Reindex Target" })
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("video_reindex", { "video_id" => video.id, "video_title" => "Video Reindex Target" })
      expect(text).to be_present
    end
  end

  # ── confirm / video_publish ───────────────────────────────────────────────

  describe ".confirm — video_publish" do
    let!(:pub_channel) { create(:channel) }
    let!(:pub_video)   { create(:video, channel: pub_channel, title: "Speed Run Gold", privacy_status: :private, publish_at: 1.day.from_now) }

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "sets privacy_status to public" do
      described_class.confirm("video_publish", { "video_id" => pub_video.id, "video_title" => "Speed Run Gold" })
      expect(pub_video.reload.privacy_status).to eq("public")
    end

    it "clears publish_at" do
      described_class.confirm("video_publish", { "video_id" => pub_video.id, "video_title" => "Speed Run Gold" })
      expect(pub_video.reload.publish_at).to be_nil
    end

    it "enqueues VideoRemoteStatusSync" do
      described_class.confirm("video_publish", { "video_id" => pub_video.id, "video_title" => "Speed Run Gold" })
      expect(VideoRemoteStatusSync).to have_received(:perform_later).with(pub_video.id)
    end

    it "returns outcome text mentioning the title" do
      text = described_class.confirm("video_publish", { "video_id" => pub_video.id, "video_title" => "Speed Run Gold" })
      expect(text).to include("Speed Run Gold")
    end

    it "returns not_found text when the video is missing" do
      text = described_class.confirm("video_publish", { "video_id" => 0, "video_title" => "Ghost" })
      expect(text).to be_present
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end
  end

  # ── confirm / video_unlist ────────────────────────────────────────────────

  describe ".confirm — video_unlist" do
    let!(:ul_channel) { create(:channel) }
    let!(:ul_video)   { create(:video, channel: ul_channel, title: "Boss Fight Compilation", privacy_status: :public) }

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "sets privacy_status to unlisted" do
      described_class.confirm("video_unlist", { "video_id" => ul_video.id, "video_title" => "Boss Fight Compilation" })
      expect(ul_video.reload.privacy_status).to eq("unlisted")
    end

    it "clears a stale publish_at so YouTube won't reject the pair (invalidPublishAt)" do
      # A previously-scheduled vid is private + publish_at; unlisting must cancel
      # the schedule, else the write-through pushes unlisted + publish_at and
      # YouTube rejects it.
      ul_video.update!(privacy_status: :private, publish_at: 1.day.from_now)
      described_class.confirm("video_unlist", { "video_id" => ul_video.id, "video_title" => "Boss Fight Compilation" })
      expect(ul_video.reload.publish_at).to be_nil
    end

    it "enqueues VideoRemoteStatusSync" do
      described_class.confirm("video_unlist", { "video_id" => ul_video.id, "video_title" => "Boss Fight Compilation" })
      expect(VideoRemoteStatusSync).to have_received(:perform_later).with(ul_video.id)
    end

    it "returns outcome text mentioning the title" do
      text = described_class.confirm("video_unlist", { "video_id" => ul_video.id, "video_title" => "Boss Fight Compilation" })
      expect(text).to include("Boss Fight Compilation")
    end

    it "returns not_found text when the video is missing" do
      text = described_class.confirm("video_unlist", { "video_id" => 0, "video_title" => "Ghost" })
      expect(text).to be_present
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end
  end

  # ── confirm / video_metadata ──────────────────────────────────────────────

  describe ".confirm — video_metadata" do
    let!(:md_channel) { create(:channel) }
    let!(:md_video)   { create(:video, channel: md_channel, title: "Let's Play Elden Ring", description: "old desc", tags: [ "old" ]) }

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    context "field: description" do
      it "updates the video's description to the staged value" do
        described_class.confirm("video_metadata", {
          "video_id" => md_video.id, "video_title" => "Let's Play Elden Ring",
          "field" => "description", "staged_value" => "New words"
        })
        expect(md_video.reload.description).to eq("New words")
      end

      it "enqueues VideoRemoteStatusSync with fields: [description]" do
        described_class.confirm("video_metadata", {
          "video_id" => md_video.id, "video_title" => "Let's Play Elden Ring",
          "field" => "description", "staged_value" => "New words"
        })
        expect(VideoRemoteStatusSync).to have_received(:perform_later).with(md_video.id, fields: [ "description" ])
      end

      it "enqueues VideoEmbedIndexJob (description feeds Video::EmbedText)" do
        expect {
          described_class.confirm("video_metadata", {
            "video_id" => md_video.id, "video_title" => "Let's Play Elden Ring",
            "field" => "description", "staged_value" => "New words"
          })
        }.to have_enqueued_job(VideoEmbedIndexJob).with(md_video.id)
      end

      it "returns outcome text mentioning the title" do
        text = described_class.confirm("video_metadata", {
          "video_id" => md_video.id, "video_title" => "Let's Play Elden Ring",
          "field" => "description", "staged_value" => "New words"
        })
        expect(text).to include("Let's Play Elden Ring")
      end
    end

    context "field: tags" do
      it "updates the video's tags to the staged array" do
        described_class.confirm("video_metadata", {
          "video_id" => md_video.id, "video_title" => "Let's Play Elden Ring",
          "field" => "tags", "staged_value" => [ "a", "b" ]
        })
        expect(md_video.reload.tags).to eq([ "a", "b" ])
      end

      it "enqueues VideoRemoteStatusSync with fields: [tags]" do
        described_class.confirm("video_metadata", {
          "video_id" => md_video.id, "video_title" => "Let's Play Elden Ring",
          "field" => "tags", "staged_value" => [ "a", "b" ]
        })
        expect(VideoRemoteStatusSync).to have_received(:perform_later).with(md_video.id, fields: [ "tags" ])
      end

      it "enqueues VideoEmbedIndexJob (tags feed Video::EmbedText)" do
        expect {
          described_class.confirm("video_metadata", {
            "video_id" => md_video.id, "video_title" => "Let's Play Elden Ring",
            "field" => "tags", "staged_value" => [ "a", "b" ]
          })
        }.to have_enqueued_job(VideoEmbedIndexJob).with(md_video.id)
      end
    end

    it "returns not_found text and enqueues nothing when the video is missing" do
      text = nil
      expect {
        text = described_class.confirm("video_metadata", {
          "video_id" => 0, "video_title" => "Ghost",
          "field" => "description", "staged_value" => "New words"
        })
      }.not_to have_enqueued_job(VideoEmbedIndexJob)
      expect(text).to be_present
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end

    it "returns the generic confirmed copy, does NOT write, and enqueues nothing for a field outside the allowlist" do
      text = nil
      expect {
        text = described_class.confirm("video_metadata", {
          "video_id" => md_video.id, "video_title" => "Let's Play Elden Ring",
          "field" => "title", "staged_value" => "Sneaky New Title"
        })
      }.not_to have_enqueued_job(VideoEmbedIndexJob)
      expect(text).to be_present
      expect(md_video.reload.title).to eq("Let's Play Elden Ring")
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end
  end

  # ── confirm / video_metadata_mass (WP4) ───────────────────────────────────
  #
  # PER ROW, deliberately no transaction: a missing vid is a collected failure
  # that never stops the rows around it (unlike video_schedule_mass's
  # all-or-nothing rollback). Outcome text names updated + failed counts.

  describe ".confirm — video_metadata_mass" do
    let!(:mm_channel) { create(:channel) }
    let!(:mm_video1)  { create(:video, channel: mm_channel, title: "Episode One", tags: [ "old" ]) }
    let!(:mm_video2)  { create(:video, channel: mm_channel, title: "Episode Two", tags: [ "old" ]) }

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    def mm_payload(field, items)
      { "command" => "video_metadata_mass", "field" => field, "items" => items }
    end

    context "happy path — every item resolves" do
      let(:items) do
        [
          { "video_id" => mm_video1.id, "video_title" => "Episode One", "staged_value" => [ "a", "b" ] },
          { "video_id" => mm_video2.id, "video_title" => "Episode Two", "staged_value" => [ "c" ] }
        ]
      end

      it "updates tags on EVERY item" do
        described_class.confirm("video_metadata_mass", mm_payload("tags", items))
        expect(mm_video1.reload.tags).to eq([ "a", "b" ])
        expect(mm_video2.reload.tags).to eq([ "c" ])
      end

      it "enqueues VideoRemoteStatusSync with fields: [tags] per item" do
        described_class.confirm("video_metadata_mass", mm_payload("tags", items))
        expect(VideoRemoteStatusSync).to have_received(:perform_later).with(mm_video1.id, fields: [ "tags" ])
        expect(VideoRemoteStatusSync).to have_received(:perform_later).with(mm_video2.id, fields: [ "tags" ])
        expect(VideoRemoteStatusSync).to have_received(:perform_later).exactly(2).times
      end

      it "enqueues VideoEmbedIndexJob once per item" do
        expect { described_class.confirm("video_metadata_mass", mm_payload("tags", items)) }
          .to have_enqueued_job(VideoEmbedIndexJob).with(mm_video1.id)
          .and have_enqueued_job(VideoEmbedIndexJob).with(mm_video2.id)
      end

      it "returns outcome text mentioning the updated count, no failures" do
        text = described_class.confirm("video_metadata_mass", mm_payload("tags", items))
        expect(text).to include("2")
      end
    end

    context "partial failure — one item's vid vanished between staging and confirming" do
      let(:items) do
        [
          { "video_id" => mm_video1.id, "video_title" => "Episode One", "staged_value" => "new description" },
          { "video_id" => 0, "video_title" => "Ghost", "staged_value" => "new description" }
        ]
      end

      it "does not raise" do
        expect { described_class.confirm("video_metadata_mass", mm_payload("description", items)) }.not_to raise_error
      end

      it "updates the vid that DID resolve — the rest of the batch is NOT rolled back" do
        described_class.confirm("video_metadata_mass", mm_payload("description", items))
        expect(mm_video1.reload.description).to eq("new description")
      end

      it "enqueues exactly ONE VideoRemoteStatusSync (for the vid that resolved)" do
        described_class.confirm("video_metadata_mass", mm_payload("description", items))
        expect(VideoRemoteStatusSync).to have_received(:perform_later).with(mm_video1.id, fields: [ "description" ])
        expect(VideoRemoteStatusSync).to have_received(:perform_later).exactly(1).times
      end

      it "returns present outcome text naming both the update and the failure" do
        text = described_class.confirm("video_metadata_mass", mm_payload("description", items))
        expect(text).to be_present
        expect(text).to include("1")
      end
    end

    context "every item's vid vanished" do
      let(:items) do
        [
          { "video_id" => 0, "video_title" => "Ghost One", "staged_value" => "x" },
          { "video_id" => 0, "video_title" => "Ghost Two", "staged_value" => "y" }
        ]
      end

      it "does not raise and writes nothing" do
        expect { described_class.confirm("video_metadata_mass", mm_payload("description", items)) }.not_to raise_error
      end

      it "enqueues zero jobs" do
        described_class.confirm("video_metadata_mass", mm_payload("description", items))
        expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
      end
    end

    it "returns the generic confirmed copy, does NOT write, and enqueues nothing for a field outside the allowlist" do
      items = [ { "video_id" => mm_video1.id, "video_title" => "Episode One", "staged_value" => "Sneaky New Title" } ]
      text  = nil
      expect {
        text = described_class.confirm("video_metadata_mass", mm_payload("title", items))
      }.not_to have_enqueued_job(VideoEmbedIndexJob)
      expect(text).to be_present
      expect(mm_video1.reload.title).to eq("Episode One")
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end
  end

  # ── confirm / video_schedule ──────────────────────────────────────────────

  describe ".confirm — video_schedule" do
    let!(:sc_channel) { create(:channel) }
    # Private + never-published — the realistic pre-schedule state. YouTube's
    # own status.publishAt constraint (Video#already_published?) refuses a vid
    # that's ever gone public; that rejection gets its own dedicated describe
    # block below (the exact scenario this fixture used to silently model as
    # a success, before the 2026-07-19 invalidPublishAt fix).
    let!(:sc_video)   { create(:video, channel: sc_channel, title: "Dungeon Clear", privacy_status: :private, publish_at: nil) }
    let(:publish_at)  { 7.days.from_now.utc }

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "sets privacy_status to private" do
      described_class.confirm("video_schedule", {
        "video_id"    => sc_video.id,
        "video_title" => "Dungeon Clear",
        "publish_at"  => publish_at.iso8601
      })
      expect(sc_video.reload.privacy_status).to eq("private")
    end

    it "sets publish_at from the ISO8601 payload value" do
      described_class.confirm("video_schedule", {
        "video_id"    => sc_video.id,
        "video_title" => "Dungeon Clear",
        "publish_at"  => publish_at.iso8601
      })
      expect(sc_video.reload.publish_at).to be_within(1.second).of(publish_at)
    end

    it "enqueues VideoRemoteStatusSync" do
      described_class.confirm("video_schedule", {
        "video_id"    => sc_video.id,
        "video_title" => "Dungeon Clear",
        "publish_at"  => publish_at.iso8601
      })
      expect(VideoRemoteStatusSync).to have_received(:perform_later).with(sc_video.id)
    end

    it "returns outcome text mentioning the title" do
      text = described_class.confirm("video_schedule", {
        "video_id"    => sc_video.id,
        "video_title" => "Dungeon Clear",
        "publish_at"  => publish_at.iso8601
      })
      expect(text).to include("Dungeon Clear")
    end

    it "returns not_found text when the video is missing" do
      text = described_class.confirm("video_schedule", {
        "video_id"    => 0,
        "video_title" => "Ghost",
        "publish_at"  => publish_at.iso8601
      })
      expect(text).to be_present
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end

    it "renders the time in the house date format without a 'UTC' label" do
      travel_to(Time.zone.local(2026, 6, 1, 9, 0)) do
        text = described_class.confirm("video_schedule", {
          "video_id"    => sc_video.id,
          "video_title" => "Dungeon Clear",
          "publish_at"  => publish_at.iso8601
        })
        expect(text).not_to include("UTC")
        expect(text).to match(/\d{1,2} \w{3} \d{2}:\d{2}/)
      end
    end
  end

  # ── confirm / disconnect — zero-video case ────────────────────────────────

  describe ".confirm — disconnect with zero videos" do
    let(:empty_connection) { create(:youtube_connection) }
    let!(:empty_channel)   { create(:channel, handle: "@bare", youtube_connection: empty_connection) }

    it "returns text that covers the zero-video case (no crash, non-empty)" do
      text = described_class.confirm("disconnect", { "channel_id" => empty_channel.id })
      expect(text).to be_present
    end
  end

  # ── cancel / disconnect — blank-handle fallback ───────────────────────────

  describe ".cancel — disconnect with blank handle" do
    let(:bare_connection) { create(:youtube_connection) }
    let!(:bare_channel) do
      create(:channel, title: "No Handle Channel", youtube_connection: bare_connection).tap do |ch|
        ch.update_column(:handle, nil)
      end
    end

    it "falls back to a non-empty cancelled message" do
      text = described_class.cancel("disconnect", { "channel_id" => bare_channel.id })
      expect(text).to be_present
    end
  end

  # ── confirm / sync_videos ─────────────────────────────────────────────────

  describe ".confirm — sync_videos" do
    it "fans out one isolated SyncVideosJob per channel in scope" do
      allow(SyncVideosJob).to receive(:perform_later)
      ch1 = create(:channel, handle: "alpha")
      ch2 = create(:channel, handle: "beta")
      described_class.confirm("sync_videos", {
        "channel_ids" => [ ch1.id, ch2.id ], "scope_label" => "all channels"
      })
      expect(SyncVideosJob).to have_received(:perform_later).with([ ch1.id ], ch1.at_handle, conversation_id: nil)
      expect(SyncVideosJob).to have_received(:perform_later).with([ ch2.id ], ch2.at_handle, conversation_id: nil)
    end

    it "fans out to every connected channel when the scope is empty (@all)" do
      allow(SyncVideosJob).to receive(:perform_later)
      ch = create(:channel, :on_connection, handle: "gamma")
      described_class.confirm("sync_videos", { "channel_ids" => [], "scope_label" => "all channels" })
      expect(SyncVideosJob).to have_received(:perform_later).with([ ch.id ], ch.at_handle, conversation_id: nil)
    end

    it "passes through video_ids for a targeted refresh" do
      allow(SyncVideosJob).to receive(:perform_later)
      described_class.confirm("sync_videos", {
        "channel_ids" => [ 1 ], "scope_label" => "@pito", "video_ids" => [ 10, 11 ]
      })
      expect(SyncVideosJob).to have_received(:perform_later)
        .with([ 1 ], "@pito", conversation_id: nil, video_ids: [ 10, 11 ])
    end

    it "returns a present-tense queued ack (not a done/count string)" do
      allow(SyncVideosJob).to receive(:perform_later)
      text = described_class.confirm("sync_videos", { "channel_ids" => [], "scope_label" => "@test" })
      # Must be non-empty and must NOT contain a literal "?" count placeholder
      expect(text).to be_present
      expect(text).not_to include("?")
    end

    it "includes the scope in the queued ack" do
      allow(SyncVideosJob).to receive(:perform_later)
      text = described_class.confirm("sync_videos", { "channel_ids" => [], "scope_label" => "all channels" })
      expect(text).to include("all channels")
    end

    it "phrases a TARGETED (#id) queued ack as the ids, not '<ids> vids'" do
      allow(SyncVideosJob).to receive(:perform_later)
      text = described_class.confirm("sync_videos", {
        "channel_ids" => [], "scope_label" => "#25", "video_ids" => [ 25 ]
      })
      # Reads "Syncing #25 from YouTube…" — NOT the misleading "#25 vids".
      expect(text).to include("#25")
      expect(text).not_to include("#25 vids")
    end
  end

  # ── confirm / sync_channel ────────────────────────────────────────────────

  describe ".confirm — sync_channel" do
    it "fans out one isolated SyncChannelJob per channel" do
      allow(SyncChannelJob).to receive(:perform_later)
      ch = create(:channel, handle: "pito")
      described_class.confirm("sync_channel", {
        "channel_ids" => [ ch.id ], "scope_label" => "@pito"
      })
      expect(SyncChannelJob).to have_received(:perform_later).with([ ch.id ], ch.at_handle, conversation_id: nil)
    end

    it "returns non-empty outcome text" do
      allow(SyncChannelJob).to receive(:perform_later)
      text = described_class.confirm("sync_channel", { "channel_ids" => [], "scope_label" => "@pito" })
      expect(text).to be_present
    end
  end

  # ── confirm / sync_channel_videos ─────────────────────────────────────────

  describe ".confirm — sync_channel_videos" do
    it "fans out one isolated SyncChannelVideosJob per channel" do
      allow(SyncChannelVideosJob).to receive(:perform_later)
      ch = create(:channel, handle: "aurora")
      described_class.confirm("sync_channel_videos", {
        "channel_ids" => [ ch.id ], "scope_label" => "@aurora"
      })
      expect(SyncChannelVideosJob).to have_received(:perform_later).with([ ch.id ], ch.at_handle, conversation_id: nil)
    end

    it "returns non-empty outcome text" do
      allow(SyncChannelVideosJob).to receive(:perform_later)
      text = described_class.confirm("sync_channel_videos", { "channel_ids" => [], "scope_label" => "@all" })
      expect(text).to be_present
    end
  end

  # ── confirm / video_publish (edge: missing video_id key in payload) ────────

  describe ".confirm — video_publish (edge: missing video_id in payload)" do
    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "returns not_found text and does not enqueue VideoRemoteStatusSync" do
      text = described_class.confirm("video_publish", { "video_title" => "Ghost No ID" })
      expect(text).to be_present
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end
  end

  # ── confirm / video_publish (edge: already-public video is idempotent) ─────

  describe ".confirm — video_publish (edge: already-public video is idempotent)" do
    let!(:idm_channel) { create(:channel) }
    let!(:idm_video) do
      create(:video, channel: idm_channel, title: "Already Public",
                     privacy_status: :public, publish_at: nil)
    end

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "still sets privacy_status to public (no short-circuit)" do
      described_class.confirm("video_publish", { "video_id" => idm_video.id, "video_title" => "Already Public" })
      expect(idm_video.reload.privacy_status).to eq("public")
    end

    it "still enqueues VideoRemoteStatusSync (no short-circuit)" do
      described_class.confirm("video_publish", { "video_id" => idm_video.id, "video_title" => "Already Public" })
      expect(VideoRemoteStatusSync).to have_received(:perform_later).with(idm_video.id)
    end
  end

  # ── confirm / video_schedule (edge: already-private with existing publish_at)

  describe ".confirm — video_schedule (edge: already-private video with existing publish_at)" do
    let!(:rsc_channel)   { create(:channel) }
    let(:old_publish_at) { 3.days.from_now.utc }
    let(:new_publish_at) { 14.days.from_now.utc }
    let!(:rsc_video) do
      create(:video, channel: rsc_channel, title: "Rescheduled Run",
                     privacy_status: :private, publish_at: old_publish_at)
    end

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "updates publish_at to the new value" do
      described_class.confirm("video_schedule", {
        "video_id"    => rsc_video.id,
        "video_title" => "Rescheduled Run",
        "publish_at"  => new_publish_at.iso8601
      })
      expect(rsc_video.reload.publish_at).to be_within(1.second).of(new_publish_at)
    end

    it "enqueues VideoRemoteStatusSync with the updated schedule" do
      described_class.confirm("video_schedule", {
        "video_id"    => rsc_video.id,
        "video_title" => "Rescheduled Run",
        "publish_at"  => new_publish_at.iso8601
      })
      expect(VideoRemoteStatusSync).to have_received(:perform_later).with(rsc_video.id)
    end
  end

  # ── confirm / video_schedule (edge: nil or invalid publish_at raises) ───────
  #
  # Time.iso8601(nil.to_s) → Time.iso8601("") raises ArgumentError.
  # Time.iso8601("not-a-time") also raises ArgumentError.
  # The executor does NOT rescue (callers are responsible per class docstring),
  # so the exception propagates raw.

  describe ".confirm — video_schedule (edge: nil or invalid publish_at propagates ArgumentError)" do
    let!(:inv_channel) { create(:channel) }
    let!(:inv_video) do
      create(:video, channel: inv_channel, title: "Bad Schedule",
                     privacy_status: :public, publish_at: nil)
    end

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "raises ArgumentError when publish_at is nil (executor does not rescue)" do
      expect {
        described_class.confirm("video_schedule", {
          "video_id"    => inv_video.id,
          "video_title" => "Bad Schedule",
          "publish_at"  => nil
        })
      }.to raise_error(ArgumentError)
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end

    it "raises ArgumentError when publish_at is an invalid ISO8601 string (executor does not rescue)" do
      expect {
        described_class.confirm("video_schedule", {
          "video_id"    => inv_video.id,
          "video_title" => "Bad Schedule",
          "publish_at"  => "not-a-time"
        })
      }.to raise_error(ArgumentError)
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end
  end

  # ── confirm / video_schedule (WP2: 60-min spacing conflict at confirm time) ─
  #
  # video.save!(context: :schedule) trips Video#publish_spacing_within_channel;
  # the rescue must return the schedule_conflict copy directly — NEVER raise
  # (so it can't fall into Pito::FollowUp::Handlers::Confirmation's generic
  # `execution_failed` rescue), and must NOT enqueue VideoRemoteStatusSync.

  describe ".confirm — video_schedule (edge: spacing conflict at confirm time)" do
    let!(:conflict_channel) { create(:channel) }
    # Truncated to whole seconds: a real schedule's publish_at always passes
    # through Time#iso8601 (the confirmation payload's transport format),
    # which truncates fractional seconds — mirror that here so the exact-60m
    # boundary test isn't flaky against stray sub-second precision this
    # fixture would otherwise carry (and a real schedule never would).
    let(:anchor_at)         { 10.days.from_now.utc.change(usec: 0) }
    let!(:anchor_video) do
      create(:video, channel: conflict_channel, title: "Anchor Episode",
                     privacy_status: :private, publish_at: anchor_at)
    end
    # privacy_status: :private isolates the concern under test (spacing) from
    # the already-published guard exercised in its own describe block below —
    # a :public fixture here would trip THAT guard first and mask the spacing
    # assertions this block exists to make.
    let!(:conflicting_video) do
      create(:video, channel: conflict_channel, title: "Too Close Episode",
                     privacy_status: :private, publish_at: nil)
    end
    let(:colliding_at) { anchor_at + 20.minutes }

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "does not raise — the RecordInvalid is rescued locally" do
      expect {
        described_class.confirm("video_schedule", {
          "video_id"    => conflicting_video.id,
          "video_title" => "Too Close Episode",
          "publish_at"  => colliding_at.iso8601
        })
      }.not_to raise_error
    end

    it "does not persist the colliding privacy_status/publish_at" do
      described_class.confirm("video_schedule", {
        "video_id"    => conflicting_video.id,
        "video_title" => "Too Close Episode",
        "publish_at"  => colliding_at.iso8601
      })
      conflicting_video.reload
      expect(conflicting_video.privacy_status).to eq("private")
      expect(conflicting_video.publish_at).to be_nil
    end

    it "does NOT enqueue VideoRemoteStatusSync" do
      described_class.confirm("video_schedule", {
        "video_id"    => conflicting_video.id,
        "video_title" => "Too Close Episode",
        "publish_at"  => colliding_at.iso8601
      })
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end

    it "returns the schedule_conflict copy, naming both videos" do
      text = described_class.confirm("video_schedule", {
        "video_id"    => conflicting_video.id,
        "video_title" => "Too Close Episode",
        "publish_at"  => colliding_at.iso8601
      })
      expect(text).to include("Too Close Episode")
      expect(text).to include("Anchor Episode")
    end

    it "is valid at exactly 4 hours away (boundary — no conflict)" do
      text = described_class.confirm("video_schedule", {
        "video_id"    => conflicting_video.id,
        "video_title" => "Too Close Episode",
        "publish_at"  => (anchor_at + 4.hours).iso8601
      })
      expect(conflicting_video.reload.privacy_status).to eq("private")
      expect(text).not_to include("Anchor Episode")
    end
  end

  # ── confirm / video_schedule (edge: already published on YouTube) ──────────
  #
  # Root cause of the 2026-07-19 invalidPublishAt production incident: YouTube's
  # status.publishAt is settable only on a vid that's private AND has never
  # gone public (developers.google.com/youtube/v3/docs/videos). The chat
  # handler's stage-time check (Video#already_published?) catches this for the
  # normal flow, but the confirm click can land after the vid went public on
  # YouTube in the interim — save!(context: :schedule) re-validates for real
  # here, same spirit as the spacing-conflict re-check above.

  describe ".confirm — video_schedule (edge: already published on YouTube)" do
    let!(:pub_channel) { create(:channel) }
    let!(:pub_video) do
      create(:video, channel: pub_channel, title: "Went Live Already",
                     privacy_status: :public, publish_at: nil)
    end

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "does not raise — the RecordInvalid is rescued locally" do
      expect {
        described_class.confirm("video_schedule", {
          "video_id"    => pub_video.id,
          "video_title" => "Went Live Already",
          "publish_at"  => 7.days.from_now.utc.iso8601
        })
      }.not_to raise_error
    end

    it "does not persist privacy_status/publish_at" do
      described_class.confirm("video_schedule", {
        "video_id"    => pub_video.id,
        "video_title" => "Went Live Already",
        "publish_at"  => 7.days.from_now.utc.iso8601
      })
      pub_video.reload
      expect(pub_video.privacy_status).to eq("public")
      expect(pub_video.publish_at).to be_nil
    end

    it "does NOT enqueue VideoRemoteStatusSync" do
      described_class.confirm("video_schedule", {
        "video_id"    => pub_video.id,
        "video_title" => "Went Live Already",
        "publish_at"  => 7.days.from_now.utc.iso8601
      })
      expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
    end

    it "returns the schedule_already_public copy, naming the video" do
      text = described_class.confirm("video_schedule", {
        "video_id"    => pub_video.id,
        "video_title" => "Went Live Already",
        "publish_at"  => 7.days.from_now.utc.iso8601
      })
      expect(text).to include("Went Live Already")
    end
  end

  # ── confirm / video_schedule_mass (WP3) ───────────────────────────────────
  #
  # All-or-nothing: items apply ascending by publish_at inside ONE transaction.
  # A mid-batch failure rolls back EVERY item (nothing partially scheduled) and
  # enqueues ZERO jobs. VideoRemoteStatusSync only fires after a clean, full
  # commit — one per vid.

  describe ".confirm — video_schedule_mass" do
    let!(:mass_channel) { create(:channel) }
    # Private + never-published — the realistic pre-schedule state; the
    # already-published guard (root cause of the 2026-07-19 invalidPublishAt
    # incident) gets its own describe block below.
    let!(:mass_video1) do
      create(:video, channel: mass_channel, title: "Episode One", privacy_status: :private, publish_at: nil)
    end
    let!(:mass_video2) do
      create(:video, channel: mass_channel, title: "Episode Two", privacy_status: :private, publish_at: nil)
    end
    let(:time1) { 10.days.from_now.utc.change(usec: 0) }
    let(:time2) { 12.days.from_now.utc.change(usec: 0) }

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    def mass_payload(items)
      { "items" => items }
    end

    context "happy path — every item clears validation" do
      let(:items) do
        [
          { "video_id" => mass_video1.id, "video_title" => "Episode One", "publish_at" => time1.iso8601 },
          { "video_id" => mass_video2.id, "video_title" => "Episode Two", "publish_at" => time2.iso8601 }
        ]
      end

      it "sets privacy_status private and publish_at on EVERY video" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(mass_video1.reload.privacy_status).to eq("private")
        expect(mass_video1.reload.publish_at).to be_within(1.second).of(time1)
        expect(mass_video2.reload.privacy_status).to eq("private")
        expect(mass_video2.reload.publish_at).to be_within(1.second).of(time2)
      end

      it "enqueues VideoRemoteStatusSync once per video" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(VideoRemoteStatusSync).to have_received(:perform_later).with(mass_video1.id)
        expect(VideoRemoteStatusSync).to have_received(:perform_later).with(mass_video2.id)
        expect(VideoRemoteStatusSync).to have_received(:perform_later).exactly(2).times
      end

      it "returns outcome text mentioning the batch count" do
        text = described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(text).to include("2")
      end

      it "applies items regardless of input order (ascending by publish_at, driven by the payload, not array order)" do
        # Payload items given latest-first; the executor sorts ascending itself.
        reversed = items.reverse
        described_class.confirm("video_schedule_mass", mass_payload(reversed))
        expect(mass_video1.reload.publish_at).to be_within(1.second).of(time1)
        expect(mass_video2.reload.publish_at).to be_within(1.second).of(time2)
      end
    end

    context "mid-batch spacing collision against an ALREADY-SCHEDULED row" do
      let!(:anchor_video) do
        create(:video, channel: mass_channel, title: "Anchor Episode",
                       privacy_status: :private, publish_at: time1 + 20.minutes)
      end
      let(:items) do
        [
          { "video_id" => mass_video1.id, "video_title" => "Episode One", "publish_at" => time1.iso8601 },
          { "video_id" => mass_video2.id, "video_title" => "Episode Two", "publish_at" => time2.iso8601 }
        ]
      end

      it "does not raise — RecordInvalid is rescued locally" do
        expect { described_class.confirm("video_schedule_mass", mass_payload(items)) }.not_to raise_error
      end

      it "rolls back EVERY item — including the one that validated fine" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(mass_video1.reload.privacy_status).to eq("private")
        expect(mass_video1.reload.publish_at).to be_nil
        expect(mass_video2.reload.privacy_status).to eq("private")
        expect(mass_video2.reload.publish_at).to be_nil
      end

      it "enqueues ZERO jobs" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
      end

      it "names the offending vid and the row it collided with" do
        text = described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(text).to include("Episode One")
        expect(text).to include("Anchor Episode")
      end
    end

    context "mid-batch INTRA-batch spacing collision (caught by construction: the first save is visible to the second's own validation)" do
      let(:items) do
        [
          { "video_id" => mass_video1.id, "video_title" => "Episode One", "publish_at" => time1.iso8601 },
          { "video_id" => mass_video2.id, "video_title" => "Episode Two", "publish_at" => (time1 + 20.minutes).iso8601 }
        ]
      end

      it "rolls back BOTH items — the first save never persists once the second fails" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(mass_video1.reload.privacy_status).to eq("private")
        expect(mass_video1.reload.publish_at).to be_nil
        expect(mass_video2.reload.privacy_status).to eq("private")
        expect(mass_video2.reload.publish_at).to be_nil
      end

      it "enqueues ZERO jobs" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
      end

      it "names the second vid and the first as the colliding row" do
        text = described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(text).to include("Episode Two")
        expect(text).to include("Episode One")
      end
    end

    context "a video vanished between staging and confirming" do
      let(:items) do
        [
          { "video_id" => mass_video1.id, "video_title" => "Episode One", "publish_at" => time1.iso8601 },
          { "video_id" => 0, "video_title" => "Ghost", "publish_at" => time2.iso8601 }
        ]
      end

      it "does not raise" do
        expect { described_class.confirm("video_schedule_mass", mass_payload(items)) }.not_to raise_error
      end

      it "rolls back the earlier item that DID save" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(mass_video1.reload.privacy_status).to eq("private")
        expect(mass_video1.reload.publish_at).to be_nil
      end

      it "enqueues ZERO jobs" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
      end

      it "returns present outcome text" do
        text = described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(text).to be_present
      end
    end

    it "is valid at exactly 4 hours away from an existing row (boundary — no conflict)" do
      create(:video, channel: mass_channel, title: "Boundary Anchor",
                     privacy_status: :private, publish_at: time1 + 4.hours)
      items = [ { "video_id" => mass_video1.id, "video_title" => "Episode One", "publish_at" => time1.iso8601 } ]
      text = described_class.confirm("video_schedule_mass", mass_payload(items))
      expect(mass_video1.reload.privacy_status).to eq("private")
      expect(text).not_to include("Boundary Anchor")
    end

    # Root cause of the 2026-07-19 invalidPublishAt production incident: a
    # batch item that's already public on YouTube trips the confirm-time
    # save!(context: :schedule) re-validation (Video#already_published?) —
    # the stage-time chat handler dry-run already catches this for the normal
    # flow, but the confirm click can land after the vid went public in the
    # interim. All-or-nothing like every other mass_schedule_* failure.
    context "mid-batch item already published on YouTube" do
      let!(:published_video) do
        create(:video, channel: mass_channel, title: "Went Live Already",
                       privacy_status: :public, publish_at: nil)
      end
      let(:items) do
        [
          { "video_id" => mass_video1.id,     "video_title" => "Episode One",       "publish_at" => time1.iso8601 },
          { "video_id" => published_video.id, "video_title" => "Went Live Already", "publish_at" => time2.iso8601 }
        ]
      end

      it "does not raise — RecordInvalid is rescued locally" do
        expect { described_class.confirm("video_schedule_mass", mass_payload(items)) }.not_to raise_error
      end

      it "rolls back EVERY item — including the one that validated fine" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(mass_video1.reload.privacy_status).to eq("private")
        expect(mass_video1.reload.publish_at).to be_nil
        expect(published_video.reload.privacy_status).to eq("public")
        expect(published_video.reload.publish_at).to be_nil
      end

      it "enqueues ZERO jobs" do
        described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(VideoRemoteStatusSync).not_to have_received(:perform_later)
      end

      it "names the already-published vid via mass_schedule_already_public" do
        text = described_class.confirm("video_schedule_mass", mass_payload(items))
        expect(text).to include("Went Live Already")
      end
    end
  end

  # ── confirm / nl_run ──────────────────────────────────────────────────────
  # The NL gate's did-you-mean confirm: re-enters Pito::Dispatch::Router with
  # the stamped `nl_command`, then projects the resulting events into one
  # outcome_text string via Pito::Mcp::EventText (mirrors the AI orchestrator's
  # own events→text projection).

  describe ".confirm — nl_run" do
    let!(:conversation) { create(:conversation) }
    let(:nl_payload) do
      {
        "command"         => "nl_run",
        "nl_command"      => "list vids",
        "conversation_id" => conversation.id
      }
    end

    it "re-enters Pito::Dispatch::Router with the nl_command and the resolved conversation, guarded as an NL retry" do
      allow(Pito::Dispatch::Router).to receive(:call).and_return(
        Pito::Chat::Result::Ok.new(events: [ { kind: :list, payload: { rows: [] } } ])
      )
      described_class.confirm("nl_run", nl_payload)
      expect(Pito::Dispatch::Router).to have_received(:call)
        .with(input: "list vids", conversation: conversation, nl_retry: true)
    end

    # P7 loop guard: a confirmed mapped command that itself soft-fails comes
    # back as the nl_fallback marker (thanks to nl_retry: true) and renders as
    # its own crisp error text — never another gate pass / did-you-mean.
    it "renders a soft-failing confirmed command as its crisp error text (no gate re-entry)" do
      marker = Pito::Chat::Result::Error.new(
        message_key: "pito.copy.videos.not_found", message_args: { ref: "tekken" }, nl_fallback: true
      )
      allow(Pito::Dispatch::Router).to receive(:call).and_return(marker)
      expect(Pito::Nl::Router).not_to receive(:route)

      text = described_class.confirm("nl_run", nl_payload)

      expect(text).to be_a(String)
      expect(text).to be_present
    end

    it "returns the text projected via Pito::Mcp::EventText over the dispatched events" do
      events = [ { kind: :list, payload: { rows: [] } } ]
      allow(Pito::Dispatch::Router).to receive(:call).and_return(
        Pito::Chat::Result::Ok.new(events: events)
      )
      allow(Pito::Mcp::EventText).to receive(:call).and_return("Projected outcome")

      text = described_class.confirm("nl_run", nl_payload)

      expect(Pito::Mcp::EventText).to have_received(:call).with(events)
      expect(text).to eq("Projected outcome")
    end
  end

  describe ".confirm — nl_run (conversation vanished)" do
    let(:vanished_payload) do
      { "command" => "nl_run", "nl_command" => "list vids", "conversation_id" => 0 }
    end

    it "does not re-enter Pito::Dispatch::Router" do
      allow(Pito::Dispatch::Router).to receive(:call)
      described_class.confirm("nl_run", vanished_payload)
      expect(Pito::Dispatch::Router).not_to have_received(:call)
    end

    it "degrades to the generic huh copy" do
      text = described_class.confirm("nl_run", vanished_payload)
      expect(I18n.t("pito.copy.huh")).to include(text)
    end
  end

  # ── cancel / nl_run ───────────────────────────────────────────────────────

  describe ".cancel — nl_run" do
    it "falls through to the generic confirmation-cancelled copy (no per-command branch)" do
      text = described_class.cancel("nl_run", {
        "command" => "nl_run", "nl_command" => "list vids", "conversation_id" => 1
      })
      expect(text).to eq(Pito::Copy.render("pito.copy.confirmation.cancelled"))
    end
  end
end
