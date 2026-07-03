# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Suggestions::Catalog, type: :service do
  # Registry is already populated by the before(:each) in rails_helper.

  # ── Helpers ────────────────────────────────────────────────────────────────

  def slash_names(authenticated:)
    described_class.to_h(authenticated:)[:slash].map { |e| e[:name] }
  end

  # ── Slash auth-filter ──────────────────────────────────────────────────────

  describe ".to_h slash auth-filtering" do
    context "when unauthenticated (authenticated: false)" do
      subject(:slash) { described_class.to_h(authenticated: false)[:slash] }

      it "includes /login (the only :unauthenticated_only spec)" do
        expect(slash_names(authenticated: false)).to include("login")
      end

      # T8.9 auth-gating pin: the unauthenticated palette is EXACTLY today's set —
      # the sole :unauthenticated_only slash verb, sourced from config/pito/verbs.yml.
      it "is exactly ['login'] — the full unauthenticated set" do
        expect(slash_names(authenticated: false)).to eq(%w[login])
      end

      it "does not include /config (an authenticated spec)" do
        expect(slash_names(authenticated: false)).not_to include("config")
      end

      it "does not include /logout (an :authenticated_only spec)" do
        expect(slash_names(authenticated: false)).not_to include("logout")
      end

      it "every entry has name, insert, description, auth keys" do
        slash.each do |entry|
          expect(entry.keys).to include(:name, :insert, :description, :auth)
        end
      end

      it "insert for login is '/login '" do
        login_entry = slash.find { |e| e[:name] == "login" }
        expect(login_entry[:insert]).to eq("/login ")
      end

      it "description for login resolves via I18n" do
        login_entry = slash.find { |e| e[:name] == "login" }
        expect(login_entry[:description]).to eq(I18n.t("pito.grammar.slash.login"))
      end
    end

    context "when authenticated (authenticated: true)" do
      subject(:slash) { described_class.to_h(authenticated: true)[:slash] }

      it "includes /config" do
        expect(slash_names(authenticated: true)).to include("config")
      end

      it "includes /help" do
        expect(slash_names(authenticated: true)).to include("help")
      end

      it "does not include /login (:unauthenticated_only spec)" do
        expect(slash_names(authenticated: true)).not_to include("login")
      end

      it "includes /logout and /connect and /disconnect" do
        names = slash_names(authenticated: true)
        expect(names).to include("logout", "connect", "disconnect")
      end

      # T8.9 auth-gating pin: the authenticated palette is EXACTLY today's set —
      # every slash verb EXCEPT :unauthenticated_only login, alphabetical, from config.
      it "is exactly the 12 non-login slash verbs, alphabetical" do
        expect(slash_names(authenticated: true)).to eq(
          %w[config connect disconnect games help jobs logout new notifications rename resume themes]
        )
      end
    end
  end

  # ── Chat ───────────────────────────────────────────────────────────────────

  describe ".to_h chat" do
    subject(:chat) { described_class.to_h(authenticated: true)[:chat] }

    it "includes list, show, and find" do
      names = chat.map { |e| e[:name] }
      expect(names).to include("list", "show", "find")
    end

    it "includes the analyze verb" do
      names = chat.map { |e| e[:name] }
      expect(names).to include("analyze")
    end

    it "insert for analyze is 'analyze '" do
      analyze_entry = chat.find { |e| e[:name] == "analyze" }
      expect(analyze_entry[:insert]).to eq("analyze ")
    end

    it "description for analyze resolves via I18n to the pito.grammar.chat.analyze key" do
      analyze_entry = chat.find { |e| e[:name] == "analyze" }
      expect(analyze_entry[:description]).to eq(I18n.t("pito.grammar.chat.analyze"))
    end

    it "every entry has name, insert, description keys" do
      chat.each do |entry|
        expect(entry.keys).to include(:name, :insert, :description)
      end
    end

    it "insert for list is 'list '" do
      list_entry = chat.find { |e| e[:name] == "list" }
      expect(list_entry[:insert]).to eq("list ")
    end

    it "description for list resolves via I18n" do
      list_entry = chat.find { |e| e[:name] == "list" }
      expect(list_entry[:description]).to eq(I18n.t("pito.grammar.chat.list"))
    end
  end

  # ── Chat slot emission ─────────────────────────────────────────────────────
  #
  # Catalog#slots_for emits only :enum slots with a Symbol source.
  # Free slots and the leading free slot in schedule/price are NOT emitted.

  describe ".to_h chat slot emission" do
    def chat_entry(name)
      described_class.to_h(authenticated: true)[:chat].find { |e| e[:name] == name.to_s }
    end

    it "show emits its selection slots (free :id slot is not emitted)" do
      expect(chat_entry("show")[:slots]).to eq([
        { name: "full", source: "full_flag" },
        { name: "with", source: "show_segments" },
        { name: "only", source: "show_segments" },
        { name: "without", source: "show_segments" }
      ])
    end

    it "list emits one slot: noun/nouns" do
      expect(chat_entry("list")[:slots]).to eq([ { name: "noun", source: "nouns" } ])
    end

    it "sync emits one slot: target/sync_targets" do
      expect(chat_entry("sync")[:slots]).to eq([ { name: "target", source: "sync_targets" } ])
    end

    it "import emits one slot: noun/import_nouns (free :title slot is not emitted)" do
      expect(chat_entry("import")[:slots]).to eq([ { name: "noun", source: "import_nouns" } ])
    end

    it "footage emits one slot: title/game_titles" do
      expect(chat_entry("footage")[:slots]).to eq([ { name: "title", source: "game_titles" } ])
    end

    it "price emits one slot: subcommand/price_subcommands (free trailing slot is not emitted)" do
      expect(chat_entry("price")[:slots]).to eq([ { name: "subcommand", source: "price_subcommands" } ])
    end

    it "delete emits one slot: title/game_titles" do
      expect(chat_entry("delete")[:slots]).to eq([ { name: "title", source: "game_titles" } ])
    end

    it "reindex emits one slot: title/game_titles" do
      expect(chat_entry("reindex")[:slots]).to eq([ { name: "title", source: "game_titles" } ])
    end

    it "schedule emits one slot: slate/schedule_whens (free leading :title slot is not emitted)" do
      expect(chat_entry("schedule")[:slots]).to eq([ { name: "slate", source: "schedule_whens" } ])
    end
  end

  # ── Hashtag ────────────────────────────────────────────────────────────────

  describe ".to_h hashtag" do
    subject(:hashtag) { described_class.to_h(authenticated: true)[:hashtag] }

    it "is empty (metric-ops add/remove specs removed)" do
      expect(hashtag).to be_empty
    end
  end

  # ── Vocabularies — static ──────────────────────────────────────────────────

  describe ".to_h vocabularies[:genres]" do
    subject(:genres) { described_class.to_h(authenticated: true)[:vocabularies][:genres] }

    it "is present" do
      expect(genres).not_to be_nil
    end

    it "includes 'RPG' in canonical members" do
      expect(genres[:canonical]).to include("RPG")
    end

    it "has a synonyms hash with at least one entry" do
      expect(genres[:synonyms]).to be_a(Hash)
      expect(genres[:synonyms]).not_to be_empty
    end

    it "does not have dynamic: true" do
      expect(genres[:dynamic]).to be(false)
    end

    it "does not have an :endpoint key" do
      expect(genres.keys).not_to include(:endpoint)
    end
  end

  describe ".to_h vocabularies[:config_keys]" do
    subject(:config_keys) { described_class.to_h(authenticated: true)[:vocabularies][:config_keys] }

    it "exposes masked_keys including client_id, client_secret, api_key" do
      expect(config_keys[:masked_keys]).to include("client_id", "client_secret", "api_key")
    end

    it "masked_keys matches MASKED_CONFIG_KEYS constant" do
      expect(config_keys[:masked_keys]).to match_array(
        Pito::Grammar::Vocabularies::MASKED_CONFIG_KEYS.to_a
      )
    end

    it "includes canonical members" do
      expect(config_keys[:canonical]).to include("client_id", "client_secret")
    end
  end

  describe ".to_h vocabularies[:nouns]" do
    subject(:nouns) { described_class.to_h(authenticated: true)[:vocabularies][:nouns] }

    it "embeds 'vids' as the canonical video noun (not 'videos')" do
      expect(nouns[:canonical]).to include("vids")
      expect(nouns[:canonical]).not_to include("videos")
    end

    it "keeps 'videos'/'video'/'vid' as synonyms of 'vids' (aliases still resolve)" do
      expect(nouns[:synonyms]).to include("videos" => "vids", "video" => "vids", "vid" => "vids")
    end
  end

  describe ".to_h vocabularies[:metrics]" do
    subject(:metrics) { described_class.to_h(authenticated: true)[:vocabularies][:metrics] }

    it "embeds 'subs' as the canonical metric (not 'subscribers')" do
      expect(metrics[:canonical]).to include("subs")
      expect(metrics[:canonical]).not_to include("subscribers")
    end

    it "keeps 'subscribers'/'subscriber' as synonyms of 'subs' (aliases still resolve)" do
      expect(metrics[:synonyms]).to include("subscribers" => "subs", "subscriber" => "subs")
    end
  end

  # ── Vocabularies — dynamic ─────────────────────────────────────────────────

  describe ".to_h vocabularies[:channels]" do
    subject(:channels) { described_class.to_h(authenticated: true)[:vocabularies][:channels] }

    it "has dynamic: true" do
      expect(channels[:dynamic]).to be(true)
    end

    it "has endpoint pointing to /suggestions" do
      expect(channels[:endpoint]).to eq("/suggestions")
    end

    it "does not embed member data (no :canonical key)" do
      expect(channels.keys).not_to include(:canonical)
    end
  end

  describe ".to_h vocabularies[:conversations]" do
    subject(:conversations) { described_class.to_h(authenticated: true)[:vocabularies][:conversations] }

    it "has dynamic: true and endpoint: /suggestions" do
      expect(conversations[:dynamic]).to be(true)
      expect(conversations[:endpoint]).to eq("/suggestions")
    end
  end

  describe ".to_h vocabularies[:game_titles]" do
    subject(:game_titles) { described_class.to_h(authenticated: true)[:vocabularies][:game_titles] }

    it "has dynamic: true and endpoint: /suggestions" do
      expect(game_titles[:dynamic]).to be(true)
      expect(game_titles[:endpoint]).to eq("/suggestions")
    end
  end

  # ── Config providers autosuggest ──────────────────────────────────────────

  describe ".to_h vocabularies[:config_providers]" do
    subject(:providers) { described_class.to_h(authenticated: true)[:vocabularies][:config_providers] }

    it "includes 'me' in the canonical list" do
      expect(providers[:canonical]).to include("me")
    end
  end

  describe ".to_h vocabularies[:config_keys]" do
    subject(:keys) { described_class.to_h(authenticated: true)[:vocabularies][:config_keys] }

    it "includes 'nickname' in the canonical list" do
      expect(keys[:canonical]).to include("nickname")
    end
  end

  describe "PROVIDER_KEYS for me" do
    it "maps 'me' provider to ['nickname']" do
      expect(Pito::Grammar::Vocabularies::PROVIDER_KEYS["me"]).to eq(%w[nickname])
    end
  end

  # ── Top-level shape ────────────────────────────────────────────────────────

  describe ".to_h top-level keys" do
    subject(:catalog) { described_class.to_h(authenticated: true) }

    it "has slash, hashtag, chat, and vocabularies keys" do
      expect(catalog.keys).to contain_exactly(:slash, :hashtag, :chat, :vocabularies)
    end

    it "vocabularies is a Hash" do
      expect(catalog[:vocabularies]).to be_a(Hash)
    end
  end

  # ── to_json ────────────────────────────────────────────────────────────────

  describe ".to_json" do
    it "returns a String for authenticated: true" do
      expect(described_class.to_json(authenticated: true)).to be_a(String)
    end

    it "returns valid JSON that round-trips for authenticated: true" do
      json   = described_class.to_json(authenticated: true)
      parsed = JSON.parse(json)
      expect(parsed).to be_a(Hash)
      expect(parsed.keys).to include("slash", "hashtag", "chat", "vocabularies")
    end

    it "returns valid JSON that round-trips for authenticated: false" do
      json   = described_class.to_json(authenticated: false)
      parsed = JSON.parse(json)
      expect(parsed["slash"].map { |e| e["name"] }).to include("login")
    end
  end
end
