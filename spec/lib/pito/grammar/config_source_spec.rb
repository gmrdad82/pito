# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::ConfigSource do
  # ── Synthetic config doc ─────────────────────────────────────────────────────
  #
  # Field-by-field construction tests use a minimal synthetic document so they
  # are fully isolated from tools.yml changes. The doc mimics the symbol-keyed
  # structure that Pito::Dispatch::Config.data returns (symbolize_names: true).

  let(:synthetic_static_vocab) do
    {
      members:  %w[hello world],
      synonyms: { hi: "hello", howdy: "hello" },
      fillers:  %w[please um]
    }
  end

  let(:synthetic_dynamic_vocab) do
    { resolver: "channels" }
  end

  let(:synthetic_chat_tool) do
    {
      aliases:     %w[tv],
      description: "pito.grammar.chat.test_tool",
      auth:        "session",
      chat:        {
        slots: [
          { name: "noun", kind: "enum", source: "test_words", optional: true,
            repeatable: false },
          { name: "title", kind: "free", optional: false }
        ]
      }
    }
  end

  # A slash-only tool exercising every T8.9 slot kind (literal / enum+when / kv+when
  # / free), tool-level aliases, branch-level description, and a branch auth tier.
  let(:synthetic_slash_tool) do
    {
      aliases: %w[cfg],
      slash:   {
        auth:        "authenticated_only",
        description: "pito.grammar.slash.test_cfg",
        slots: [
          { name: "provider", kind: "literal", source: "test_providers" },
          { name: "state",    kind: "enum",    source: "on_off",    optional: true,
            when: { provider: %w[sound] } },
          { name: "settings", kind: "kv",      source: "test_keys", optional: true, repeatable: true,
            when: { provider: %w[google voyage] } },
          { name: "note",     kind: "free",    optional: true }
        ]
      }
    }
  end

  let(:synthetic_doc) do
    {
      vocabularies: {
        test_words:  synthetic_static_vocab,
        dyn_vocab:   synthetic_dynamic_vocab
      },
      tools: {
        test_tool:    synthetic_chat_tool,
        test_cfg:     synthetic_slash_tool,
        reply_only:   {
          # No `chat:`/`slash:` branch — must NOT produce a chat or slash spec
          reply: { targets: { some_target: { mode: "append" } } }
        }
      }
    }
  end

  before do
    allow(Pito::Dispatch::Config).to receive(:data).and_return(synthetic_doc)
  end

  # ── .vocabularies ─────────────────────────────────────────────────────────────

  describe ".vocabularies (synthetic doc)" do
    subject(:vocabs) { described_class.vocabularies }

    it "returns an Array of Vocabulary objects" do
      expect(vocabs).to be_an(Array)
      expect(vocabs).to all(be_a(Pito::Grammar::Vocabulary))
    end

    it "builds one Vocabulary per vocabularies entry" do
      expect(vocabs.length).to eq(2)
    end

    context "static vocabulary :test_words" do
      subject(:vocab) { vocabs.find { |v| v.name == :test_words } }

      it "is present" do
        expect(vocab).not_to be_nil
      end

      it "name is symbolized from the YAML key" do
        expect(vocab.name).to eq(:test_words)
      end

      it "canonical has the expected members as Strings" do
        expect(vocab.canonical).to eq(%w[hello world])
      end

      it "synonyms has String keys (converted from YAML symbol keys)" do
        expect(vocab.synonyms.keys).to all(be_a(String))
        expect(vocab.synonyms["hi"]).to eq("hello")
        expect(vocab.synonyms["howdy"]).to eq("hello")
      end

      it "fillers contains the expected words" do
        expect(vocab.filler?("please")).to be(true)
        expect(vocab.filler?("um")).to be(true)
        expect(vocab.filler?("hello")).to be(false)
      end

      it "is not dynamic" do
        expect(vocab.dynamic?).to be(false)
      end

      it "resolve returns the canonical form (case-insensitive)" do
        expect(vocab.resolve("hello")).to eq("hello")
        expect(vocab.resolve("WORLD")).to eq("world")
      end

      it "resolve returns nil for unknown tokens" do
        expect(vocab.resolve("unknown")).to be_nil
      end

      it "resolve follows synonyms" do
        expect(vocab.resolve("hi")).to eq("hello")
      end
    end

    context "dynamic vocabulary :dyn_vocab" do
      subject(:vocab) { vocabs.find { |v| v.name == :dyn_vocab } }

      it "is present" do
        expect(vocab).not_to be_nil
      end

      it "is dynamic" do
        expect(vocab.dynamic?).to be(true)
      end

      it "has a callable resolver (wired from DYNAMIC_RESOLVERS[:channels])" do
        expect(vocab.resolver).to respond_to(:call)
        expect(vocab.resolver).to eq(described_class::DYNAMIC_RESOLVERS[:channels])
      end

      it "has an empty canonical array" do
        expect(vocab.canonical).to be_empty
      end
    end
  end

  # ── .chat_specs ──────────────────────────────────────────────────────────────

  describe ".chat_specs (synthetic doc)" do
    subject(:specs) { described_class.chat_specs }

    it "returns an Array of Spec objects" do
      expect(specs).to be_an(Array)
      expect(specs).to all(be_a(Pito::Grammar::Spec))
    end

    it "produces exactly one spec (the chat-branch tool; reply-only tool excluded)" do
      expect(specs.length).to eq(1)
    end

    context ":test_tool spec" do
      subject(:spec) { specs.first }

      it "namespace is :chat" do
        expect(spec.namespace).to eq(:chat)
      end

      it "name is symbolized from the YAML key" do
        expect(spec.name).to eq(:test_tool)
      end

      it "aliases are symbolized from the YAML array" do
        expect(spec.aliases).to eq([ :tv ])
      end

      it "description_key matches the YAML string" do
        expect(spec.description_key).to eq("pito.grammar.chat.test_tool")
      end

      it "auth is always :any for chat specs regardless of YAML tool-level auth" do
        expect(spec.auth).to eq(:any)
      end

      it "has two slots in declaration order" do
        expect(spec.slots.length).to eq(2)
      end

      context "first slot :noun" do
        subject(:slot) { spec.slot(:noun) }

        it "name is symbolized" do
          expect(slot.name).to eq(:noun)
        end

        it "kind is :enum" do
          expect(slot.kind).to eq(:enum)
        end

        it "source is symbolized vocabulary name" do
          expect(slot.source).to eq(:test_words)
        end

        it "optional? is true" do
          expect(slot.optional?).to be(true)
        end

        it "repeatable? is false" do
          expect(slot.repeatable?).to be(false)
        end

        it "introducer is nil (not set)" do
          expect(slot.introducer).to be_nil
        end
      end

      context "second slot :title" do
        subject(:slot) { spec.slot(:title) }

        it "kind is :free" do
          expect(slot.kind).to eq(:free)
        end

        it "source is nil (free slots carry no source)" do
          expect(slot.source).to be_nil
        end

        it "optional? is false" do
          expect(slot.optional?).to be(false)
        end
      end
    end
  end

  # ── .slash_specs (synthetic doc) ──────────────────────────────────────────────

  describe ".slash_specs (synthetic doc)" do
    subject(:specs) { described_class.slash_specs }

    it "returns an Array of Spec objects" do
      expect(specs).to be_an(Array)
      expect(specs).to all(be_a(Pito::Grammar::Spec))
    end

    it "produces exactly one spec (the slash-branch tool; chat + reply-only excluded)" do
      expect(specs.length).to eq(1)
      expect(specs.first.name).to eq(:test_cfg)
    end

    context ":test_cfg spec" do
      subject(:spec) { specs.first }

      it "namespace is :slash" do
        expect(spec.namespace).to eq(:slash)
      end

      it "aliases come from the tool-level aliases key" do
        expect(spec.aliases).to eq([ :cfg ])
      end

      it "description_key is the BRANCH description (slash[:description])" do
        expect(spec.description_key).to eq("pito.grammar.slash.test_cfg")
      end

      it "auth is the branch auth tier, symbolized" do
        expect(spec.auth).to eq(:authenticated_only)
      end

      it "has four slots in declaration order" do
        expect(spec.slots.map(&:name)).to eq(%i[provider state settings note])
      end

      context ":provider literal slot" do
        subject(:slot) { spec.slot(:provider) }

        it "kind is :literal" do
          expect(slot.kind).to eq(:literal)
        end

        it "source is the symbolized vocabulary name" do
          expect(slot.source).to eq(:test_providers)
        end

        it "has no condition" do
          expect(slot.condition).to be_nil
        end
      end

      context ":state enum slot with a when: condition" do
        subject(:slot) { spec.slot(:state) }

        it "kind is :enum and optional? true" do
          expect(slot.kind).to eq(:enum)
          expect(slot.optional?).to be(true)
        end

        it "condition is the verbatim symbol-keyed when: Hash" do
          expect(slot.condition).to eq(provider: %w[sound])
        end

        it "is eligible only when the prior :provider resolves to sound" do
          expect(slot.eligible?(provider: "sound")).to be(true)
          expect(slot.eligible?(provider: "google")).to be(false)
        end
      end

      context ":settings kv slot with a when: condition" do
        subject(:slot) { spec.slot(:settings) }

        it "kind is :kv, repeatable and optional" do
          expect(slot.kind).to eq(:kv)
          expect(slot.repeatable?).to be(true)
          expect(slot.optional?).to be(true)
        end

        it "condition gates on the credential providers" do
          expect(slot.condition).to eq(provider: %w[google voyage])
          expect(slot.eligible?(provider: "google")).to be(true)
          expect(slot.eligible?(provider: "sound")).to be(false)
        end
      end

      context ":note free slot" do
        subject(:slot) { spec.slot(:note) }

        it "kind is :free with a nil source and nil condition" do
          expect(slot.kind).to eq(:free)
          expect(slot.source).to be_nil
          expect(slot.condition).to be_nil
        end
      end
    end
  end

  # ── Real tools.yml spot checks ───────────────────────────────────────────────
  #
  # These tests use the actual config/pito/tools.yml (no stub) to pin that the
  # builder faithfully translates the real file into the expected objects.

  describe ".vocabularies (real tools.yml)" do
    before { allow(Pito::Dispatch::Config).to receive(:data).and_call_original }

    subject(:vocabs) { described_class.vocabularies }

    it "returns an Array of Vocabulary objects" do
      expect(vocabs).to be_an(Array)
      expect(vocabs).to all(be_a(Pito::Grammar::Vocabulary))
    end

    it "includes all expected static vocabulary names" do
      names = vocabs.map(&:name)
      expect(names).to include(
        :nouns, :slash_tools, :config_providers, :config_keys, :genres, :platforms,
        :release_status, :metrics, :on_off, :hashtag_tools, :fillers, :connectives,
        :games_subcommands, :jobs_subcommands, :import_nouns, :sync_targets,
        :schedule_whens,
        :visit_destinations, :full_flag, :show_segments
      )
    end

    it "includes all dynamic vocabulary names" do
      names = vocabs.map(&:name)
      expect(names).to include(:channels, :conversations, :game_titles, :video_titles)
    end

    context ":nouns vocabulary" do
      subject(:nouns) { vocabs.find { |v| v.name == :nouns } }

      it 'has canonical members ["channels", "vids", "games"]' do
        expect(nouns.canonical).to contain_exactly("channels", "vids", "games")
      end

      it 'resolves "channel" to "channels"' do
        expect(nouns.resolve("channel")).to eq("channels")
      end

      it 'resolves "videos" to "vids"' do
        expect(nouns.resolve("videos")).to eq("vids")
      end

      it 'resolves "gamez" to "games"' do
        expect(nouns.resolve("gamez")).to eq("games")
      end
    end

    context ":on_off vocabulary" do
      subject(:on_off) { vocabs.find { |v| v.name == :on_off } }

      it 'has canonical members ["on", "off"]' do
        expect(on_off.canonical).to contain_exactly("on", "off")
      end

      it 'resolves "true" to "on"' do
        expect(on_off.resolve("true")).to eq("on")
      end

      it 'resolves "false" to "off"' do
        expect(on_off.resolve("false")).to eq("off")
      end

      it 'resolves "yes" to "on"' do
        expect(on_off.resolve("yes")).to eq("on")
      end

      it 'resolves "no" to "off"' do
        expect(on_off.resolve("no")).to eq("off")
      end
    end

    context ":metrics vocabulary" do
      subject(:metrics) { vocabs.find { |v| v.name == :metrics } }

      it 'has "subs" as canonical (not "subscribers")' do
        expect(metrics.canonical).to include("subs")
        expect(metrics.canonical).not_to include("subscribers")
      end

      it 'resolves "subscribers" to "subs"' do
        expect(metrics.resolve("subscribers")).to eq("subs")
      end

      it 'filler? is true for "count"' do
        expect(metrics.filler?("count")).to be(true)
      end
    end

    context ":genres vocabulary" do
      subject(:genres) { vocabs.find { |v| v.name == :genres } }

      it 'resolves "fps" to "Shooter"' do
        expect(genres.resolve("fps")).to eq("Shooter")
      end

      it 'resolves "sim" to "Simulation"' do
        expect(genres.resolve("sim")).to eq("Simulation")
      end
    end

    context ":platforms vocabulary" do
      subject(:platforms) { vocabs.find { |v| v.name == :platforms } }

      it 'resolves "ps5" to "PlayStation 5"' do
        expect(platforms.resolve("ps5")).to eq("PlayStation 5")
      end

      it 'resolves "switch" to "Nintendo Switch"' do
        expect(platforms.resolve("switch")).to eq("Nintendo Switch")
      end
    end

    context ":release_status vocabulary" do
      subject(:rs) { vocabs.find { |v| v.name == :release_status } }

      it 'resolves "unreleased" to "upcoming"' do
        expect(rs.resolve("unreleased")).to eq("upcoming")
      end

      it 'resolves "tbd" to "tba"' do
        expect(rs.resolve("tbd")).to eq("tba")
      end

      it 'resolves "to be announced" to "tba"' do
        expect(rs.resolve("to be announced")).to eq("tba")
      end
    end

    context ":show_segments vocabulary" do
      subject(:segs) { vocabs.find { |v| v.name == :show_segments } }

      it "includes hyphenated segment names as strings" do
        expect(segs.canonical).to include("at-a-glance", "game", "games", "videos")
      end
    end

    context ":game_titles dynamic vocabulary" do
      subject(:game_titles) { vocabs.find { |v| v.name == :game_titles } }

      it "is dynamic" do
        expect(game_titles.dynamic?).to be(true)
      end

      it "has a callable resolver (the game_titles lambda)" do
        expect(game_titles.resolver).to respond_to(:call)
        expect(game_titles.resolver).to eq(described_class::DYNAMIC_RESOLVERS[:game_titles])
      end
    end

    context ":channels dynamic vocabulary" do
      subject(:channels) { vocabs.find { |v| v.name == :channels } }

      it "is dynamic" do
        expect(channels.dynamic?).to be(true)
      end

      it "resolver equals DYNAMIC_RESOLVERS[:channels]" do
        expect(channels.resolver).to eq(described_class::DYNAMIC_RESOLVERS[:channels])
      end
    end
  end

  describe ".chat_specs (real tools.yml)" do
    before { allow(Pito::Dispatch::Config).to receive(:data).and_call_original }

    subject(:specs) { described_class.chat_specs }

    it "all specs have namespace :chat" do
      expect(specs.map(&:namespace).uniq).to eq([ :chat ])
    end

    it "includes the expected chat tools" do
      names = specs.map(&:name)
      expect(names).to include(
        :list, :show, :analyze, :import, :sync,
        :delete, :reindex, :publish, :unlist,
        :schedule, :link, :unlink, :help, :shinies, :greet, :farewell
      )
    end

    it "does NOT include price/platform (retired standalone tools, Q16/Q16b)" do
      names = specs.map(&:name)
      expect(names).not_to include(:price, :platform)
    end

    it "does not include reply-only tools (next, sort, with, without, confirm, cancel)" do
      names = specs.map(&:name)
      expect(names).not_to include(:next, :sort, :with, :without, :confirm, :cancel)
    end

    it "includes visit (chat-declared since 4.1.0 — no longer reply-only)" do
      names = specs.map(&:name)
      expect(names).to include(:visit)
    end

    # `find` declares no chat: branch (3.0.1 P6) — it exists only to feed
    # nl_examples: into the NL corpus, so it must never produce a grammar spec
    # (that was the 3.0.0 bug: a chat: block first-token-captured "find …"
    # with no chat.dispatch handler behind it, a permanent dead end).
    it "does not include :find (NL-corpus-only tool, no chat branch)" do
      names = specs.map(&:name)
      expect(names).not_to include(:find)
    end

    context ":list spec" do
      subject(:spec) { specs.find { |s| s.name == :list } }

      it "has alias :ls" do
        expect(spec.aliases).to include(:ls)
      end

      it "has a single :noun enum slot sourced from :nouns" do
        expect(spec.slots.length).to eq(1)
        slot = spec.slot(:noun)
        expect(slot.kind).to eq(:enum)
        expect(slot.source).to eq(:nouns)
        expect(slot.optional?).to be(true)
      end

      it "has description_key pito.grammar.chat.list" do
        expect(spec.description_key).to eq("pito.grammar.chat.list")
      end

      it "has auth :any" do
        expect(spec.auth).to eq(:any)
      end
    end

    context ":show spec" do
      subject(:spec) { specs.find { |s| s.name == :show } }

      it "has five slots in order: id, full, with, only, without (W5/D17)" do
        expect(spec.slots.map(&:name)).to eq([ :id, :full, :with, :only, :without ])
      end

      it ":id slot is a :free optional slot" do
        id = spec.slot(:id)
        expect(id.kind).to eq(:free)
        expect(id.optional?).to be(true)
      end

      it ":full slot is a :enum optional slot sourced from :full_flag" do
        full = spec.slot(:full)
        expect(full.kind).to eq(:enum)
        expect(full.source).to eq(:full_flag)
        expect(full.optional?).to be(true)
      end

      it ":with slot has introducer :with and repeatable? true" do
        w = spec.slot(:with)
        expect(w.introducer).to eq(:with)
        expect(w.repeatable?).to be(true)
        expect(w.source).to eq(:show_segments)
      end

      it ":only slot has introducer :only and repeatable? true" do
        o = spec.slot(:only)
        expect(o.introducer).to eq(:only)
        expect(o.repeatable?).to be(true)
        expect(o.source).to eq(:show_segments)
      end
    end

    context ":analyze spec" do
      subject(:spec) { specs.find { |s| s.name == :analyze } }

      it "has aliases :analytics and :stats" do
        expect(spec.aliases).to match_array([ :analytics, :stats ])
      end

      it "has :noun (nouns) + :full (full_flag) + :without (analyze_segments) slots (W5/D17)" do
        expect(spec.slots.map(&:name)).to eq([ :noun, :full, :without ])
        expect(spec.slot(:noun).source).to eq(:nouns)
        expect(spec.slot(:full).source).to eq(:full_flag)
        expect(spec.slot(:without).source).to eq(:analyze_segments)
      end
    end

    context ":import spec" do
      subject(:spec) { specs.find { |s| s.name == :import } }

      it "has two slots: noun and title" do
        expect(spec.slots.map(&:name)).to eq([ :noun, :title ])
      end

      it ":noun slot is an :enum slot with optional? true (bare `import <title>` / `import`)" do
        slot = spec.slot(:noun)
        expect(slot.kind).to eq(:enum)
        expect(slot.source).to eq(:import_nouns)
        expect(slot.optional?).to be(true)
      end

      it ":title slot is a :free optional slot" do
        slot = spec.slot(:title)
        expect(slot.kind).to eq(:free)
        expect(slot.optional?).to be(true)
      end
    end

    context ":delete spec" do
      subject(:spec) { specs.find { |s| s.name == :delete } }

      it "has aliases :rm and :del" do
        expect(spec.aliases).to match_array([ :rm, :del ])
      end

      it "has a single :title enum slot sourced from :game_titles" do
        slot = spec.slot(:title)
        expect(slot.kind).to eq(:enum)
        expect(slot.source).to eq(:game_titles)
      end
    end

    context ":schedule spec" do
      subject(:spec) { specs.find { |s| s.name == :schedule } }

      it "has slots :title and :slate" do
        expect(spec.slots.map(&:name)).to eq([ :title, :slate ])
      end

      it ":title is a :free optional slot" do
        expect(spec.slot(:title).kind).to eq(:free)
        expect(spec.slot(:title).optional?).to be(true)
      end

      it ":slate is an :enum optional slot sourced from :schedule_whens" do
        slate = spec.slot(:slate)
        expect(slate.kind).to eq(:enum)
        expect(slate.source).to eq(:schedule_whens)
        expect(slate.optional?).to be(true)
      end
    end

    context ":help spec (multi-branch tool — only chat branch produced)" do
      subject(:spec) { specs.find { |s| s.name == :help } }

      it "is present" do
        expect(spec).not_to be_nil
      end

      it "has no slots" do
        expect(spec.slots).to be_empty
      end

      it "description_key is the chat description (not slash description)" do
        expect(spec.description_key).to eq("pito.grammar.chat.help")
      end
    end

    context ":greet spec" do
      subject(:spec) { specs.find { |s| s.name == :greet } }

      it "is present with empty slots" do
        expect(spec).not_to be_nil
        expect(spec.slots).to be_empty
      end
    end

    context ":farewell spec" do
      subject(:spec) { specs.find { |s| s.name == :farewell } }

      it "is present with empty slots" do
        expect(spec).not_to be_nil
        expect(spec.slots).to be_empty
      end
    end

    it "each spec's slot arrays are independent objects (no shared mutable state)" do
      list_slots = specs.find { |s| s.name == :list }.slots
      show_slots = specs.find { |s| s.name == :show }.slots
      expect(list_slots).not_to equal(show_slots)
    end
  end

  # ── .slash_specs (real tools.yml) ─────────────────────────────────────────────
  #
  # Parity proof: config-built slash specs must match the pre-T8.9 hand-authored
  # table + per-handler grammar field-by-field. Auth tiers are the risk surface.

  describe ".slash_specs (real tools.yml)" do
    before { allow(Pito::Dispatch::Config).to receive(:data).and_call_original }

    subject(:specs) { described_class.slash_specs }

    it "all specs have namespace :slash" do
      expect(specs.map(&:namespace).uniq).to eq([ :slash ])
    end

    it "includes exactly the 13 declared slash tools" do
      expect(specs.map(&:name)).to contain_exactly(
        :login, :logout, :connect, :new, :resume, :games, :config,
        :disconnect, :jobs, :notifications, :rename, :themes, :help
      )
    end

    it "pins every tool's auth tier (the risk surface)" do
      auth = specs.to_h { |s| [ s.name, s.auth ] }
      expect(auth).to eq(
        login:         :unauthenticated_only,
        logout:        :authenticated_only,
        connect:       :authenticated_only,
        new:           :authenticated_only,
        resume:        :authenticated_only,
        games:         :authenticated_only,
        config:        :authenticated_only,
        disconnect:    :authenticated_only,
        jobs:          :authenticated_only,
        notifications: :authenticated_only,
        rename:        :authenticated_only,
        themes:        :authenticated_only,
        help:          :any
      )
    end

    it ":login carries the :authenticate alias and a :code free slot" do
      login = specs.find { |s| s.name == :login }
      expect(login.aliases).to eq([ :authenticate ])
      expect(login.slot(:code).kind).to eq(:free)
      expect(login.slot(:code).optional?).to be(false)
    end

    it ":logout carries the :exit and :quit aliases" do
      logout = specs.find { |s| s.name == :logout }
      expect(logout.aliases).to match_array([ :exit, :quit ])
    end

    it ":notifications carries the :notifs alias" do
      notifs = specs.find { |s| s.name == :notifications }
      expect(notifs.aliases).to eq([ :notifs ])
    end

    it ":help uses the slash description (not the chat description) and auth :any" do
      help = specs.find { |s| s.name == :help }
      expect(help.description_key).to eq("pito.grammar.slash.help")
      expect(help.auth).to eq(:any)
      expect(help.slots).to be_empty
    end

    it ":games has a :subcommand enum slot and a :title free slot" do
      games = specs.find { |s| s.name == :games }
      expect(games.slot(:subcommand).kind).to eq(:enum)
      expect(games.slot(:subcommand).source).to eq(:games_subcommands)
      expect(games.slot(:title).kind).to eq(:free)
    end

    context ":config spec (the provider→keys grammar)" do
      subject(:config) { specs.find { |s| s.name == :config } }

      it "has slots :provider, :state, :settings in order" do
        expect(config.slots.map(&:name)).to eq(%i[provider state settings])
      end

      it ":provider is a literal slot sourced from :config_providers" do
        expect(config.slot(:provider).kind).to eq(:literal)
        expect(config.slot(:provider).source).to eq(:config_providers)
      end

      it ":state is an optional on_off enum gated on provider=sound" do
        state = config.slot(:state)
        expect(state.kind).to eq(:enum)
        expect(state.source).to eq(:on_off)
        expect(state.optional?).to be(true)
        expect(state.eligible?(provider: "sound")).to be(true)
        expect(state.eligible?(provider: "google")).to be(false)
      end

      it ":settings is a repeatable, optional kv gated on the credential providers" do
        settings = config.slot(:settings)
        expect(settings.kind).to eq(:kv)
        expect(settings.source).to eq(:config_keys)
        expect(settings.repeatable?).to be(true)
        expect(settings.optional?).to be(true)
        expect(settings.eligible?(provider: "google")).to be(true)
        expect(settings.eligible?(provider: "sound")).to be(false)
      end
    end

    it "each spec's slot arrays are independent objects (no shared mutable state)" do
      config_slots = specs.find { |s| s.name == :config }.slots
      games_slots  = specs.find { |s| s.name == :games }.slots
      expect(config_slots).not_to equal(games_slots)
    end
  end

  # ── DYNAMIC_RESOLVERS constant ────────────────────────────────────────────────

  describe "DYNAMIC_RESOLVERS" do
    before { allow(Pito::Dispatch::Config).to receive(:data).and_call_original }

    it "includes all four expected resolver names" do
      expect(described_class::DYNAMIC_RESOLVERS.keys).to contain_exactly(
        :channels, :conversations, :game_titles, :video_titles
      )
    end

    it "every resolver is a callable lambda" do
      described_class::DYNAMIC_RESOLVERS.each do |name, resolver|
        expect(resolver).to respond_to(:call), "DYNAMIC_RESOLVERS[:#{name}] must be callable"
      end
    end

    it "is frozen" do
      expect(described_class::DYNAMIC_RESOLVERS).to be_frozen
    end
  end
end
