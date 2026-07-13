# frozen_string_literal: true

require "rails_helper"

# The living background's Option-B contract (F2/F3): eligible events carry a
# derived `fx` stamp; everything else stays untouched and the sky answers.
RSpec.describe Pito::Fx::Context do
  let(:channel) { create(:channel) }
  let(:game)    { create(:game, title: "Stamped") }
  let(:video)   { create(:video, title: "Stamped vid", channel:) }

  before { create(:video_game_link, video:, game:) }

  # Attaches real (fake-byte) cover art the same way the rest of the suite
  # does (Pito::ImagePath spec, Game::CoverArt::Normalizer spec) — no fixture
  # files needed, ActiveStorage only cares about the attachment existing.
  def attach_cover_art(game)
    game.cover_art.attach(io: StringIO.new("fake-jpeg-data"), filename: "cover.jpg", content_type: "image/jpeg")
  end

  # The exact host-independent variant path the production `cover_path`
  # helper computes — used to assert `covers` for real, not just its shape.
  def expected_cover_path(game, variant)
    Rails.application.routes.url_helpers.rails_representation_path(
      game.cover_art.variant(variant), only_path: true
    )
  end

  describe ".derive" do
    it "answers nil for non-eligible kinds regardless of payload" do
      %w[echo thinking confirmation error system_follow_up enhanced_follow_up].each do |kind|
        expect(described_class.derive(kind:, payload: { "game_id" => game.id })).to be_nil
      end
    end

    it "stamps :ai events as the ai mood with no covers" do
      expect(described_class.derive(kind: "ai", payload: { "blocks" => [] }))
        .to eq({ "context" => "ai", "covers" => [] })
    end

    it "answers nil (the sky) for an eligible event with no markers" do
      expect(described_class.derive(kind: "system", payload: { "text" => "plain" })).to be_nil
    end

    describe "the analyze marker (Pito::MessageBuilder::Analyze::Message shape)" do
      it "derives analyze_channel with no covers for level channel" do
        fx = described_class.derive(
          kind: "enhanced",
          payload: { "analyze" => { "level" => "channel", "entity_ids" => [ channel.id ] } }
        )
        expect(fx).to eq({ "context" => "analyze_channel", "covers" => [] })
      end

      it "derives analyze_vid with the linked game's single detail cover for one entity id" do
        attach_cover_art(game)
        fx = described_class.derive(
          kind: "enhanced",
          payload: { "analyze" => { "level" => "vid", "entity_ids" => [ video.id ] } }
        )
        expect(fx).to eq({ "context" => "analyze_vid", "covers" => [ expected_cover_path(game, :detail) ] })
      end

      it "derives analyze_game with a single detail cover for one entity id" do
        attach_cover_art(game)
        fx = described_class.derive(
          kind: "enhanced",
          payload: { "analyze" => { "level" => "game", "entity_ids" => [ game.id ] } }
        )
        expect(fx).to eq({ "context" => "analyze_game", "covers" => [ expected_cover_path(game, :detail) ] })
      end

      it "falls back to the bare cover-less analyze context for multiple entity_ids (breakdowns)" do
        other_game = create(:game)
        fx = described_class.derive(
          kind: "enhanced",
          payload: { "analyze" => { "level" => "game", "entity_ids" => [ game.id, other_game.id ] } }
        )
        expect(fx).to eq({ "context" => "analyze", "covers" => [] })
      end

      it "falls back to the bare cover-less analyze context for empty entity_ids" do
        fx = described_class.derive(
          kind: "enhanced",
          payload: { "analyze" => { "level" => "game", "entity_ids" => [] } }
        )
        expect(fx).to eq({ "context" => "analyze", "covers" => [] })
      end
    end

    describe "the analytics marker (Pito::MessageBuilder::Analytics::Enhanced shape)" do
      it "derives analyze_channel for scope_type Channel" do
        fx = described_class.derive(
          kind: "enhanced",
          payload: { "analytics" => { "scope_type" => "Channel", "scope_id" => channel.id } }
        )
        expect(fx).to eq({ "context" => "analyze_channel", "covers" => [] })
      end

      it "derives analyze_vid for scope_type Video with a scope_id" do
        attach_cover_art(game)
        fx = described_class.derive(
          kind: "enhanced",
          payload: { "analytics" => { "scope_type" => "Video", "scope_id" => video.id } }
        )
        expect(fx).to eq({ "context" => "analyze_vid", "covers" => [ expected_cover_path(game, :detail) ] })
      end

      it "derives analyze_game for scope_type Game with a scope_id" do
        attach_cover_art(game)
        fx = described_class.derive(
          kind: "enhanced",
          payload: { "analytics" => { "scope_type" => "Game", "scope_id" => game.id } }
        )
        expect(fx).to eq({ "context" => "analyze_game", "covers" => [ expected_cover_path(game, :detail) ] })
      end

      it "falls back to the bare cover-less analyze context for scope_ids (multi-entity at-a-glance)" do
        other_game = create(:game)
        fx = described_class.derive(
          kind: "enhanced",
          payload: { "analytics" => { "scope_type" => "Game", "scope_ids" => [ game.id, other_game.id ] } }
        )
        expect(fx).to eq({ "context" => "analyze", "covers" => [] })
      end
    end

    describe "plain entity markers (no analyze/analytics marker present)" do
      it "derives channel with the wall of games linked through the channel's vids" do
        attach_cover_art(game)
        fx = described_class.derive(kind: "enhanced", payload: { "channel_id" => channel.id })
        expect(fx).to eq({ "context" => "channel", "covers" => [ expected_cover_path(game, :strip) ] })
      end

      it "caps the channel wall at WALL_COVERS_MAX" do
        # Every candidate game must carry cover art here: the SQL cap picks
        # WALL_COVERS_MAX ids first, THEN covers filter art-less ones out —
        # an uncovered game among the picked ids would starve the count.
        attach_cover_art(game)
        (described_class::WALL_COVERS_MAX + 3).times do
          g = create(:game)
          attach_cover_art(g)
          v = create(:video, channel:)
          create(:video_game_link, video: v, game: g)
        end

        fx = described_class.derive(kind: "system", payload: { "channel_id" => channel.id })
        expect(fx["context"]).to eq("channel")
        expect(fx["covers"].size).to eq(described_class::WALL_COVERS_MAX)
      end

      it "derives vid_detail with the linked game's single detail cover" do
        attach_cover_art(game)
        fx = described_class.derive(kind: "enhanced", payload: { "video_id" => video.id })
        expect(fx).to eq({ "context" => "vid_detail", "covers" => [ expected_cover_path(game, :detail) ] })
      end

      it "derives vid_list with a strip-variant wall" do
        attach_cover_art(game)
        fx = described_class.derive(kind: "system", payload: { "video_ids" => [ video.id ] })
        expect(fx).to eq({ "context" => "vid_list", "covers" => [ expected_cover_path(game, :strip) ] })
      end

      it "caps vid_list at WALL_COVERS_MAX (the old VID_COVERS_MAX of 8 no longer applies)" do
        videos = (described_class::WALL_COVERS_MAX + 3).times.map do
          g = create(:game)
          attach_cover_art(g)
          v = create(:video, channel:)
          create(:video_game_link, video: v, game: g)
          v
        end

        fx = described_class.derive(kind: "system", payload: { "video_ids" => videos.map(&:id) })
        expect(fx["context"]).to eq("vid_list")
        expect(fx["covers"].size).to eq(described_class::WALL_COVERS_MAX)
      end

      it "derives game_detail with a single detail cover" do
        attach_cover_art(game)
        fx = described_class.derive(kind: "enhanced", payload: { "game_id" => game.id })
        expect(fx).to eq({ "context" => "game_detail", "covers" => [ expected_cover_path(game, :detail) ] })
      end

      it "derives game_list with a strip-variant wall" do
        attach_cover_art(game)
        fx = described_class.derive(kind: "system", payload: { "game_ids" => [ game.id ] })
        expect(fx).to eq({ "context" => "game_list", "covers" => [ expected_cover_path(game, :strip) ] })
      end

      it "contributes no cover for art-less games instead of raising" do
        fx = described_class.derive(kind: "enhanced", payload: { "game_id" => game.id })
        expect(fx).to eq({ "context" => "game_detail", "covers" => [] }) # factory game has no attached cover_art
      end
    end

    describe "marker priority (first match wins, most-specific first)" do
      it "ranks an analyze marker above channel_id/video_id/game_id in the same payload" do
        fx = described_class.derive(
          kind: "enhanced",
          payload: {
            "analytics"  => { "status" => "ready" },
            "channel_id" => channel.id, "video_id" => video.id, "game_id" => game.id
          }
        )
        expect(fx).to eq({ "context" => "analyze", "covers" => [] })
      end

      it "ranks channel_id above video_id" do
        fx = described_class.derive(
          kind: "enhanced", payload: { "channel_id" => channel.id, "video_id" => video.id }
        )
        expect(fx["context"]).to eq("channel")
      end

      it "ranks video_id above game_id" do
        fx = described_class.derive(
          kind: "enhanced", payload: { "video_id" => video.id, "game_id" => game.id }
        )
        expect(fx["context"]).to eq("vid_detail")
      end
    end
  end

  describe "the Broadcaster stamp (persist + replace choke points)" do
    let(:conversation) { Conversation.create! }
    let(:turn) { conversation.turns.create!(position: 1, input_kind: :chat, input_text: "show game") }
    let(:broadcaster) { Pito::Stream::Broadcaster.new(conversation:) }

    it "stamps eligible events at emit" do
      event = broadcaster.emit(turn:, kind: :enhanced, payload: { "game_id" => game.id })
      expect(event.reload.payload["fx"]).to eq({ "context" => "game_detail", "covers" => [] })
    end

    it "never stamps non-eligible kinds" do
      event = broadcaster.emit(turn:, kind: :echo, payload: { "text" => "show game 1", "game_id" => game.id })
      expect(event.reload.payload).not_to have_key("fx")
    end

    it "re-derives on replace so the mood tracks replaced content" do
      event = broadcaster.emit(turn:, kind: :enhanced, payload: { "game_id" => game.id })
      event.update!(payload: event.payload.except("game_id", "fx").merge("video_id" => video.id))

      broadcaster.replace_event(event)
      expect(event.reload.payload["fx"]["context"]).to eq("vid_detail")
    end

    it "travels the JSON mirror verbatim" do
      event = broadcaster.emit(turn:, kind: :enhanced, payload: { "game_id" => game.id })
      expect(Pito::Stream::EventJson.call(event)[:payload]["fx"])
        .to eq({ "context" => "game_detail", "covers" => [] })
    end
  end
  describe "ai answers linked to a game (owner 2026-07-13: glow's exclusive home)" do
    it "derives ai_game with the game's cover when EXACTLY ONE game media block is present" do
      attach_cover_art(game)
      result = described_class.derive(kind: :ai, payload: {
        "blocks" => [ { "type" => "media", "entity" => "game", "id" => game.id } ]
      })
      expect(result["context"]).to eq("ai_game")
      expect(result["covers"].length).to eq(1)
    end

    it "derives ai_game from a SUGGESTION block naming one game (real answers carry suggestions, not media)" do
      attach_cover_art(game)
      result = described_class.derive(kind: :ai, payload: {
        "blocks" => [
          { "type" => "text", "text" => "You should play it." },
          { "type" => "suggestion", "command" => "show game #{game.id}" }
        ]
      })
      expect(result["context"]).to eq("ai_game")
    end

    it "stays plain ai when suggestions name DIFFERENT games" do
      result = described_class.derive(kind: :ai, payload: {
        "blocks" => [
          { "type" => "suggestion", "command" => "show game 1" },
          { "type" => "suggestion", "command" => "update game footage 2 4" }
        ]
      })
      expect(result["context"]).to eq("ai")
    end

    it "stays plain cover-less ai for zero games, many games, or the pending shell" do
      expect(described_class.derive(kind: :ai, payload: { "blocks" => [] })).to eq("context" => "ai", "covers" => [])
      two = [ { "type" => "media", "entity" => "game", "id" => 1 }, { "type" => "media", "entity" => "game", "id" => 2 } ]
      expect(described_class.derive(kind: :ai, payload: { "blocks" => two })["context"]).to eq("ai")
      expect(described_class.derive(kind: :ai, payload: nil)["context"]).to eq("ai")
    end
  end
end
