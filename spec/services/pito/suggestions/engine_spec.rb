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

    it "suggests on and off after '/config motion '" do
      result = call(input: "/config motion ", cursor: 15, authenticated: true)
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

  describe "slash mode — arg stage (/config fx <effect> slot)" do
    it "suggests the reveal effects after '/config fx '" do
      result = call(input: "/config fx ", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("typewriter", "scramble", "comet")
    end

    it "does NOT suggest on/off after '/config fx '" do
      result = call(input: "/config fx ", cursor: 11, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).not_to include("on", "off")
    end
  end

  describe "slash mode — arg stage (/config provider slot)" do
    it "suggests providers including sound, motion, and fx after '/config '" do
      result = call(input: "/config ", cursor: 8, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("sound", "motion", "fx")
    end
  end

  # ── SLASH — unknown verb ─────────────────────────────────────────────────────

  describe "slash mode — unknown verb" do
    it "returns empty menu_items when no spec matches" do
      result = call(input: "/frobnicate ", cursor: 12, authenticated: true)
      expect(result[:menu_items]).to eq([])
    end
  end

  # ── FREE MODE — ghost text ───────────────────────────────────────────────────

  describe "free mode — ghost text" do
    it "returns :free mode for non-slash, non-hash, non-empty input" do
      result = call(input: "list upc", cursor: 8, authenticated: true)
      expect(result[:mode]).to eq(:free)
    end

    it "returns empty menu_items in free mode" do
      result = call(input: "list upc", cursor: 8, authenticated: true)
      expect(result[:menu_items]).to eq([])
    end

    describe "complete_current" do
      it "completes 'upc' → 'oming' for the :status slot in 'find upc'" do
        result = call(input: "find upc", cursor: 8, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("oming")
      end

      it "completes the unambiguous :status partial in 'find u'" do
        # :status vocab has 'released', 'upcoming', 'tba'. "u" matches only
        # "upcoming" → complete "pcoming". (`find` keeps the release-status slot;
        # `list` now ghosts nouns instead.)
        result = call(input: "find u", cursor: 6, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("pcoming")
      end

      it "completes the :noun slot for the list verb ('list cha' → 'nnels')" do
        result = call(input: "list cha", cursor: 8, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("nnels")
      end

      it "completes the video :noun slot to the canonical short form ('list v' → 'ids')" do
        result = call(input: "list v", cursor: 6, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("ids")
      end

      it "returns '' when no chat spec matches the first word" do
        result = call(input: "frobnicate x", cursor: 12, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end

      # Regression (VB2): a bare COMPLETE chat verb with no trailing space (zero
      # typed arg words) used to crash compute_ghost via `[].first(-1)` →
      # "negative array size", so `list`/`ls` (and every verb) failed to suggest.
      it "does not crash on a bare complete chat verb (list / ls / show / sync)" do
        %w[list ls show sync delete].each do |verb|
          expect { call(input: verb, cursor: verb.length, authenticated: true) }
            .not_to raise_error
        end
      end

      it "still ghosts the canonical verb from an unambiguous prefix ('lis' → 't')" do
        result = call(input: "lis", cursor: 3, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("t")
      end

      it "returns '' when no vocab member matches the partial" do
        result = call(input: "list zzz", cursor: 8, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end
    end

    describe "next_hint / default completion at a fresh slot" do
      it "ghosts the first enum value (TAB-completable) at a trailing space, no <brackets>" do
        result = call(input: "list ", cursor: 5, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("channels")
        expect(result[:ghost][:next_hint]).to eq("")
        expect(result[:ghost][:next_hint]).not_to include("<")
      end

      it "next_hint is a string" do
        result = call(input: "list ", cursor: 5, authenticated: true)
        expect(result[:ghost][:next_hint]).to be_a(String)
      end

      it "next_hint is empty when complete_current is active" do
        result = call(input: "list cha", cursor: 8, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("nnels")
        expect(result[:ghost][:next_hint]).to eq("")
      end

      it "returns empty ghost for unknown first word" do
        result = call(input: "frobnicate x", cursor: 12, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
        expect(result[:ghost][:next_hint]).to eq("")
      end
    end
  end

  describe "free mode — verb stage prefix completion" do
    it "completes a unique verb prefix ('sy' → 'nc' for 'sync')" do
      result = call(input: "sy", cursor: 2, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("nc")
    end

    it "completes 'syn' → 'c' for 'sync'" do
      result = call(input: "syn", cursor: 3, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("c")
    end

    it "stays silent for an ambiguous verb prefix ('s' matches show and sync)" do
      result = call(input: "s", cursor: 1, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("")
    end

    it "does not verb-complete once a trailing space follows the partial" do
      result = call(input: "sy ", cursor: 3, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("")
    end
  end

  describe "free mode — sync target slot" do
    it "ghosts the first sync target at a trailing space ('sync ' → 'channels')" do
      result = call(input: "sync ", cursor: 5, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("channels")
    end

    it "completes 'sync c' → 'hannels'" do
      result = call(input: "sync c", cursor: 6, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("hannels")
    end

    it "completes 'sync v' → 'ids' (canonical short noun)" do
      result = call(input: "sync v", cursor: 6, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("ids")
    end

    it "completes 'sync vi' → 'ds' (canonical short noun)" do
      result = call(input: "sync vi", cursor: 7, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("ds")
    end
  end

  describe "free mode — sync clause ghost (SyncClauseGhost integration)" do
    it "ghosts 'with' after 'sync channels '" do
      result = call(input: "sync channels ", cursor: 14, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("with")
    end

    it "completes 'sync channels w' → 'ith'" do
      result = call(input: "sync channels w", cursor: 15, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("ith")
    end

    it "ghosts 'vids' after 'sync channels with '" do
      result = call(input: "sync channels with ", cursor: 19, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("vids")
    end

    it "completes 'sync channels with v' → 'ids'" do
      result = call(input: "sync channels with v", cursor: 20, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("ids")
    end
  end

  # `schedule <id> <when|slate>` — the trailing enum slot (:schedule_whens)
  # surfaces `slate` as a TAB-completable ghost alongside an explicit date.
  describe "free mode — schedule slate slot" do
    it "ghosts 'slate' at a trailing space ('schedule ' → 'slate')" do
      result = call(input: "schedule ", cursor: 9, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("slate")
    end

    it "ghosts 'slate' after the id ('schedule 5 ' → 'slate')" do
      result = call(input: "schedule 5 ", cursor: 11, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("slate")
    end

    it "completes 'schedule 5 sl' → 'ate'" do
      result = call(input: "schedule 5 sl", cursor: 13, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("ate")
    end

    it "stays silent while typing an explicit <when> ('schedule 5 tomorrow')" do
      result = call(input: "schedule 5 tomorrow", cursor: 19, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("")
    end
  end

  # `price set <id> <amount>` / `price unset <id>` — the leading enum slot
  # (:price_subcommands) surfaces `set`/`unset` as a TAB-completable ghost.
  describe "free mode — price subcommand slot" do
    it "ghosts 'set' at a trailing space ('price ' → 'set')" do
      result = call(input: "price ", cursor: 6, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("set")
    end

    it "completes 'price u' → 'nset'" do
      result = call(input: "price u", cursor: 7, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("nset")
    end

    it "stays silent past the subcommand ('price set 5 ' — id/amount are free)" do
      result = call(input: "price set 5 ", cursor: 12, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("")
    end
  end

  describe "free mode — import noun slot" do
    it "ghosts 'game' at a trailing space ('import ' → 'game')" do
      result = call(input: "import ", cursor: 7, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("game")
    end

    it "completes 'import g' → 'ame'" do
      result = call(input: "import g", cursor: 8, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("ame")
    end
  end

  describe "free mode — analyze noun slot" do
    it "ghosts 'channels' at a trailing space ('analyze ' → 'channels')" do
      result = call(input: "analyze ", cursor: 8, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("channels")
    end

    it "completes 'analyze v' → 'ids'" do
      result = call(input: "analyze v", cursor: 9, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("ids")
    end
  end

  describe "free mode — footage dynamic game_titles slot", :db do
    let!(:game) { create(:game, title: "Zelda") }

    it "ghost-completes toward a matching game title for 'footage zel'" do
      result = call(input: "footage zel", cursor: 11, authenticated: true)
      # dynamic slot: resolver finds "Zelda", partial "zel" (length 3) →
      # remaining = "Zelda"[3..] = "da"
      expect(result[:ghost][:complete_current]).to eq("da")
    end

    it "returns empty menu_items (free mode uses ghost path, not palette)" do
      result = call(input: "footage zel", cursor: 11, authenticated: true)
      expect(result[:menu_items]).to eq([])
    end
  end

  describe "free mode — reindex dynamic game_titles slot", :db do
    let!(:game) { create(:game, title: "Zelda") }

    it "ghost-completes toward a matching game title for 'reindex zel'" do
      result = call(input: "reindex zel", cursor: 11, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("da")
    end

    it "returns empty menu_items (free mode uses ghost path, not palette)" do
      result = call(input: "reindex zel", cursor: 11, authenticated: true)
      expect(result[:menu_items]).to eq([])
    end
  end

  # ── FREE MODE — ghost text (P31.0.al required cases) ────────────────────────

  describe "free-mode ghost" do
    # Case 1: fully-resolved command — no spurious complete_current
    it "returns empty complete_current for a fully-typed command 'list upcoming RPG games for PS5'" do
      input = "list upcoming RPG games for PS5"
      result = call(input: input, cursor: input.length, authenticated: true)
      expect(result[:mode]).to eq(:free)
      expect(result[:ghost][:complete_current]).to eq("")
    end

    # Case 2: multi-genre + platform — all tokens resolve, no completion needed
    it "returns empty complete_current for 'list upcoming racing and rpg games for playstation'" do
      input = "list upcoming racing and rpg games for playstation"
      result = call(input: input, cursor: input.length, authenticated: true)
      expect(result[:mode]).to eq(:free)
      expect(result[:ghost][:complete_current]).to eq("")
    end

    # Case 3: partial token — unique prefix completion
    it "returns 'oming' for complete_current when input is 'find upc'" do
      input = "find upc"
      result = call(input: input, cursor: input.length, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("oming")
    end

    # Case 4: trailing space — first enum value ghosted (TAB-completable)
    it "ghosts the first noun (TAB-completable) when input is 'list '" do
      input = "list "
      result = call(input: input, cursor: input.length, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("channels")
      expect(result[:ghost][:next_hint]).to eq("")
    end

    # Case 5: unmatched verb — empty ghost
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

    it "ghosts the first action so TAB completes it (no <brackets>)" do
      result = call(input: "#alpha-1266 ", cursor: 12, conversation:)
      expect(result[:ghost][:complete_current]).to eq("show")
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

    it "switches to stage: :arg once the verb is finalised (a second space)" do
      stamp("gl-5", "game_list")
      result = call(input: "#gl-5 with ", cursor: 11, conversation:)
      expect(result[:stage]).to eq(:arg)
    end

    it "each palette item inserts `<verb> ` (spliced over the partial verb token)" do
      stamp("vl-6", "video_list")
      items = call(input: "#vl-6 ", cursor: 6, conversation:)[:menu_items]
      schedule = items.find { |i| i[:label] == "schedule" }
      expect(schedule[:insert]).to eq("schedule ")
    end

    # `#<handle> price …` (game_list / game_detail) ghosts set/unset at the
    # subcommand position, then stays silent over the free id/amount.
    it "ghosts 'set' after '#<handle> price ' (game_list reply)" do
      stamp("gl-7", "game_list")
      result = call(input: "#gl-7 price ", cursor: 12, conversation:)
      expect(result[:ghost][:complete_current]).to eq("set")
      expect(result[:stage]).to eq(:arg)
    end

    it "completes '#<handle> price u' → 'nset'" do
      stamp("gl-8", "game_list")
      result = call(input: "#gl-8 price u", cursor: 13, conversation:)
      expect(result[:ghost][:complete_current]).to eq("nset")
    end

    it "stays silent past the subcommand ('#<handle> price set 5 ')" do
      stamp("gl-9", "game_list")
      result = call(input: "#gl-9 price set 5 ", cursor: 18, conversation:)
      expect(result[:ghost][:complete_current]).to eq("")
    end
  end

  # hashtag column ghost for game_list/video_list with/without actions
  describe "hashtag follow-up: column ghost for game_list with/without", :db do
    let(:conversation) { Conversation.create! }
    let(:turn) { conversation.turns.create!(input_kind: :slash, input_text: "/list games", position: 1) }

    before do
      Pito::FollowUp::Registry.register_all!
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "glist-4444", "reply_target" => "game_list", "body" => "games" }
      )
    end

    it "ghosts the first game column token when '#<handle> with ' (trailing space)" do
      result = call(input: "#glist-4444 with ", cursor: 17, conversation:)
      expect(result[:ghost][:complete_current]).to eq("platform")
      expect(result[:ghost][:next_hint]).to eq("")
    end

    it "excludes already-typed platform and ghosts the next column for '#<handle> with platform, '" do
      result = call(input: "#glist-4444 with platform, ", cursor: 27, conversation:)
      expect(result[:ghost][:complete_current]).to eq("genre")
    end

    it "completes a partial token: 'gen' → 're'" do
      result = call(input: "#glist-4444 with platform, gen", cursor: 30, conversation:)
      expect(result[:ghost][:complete_current]).to eq("re")
    end

    it "without behaves the same as with (ghosts first column)" do
      result = call(input: "#glist-4444 without ", cursor: 20, conversation:)
      expect(result[:ghost][:complete_current]).to eq("platform")
    end

    it "offers a column menu palette for with/without" do
      result = call(input: "#glist-4444 with ", cursor: 17, conversation:)
      expect(result[:menu_items].map { |i| i[:label] }).to include("platform", "genre", "release")
    end
  end

  describe "hashtag follow-up: column ghost for video_list with/without", :db do
    let(:conversation) { Conversation.create! }
    let(:turn) { conversation.turns.create!(input_kind: :slash, input_text: "/list videos", position: 1) }

    before do
      Pito::FollowUp::Registry.register_all!
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "vlist-5555", "reply_target" => "video_list", "body" => "videos" }
      )
    end

    it "ghosts the first video column token when '#<handle> with ' (trailing space)" do
      result = call(input: "#vlist-5555 with ", cursor: 17, conversation:)
      expect(result[:ghost][:complete_current]).to eq("channel")
    end

    it "excludes already-typed game and ghosts channel for '#<handle> with game, '" do
      result = call(input: "#vlist-5555 with game, ", cursor: 23, conversation:)
      expect(result[:ghost][:complete_current]).to eq("channel")
    end

    it "without behaves the same as with (ghosts first video column)" do
      result = call(input: "#vlist-5555 without ", cursor: 20, conversation:)
      expect(result[:ghost][:complete_current]).to eq("channel")
    end

    it "ghosts the next column (visibility) after channel is already typed" do
      result = call(input: "#vlist-5555 with channel, ", cursor: 26, conversation:)
      expect(result[:ghost][:complete_current]).to eq("visibility")
    end

    it "channel is offered — partial 'ch' completes to 'annel'" do
      result = call(input: "#vlist-5555 with ch", cursor: 19, conversation:)
      expect(result[:ghost][:complete_current]).to eq("annel")
    end

    it "visibility column is offered — partial 'vis' completes to 'ibility'" do
      result = call(input: "#vlist-5555 with vis", cursor: 20, conversation:)
      expect(result[:ghost][:complete_current]).to eq("ibility")
    end
  end

  describe "hashtag follow-up: sort/order ghost for game_list", :db do
    let(:conversation) { Conversation.create! }
    let(:turn) { conversation.turns.create!(input_kind: :slash, input_text: "/list games", position: 1) }

    before do
      Pito::FollowUp::Registry.register_all!
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "gsort-1111", "reply_target" => "game_list",
                   "list_columns" => [], "body" => "games" }
      )
    end

    it "suggests sort and order in the action palette" do
      result = call(input: "#gsort-1111 ", cursor: 12, conversation:)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("sort", "order")
    end

    it "ghosts 'by' when nothing is typed after the verb" do
      result = call(input: "#gsort-1111 sort ", cursor: 17, conversation:)
      expect(result[:ghost][:complete_current]).to eq("by")
    end

    it "ghosts 'y' when 'b' is typed after the verb" do
      result = call(input: "#gsort-1111 sort b", cursor: 18, conversation:)
      expect(result[:ghost][:complete_current]).to eq("y")
    end

    it "ghosts the first sort column after 'sort by '" do
      result = call(input: "#gsort-1111 sort by ", cursor: 20, conversation:)
      expect(result[:ghost][:complete_current]).to eq("id")
    end

    it "completes 'tle' after 'sort by ti'" do
      result = call(input: "#gsort-1111 sort by ti", cursor: 22, conversation:)
      expect(result[:ghost][:complete_current]).to eq("tle")
    end

    it "ghosts 'by' for 'order ' (alias)" do
      result = call(input: "#gsort-1111 order ", cursor: 18, conversation:)
      expect(result[:ghost][:complete_current]).to eq("by")
    end

    it "returns empty menu_items (sort ghost has no palette)" do
      result = call(input: "#gsort-1111 sort by ", cursor: 20, conversation:)
      expect(result[:menu_items]).to be_empty
    end
  end

  describe "hashtag follow-up: sort ghost for video_list with views column", :db do
    let(:conversation) { Conversation.create! }
    let(:turn) { conversation.turns.create!(input_kind: :slash, input_text: "/list videos", position: 1) }

    before do
      Pito::FollowUp::Registry.register_all!
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "vsort-2222", "reply_target" => "video_list",
                   "list_columns" => [ "views" ], "body" => "videos" }
      )
    end

    it "ghosts 'by' when nothing after the verb" do
      result = call(input: "#vsort-2222 sort ", cursor: 17, conversation:)
      expect(result[:ghost][:complete_current]).to eq("by")
    end

    it "completes 'iews' after 'sort by v' when views is a present column" do
      result = call(input: "#vsort-2222 sort by v", cursor: 21, conversation:)
      expect(result[:ghost][:complete_current]).to eq("iews")
    end

    it "ghosts first column after 'sort by '" do
      result = call(input: "#vsort-2222 sort by ", cursor: 20, conversation:)
      # Base tokens: id, title; then views (present with-col, requires_with: true)
      expect(result[:ghost][:complete_current]).to eq("id")
    end
  end

  # hashtag --help ghost: when the partial starts with "-" and prefixes
  # "--help", the engine returns a --help ghost + menu item.
  describe "hashtag follow-up: --help ghost", :db do
    let(:conversation) { Conversation.create! }
    let(:turn) { conversation.turns.create!(input_kind: :slash, input_text: "/list games", position: 1) }

    before do
      Pito::FollowUp::Registry.register_all!
      Event.create_with_position!(
        conversation:, turn:, kind: "system",
        payload: { "reply_handle" => "glist-5555", "reply_target" => "game_list", "body" => "games" }
      )
    end

    context "verb-stage partial: -" do
      subject(:result) { call(input: "#glist-5555 -", cursor: 13, conversation:) }

      it "returns :hashtag mode" do
        expect(result[:mode]).to eq(:hashtag)
      end

      it "ghost completes toward --help ('-help' remaining)" do
        expect(result[:ghost][:complete_current]).to eq("-help")
      end

      it "menu includes --help item" do
        expect(result[:menu_items].map { |i| i[:label] }).to include("--help")
      end
    end

    context "verb-stage partial: --" do
      subject(:result) { call(input: "#glist-5555 --", cursor: 14, conversation:) }

      it "ghost completes 'help'" do
        expect(result[:ghost][:complete_current]).to eq("help")
      end
    end

    context "verb-stage partial: --h" do
      subject(:result) { call(input: "#glist-5555 --h", cursor: 15, conversation:) }

      it "ghost completes 'elp'" do
        expect(result[:ghost][:complete_current]).to eq("elp")
      end
    end

    context "verb-stage partial: --help (fully typed)" do
      subject(:result) { call(input: "#glist-5555 --help", cursor: 18, conversation:) }

      it "ghost complete_current is empty (exact match)" do
        expect(result[:ghost][:complete_current]).to eq("")
      end
    end

    context "arg-stage: #handle show -" do
      subject(:result) { call(input: "#glist-5555 show -", cursor: 18, conversation:) }

      it "returns :hashtag mode" do
        expect(result[:mode]).to eq(:hashtag)
      end

      it "ghost completes toward --help ('-help' remaining)" do
        expect(result[:ghost][:complete_current]).to eq("-help")
      end

      it "menu includes --help item" do
        expect(result[:menu_items].map { |i| i[:label] }).to include("--help")
      end
    end

    context "arg-stage: #handle show --" do
      subject(:result) { call(input: "#glist-5555 show --", cursor: 19, conversation:) }

      it "ghost completes 'help'" do
        expect(result[:ghost][:complete_current]).to eq("help")
      end
    end

    context "normal verb-stage partial with no dash (no change)" do
      subject(:result) { call(input: "#glist-5555 sho", cursor: 15, conversation:) }

      it "ghost completes 'w' (prefix match on show)" do
        expect(result[:ghost][:complete_current]).to eq("w")
      end

      it "does NOT include --help in menu" do
        expect(result[:menu_items].map { |i| i[:label] }).not_to include("--help")
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
  # reply-verb palette, and `slate` must be offered for its argument slot.
  describe "hashtag follow-up: schedule verb + slate arg for video_list", :db do
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

    it "offers slate for the schedule argument ('#<handle> schedule ')" do
      result = call(input: "#vsched-7777 schedule ", cursor: 22, conversation:)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("slate")
      expect(result[:ghost][:complete_current]).to eq("slate")
    end

    it "completes 'schedule sl' → 'ate' for the schedule argument" do
      result = call(input: "#vsched-7777 schedule sl", cursor: 24, conversation:)
      expect(result[:ghost][:complete_current]).to eq("ate")
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

    it "returns channel menu_items when authenticated" do
      result = call(input: "/disconnect @al", cursor: 15, authenticated: true)
      labels = result[:menu_items].map { |i| i[:label] }
      expect(labels).to include("@alpha")
    end

    it "auth-gates :channels — returns NO menu_items when not authenticated" do
      result = call(input: "/disconnect @al", cursor: 15, authenticated: false)
      expect(result[:menu_items]).to be_empty
    end

    it "insert for a channel item ends with a space" do
      result = call(input: "/disconnect @al", cursor: 15, authenticated: true)
      result[:menu_items].each do |item|
        expect(item[:insert]).to end_with(" ")
      end
    end

    # Scoping guard: only `/config` args become a palette. Other slash args (here
    # the dynamic :channels slot) keep the inline-ghost arg treatment.
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

  # ── GHOST — cursor position variants ─────────────────────────────────────────

  describe "ghost text — cursor position variants" do
    context "cursor at end of a partial word" do
      it "completes 'upc' at end-of-input → 'oming'" do
        result = call(input: "find upc", cursor: 8, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("oming")
      end
    end

    context "cursor at end of a fully-typed word (no partial suffix)" do
      it "returns empty complete_current for 'list upcoming'" do
        result = call(input: "list upcoming", cursor: 13, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("")
      end
    end

    context "cursor mid-word (user placed cursor inside a token)" do
      # When cursor is at position 6 in "find upcoming" (after "upc" but before "oming"),
      # the engine sees input[0..5] = "find u" — completes "pcoming"
      it "completes using only text before cursor" do
        result = call(input: "find upcoming", cursor: 6, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("pcoming")
      end
    end

    context "no partial word typed (cursor at trailing space)" do
      it "ghosts the first enum value as a TAB-completable completion" do
        result = call(input: "list ", cursor: 5, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("channels")
        expect(result[:ghost][:next_hint]).to eq("")
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

    it "slash arg-stage ghost is empty (ghost is server-side in arg stage)" do
      # Engine does not compute ghost locally for slash arg-stage; the debounced
      # /suggestions fetch fills this after the response arrives.
      result = call(input: "/config goo", cursor: 11, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("")
    end

    it "insert for the provider ends with a space" do
      result = call(input: "/config goo", cursor: 11, authenticated: true)
      item = result[:menu_items].find { |i| i[:label] == "google" }
      expect(item[:insert]).to end_with(" ")
    end
  end

  # ── GHOST — kv-key ghost from Engine (already covered above + cursor tests) ──

  describe "slash mode — kv-key ghost (/config igdb client_s → ecret)" do
    it "ghost complete_current is 'ecret' for '/config igdb client_s'" do
      result = call(input: "/config igdb client_s", cursor: 21, authenticated: true)
      expect(result[:ghost][:complete_current]).to eq("ecret")
    end
  end

  # ── Partial kv-key ghost completion ──────────────────────────────────────────

  describe "slash mode — partial kv-key ghost completion" do
    context "unique prefix" do
      it "returns ghost 'ecret' for '/config igdb client_s'" do
        result = call(input: "/config igdb client_s", cursor: 21, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("ecret")
        expect(result[:ghost][:next_hint]).to eq("")
      end

      it "returns ghost 'irect_uri' for '/config google redi'" do
        result = call(input: "/config google redi", cursor: 19, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("rect_uri")
        expect(result[:ghost][:next_hint]).to eq("")
      end

      it "returns ghost '_key' for '/config voyage api'" do
        result = call(input: "/config voyage api", cursor: 18, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("_key")
        expect(result[:ghost][:next_hint]).to eq("")
      end

      it "returns ghost 'cord' for '/config webhook dis'" do
        result = call(input: "/config webhook dis", cursor: 19, authenticated: true)
        expect(result[:ghost][:complete_current]).to eq("cord")
        expect(result[:ghost][:next_hint]).to eq("")
      end
    end

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

  # ── FREE MODE — list clause ghost (integration) ──────────────────────────────

  describe "free mode — list clause ghost integration" do
    it "returns 'platform' as complete_current for 'list games with '" do
      result = call(input: "list games with ", cursor: 16)
      expect(result[:ghost][:complete_current]).to eq("platform")
    end

    it "returns 'gth' as complete_current for 'list videos with len'" do
      result = call(input: "list videos with len", cursor: 20)
      expect(result[:ghost][:complete_current]).to eq("gth")
    end

    it "returns 'with' as complete_current for 'list games ' (connector branch)" do
      result = call(input: "list games ", cursor: 11)
      expect(result[:ghost][:complete_current]).to eq("with")
    end

    it "still ghosts 'channels' (first noun) for bare 'list '" do
      result = call(input: "list ", cursor: 5)
      expect(result[:ghost][:complete_current]).to eq("channels")
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
end
