# frozen_string_literal: true

require "rails_helper"

# ── Segment verbs (plan-0.9.5 D20/D21) ──────────────────────────────────────
#
# Seven top-level chat verbs, each promoting ONE :enhanced segment of
# show/analyze into its own verb via the single generic
# Pito::Chat::Handlers::SegmentVerb + a `segment_of` config binding — additive;
# show/analyze untouched. Semantics equal `<parent> <noun> <ref> only <segment>`.
#
# This proves the mechanism end-to-end through the PUBLIC Router:
#   * recognition — every verb + alias parses to its canonical verb, and the
#     noun-filler words that also became verbs (videos/vids/channels) still parse
#     to their ORIGINAL verb at position ≥2 (`list videos`, `analyze channels`);
#   * byte-identity — each verb×valid-entity emits EXACTLY the parent's
#     `only <segment>` events (Router output compared for equality);
#   * rejection — an off-entity segment (`similar channel`) yields the SAME
#     `segments.unknown` error the parent's `only <segment>` form produces;
#   * schema — the `segment_of` contract accepts valid bindings, rejects bad ones;
#   * palette — the verb + its slot surface from config (no hand-maintained list).
RSpec.describe "segment verbs (D20/D21)", type: :dispatch do
  let(:conversation) { Conversation.singleton }

  def route(input)
    Pito::Dispatch::Router.call(input: input, conversation: conversation)
  end

  def parse(input)
    tokens = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(input))
    Pito::Chat::Parser.call(tokens, raw: input, conversation: conversation)
  end

  # ── recognition ────────────────────────────────────────────────────────────
  describe "recognition — canonical verbs + aliases at position 1" do
    {
      "at-a-glance"   => :"at-a-glance", "glance" => :"at-a-glance", "overview" => :"at-a-glance",
      "videos"        => :videos,        "vids"   => :videos,
      "linked-game"   => :"linked-game",
      "similar"       => :similar,       "similars" => :similar,
      "linked-videos" => :"linked-videos", "linked-vids" => :"linked-videos",
      "channels"      => :channels,      "handles" => :channels,
      "breakdowns"    => :breakdowns,    "lifetime" => :breakdowns, "life" => :breakdowns
    }.each do |token, verb|
      it "#{token.inspect} → verb #{verb.inspect}, a :new_turn" do
        msg = parse("#{token} game 1")
        expect(msg.kind).to eq(:new_turn)
        expect(msg.verb).to eq(verb)
      end
    end
  end

  describe "recognition — negatives: the filler/vocabulary words stay their original verb at position ≥2" do
    {
      "list videos"      => :list,
      "list vids"        => :list,
      "ls videos"        => :list,
      "analyze channels" => :analyze,
      "analyze vids"     => :analyze,
      "show videos"      => :show,
      "sync vids"        => :sync
    }.each do |input, verb|
      it "#{input.inspect} still parses to #{verb.inspect} (position-1 verb match beats position-n filler)" do
        expect(parse(input).verb).to eq(verb)
      end
    end
  end

  # ── byte-identity: verb×valid-entity == the parent's only-<segment> form ─────
  describe "byte-identity with the parent's only-<segment> emission" do
    let!(:channel) { create(:channel, handle: "byteid") }
    let!(:game)    { create(:game) }
    let!(:video)   { create(:video, channel: channel) }
    let!(:link)    { create(:video_game_link, video: video, game: game) }

    # Analytics pending cards mint a random per-card token (SecureRandom.hex(4));
    # pin it so the ONLY remaining difference between the two forms would be a real
    # divergence in the emitted payload. (The deterministic copy sampler handles
    # the witty-copy variance.)
    before do
      allow(SecureRandom).to receive(:hex).and_wrap_original do |orig, *args|
        args == [ 4 ] ? "cafebabe" : orig.call(*args)
      end
      # analyze pending cards also mint a random reply_handle at build time.
      allow(Pito::HandleGenerator).to receive(:call).and_return("zeta-0000")
    end

    # [segment-verb input, equivalent parent `only <segment>` input]
    def cases
      {
        "at-a-glance channel"   => [ "at-a-glance channel @byteid",     "show channel @byteid only at-a-glance" ],
        "at-a-glance vid"       => [ "at-a-glance vid ##{video.id}",    "show vid ##{video.id} only at-a-glance" ],
        "at-a-glance game"      => [ "at-a-glance game ##{game.id}",    "show game ##{game.id} only at-a-glance" ],
        "videos channel"        => [ "videos channel @byteid",          "show channel @byteid only videos" ],
        "linked-game vid"       => [ "linked-game vid ##{video.id}",    "show vid ##{video.id} only linked-game" ],
        "similar game"          => [ "similar game ##{game.id}",        "show game ##{game.id} only similar" ],
        "linked-videos game"    => [ "linked-videos game ##{game.id}",  "show game ##{game.id} only linked-videos" ],
        "channels game"         => [ "channels game ##{game.id}",       "show game ##{game.id} only channels" ],
        "breakdowns channel"    => [ "breakdowns channel @byteid",      "analyze channel @byteid only breakdowns" ],
        "breakdowns vid"        => [ "breakdowns vid ##{video.id}",     "analyze vid ##{video.id} only breakdowns" ],
        "breakdowns game"       => [ "breakdowns game ##{game.id}",     "analyze game ##{game.id} only breakdowns" ]
      }
    end

    it "each verb emits exactly the parent's only-<segment> events" do
      aggregate_failures do
        cases.each do |label, (seg_input, parent_input)|
          seg    = route(seg_input)
          parent = route(parent_input)

          expect(seg).to be_a(Pito::Chat::Result::Ok), "#{label}: expected Ok, got #{seg.class}"
          expect(seg.events).to eq(parent.events), "#{label}: segment-verb events differ from `#{parent_input}`"
          expect(seg.events).not_to be_empty, "#{label}: expected a non-empty emission"
        end
      end
    end
  end

  # ── entity availability — off-entity segment rejects like the parent ─────────
  describe "off-entity rejection matches the parent's only-<segment> rejection" do
    let!(:channel) { create(:channel, handle: "byteid") }

    it "`similar channel @h` == `show channel @h only similar` (segments.unknown error)" do
      seg    = route("similar channel @byteid")
      parent = route("show channel @byteid only similar")

      expect(seg).to be_a(Pito::Chat::Result::Error)
      expect(parent).to be_a(Pito::Chat::Result::Error)
      # Deterministic copy sampler (spec/support/copy.rb) → identical rendered copy.
      expect(seg.message_key).to eq(parent.message_key)
    end

    # NB: the parent `show game #id only videos` can't be compared here — "videos"
    # is a VIDEO noun-filler, so show's video_target? misroutes that only-clause to
    # the video branch (a pre-existing show quirk). The segment verb resolves the
    # game cleanly and rejects on availability, which is the correct behaviour.
    it "`videos game #id` rejects — videos is not a game segment" do
      game   = create(:game)
      result = route("videos game ##{game.id}")

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to match(/videos/)
      expect(result.message_key).to eq(Pito::Copy.render(
        "pito.copy.segments.unknown",
        tokens: "videos",
        names:  Pito::Chat::Segments.names(verb: :show, entity: :game).join(", ")
      ))
    end
  end

  # ── schema: the segment_of contract ─────────────────────────────────────────
  describe "segment_of schema validation" do
    # A minimal, otherwise-valid document: a `show`-like parent declaring a
    # `similar` game segment, plus a segment verb pointing at it.
    def document(segment_of)
      {
        schema_version: 1,
        verbs: {
          show: {
            chat: { dispatch: "Chat::Handlers::Show" },
            segments: { game: { "similar" => { builder: "MessageBuilder::X", kind: "enhanced", reply_target: "game_similar" } } }
          },
          myverb: {
            chat: { dispatch: "Chat::Handlers::SegmentVerb", segment_of: segment_of }
          }
        }
      }
    end

    def errors_for(segment_of)
      Pito::Dispatch::Schema.validate(document(segment_of)).map(&:to_s)
    end

    it "accepts a binding to an existing parent segment" do
      expect(errors_for({ verb: "show", segment: "similar" })).to eq([])
    end

    it "rejects a parent verb that declares no segments block" do
      expect(errors_for({ verb: "analyze", segment: "similar" }).join)
        .to match(/segment_of\.verb .*not a verb declaring a segments block/)
    end

    it "rejects a segment name absent from the parent" do
      expect(errors_for({ verb: "show", segment: "nope" }).join)
        .to match(/segment_of\.segment "nope" is not a segment of show/)
    end

    it "rejects unknown keys inside segment_of" do
      expect(errors_for({ verb: "show", segment: "similar", extra: 1 }).join)
        .to match(/segment_of\.extra: unknown key/)
    end

    it "rejects a missing required key" do
      expect(errors_for({ verb: "show" }).join).to match(/segment_of\.segment: missing required key/)
    end

    it "the real config validates and has no alias collisions" do
      doc = Pito::Dispatch::Config.data
      expect(Pito::Dispatch::Schema.validate(doc)).to eq([])
      expect(Pito::Dispatch::Schema.alias_collisions(doc)).to eq([])
    end
  end

  # ── palette / catalog derives from config ────────────────────────────────────
  describe "palette derives from config" do
    subject(:chat) { Pito::Suggestions::Catalog.to_h(authenticated: true)[:chat] }

    it "surfaces an `at-a-glance ` completion carrying its noun slot" do
      entry = chat.find { |e| e[:name] == "at-a-glance" }
      expect(entry).to be_present
      expect(entry[:insert]).to eq("at-a-glance ")
      expect(entry[:slots]).to eq([ { name: "noun", source: "nouns" } ])
    end

    it "surfaces all seven segment verbs" do
      names = chat.map { |e| e[:name] }
      expect(names).to include("at-a-glance", "videos", "linked-game", "similar", "linked-videos", "channels", "breakdowns")
    end
  end

  # ── the `linked` two-word forms (plan-0.9.5 E14) ─────────────────────────────
  #
  # ONE keyed verb where the NOUN names WHAT YOU GET (the segment) and the id is
  # the OTHER entity's, so `entity:` FORCES the parent's branch:
  #   linked game #vid  == show vid  #vid  only linked-game
  #   linked vids #game == show game #game only linked-videos
  # The one-word linked-game / linked-videos verbs AND link/unlink are unaffected.
  describe "the `linked` keyed verb" do
    describe "recognition — `linked` at position 1, distinct from link / linked-*" do
      { "linked game 1" => :linked, "linked vids 1" => :linked, "linked videos 1" => :linked }.each do |input, verb|
        it "#{input.inspect} → #{verb.inspect}, a :new_turn" do
          msg = parse(input)
          expect(msg.kind).to eq(:new_turn)
          expect(msg.verb).to eq(verb)
        end
      end

      # Negatives: `link`/`unlink` and the one-word segment verbs keep their verb —
      # the token distinction `link` ≠ `linked` and `linked` ≠ `linked-game` holds.
      {
        "link game 1 to vid 2"     => :link,
        "unlink game 1 from vid 2" => :unlink,
        "linked-game vid 1"        => :"linked-game",
        "linked-videos game 1"     => :"linked-videos"
      }.each do |input, verb|
        it "#{input.inspect} still parses to #{verb.inspect} (link ≠ linked; hyphenated verbs distinct)" do
          expect(parse(input).verb).to eq(verb)
        end
      end
    end

    describe "byte-identity — noun picks the segment, id is the OTHER entity" do
      let!(:channel) { create(:channel, handle: "e14") }
      let!(:game)    { create(:game) }
      let!(:video)   { create(:video, channel: channel) }
      let!(:link)    { create(:video_game_link, video: video, game: game) }

      # Same determinism pins as the flat byte-identity block above.
      before do
        allow(SecureRandom).to receive(:hex).and_wrap_original do |orig, *args|
          args == [ 4 ] ? "cafebabe" : orig.call(*args)
        end
        allow(Pito::HandleGenerator).to receive(:call).and_return("zeta-0000")
      end

      it "`linked game #vid` == `show vid #vid only linked-game`" do
        seg    = route("linked game ##{video.id}")
        parent = route("show vid ##{video.id} only linked-game")

        expect(seg).to be_a(Pito::Chat::Result::Ok)
        expect(seg.events).to eq(parent.events)
        expect(seg.events).not_to be_empty
      end

      it "`linked vids #game` == `show game #game only linked-videos`" do
        seg    = route("linked vids ##{game.id}")
        parent = route("show game ##{game.id} only linked-videos")

        expect(seg).to be_a(Pito::Chat::Result::Ok)
        expect(seg.events).to eq(parent.events)
        expect(seg.events).not_to be_empty
      end

      it "the `videos` noun synonym drives the vids branch (== linked-videos)" do
        seg    = route("linked videos ##{game.id}")
        parent = route("show game ##{game.id} only linked-videos")

        expect(seg.events).to eq(parent.events)
      end
    end

    describe "wrong ref — the parent's own not-found copy" do
      it "`linked game #<missing>` == `show vid #<missing> only linked-game` (videos not-found)" do
        seg    = route("linked game #999999")
        parent = route("show vid #999999 only linked-game")

        expect(seg.events).to eq(parent.events)
        expect(seg.events).not_to be_empty
      end
    end

    describe "no noun — a helpful rejection" do
      it "`linked #5` → the needs-noun usage hint (Error)" do
        result = route("linked #5")

        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.linked.needs_noun")
      end
    end

    # ── schema: the keyed segment_of contract ──────────────────────────────────
    describe "keyed segment_of schema validation" do
      # A minimal parent `show` declaring vid `linked-game` + game `linked-videos`,
      # plus a keyed segment verb pointing at them.
      def keyed_document(segment_of)
        {
          schema_version: 1,
          verbs: {
            show: {
              chat: { dispatch: "Chat::Handlers::Show" },
              segments: {
                vid:  { "linked-game"   => { builder: "MessageBuilder::X", kind: "enhanced", reply_target: "game_detail" } },
                game: { "linked-videos" => { builder: "MessageBuilder::Y", kind: "enhanced", reply_target: "game_linked_videos" } }
              }
            },
            linked: {
              chat: { dispatch: "Chat::Handlers::SegmentVerb", segment_of: segment_of }
            }
          }
        }
      end

      def keyed_errors(segment_of)
        Pito::Dispatch::Schema.validate(keyed_document(segment_of)).map(&:to_s)
      end

      it "accepts a per-noun keyed binding (entity-forced, with aliases)" do
        expect(keyed_errors(
          game: { verb: "show", segment: "linked-game",   entity: "vid" },
          vids: { verb: "show", segment: "linked-videos", entity: "game", aliases: [ "videos" ] }
        )).to eq([])
      end

      it "rejects an unknown entity in a branch" do
        expect(keyed_errors(game: { verb: "show", segment: "linked-game", entity: "nope" }).join)
          .to match(/segment_of\.game\.entity: invalid entity "nope"/)
      end

      it "rejects a segment that is not a segment of the FORCED entity" do
        # linked-videos is a game segment, not a vid segment.
        expect(keyed_errors(game: { verb: "show", segment: "linked-videos", entity: "vid" }).join)
          .to match(/segment_of\.segment "linked-videos" is not a segment of show for vid/)
      end

      it "rejects an unknown key inside a branch" do
        expect(keyed_errors(game: { verb: "show", segment: "linked-game", entity: "vid", extra: 1 }).join)
          .to match(/segment_of\.game\.extra: unknown key/)
      end

      it "rejects a branch missing the required entity key" do
        expect(keyed_errors(game: { verb: "show", segment: "linked-game" }).join)
          .to match(/segment_of\.game\.entity: missing required key/)
      end

      it "the real config (with `linked`) validates and has no alias collisions" do
        doc = Pito::Dispatch::Config.data
        expect(Pito::Dispatch::Schema.validate(doc)).to eq([])
        expect(Pito::Dispatch::Schema.alias_collisions(doc)).to eq([])
      end
    end

    describe "palette — `linked` surfaces from config" do
      subject(:chat) { Pito::Suggestions::Catalog.to_h(authenticated: true)[:chat] }

      it "includes `linked` carrying its noun slot" do
        entry = chat.find { |e| e[:name] == "linked" }
        expect(entry).to be_present
        expect(entry[:insert]).to eq("linked ")
        expect(entry[:slots]).to eq([ { name: "noun", source: "nouns" } ])
      end
    end
  end
end
