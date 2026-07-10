# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Suggestions::Engine, type: :service do
  # Registry is populated before every example by rails_helper before(:each).

  def call(**kwargs)
    described_class.call(**kwargs)
  end

  # ── MODE DETECTION ──────────────────────────────────────────────────────────

  describe "mode detection" do
    it "returns :none for empty input" do
      expect(call(input: "", cursor: 0)[:mode]).to eq(:none)
    end

    it "returns :none for whitespace-only input" do
      expect(call(input: "   ", cursor: 3)[:mode]).to eq(:none)
    end

    it "returns :slash for input starting with /" do
      expect(call(input: "/config", cursor: 7)[:mode]).to eq(:slash)
    end

    it "returns :hashtag for input starting with #" do
      expect(call(input: "#handle add", cursor: 11)[:mode]).to eq(:hashtag)
    end

    it "returns :free for plain text" do
      expect(call(input: "list upcoming", cursor: 13)[:mode]).to eq(:free)
    end
  end

  # ── SLASH — VERB STAGE ──────────────────────────────────────────────────────

  describe "slash mode — verb stage" do
    context "when authenticated: true" do
      it "prefix-matches /co → includes /config and /connect" do
        result = call(input: "/co", cursor: 3, authenticated: true)
        expect(result[:mode]).to eq(:slash)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).to include("/config", "/connect")
      end

      it "insert strings end with a space" do
        result = call(input: "/co", cursor: 3, authenticated: true)
        result[:menu_items].each do |item|
          expect(item[:insert]).to end_with(" ")
        end
      end

      it "excludes /login when authenticated" do
        result = call(input: "/", cursor: 1, authenticated: true)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).not_to include("/login")
      end

      it "includes /config when authenticated" do
        result = call(input: "/", cursor: 1, authenticated: true)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).to include("/config")
      end

      it "returns ghost: empty strings in slash mode" do
        result = call(input: "/co", cursor: 3, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
        expect(result[:ghost][:next_hint]).to eq("")
      end
    end

    context "when authenticated: false" do
      it "returns only /login" do
        result = call(input: "/", cursor: 1, authenticated: false)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).to eq([ "/login" ])
      end

      it "does not include /config when unauthenticated" do
        result = call(input: "/", cursor: 1, authenticated: false)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).not_to include("/config")
      end
    end

    context "menu_item shape" do
      it "has label, insert, description, and masked keys" do
        result = call(input: "/", cursor: 1, authenticated: true)
        item = result[:menu_items].first
        expect(item.keys).to include(:label, :insert, :description, :masked)
      end

      it "masked is false for verb-stage items" do
        result = call(input: "/", cursor: 1, authenticated: true)
        result[:menu_items].each do |item|
          expect(item[:masked]).to be(false)
        end
      end
    end
  end

  # ── SLASH — ARG STAGE (static) ──────────────────────────────────────────────

  describe "slash mode — arg stage (/config provider slot)" do
    it "suggests config providers after '/config '" do
      result = call(input: "/config ", cursor: 8, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("google", "voyage", "igdb", "webhook")
    end

    it "filters providers by partial prefix" do
      result = call(input: "/config g", cursor: 9, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("google")
      expect(labels).not_to include("voyage")
    end

    it "insert for a provider ends with a space" do
      result = call(input: "/config ", cursor: 8, authenticated: true)
      result[:menu_items].each do |item|
        expect(item[:insert]).to end_with(" ")
      end
    end

    it "mode is :slash" do
      result = call(input: "/config ", cursor: 8, authenticated: true)
      expect(result[:mode]).to eq(:slash)
    end

    # The provider list is browsable: tagged stage: :verb so the client renders
    # the whole set as a selectable palette (not just the top hit as a ghost).
    it "tags the provider slot stage: :verb (palette, not arg ghost)" do
      result = call(input: "/config ", cursor: 8, authenticated: true)
      expect(result[:stage]).to eq(:verb)
    end

    it "keeps stage: :verb while filtering providers by prefix ('/config g')" do
      result = call(input: "/config g", cursor: 9, authenticated: true)
      expect(result[:stage]).to eq(:verb)
    end
  end

  describe "slash mode — arg stage (/config kv slot)" do
    it "suggests config keys after provider is typed" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("client_id", "client_secret", "api_key")
    end

    it "sets masked: true for sensitive keys (client_id, client_secret, api_key)" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      masked_labels = result[:menu_items].select { |i| i[:masked] }.map { |i| i[:label] }
      expect(masked_labels).to include("client_id", "client_secret", "api_key")
    end

    it "sets masked: false for non-sensitive keys (redirect_uri, slack, discord)" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      non_masked = result[:menu_items].reject { |i| i[:masked] }.map { |i| i[:label] }
      expect(non_masked).to include("redirect_uri")
    end

    it "insert for a kv key ends with '='" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      result[:menu_items].each do |item|
        expect(item[:insert]).to end_with("=")
      end
    end

    it "does NOT suggest on/off after /config google (credential provider)" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).not_to include("on", "off")
    end

    # The per-provider key list is browsable: tagged stage: :verb so the client
    # renders it as a selectable palette (masked secrets stay masked).
    it "tags the kv key slot stage: :verb (palette, not arg ghost)" do
      result = call(input: "/config google ", cursor: 15, authenticated: true)
      expect(result[:stage]).to eq(:verb)
    end

    # Bug B — the palette must empty out so Enter SUBMITS instead of re-selecting
    # a key the user already supplied / is currently filling in.
    it "suggests nothing while typing a value (key=…)" do
      input = "/config voyage api_key=pa-secret"
      expect(call(input:, cursor: input.length, authenticated: true)[:menu_items]).to be_empty
    end

    it "excludes keys already supplied earlier in the line" do
      input  = "/config google client_id=x "
      labels = call(input:, cursor: input.length, authenticated: true)[:menu_items].map { |i| i[:label] }
      expect(labels).not_to include("client_id")
      expect(labels).to include("client_secret", "redirect_uri", "api_key")
    end

    it "offers nothing once every provider key is supplied" do
      input = "/config google client_id=a client_secret=b redirect_uri=c api_key=d "
      expect(call(input:, cursor: input.length, authenticated: true)[:menu_items]).to be_empty
    end
  end

  describe "slash mode — arg stage (/config sound|motion on/off slot)" do
    it "suggests on and off after '/config sound '" do
      result = call(input: "/config sound ", cursor: 14, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("on", "off")
    end

    it "does NOT suggest kv keys after '/config sound '" do
      result = call(input: "/config sound ", cursor: 14, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).not_to include("client_id", "client_secret", "api_key")
    end

    it "filters on/off by prefix after '/config sound o'" do
      result = call(input: "/config sound o", cursor: 15, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("on", "off")
    end

    it "insert for on/off ends with a space" do
      result = call(input: "/config sound ", cursor: 14, authenticated: true)
      result[:menu_items].each do |item|
        expect(item[:insert]).to end_with(" ")
      end
    end
  end

  describe "slash mode — arg stage (/config provider slot)" do
    it "suggests providers including sound after '/config ' (motion/fx removed — item 18)" do
      result = call(input: "/config ", cursor: 8, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("sound")
      expect(labels).not_to include("motion", "fx")
    end
  end

  # ── SLASH — unknown verb ─────────────────────────────────────────────────────

  describe "slash mode — unknown verb" do
    it "returns empty menu_items when no spec matches" do
      result = call(input: "/frobnicate ", cursor: 12, authenticated: true)
      expect(result[:menu_items]).to eq([])
    end
  end

  # ── FREE MODE ────────────────────────────────────────────────────────────────

  describe "free mode" do
    it "returns :free mode for non-slash, non-hash, non-empty input" do
      result = call(input: "list upc", cursor: 8, authenticated: true)
      expect(result[:mode]).to eq(:free)
    end

    it "returns empty menu_items in free mode" do
      result = call(input: "list upc", cursor: 8, authenticated: true)
      expect(result[:menu_items]).to eq([])
    end

    it "always returns EMPTY_GHOST in free mode (no inline completions)" do
      result = call(input: "find upc", cursor: 8, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("")
      expect(result[:ghost][:next_hint]).to eq("")
    end

    it "does not crash on any free-mode verb input" do
      %w[list ls show sync delete].each do |verb|
        expect { call(input: verb, cursor: verb.length, authenticated: true) }
          .not_to raise_error
      end
    end
  end

  # ── free mode — the VERB stage (G75, 1.1.0) ─────────────────────────────────
  #
  # Before 1.1.0 the palette ignored the verb position entirely (arg-stage
  # only, G33): typing "l"/"lis"/"analy" popped nothing. Now the first word
  # prefix-filters the chat catalog, alias-aware (G75b): one row per verb,
  # labeled by the matched token (canonical preferred), inserting what the
  # user typed — "ls" stays "ls ", never rewritten to "list".

  describe "free mode — verb stage (G75)" do
    it "offers chat verbs matching the typed prefix, stage :verb, alphabetical" do
      result = call(input: "lis", cursor: 3, authenticated: true)
      expect(result[:stage]).to eq(:verb)
      expect(result[:menu_items].map { |i| i[:label] }).to eq([ "list" ])
    end

    it "matches ALIASES too, keeping what the user typed (G75b: ls is not rewritten)" do
      result = call(input: "ls", cursor: 2, authenticated: true)
      item = result[:menu_items].find { |i| i[:label] == "ls" }
      expect(item).to be_present
      expect(item[:insert]).to eq("ls ")
    end

    it "offers ONE row per verb even when several of its tokens match (G75b dedup)" do
      # "break" matches both the canonical `breakdowns` and its `breakdown`
      # alias — one row, canonical label preferred.
      labels = call(input: "break", cursor: 5, authenticated: true)[:menu_items].map { |i| i[:label] }
      expect(labels).to eq([ "breakdowns" ])
    end

    it "narrows as the prefix grows" do
      broad  = call(input: "l", cursor: 1, authenticated: true)[:menu_items]
      narrow = call(input: "lin", cursor: 3, authenticated: true)[:menu_items]
      expect(broad.size).to be > narrow.size
      expect(narrow.map { |i| i[:label] }).to all(start_with("lin"))
    end

    it "returns nothing for a prefix matching no verb" do
      expect(call(input: "zzz", cursor: 3, authenticated: true)[:menu_items]).to eq([])
    end

    it "returns nothing for anonymous visitors (every chat verb is auth-gated at dispatch)" do
      expect(call(input: "l", cursor: 1, authenticated: false)[:menu_items]).to eq([])
    end

    it "leaves the ghost empty (palette-only, like every suggestion surface)" do
      result = call(input: "lis", cursor: 3, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("")
    end
  end

  # ── free mode — slot PROGRESSION (G32) ──────────────────────────────────────
  #
  # Regression: the walk only tracked introducer keywords, so a committed
  # plain slot ("ls games ") kept re-offering the first slot's vocabulary
  # forever. Committed tokens must FILL their slots (aliases included) and
  # suggestions must advance to what's still open.

  describe "free mode — slot progression (G32)" do
    def labels(text)
      call(input: text, cursor: text.length, authenticated: true)[:menu_items].map { |i| i[:label] }
    end

    it "offers the noun set at the first position" do
      expect(labels("ls ")).to eq(%w[channels games vids])
    end

    it "stops re-offering the noun once filled (`ls games ` → the kwarg openers, G33)" do
      expect(labels("ls games ")).not_to include("games", "vids", "channels")
      expect(labels("ls games ")).to eq([ "sorted by", "upcoming", "with" ])
    end

    it "fills a slot through an alias (`analyze vid ` → vids) and advances to the remaining introducer" do
      expect(labels("analyze vid ")).to eq(%w[without])
    end

    it "excludes committed members of a repeatable introduced slot" do
      with_members = labels("show game 5 with ")
      expect(with_members).to include("similar")

      after_similar = labels("show game 5 with similar ")
      expect(after_similar).not_to include("similar")
      expect(after_similar).to eq(with_members - %w[similar])
    end

    it "never re-offers the filled noun on analyze" do
      expect(labels("analyze vid ")).not_to include("vids", "games", "channels")
    end
  end

  # ── free mode — the #id gate (G37) ──────────────────────────────────────────
  #
  # A :free slot (show's id position) is a positional gate: slots declared
  # after it stay unsuggested until an id-looking token fills it — following
  # the palette could previously compose "show game full" with the id
  # silently skipped. Nouns don't fill the gate (structural, not the ref).

  describe "free mode — the #id gate (G37)" do
    def labels(text)
      call(input: text, cursor: text.length, authenticated: true)[:menu_items].map { |i| i[:label] }
    end

    it "offers nothing at `show ` — the id position is reserved" do
      expect(labels("show ")).to be_empty
    end

    it "offers nothing at `show game ` — a noun does not fill the gate" do
      expect(labels("show game ")).to be_empty
    end

    it "opens the selectors once an id fills the gate" do
      expect(labels("show game 5 ")).to eq(%w[full only with without])
      expect(labels("show game #12 ")).to eq(%w[full only with without])
    end

    it "does not gate verbs whose free slot comes after their enums (price)" do
      expect(labels("price ")).to eq(%w[set unset])
    end

    it "does not gate verbs without a free slot (analyze)" do
      expect(labels("analyze vid ")).to eq(%w[without])
    end
  end

  # ── free mode — `list` kwargs (G33) ─────────────────────────────────────────
  #
  # The list handler RAW-parses its kwargs (with-columns, sort clause,
  # upcoming/visibility filters) — they are not verbs.yml slots, so after the
  # noun the palette went silent. The engine now suggests the clause the
  # cursor is inside, from the same ListColumns vocabularies the tables use.

  describe "free mode — list kwargs (G33)" do
    def labels(text)
      call(input: text, cursor: text.length, authenticated: true)[:menu_items].map { |i| i[:label] }
    end

    it "offers the kwarg openers after the games noun" do
      expect(labels("ls games ")).to eq([ "sorted by", "upcoming", "with" ])
    end

    it "offers the vids visibility filters among the openers" do
      expect(labels("ls vids ")).to eq([ "published", "scheduled", "sorted by", "unlisted", "with" ])
    end

    it "consumes a committed filter token" do
      expect(labels("list games upcoming ")).to eq([ "sorted by", "with" ])
    end

    it "suggests the surface's columns inside `with `" do
      expect(labels("ls games with ")).to eq(%w[channel developer footage genre likes platform price publisher views])
    end

    it "excludes columns already committed in the with-clause" do
      expect(labels("ls games with platform, ")).not_to include("platform")
    end

    it "suggests channels' addable column inside `with `" do
      expect(labels("ls channels with ")).to eq(%w[likes])
    end

    it "suggests base sort tokens after `sorted by` (unsortable with-columns excluded)" do
      # platform is with-selected but has no sort key (G26.7) — never offered.
      expect(labels("ls games with platform sorted by ")).to eq(%w[id title])
    end

    it "includes a sortable with-selected column in the sort tokens" do
      expect(labels("ls games with price sorted by ")).to include("price")
    end

    it "offers asc/desc once the sort column is committed" do
      expect(labels("ls games with price sorted by price ")).to eq(%w[asc desc])
    end
  end

  describe "free mode — footage dynamic game_titles slot", :db do
    let!(:game) { create(:game, title: "Zelda") }

    it "returns game titles matching the partial (plan-0.9.5 E8: footage zel → Zelda)" do
      result = call(input: "footage zel", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("Zelda")
    end
  end

  describe "free mode — reindex dynamic game_titles slot", :db do
    let!(:game) { create(:game, title: "Zelda") }

    it "returns game titles matching the partial (plan-0.9.5 E8: reindex zel → Zelda)" do
      result = call(input: "reindex zel", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("Zelda")
    end
  end

  # ── FREE MODE — fixed ghost cases ────────────────────────────────────────────

  describe "free-mode ghost" do
    # Fully-resolved command — no spurious complete_current
    it "returns empty complete_current for a fully-typed command 'list upcoming RPG games for PS5'" do
      input = "list upcoming RPG games for PS5"
      result = call(input: input, cursor: input.length, authenticated: true)
      expect(result[:mode]).to eq(:free)
      expect(result[:ghost][:complete_current]).to eq("")
    end

    # Multi-genre + platform — all tokens resolve, no completion needed
    it "returns empty complete_current for 'list upcoming racing and rpg games for playstation'" do
      input = "list upcoming racing and rpg games for playstation"
      result = call(input: input, cursor: input.length, authenticated: true)
      expect(result[:mode]).to eq(:free)
      expect(result[:ghost][:complete_current]).to eq("")
    end

    # Unmatched verb — empty ghost
    it "returns empty ghost for unmatched verb 'frobnicate stuff'" do
      input = "frobnicate stuff"
      result = call(input: input, cursor: input.length, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("")
      expect(result[:ghost][:next_hint]).to eq("")
    end
  end

  # ── HASHTAG MODE ─────────────────────────────────────────────────────────────

  describe "hashtag mode" do
    it "returns :hashtag mode" do
      result = call(input: "#mychannel ", cursor: 11)
      expect(result[:mode]).to eq(:hashtag)
    end

    it "returns no menu items for a handle that has no live follow-up event (legacy path)" do
      # The :hashtag grammar add/remove specs have been removed; non-follow-up handles
      # yield no verb completions.
      result = call(input: "#mychannel ", cursor: 11)
      expect(result[:menu_items]).to be_empty
    end

    it "returns empty ghost for a handle that has no live follow-up event" do
      result = call(input: "#mychannel a", cursor: 12)
      expect(result[:ghost][:complete_current]).to eq("")
    end
  end

  # ── HASHTAG — follow-up-target aware ──────────────────────────────────────────
  describe "hashtag mode for a live follow-up handle", :db do
    let(:conversation) { Conversation.create! }
    let(:turn) { conversation.turns.create!(input_kind: :slash, input_text: "/games list", position: 1) }

    before do
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "alpha-1266", "reply_target" => "game_list", "body" => "games" }
      )
    end

    it "suggests the target's actions (show/delete/rm/with/without)" do
      result = call(input: "#alpha-1266 ", cursor: 12, conversation:)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("show", "delete", "rm", "with", "without")
    end

    it "returns EMPTY_GHOST in the reply-verb position (no inline ghost)" do
      result = call(input: "#alpha-1266 ", cursor: 12, conversation:)
      expect(result[:ghost][:complete_current]).to eq("")
      expect(result[:ghost][:next_hint]).to eq("")
    end

    it "returns no menu items when the handle isn't a live follow-up (no legacy hashtag specs)" do
      result = call(input: "#unknown-9999 ", cursor: 14, conversation:)
      expect(result[:menu_items]).to be_empty
    end
  end

  # ── Reply-verb PALETTE stage — the full allowed-verb set per reply_target ─────
  #
  # Regression guard: the engine must tag the reply-verb position stage: :verb and
  # return EVERY allowed action (not just `show`), so the client can render a
  # palette through which with/without/shinies/schedule/etc. are selectable.
  describe "hashtag follow-up: reply-verb palette stage", :db do
    let(:conversation) { Conversation.create! }
    let(:turn) { conversation.turns.create!(input_kind: :slash, input_text: "/list", position: 1) }

    before { Pito::FollowUp::Registry.register_all! }

    def stamp(handle, target)
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => handle, "reply_target" => target, "body" => "x" }
      )
    end

    it "tags the bare reply-verb position stage: :verb (palette, not ghost)" do
      stamp("vl-1", "video_list")
      result = call(input: "#vl-1 ", cursor: 6, conversation:)
      expect(result[:stage]).to eq(:verb)
    end

    it "tags a partially-typed reply verb stage: :verb" do
      stamp("vl-2", "video_list")
      result = call(input: "#vl-2 sh", cursor: 8, conversation:)
      expect(result[:stage]).to eq(:verb)
    end

    it "returns video_list's full verb set incl. schedule + with/without + shinies" do
      stamp("vl-3", "video_list")
      labels = call(input: "#vl-3 ", cursor: 6, conversation:)[:menu_items].map { |i| i[:label] }
      expect(labels).to include("show", "delete", "schedule", "publish", "unlist",
                                "with", "without", "sort", "order", "shinies")
    end

    it "returns game_list's full verb set incl. with/without + shinies" do
      stamp("gl-3", "game_list")
      labels = call(input: "#gl-3 ", cursor: 6, conversation:)[:menu_items].map { |i| i[:label] }
      expect(labels).to include("show", "with", "without", "sort", "order", "shinies")
    end

    it "returns video_detail's verb set (rm/reindex/link/shinies)" do
      stamp("vd-3", "video_detail")
      labels = call(input: "#vd-3 ", cursor: 6, conversation:)[:menu_items].map { |i| i[:label] }
      expect(labels).to include("rm", "delete", "reindex", "link", "unlink", "shinies")
    end

    it "returns channel_list's verb set (shinies; visit moved to channel_detail)" do
      stamp("cl-3", "channel_list")
      labels = call(input: "#cl-3 ", cursor: 6, conversation:)[:menu_items].map { |i| i[:label] }
      expect(labels).to include("shinies")
      expect(labels).not_to include("visit")
    end

    it "returns channel_detail's verb set (visit)" do
      stamp("cd-3", "channel_detail")
      labels = call(input: "#cd-3 ", cursor: 6, conversation:)[:menu_items].map { |i| i[:label] }
      expect(labels).to include("visit")
    end

    it "filters the palette by the typed verb prefix and keeps stage: :verb" do
      stamp("gl-4", "game_list")
      result = call(input: "#gl-4 wi", cursor: 8, conversation:)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("with", "without")
      expect(labels).not_to include("show")
      expect(result[:stage]).to eq(:verb)
    end

    it "keeps stage: :arg once a NO-ARG verb is finalised (a second space)" do
      stamp("gl-5", "game_list")
      result = call(input: "#gl-5 next ", cursor: 11, conversation:)
      expect(result[:stage]).to eq(:arg)
      expect(result[:menu_items]).to be_empty
    end

    it "tags stage: :verb with argument items once an ARG verb is finalised (E13)" do
      stamp("gl-6", "game_list")
      result = call(input: "#gl-6 with ", cursor: 11, conversation:)
      expect(result[:stage]).to eq(:verb)
      expect(result[:menu_items]).not_to be_empty
    end

    it "each palette item inserts `<verb> ` (spliced over the partial verb token)" do
      stamp("vl-6", "video_list")
      items = call(input: "#vl-6 ", cursor: 6, conversation:)[:menu_items]
      schedule = items.find { |i| i[:label] == "schedule" }
      expect(schedule[:insert]).to eq("schedule ")
    end
  end

  # ── Reply ARG-stage argument suggestions (plan-0.9.5 E13) ─────────────────────
  #
  # After `#handle <verb> ` the palette suggests the verb's possible ARGUMENT
  # tokens for the source message's reply_target — config-driven from the verb's
  # declared reply branch (ref/args resolvers in config/pito/verbs.yml).
  describe "hashtag follow-up: arg-stage argument suggestions", :db do
    let(:conversation) { Conversation.create! }
    let(:turn) { conversation.turns.create!(input_kind: :chat, input_text: "list games", position: 1) }

    before { Pito::FollowUp::Registry.register_all! }

    def stamp(handle, target, extra = {})
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => handle, "reply_target" => target, "body" => "x" }.merge(extra)
      )
    end

    def labels(input, cursor)
      call(input:, cursor:, conversation:)[:menu_items].map { |i| i[:label] }
    end

    context "columns — with/without on list targets" do
      before { stamp("gl-1", "game_list", "list_columns" => %w[genre]) }

      it "suggests the surface's ADDABLE column tokens for `with` (visible columns excluded)" do
        expect(labels("#gl-1 with ", 11)).to eq(%w[channel developer footage likes platform price publisher views])
      end

      it "suggests the REMOVABLE (visible) column tokens for `without`" do
        expect(labels("#gl-1 without ", 14)).to eq(%w[genre])
      end

      it "narrows by the mid-token prefix" do
        expect(labels("#gl-1 with p", 12)).to eq(%w[platform price publisher])
      end

      it "excludes column tokens already typed in the reply" do
        expect(labels("#gl-1 with platform ", 20)).to eq(%w[channel developer footage likes price publisher views])
      end

      it "tags a non-empty argument menu stage: :verb (browsable palette)" do
        result = call(input: "#gl-1 with ", cursor: 11, conversation:)
        expect(result[:stage]).to eq(:verb)
      end

      it "uses the VIDEO surface's display tokens on video_list (duration canonical, comms gone — G26; publish_at — U6)" do
        stamp("vl-1", "video_list", "list_columns" => %w[views])
        expect(labels("#vl-1 with ", 11)).to eq(%w[category channel duration game likes publish_at visibility])
      end

      it "derives game_linked_videos columns from the VIDEO surface" do
        stamp("lv-1", "game_linked_videos", "list_columns" => [])
        expect(labels("#lv-1 without ", 14)).to be_empty
        expect(labels("#lv-1 with ", 11)).to include("duration", "views")
        expect(labels("#lv-1 with ", 11)).not_to include("comms", "comments", "length")
      end
    end

    context "price openers — price on a game detail card (G31)" do
      it "suggests set/unset at the first argument position" do
        stamp("gd-price", "game_detail")
        expect(labels("#gd-price price ", 16)).to eq(%w[set unset])
      end

      it "offers nothing once a token is committed (the amount is free-form)" do
        stamp("gd-price2", "game_detail")
        expect(labels("#gd-price2 price set ", 21)).to be_empty
      end
    end

    context "sort keys — sort/order on list targets" do
      it "suggests base + visible columns' sort tokens on game_list" do
        stamp("gl-2", "game_list", "list_columns" => %w[price])
        expect(labels("#gl-2 sort ", 11)).to eq(%w[id price title])
      end

      it "honours the `order` alias" do
        stamp("gl-2b", "game_list", "list_columns" => %w[price])
        expect(labels("#gl-2b order ", 13)).to eq(%w[id price title])
      end

      # G82: counters sort only while visible — real payloads always stamp the
      # selection (subs/views/vids by default), so the completions mirror it.
      it "suggests identity + the stamped visible columns on channel_list" do
        stamp("cl-1", "channel_list", "list_columns" => %w[subs views vids])
        expect(labels("#cl-1 sort ", 11)).to eq(%w[handle subs title vids views])
      end

      it "offers only identity sorts when every counter was without-ed away" do
        stamp("cl-1b", "channel_list", "list_columns" => [])
        expect(labels("#cl-1b sort ", 12)).to eq(%w[handle title])
      end

      it "treats the leading `by` particle as transparent" do
        stamp("cl-2", "channel_list", "list_columns" => %w[subs views vids])
        expect(labels("#cl-2 sort by ", 14)).to eq(%w[handle subs title vids views])
      end

      it "suggests nothing once the sort column is committed" do
        stamp("cl-9", "channel_list")
        result = call(input: "#cl-9 sort views ", cursor: 17, conversation:)
        expect(result[:menu_items]).to be_empty
        expect(result[:stage]).to eq(:arg)
      end
    end

    context "metrics — with/without on analyze surfaces" do
      it "suggests metric tokens for `with` on analyze_message" do
        stamp("aa-1", "analyze_message")
        expect(labels("#aa-1 with ", 11)).to eq([ "ctr", "subs", "views", "watch time" ])
      end

      it "suggests metric tokens for `without` on analytics_glance" do
        stamp("ag-1", "analytics_glance")
        expect(labels("#ag-1 without ", 14)).to eq([ "ctr", "subs", "views", "watch time" ])
      end

      it "excludes metrics already typed (aliases resolved)" do
        stamp("aa-2", "analyze_message")
        expect(labels("#aa-2 with subscribers ", 23)).to eq([ "ctr", "views", "watch time" ])
      end
    end

    context "row ids — verbs whose ref is a list row id" do
      before do
        stamp("gl-3r", "game_list",
              "list_columns" => [],
              "table_rows"   => [
                { "cells" => [ { "text" => "#12" }, { "text" => "A" } ] },
                { "cells" => [ { "text" => "#3" },  { "text" => "B" } ] },
                { "cells" => [ { "text" => "#1" },  { "text" => "C" } ] }
              ])
      end

      it "suggests the source list's row ids for `show` (numeric ascending)" do
        expect(labels("#gl-3r show ", 12)).to eq(%w[#1 #3 #12])
      end

      it "suggests row ids for `delete` via its rm alias" do
        expect(labels("#gl-3r rm ", 10)).to eq(%w[#1 #3 #12])
      end

      it "inserts the id token with a trailing space" do
        items = call(input: "#gl-3r show ", cursor: 12, conversation:)[:menu_items]
        expect(items.first[:insert]).to eq("#1 ")
      end

      it "narrows by a typed partial with or without the # prefix" do
        expect(labels("#gl-3r show 1", 13)).to eq(%w[#1 #12])
        expect(labels("#gl-3r show #1", 14)).to eq(%w[#1 #12])
      end

      it "stops suggesting once the row id is committed" do
        expect(labels("#gl-3r show 3 ", 14)).to be_empty
      end

      it "suggests the row id first for verbs that interleave id + value (price)" do
        expect(labels("#gl-3r price ", 13)).to eq(%w[#1 #3 #12])
        # After the row id, the enumerable openers follow (G31); the amount
        # itself stays free-form.
        expect(labels("#gl-3r price 3 ", 15)).to eq(%w[set unset])
        expect(labels("#gl-3r price 3 set ", 19)).to be_empty
      end
    end

    context "declared args enums — visit destination" do
      it "suggests the visit_destinations vocabulary on channel_detail" do
        stamp("cd-9", "channel_detail", "channel_id" => 1)
        expect(labels("#cd-9 visit ", 12)).to eq(%w[channel studio])
      end
    end

    context "no-arg / undeclared verbs" do
      it "returns an empty :arg menu for a verb with no reply-branch config (share)" do
        stamp("gl-4n", "game_list")
        result = call(input: "#gl-4n share ", cursor: 13, conversation:)
        expect(result[:menu_items]).to be_empty
        expect(result[:stage]).to eq(:arg)
      end
    end
  end

  # filter_link_unlink is a pass-through: both link and unlink are always
  # included in the palette regardless of whether a VideoGameLink exists.
  describe "hashtag follow-up: game_detail palette always includes both link and unlink", :db do
    let(:conversation) { Conversation.create! }
    let(:turn)         { conversation.turns.create!(input_kind: :chat, input_text: "show game x", position: 1) }
    let(:game)         { create(:game, title: "Dead Space") }

    before do
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "dead-1000", "reply_target" => "game_detail", "game_id" => game.id, "body" => "card" }
      )
    end

    def labels
      call(input: "#dead-1000 ", cursor: 11, conversation:)[:menu_items].map { |i| i[:label] }
    end

    it "includes both link and unlink when the game has no linked video" do
      expect(labels).to include("link", "unlink")
    end

    it "includes both link and unlink when the game is already linked to a video" do
      create(:video_game_link, game:, video: create(:video, :public, channel: create(:channel)))
      expect(labels).to include("link", "unlink")
    end
  end

  # filter_link_unlink is a pass-through: list handles that declare link and
  # unlink in self.actions always expose both, regardless of link-state.
  describe "hashtag follow-up: list handle palette includes both link and unlink", :db do
    let(:conversation) { Conversation.create! }

    before { Pito::FollowUp::Registry.register_all! }

    context "game_list" do
      let(:turn) { conversation.turns.create!(input_kind: :slash, input_text: "/list games", position: 1) }

      before do
        Event.create_with_position!(
          conversation:, turn:, kind: "system",
          payload: { "reply_handle" => "glink-1001", "reply_target" => "game_list", "body" => "games" }
        )
      end

      it "includes both link and unlink in the action palette" do
        result = call(input: "#glink-1001 ", cursor: 12, conversation:)
        expect(result[:menu_items].map { |i| i[:label] }).to include("link", "unlink")
      end
    end

    context "video_list" do
      let(:turn) { conversation.turns.create!(input_kind: :slash, input_text: "/list videos", position: 1) }

      before do
        Event.create_with_position!(
          conversation:, turn:, kind: "system",
          payload: { "reply_handle" => "vlink-1002", "reply_target" => "video_list", "body" => "videos" }
        )
      end

      it "includes both link and unlink in the action palette" do
        result = call(input: "#vlink-1002 ", cursor: 12, conversation:)
        expect(result[:menu_items].map { |i| i[:label] }).to include("link", "unlink")
      end
    end
  end

  # shinies appears in the action palette for all five follow-up source types.
  describe "hashtag follow-up: shinies offered for game_detail", :db do
    let(:conversation) { Conversation.create! }
    let(:turn)         { conversation.turns.create!(input_kind: :chat, input_text: "show game x", position: 1) }
    let!(:game)        { create(:game, title: "Hollow Knight") }

    before do
      Pito::FollowUp::Registry.register_all!
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "gdet-8888", "reply_target" => "game_detail", "game_id" => game.id, "body" => "card" }
      )
    end

    it "includes shinies in the action palette when replying to a game_detail event" do
      result = call(input: "#gdet-8888 ", cursor: 11, conversation:)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("shinies")
    end
  end

  # `schedule` is a declared video_list reply action, so it must appear in the
  # reply-verb palette.
  describe "hashtag follow-up: schedule verb for video_list", :db do
    let(:conversation) { Conversation.create! }
    let(:turn)         { conversation.turns.create!(input_kind: :slash, input_text: "/list videos", position: 1) }

    before do
      Pito::FollowUp::Registry.register_all!
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "vsched-7777", "reply_target" => "video_list", "body" => "videos" }
      )
    end

    it "includes schedule in the reply-verb action palette" do
      result = call(input: "#vsched-7777 ", cursor: 13, conversation:)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("schedule")
    end
  end

  # schedule IS a declared video_detail action (0.8.5 video-card ops), so it is
  # offered in the reply-verb palette for a video_detail reply.
  describe "hashtag follow-up: schedule offered for video_detail", :db do
    let(:conversation) { Conversation.create! }
    let(:turn)         { conversation.turns.create!(input_kind: :chat, input_text: "show vid x", position: 1) }
    let!(:video)       { create(:video, :public, channel: create(:channel)) }

    before do
      Pito::FollowUp::Registry.register_all!
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "vdet-6666", "reply_target" => "video_detail", "video_id" => video.id, "body" => "card" }
      )
    end

    it "includes schedule (and the other video-card ops) in the reply-verb action palette" do
      result = call(input: "#vdet-6666 ", cursor: 11, conversation:)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("schedule")
      expect(labels).to include("publish", "unlist", "sync")
    end
  end

  # ── DYNAMIC SLOTS — :channels ─────────────────────────────────────────────────

  describe "dynamic slot — :channels (/disconnect)", :db do
    let!(:channel) { create(:channel, handle: "@alpha") }

    # Non-config slash args return empty menu_items (only /config offers a
    # browsable palette; all other slash arg stages return nothing).
    it "returns NO menu_items for non-config slash args (auth or not)" do
      result = call(input: "/disconnect @al", cursor: 15, authenticated: true)
      expect(result[:menu_items]).to be_empty
    end

    it "returns NO menu_items when not authenticated" do
      result = call(input: "/disconnect @al", cursor: 15, authenticated: false)
      expect(result[:menu_items]).to be_empty
    end

    # Scoping guard: only `/config` args become a palette. Other slash args (here
    # the dynamic :channels slot) keep stage: :arg.
    it "keeps stage: :arg for non-config slash args (/disconnect)" do
      result = call(input: "/disconnect @al", cursor: 15, authenticated: true)
      expect(result[:stage]).to eq(:arg)
    end
  end

  # ── DYNAMIC SLOTS — :game_titles ─────────────────────────────────────────────

  describe "dynamic slot — :game_titles", :db do
    let!(:game) { create(:game, title: "Alpha Quest") }

    # Game titles appear in the :chat namespace via specs that use a :game_title slot.
    # However, the static chat specs use :genres/:platforms/:release_status.
    # The game_titles dynamic vocab is tested here via direct vocab lookup.
    # We verify that unauthenticated users CAN get game_titles (not auth-gated).
    it "resolves :game_titles for unauthenticated users (not auth-gated)" do
      vocab = Pito::Grammar::Registry.vocabulary(:game_titles)
      expect(vocab).not_to be_nil
      expect(vocab).to be_dynamic

      # Engine's suggest_dynamic should work for game_titles without auth.
      # Test via suggest_dynamic directly (white-box):
      result = described_class.send(
        :suggest_dynamic, vocab, :game_titles, "Alpha", authenticated: false
      )
      labels = result.map { |i| i[:label] }
      expect(labels).to include("Alpha Quest")
    end

    it "resolves :game_titles for authenticated users" do
      vocab = Pito::Grammar::Registry.vocabulary(:game_titles)
      result = described_class.send(
        :suggest_dynamic, vocab, :game_titles, "Alpha", authenticated: true
      )
      labels = result.map { |i| i[:label] }
      expect(labels).to include("Alpha Quest")
    end
  end

  # ── DYNAMIC SLOTS — :conversations (auth-gated) ───────────────────────────────

  describe "dynamic slot — :conversations (auth-gated)", :db do
    let!(:conversation_record) { create(:conversation) }

    it "auth-gates :conversations — returns empty for unauthenticated" do
      vocab = Pito::Grammar::Registry.vocabulary(:conversations)
      result = described_class.send(
        :suggest_dynamic, vocab, :conversations, "", authenticated: false
      )
      expect(result).to be_empty
    end

    it "resolves :conversations for authenticated users" do
      vocab = Pito::Grammar::Registry.vocabulary(:conversations)
      result = described_class.send(
        :suggest_dynamic, vocab, :conversations, "", authenticated: true
      )
      # Should include the uuid of the created conversation.
      labels = result.map { |i| i[:label] }
      expect(labels).to include(conversation_record.uuid)
    end
  end

  # ── ERROR RESILIENCE ──────────────────────────────────────────────────────────

  describe "error resilience" do
    it "returns empty menu_items when the dynamic resolver raises" do
      bad_vocab = Pito::Grammar::Vocabulary.define(
        name:     :bad_test_vocab,
        dynamic:  true,
        resolver: ->(_ctx) { raise "boom" }
      )
      result = described_class.send(
        :suggest_dynamic, bad_vocab, :bad_test_vocab, "", authenticated: true
      )
      expect(result).to eq([])
    end
  end

  # ── RETURN SHAPE ─────────────────────────────────────────────────────────────

  describe "return shape" do
    it "always has mode, menu_items, and ghost keys" do
      result = call(input: "", cursor: 0)
      expect(result.keys).to include(:mode, :menu_items, :ghost)
    end

    it "ghost always has complete_current and next_hint keys" do
      result = call(input: "", cursor: 0)
      expect(result[:ghost].keys).to include(:complete_current, :next_hint)
    end

    it "menu_items is always an Array" do
      result = call(input: "", cursor: 0)
      expect(result[:menu_items]).to be_an(Array)
    end
  end

  # ── GHOST — cursor position (valid cases only) ────────────────────────────────

  describe "ghost text — cursor position variants" do
    context "cursor at end of a fully-typed word (no partial suffix)" do
      it "returns empty complete_current for 'list upcoming'" do
        result = call(input: "list upcoming", cursor: 13, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end
    end

    context "no match for the partial" do
      it "returns empty ghost when partial matches nothing" do
        result = call(input: "list zzz", cursor: 8, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
        expect(result[:ghost][:next_hint]).to eq("")
      end
    end
  end

  # ── GHOST — provider-name menu items in slash arg stage ──────────────────

  describe "slash mode — provider prefix menu_items (/config goo → google)" do
    # In slash arg-stage the ghost text comes from the debounced server fetch
    # (not locally computed), so Engine#call returns ghost: "" — the JS controller
    # overlays the ghost after receiving the fetch response.
    # The engine does however produce menu_items for the prefix; that is what we
    # assert here.

    it "suggests 'google' via menu_items for '/config goo'" do
      result = call(input: "/config goo", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("google")
    end

    it "does not include 'voyage' for '/config goo'" do
      result = call(input: "/config goo", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).not_to include("voyage")
    end

    it "suggests 'google' via menu_items for '/config g'" do
      result = call(input: "/config g", cursor: 9, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("google")
    end

    it "slash arg-stage ghost is empty" do
      result = call(input: "/config goo", cursor: 11, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("")
    end

    it "insert for the provider ends with a space" do
      result = call(input: "/config goo", cursor: 11, authenticated: true)
      item = result[:menu_items].find { |i| i[:label] == "google" }
      expect(item[:insert]).to end_with(" ")
    end
  end

  # ── Partial kv-key: palette menu items still scoped; ghost is always empty ───

  describe "slash mode — partial kv-key ghost completion" do
    context "ambiguous prefix (matches >1 key)" do
      it "returns empty ghost for '/config igdb cl' (client_id and client_secret both match)" do
        result = call(input: "/config igdb cl", cursor: 15, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end

      it "returns empty ghost for '/config google cl' (client_id and client_secret both match)" do
        result = call(input: "/config google cl", cursor: 17, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end
    end

    context "non-matching prefix" do
      it "returns empty ghost for '/config igdb xyz'" do
        result = call(input: "/config igdb xyz", cursor: 16, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end
    end

    context "key already typed (partial has '=')" do
      it "returns empty ghost for '/config igdb client_id='" do
        result = call(input: "/config igdb client_id=", cursor: 23, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end
    end

    context "menu items are provider-scoped when partial is typed" do
      it "restricts menu items to igdb keys for '/config igdb client_s'" do
        result = call(input: "/config igdb client_s", cursor: 21, authenticated: true)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).to include("client_secret")
        expect(labels).not_to include("redirect_uri", "api_key", "slack", "discord")
      end

      it "restricts menu items to google keys for '/config google redi'" do
        result = call(input: "/config google redi", cursor: 19, authenticated: true)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).to include("redirect_uri")
        expect(labels).not_to include("slack", "discord", "client_id")
      end

      it "shows all igdb keys when no partial is typed yet" do
        result = call(input: "/config igdb ", cursor: 13, authenticated: true)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).to include("client_id", "client_secret")
        expect(labels).not_to include("redirect_uri", "api_key", "slack", "discord")
      end
    end
  end

  # ── Suggestions stop when all non-repeatable slots are filled ────────────────

  describe "suggestions stop after single-slot commands are satisfied" do
    before { Pito::Grammar::Registry.reset!; Pito::Grammar::Registry.register_all! }
    after  { Pito::Grammar::Registry.reset! }

    context "/themes — no positional slots (suggestions always empty after '/themes ')" do
      it "yields NO suggestions after '/themes ' (no slots to fill)" do
        result = call(input: "/themes ", cursor: 8, authenticated: true)
        expect(result[:menu_items]).to be_empty
      end
    end

    context "/config google kv slot — repeatable, continues to suggest keys" do
      it "still suggests kv keys after '/config google client_id=x '" do
        result = call(input: "/config google client_id=x ", cursor: 27, authenticated: true)
        labels = result[:menu_items].map { |i| i[:label] }
        expect(labels).not_to be_empty
        expect(labels).to include("client_secret", "redirect_uri", "api_key")
      end
    end

    context "/config sound — non-repeatable enum slot" do
      it "yields NO suggestions after '/config sound on '" do
        result = call(input: "/config sound on ", cursor: 17, authenticated: true)
        expect(result[:menu_items]).to be_empty
      end
    end
  end

  # ── FREE MODE — chat verb slot palette suggestions (plan-0.9.5 E8/D5) ─────────
  #
  # Every chat verb's declared enum kwargs now autosuggest once the verb is
  # committed (a space has been typed after it).  Ghost text is always empty
  # (removed owner 2026-06-29); only menu_items are populated.

  describe "free mode — list/ls noun slot" do
    it "suggests all nouns after 'list '" do
      result = call(input: "list ", cursor: 5, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("channels", "vids", "games")
    end

    it "filters nouns by prefix ('list g' → games only)" do
      result = call(input: "list g", cursor: 6, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("games")
      expect(labels).not_to include("channels", "vids")
    end

    it "suggests nouns for the 'ls' alias" do
      result = call(input: "ls ", cursor: 3, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("channels", "vids", "games")
    end

    it "tags stage: :verb for the palette" do
      result = call(input: "list ", cursor: 5, authenticated: true)
      expect(result[:stage]).to eq(:verb)
    end

    it "insert strings end with a space" do
      result = call(input: "list ", cursor: 5, authenticated: true)
      result[:menu_items].each { |i| expect(i[:insert]).to end_with(" ") }
    end

    it "returns items sorted alphabetically" do
      result = call(input: "list ", cursor: 5, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to eq(labels.sort_by(&:downcase))
    end
  end

  describe "free mode — show full/with/only slots" do
    it "suggests full, with, only before any introducer is typed ('show game 5 ')" do
      result = call(input: "show game 5 ", cursor: 12, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("full", "with", "only")
    end

    it "tags stage: :verb when suggestions are present" do
      result = call(input: "show game 5 ", cursor: 12, authenticated: true)
      expect(result[:stage]).to eq(:verb)
    end

    it "returns items sorted alphabetically (full, only, with)" do
      result = call(input: "show game 5 ", cursor: 12, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to eq(labels.sort_by(&:downcase))
    end

    it "suggests show_segments after 'show game 5 with '" do
      result = call(input: "show game 5 with ", cursor: 17, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("at-a-glance", "channels", "detail",
                                "game", "games", "similar", "videos")
      expect(labels).not_to include("full", "only")
    end

    it "suggests show_segments after 'show game 5 only '" do
      result = call(input: "show game 5 only ", cursor: 17, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("at-a-glance", "detail", "videos")
      expect(labels).not_to include("full", "with")
    end

    it "filters segment names by partial ('show game 5 with det' → detail)" do
      result = call(input: "show game 5 with det", cursor: 20, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("detail")
      expect(labels).not_to include("channels", "videos")
    end

    it "filters introducer keywords by partial ('show game 5 wi' → with)" do
      result = call(input: "show game 5 wi", cursor: 14, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("with")
      expect(labels).not_to include("only", "full")
    end

    it "last-typed introducer wins — 'show game 5 with detail only ' → only's segments" do
      result = call(input: "show game 5 with detail only ", cursor: 29, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("at-a-glance", "detail", "videos")
      # The :only slot's vocab is shown (same source as :with — show_segments).
      expect(labels).not_to include("full", "with")
    end
  end

  describe "free mode — analyze/analytics/stats noun slot" do
    it "suggests all nouns after 'analyze '" do
      result = call(input: "analyze ", cursor: 8, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("channels", "vids", "games")
    end

    it "suggests nouns for the 'analytics' alias" do
      result = call(input: "analytics ", cursor: 10, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("channels", "vids", "games")
    end

    it "suggests nouns for the 'stats' alias" do
      result = call(input: "stats ", cursor: 6, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("channels", "vids", "games")
    end
  end

  describe "free mode — import noun slot" do
    it "suggests 'game' after 'import '" do
      result = call(input: "import ", cursor: 7, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("game")
    end

    it "does not suggest 'games' (canonical is 'game' only)" do
      result = call(input: "import ", cursor: 7, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).not_to include("games")
    end
  end

  describe "free mode — sync target slot" do
    it "suggests sync targets after 'sync '" do
      result = call(input: "sync ", cursor: 5, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("channels", "vids")
    end

    it "filters targets by prefix ('sync c' → channels)" do
      result = call(input: "sync c", cursor: 6, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("channels")
      expect(labels).not_to include("vids")
    end
  end

  describe "free mode — footage game_titles dynamic slot", :db do
    let!(:game) { create(:game, title: "Celeste") }

    it "returns game titles matching the partial ('footage cel' → Celeste)" do
      result = call(input: "footage cel", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("Celeste")
    end

    it "tags stage: :verb for the dynamic palette" do
      result = call(input: "footage cel", cursor: 11, authenticated: true)
      expect(result[:stage]).to eq(:verb)
    end
  end

  describe "free mode — price subcommand slot" do
    it "suggests set and unset after 'price '" do
      result = call(input: "price ", cursor: 6, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("set", "unset")
    end

    it "filters subcommands by prefix ('price s' → set)" do
      result = call(input: "price s", cursor: 7, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("set")
      expect(labels).not_to include("unset")
    end
  end

  describe "free mode — delete/rm/del game_titles dynamic slot", :db do
    let!(:game) { create(:game, title: "Dark Souls") }

    it "suggests game titles matching the partial ('delete dark' → Dark Souls)" do
      result = call(input: "delete dark", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("Dark Souls")
    end

    it "suggests game titles for the 'rm' alias" do
      result = call(input: "rm dark", cursor: 7, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("Dark Souls")
    end

    it "suggests game titles for the 'del' alias" do
      result = call(input: "del dark", cursor: 8, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("Dark Souls")
    end
  end

  describe "free mode — reindex game_titles dynamic slot", :db do
    let!(:game) { create(:game, title: "Hollow Knight") }

    it "suggests game titles matching the partial ('reindex hol' → Hollow Knight)" do
      result = call(input: "reindex hol", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("Hollow Knight")
    end
  end

  describe "free mode — platform subcommand slot" do
    it "suggests set and unset after 'platform '" do
      result = call(input: "platform ", cursor: 9, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("set", "unset")
    end
  end

  describe "free mode — schedule slate slot" do
    it "suggests 'slate' after 'schedule some-id '" do
      result = call(input: "schedule some-id ", cursor: 17, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("slate")
    end

    it "filters 'slate' by partial ('schedule some-id sl' → slate)" do
      result = call(input: "schedule some-id sl", cursor: 19, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("slate")
    end
  end

  describe "free mode — find status/genre/platform slots" do
    it "suggests release_status members, genre names, and 'for' after 'find '" do
      result = call(input: "find ", cursor: 5, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("released", "upcoming", "tba")
      expect(labels).to include("Shooter", "RPG", "Racing")
      expect(labels).to include("for")
    end

    it "returns items sorted alphabetically" do
      result = call(input: "find ", cursor: 5, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to eq(labels.sort_by(&:downcase))
    end

    it "suggests platform names after 'find for '" do
      result = call(input: "find for ", cursor: 9, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("PlayStation 5", "Nintendo Switch", "PC")
      expect(labels).not_to include("released", "upcoming", "Shooter")
    end

    it "filters platform names by partial ('find for pl' → PlayStation names)" do
      result = call(input: "find for pl", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("PlayStation 5", "PlayStation 4")
      expect(labels).not_to include("PC", "Nintendo Switch")
    end

    it "filters 'for' introducer by partial ('find fo' → for)" do
      result = call(input: "find fo", cursor: 7, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("for")
      expect(labels).not_to include("released", "Shooter")
    end
  end

  describe "free mode — verbs with no suggestable slots yield empty menu_items" do
    it "returns empty for 'publish ' (free slot only)" do
      result = call(input: "publish ", cursor: 8, authenticated: true)
      expect(result[:menu_items]).to be_empty
    end

    it "returns empty for 'link ' (free slot only)" do
      result = call(input: "link ", cursor: 5, authenticated: true)
      expect(result[:menu_items]).to be_empty
    end

    it "returns empty for 'unlink ' (free slot only)" do
      result = call(input: "unlink ", cursor: 7, authenticated: true)
      expect(result[:menu_items]).to be_empty
    end

    it "returns empty for 'help ' (no slots)" do
      result = call(input: "help ", cursor: 5, authenticated: true)
      expect(result[:menu_items]).to be_empty
    end

    it "returns empty for unknown verb 'frobnicate '" do
      result = call(input: "frobnicate ", cursor: 11, authenticated: true)
      expect(result[:menu_items]).to be_empty
    end

    it "mode stays :free even when items are returned" do
      result = call(input: "list ", cursor: 5, authenticated: true)
      expect(result[:mode]).to eq(:free)
    end
  end
end
