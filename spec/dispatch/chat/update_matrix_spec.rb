# frozen_string_literal: true

require "rails_helper"
require "bigdecimal"

# ── Dispatch matrix: `update` (game footage/price/platform local writes;
#    vid description/tags staged confirmations) ──────────────────────────────
#
# Subject:  Pito::Chat::Handlers::Update (lib/pito/chat/handlers/update.rb)
# Grammar:  verbs.update in config/pito/tools.yml — update_nouns (game/games,
#           vid/vids/video/videos) + update_fields (footage/price/platform,
#           description/tags). The handler's PATTERN parses message.raw
#           directly (`update <noun> <field> #?<id> <value…>`), so every case
#           here goes through the REAL pipeline — Pito::Dispatch::Router,
#           config-driven dispatch, a real Conversation, real Game/Video rows —
#           rather than constructing the handler by hand.
#
# Game fields (footage/price/platform) write the column IMMEDIATELY and return
# Result::Ok with one :system event. Vid fields (description/tags) never write
# directly: they stage a :confirmation event
# (Pito::MessageBuilder::Video::MetadataConfirmation) whose `yes` reply runs
# Confirmation::Executor#confirm_video_metadata (out of scope here — this spec
# only pins that nothing is written until that confirmation fires).
RSpec.describe "Dispatch matrix — update (game/vid metadata writes)", type: :dispatch do
  let(:conversation) { Conversation.singleton }

  before { conversation.turns.destroy_all }

  def dispatch(raw)
    Pito::Dispatch::Router.call(input: raw, conversation:)
  end

  # ── game footage — local write, 0.5-step ceil (Pito::Games::FootageAmount) ──

  describe "update game footage <id> <hours>" do
    let!(:game) { create(:game, footage_hours: 0) }

    it "writes footage_hours as an exact Rational (8.5h == 17/2r)" do
      result = dispatch("update game footage #{game.id} 8.5")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
      expect(game.reload.footage_hours).to eq(17/2r)
    end

    it "accepts the '#<id>' hash-id form identically" do
      result = dispatch("update game footage ##{game.id} 8.5")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game.reload.footage_hours).to eq(17/2r)
    end

    it "ceils a sub-half-hour amount ('.3') UP to the next 0.5 step" do
      result = dispatch("update game footage #{game.id} .3")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game.reload.footage_hours).to eq(1/2r)
    end
  end

  # ── game price — local write, exact BigDecimal, html :system payload ───────

  describe "update game price <id> <amount>" do
    let!(:game) { create(:game, price: nil) }

    it "persists the price as an exact BigDecimal and returns an html :system payload" do
      result = dispatch("update game price #{game.id} 59.99")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.size).to eq(1)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["html"]).to be(true)
      expect(event[:payload]["body"]).to be_a(String).and be_present
      expect(game.reload.price).to eq(BigDecimal("59.99"))
    end
  end

  # ── game platform — local write, adds the normalized family, no dupes ──────

  describe "update game platform <id> <name>" do
    let!(:game) { create(:game, platforms: []) }

    it "normalizes 'ps5' to the 'PlayStation 5' family and adds it" do
      result = dispatch("update game platform #{game.id} ps5")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
      expect(game.reload.platforms).to eq([ "PlayStation 5" ])
    end

    it "enqueues GameEmbedIndexJob (platforms feed Game::EmbedText) when the platform is actually added" do
      expect { dispatch("update game platform #{game.id} ps5") }
        .to have_enqueued_job(GameEmbedIndexJob).with(game.id)
    end

    it "does not duplicate the platform when the same update runs again" do
      dispatch("update game platform #{game.id} ps5")
      result = dispatch("update game platform #{game.id} ps5")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game.reload.platforms).to eq([ "PlayStation 5" ])
    end

    it "does not re-enqueue GameEmbedIndexJob on a no-op repeat (already present)" do
      dispatch("update game platform #{game.id} ps5")

      expect { dispatch("update game platform #{game.id} ps5") }
        .not_to have_enqueued_job(GameEmbedIndexJob)
    end
  end

  # ── vid description — staged confirmation, NO write yet ────────────────────

  describe "update vid description <id> <text>" do
    let!(:video) { create(:video, description: "original description") }

    it "stages ONE :confirmation event carrying the raw text; no column write yet" do
      result = dispatch("update vid description #{video.id} A new description")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.size).to eq(1)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("video_metadata")
      expect(event[:payload]["field"]).to eq("description")
      expect(event[:payload]["staged_value"]).to eq("A new description")
      expect(event[:payload]["video_id"]).to eq(video.id)
      expect(event[:payload]["reply_handle"]).to be_present

      expect(video.reload.description).to eq("original description")
    end
  end

  # ── vid tags — staged confirmation (comma-split array), NO write yet ───────

  describe "update vid tags <id> <t1, t2, …>" do
    let!(:video) { create(:video, tags: []) }

    it "stages the comma-split tags array as staged_value; no column write yet" do
      result = dispatch("update vid tags #{video.id} minecraft, hardcore, ep 4")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("video_metadata")
      expect(event[:payload]["field"]).to eq("tags")
      expect(event[:payload]["staged_value"]).to eq([ "minecraft", "hardcore", "ep 4" ])
      expect(event[:payload]["video_id"]).to eq(video.id)
      expect(event[:payload]["reply_handle"]).to be_present

      expect(video.reload.tags).to eq([])
    end
  end

  # ── noun/field mismatch → usage ─────────────────────────────────────────────
  #
  # GAME_FIELDS = footage/price/platform; VID_FIELDS = description/tags. A field
  # from the wrong list for the resolved noun never reaches the not-found /
  # bad-value branches — it fails the field-membership guard first.

  describe "noun/field mismatch → pito.chat.update.usage" do
    it "'update game description <id> x' → Error usage (description is a vid-only field)" do
      game = create(:game)

      result = dispatch("update game description #{game.id} x")

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.update.usage")
    end

    it "'update vid price <id> 9' → Error usage (price is a game-only field)" do
      video = create(:video)

      result = dispatch("update vid price #{video.id} 9")

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.update.usage")
    end
  end

  # ── unknown id → not_found ───────────────────────────────────────────────────

  describe "unknown id → pito.chat.update.not_found" do
    it "'update game price <missing-id> 9' → Error not_found" do
      missing_id = (::Game.maximum(:id) || 0) + 999
      expect(::Game.find_by(id: missing_id)).to be_nil # guard: id genuinely unused

      result = dispatch("update game price #{missing_id} 9")

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.update.not_found")
    end
  end

  # ── bad values → bad_value ──────────────────────────────────────────────────
  #
  # NOTE (discrepancy, reported — handler NOT changed): the platform field's
  # `bad_value` branch (`return bad_value("platform", value) if normalized.nil?`
  # in update_platform) is effectively unreachable. Pito::Games::PlatformInput
  # .normalize NEVER returns nil — non-blank input always falls through to
  # `text.titleize`, and blank input returns "" (not nil). So
  # 'update game platform <id> zzz-nonsense' does NOT hit bad_value: it
  # succeeds and adds the titleized "Zzz Nonsense" as a platform. Pinned below
  # as the ACTUAL behavior; see final report for the full discrepancy note.

  describe "bad values → pito.chat.update.bad_value" do
    it "'update game footage <id> abc' → Error bad_value (non-numeric hours)" do
      game = create(:game)

      result = dispatch("update game footage #{game.id} abc")

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.update.bad_value")
    end

    it "'update game platform <id> zzz-nonsense' → Result::Ok (NOT bad_value — see discrepancy note above)" do
      game = create(:game, platforms: [])

      result = dispatch("update game platform #{game.id} zzz-nonsense")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game.reload.platforms).to eq([ "Zzz Nonsense" ])
    end
  end

  # ── malformed input → usage ─────────────────────────────────────────────────

  describe "malformed input → pito.chat.update.usage" do
    [ "update", "update game", "update game price" ].each do |raw|
      it "#{raw.inspect} → Error usage" do
        result = dispatch(raw)

        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.update.usage")
      end
    end
  end

  # ── noun synonyms route correctly ───────────────────────────────────────────

  describe "noun synonyms" do
    it "'update video description <id> x' (video → vid) stages a :confirmation" do
      video = create(:video, description: "kept")

      result = dispatch("update video description #{video.id} x")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["field"]).to eq("description")
      expect(event[:payload]["video_id"]).to eq(video.id)
      expect(video.reload.description).to eq("kept")
    end

    it "'update games price <id> 5' (games → game) writes the price locally" do
      game = create(:game, price: nil)

      result = dispatch("update games price #{game.id} 5")

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(game.reload.price).to eq(BigDecimal("5.00"))
    end
  end
end
