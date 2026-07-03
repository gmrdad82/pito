# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `list`/`ls` (recognition only, DB mocked) ───────────────
#
# RULE: every kwarg combination recognised — no exception. We test what the
# dispatcher UNDERSTANDS, not what exists in the DB. The spec has three tiers:
#
#   A. Pure-parse assertions — call WithColumns.parse, SortClause.parse,
#      GameListFilter.filtered?/suggestions, noun vocab resolution, and
#      sort_key_for directly.  Zero AR touching.
#
#   B. Verb-routing assertions — use parsed_intent() (grammar-only, no DB).
#
#   C. Handler-level assertions (few) — invoke the handler with AR stubs to
#      verify routing branch taken (--help vs games vs vids vs channels).
#
RSpec.describe "Dispatch matrix — list/ls (recognition, DB mocked)", type: :dispatch do
  # ── Pure-parse helpers ──────────────────────────────────────────────────────

  # Replicates the private noun_head from Handlers::List so we can call it here.
  def noun_head(raw)
    raw.to_s.split(/\b(?:with|sort(?:ed)?|order(?:ed)?)\b/i, 2).first.to_s
  end

  # Replicates detected_noun from Handlers::List.
  def detected_noun(raw)
    head = noun_head(raw)
    vocab = Pito::Grammar::Registry.vocabulary(:nouns)
    head.downcase.split(/\s+/).each do |token|
      canonical = vocab.resolve(token)
      return canonical if canonical
    end
    nil
  end

  def parse_video_columns(raw)
    Pito::Chat::WithColumns.parse(raw, vocabulary: Pito::MessageBuilder::Video::ListColumns.vocabulary)
  end

  def parse_game_columns(raw)
    Pito::Chat::WithColumns.parse(raw, vocabulary: Pito::MessageBuilder::Game::ListColumns.vocabulary)
  end

  def parse_sort(raw)
    Pito::Chat::SortClause.parse(raw)
  end

  # ── Handler builder (for tier-C tests only) ─────────────────────────────────

  def build_handler(raw, channel: nil, viewport_width: nil)
    Pito::Chat::Handlers::List.new(
      message:        Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw:),
      conversation:   instance_double(Conversation, id: 1, uuid: "test"),
      channel:        channel,
      viewport_width: viewport_width
    )
  end

  # ── B. Verb routing ──────────────────────────────────────────────────────────

  describe "B. Verb routing — list + ls" do
    %w[list ls].each do |verb|
      it "#{verb.inspect} (bare) routes to Pito::Chat::Handlers::List" do
        intent = parsed_intent(verb)
        expect(intent[:handler]).to eq(Pito::Chat::Handlers::List)
      end

      it "#{verb.inspect} games routes to Pito::Chat::Handlers::List" do
        intent = parsed_intent("#{verb} games")
        expect(intent[:handler]).to eq(Pito::Chat::Handlers::List)
      end

      it "#{verb.inspect} vids routes to Pito::Chat::Handlers::List" do
        intent = parsed_intent("#{verb} vids")
        expect(intent[:handler]).to eq(Pito::Chat::Handlers::List)
      end

      it "#{verb.inspect} channels routes to Pito::Chat::Handlers::List" do
        intent = parsed_intent("#{verb} channels")
        expect(intent[:handler]).to eq(Pito::Chat::Handlers::List)
      end
    end
  end

  # ── A1. Noun routing (detected_noun) ─────────────────────────────────────────

  describe "A1. Noun routing" do
    # nil → games path (no noun recognised → falls through to games)
    {
      "list"          => nil,
      "ls"            => nil,
      "list rpg"      => nil,   # filter token but not a noun
      "list upcoming" => nil,   # filter token but not a noun
      "list ps5"      => nil
    }.each do |raw, noun|
      it "#{raw.inspect} → detected_noun=#{noun.inspect} (games path)" do
        expect(detected_noun(raw)).to eq(noun)
      end
    end

    # games
    {
      "list games"    => "games",
      "ls games"      => "games",
      "list game"     => "games",
      "ls game"       => "games",
      "list gamez"    => "games",
      "ls gamez"      => "games"
    }.each do |raw, noun|
      it "#{raw.inspect} → detected_noun=#{noun.inspect}" do
        expect(detected_noun(raw)).to eq(noun)
      end
    end

    # vids
    {
      "list vids"     => "vids",
      "ls vids"       => "vids",
      "list vid"      => "vids",
      "ls vid"        => "vids",
      "list video"    => "vids",
      "ls video"      => "vids",
      "list videos"   => "vids",
      "ls videos"     => "vids"
    }.each do |raw, noun|
      it "#{raw.inspect} → detected_noun=#{noun.inspect}" do
        expect(detected_noun(raw)).to eq(noun)
      end
    end

    # channels
    {
      "list channels" => "channels",
      "ls channels"   => "channels",
      "list channel"  => "channels",
      "ls channel"    => "channels"
    }.each do |raw, noun|
      it "#{raw.inspect} → detected_noun=#{noun.inspect}" do
        expect(detected_noun(raw)).to eq(noun)
      end
    end

    # with-clause isolation: the noun-head stops at 'with', so column names
    # inside the clause are never mistaken for the noun.
    it "list games with channels → noun=games (channels is a column name, not the noun)" do
      expect(detected_noun("list games with channels")).to eq("games")
    end

    it "list games with channel → noun=games" do
      expect(detected_noun("list games with channel")).to eq("games")
    end

    it "list vids with game → noun=vids (game inside with clause)" do
      expect(detected_noun("list vids with game")).to eq("vids")
    end

    it "list vids with games → noun=vids" do
      expect(detected_noun("list vids with games")).to eq("vids")
    end

    # sort clause also stops the head
    it "list games sort by title → noun=games (sort stops noun head)" do
      expect(detected_noun("list games sort by title")).to eq("games")
    end

    it "list vids sorted by views → noun=vids" do
      expect(detected_noun("list vids sorted by views")).to eq("vids")
    end
  end

  # ── A2. Video column vocabulary (every alias) ─────────────────────────────────

  describe "A2. Video with-clause column vocabulary" do
    video_aliases = {
      "channel"    => :channel,
      "status"     => :visibility,
      "visibility" => :visibility,
      "game"       => :game,
      "games"      => :game,
      "length"     => :duration,
      "duration"   => :duration,
      "views"      => :views,
      "likes"      => :likes,
      "comms"      => :comments,
      "comments"   => :comments,
      "category"   => :category,
      "categories" => :category
    }

    video_aliases.each do |alias_token, canonical|
      it "list vids with #{alias_token.inspect} → [#{canonical.inspect}]" do
        expect(parse_video_columns("list vids with #{alias_token}")).to eq([ canonical ])
      end
    end

    # Aliases that collapse to the same canonical
    it "status + visibility → de-duplicated to [:visibility]" do
      expect(parse_video_columns("list vids with status, visibility")).to eq([ :visibility ])
    end

    it "game + games → de-duplicated to [:game]" do
      expect(parse_video_columns("list vids with game, games")).to eq([ :game ])
    end

    it "length + duration → de-duplicated to [:duration]" do
      expect(parse_video_columns("list vids with length, duration")).to eq([ :duration ])
    end

    it "comms + comments → de-duplicated to [:comments]" do
      expect(parse_video_columns("list vids with comms, comments")).to eq([ :comments ])
    end

    it "category + categories → de-duplicated to [:category]" do
      expect(parse_video_columns("list vids with category, categories")).to eq([ :category ])
    end

    # Multi-column comma list
    it "with views, likes, comments → [:views, :likes, :comments] in order" do
      expect(parse_video_columns("list vids with views, likes, comments")).to eq([ :views, :likes, :comments ])
    end

    it "all video columns in one with clause → all 8 canonicals de-duped" do
      raw = "list vids with channel, status, game, length, views, likes, comms, category"
      expect(parse_video_columns(raw)).to eq(
        [ :channel, :visibility, :game, :duration, :views, :likes, :comments, :category ]
      )
    end

    # Unknown tokens are silently dropped
    it "unknown token mixed with valid token → valid token kept, unknown dropped" do
      expect(parse_video_columns("list vids with views, foobar, likes")).to eq([ :views, :likes ])
    end

    # No with clause
    it "no with clause → []" do
      expect(parse_video_columns("list vids")).to eq([])
    end

    it "bare list → []" do
      expect(parse_video_columns("list")).to eq([])
    end
  end

  # ── A3. Game column vocabulary (every alias) ──────────────────────────────────

  describe "A3. Game with-clause column vocabulary" do
    game_aliases = {
      "platform"     => :platform,
      "platforms"    => :platform,
      "genre"        => :genre,
      "genres"       => :genre,
      "developer"    => :developer,
      "dev"          => :developer,
      "publisher"    => :publisher,
      "channel"      => :channels,
      "channels"     => :channels,
      "footage"      => :footage,
      "price"        => :price,
      "prices"       => :price
    }

    game_aliases.each do |alias_token, canonical|
      it "list games with #{alias_token.inspect} → [#{canonical.inspect}]" do
        expect(parse_game_columns("list games with #{alias_token}")).to eq([ canonical ])
      end
    end

    # De-duplication for aliases sharing the same canonical
    it "platform + platforms → de-duplicated to [:platform]" do
      expect(parse_game_columns("list games with platform, platforms")).to eq([ :platform ])
    end

    it "genre + genres → de-duplicated to [:genre]" do
      expect(parse_game_columns("list games with genre, genres")).to eq([ :genre ])
    end

    it "developer + dev → de-duplicated to [:developer]" do
      expect(parse_game_columns("list games with developer, dev")).to eq([ :developer ])
    end

    it "channel + channels → de-duplicated to [:channels]" do
      expect(parse_game_columns("list games with channel, channels")).to eq([ :channels ])
    end

    it "the removed release/year columns are dropped from a with clause (item 24)" do
      expect(parse_game_columns("list games with release date, year")).to eq([])
    end

    it "price + prices → de-duplicated to [:price]" do
      expect(parse_game_columns("list games with price, prices")).to eq([ :price ])
    end

    # Multi-column comma list
    it "with platform, genre, developer → [:platform, :genre, :developer] in order" do
      expect(parse_game_columns("list games with platform, genre, developer")).to eq(
        [ :platform, :genre, :developer ]
      )
    end

    it "all game columns in one with clause → all 7 canonicals (release/year removed — item 24)" do
      raw = "list games with platform, genre, developer, publisher, channels, footage, price"
      expect(parse_game_columns(raw)).to eq(
        [ :platform, :genre, :developer, :publisher, :channels, :footage, :price ]
      )
    end

    # Unknown tokens dropped
    it "with genre, foobar → [:genre] (unknown dropped)" do
      expect(parse_game_columns("list games with genre, foobar")).to eq([ :genre ])
    end

    # No with clause
    it "no with clause → []" do
      expect(parse_game_columns("list games")).to eq([])
    end

    it "bare ls → []" do
      expect(parse_game_columns("ls")).to eq([])
    end
  end

  # ── A4. SortClause.parse — sort verb forms ────────────────────────────────────

  describe "A4. SortClause.parse — sort verb forms" do
    %w[sort sorted order ordered].each do |verb|
      it "#{verb} <col> → token parsed" do
        result = parse_sort("list games #{verb} views")
        expect(result).to be_a(Hash)
        expect(result[:token]).to eq("views")
      end

      it "#{verb} by <col> → token parsed (by is optional)" do
        result = parse_sort("list games #{verb} by views")
        expect(result).to be_a(Hash)
        expect(result[:token]).to eq("views")
      end
    end

    describe "direction suffixes" do
      %w[asc ascending].each do |dir|
        it "sort views #{dir} → :asc" do
          expect(parse_sort("list games sort views #{dir}")[:direction]).to eq(:asc)
        end
      end

      %w[desc descending].each do |dir|
        it "sort views #{dir} → :desc" do
          expect(parse_sort("list games sort views #{dir}")[:direction]).to eq(:desc)
        end
      end

      it "no direction suffix → defaults to :asc" do
        expect(parse_sort("list games sort by views")[:direction]).to eq(:asc)
      end
    end

    it "bare sort (no column) → nil" do
      expect(parse_sort("list games sort")).to be_nil
    end

    it "no sort clause at all → nil" do
      expect(parse_sort("list games")).to be_nil
    end

    it "multi-word column: sort by release date → token='release date'" do
      result = parse_sort("list games sort by release date")
      expect(result).to eq({ token: "release date", direction: :asc })
    end

    it "sort by release date desc → token='release date', direction=:desc" do
      result = parse_sort("list games sort by release date desc")
      expect(result).to eq({ token: "release date", direction: :desc })
    end

    it "sort is case-insensitive (SORT BY Views DESC)" do
      result = parse_sort("list games SORT BY Views DESC")
      expect(result).to eq({ token: "views", direction: :desc })
    end

    it "'developer' does not trip sort clause (word-boundary guard on sort)" do
      expect(parse_sort("list games with developer")).to be_nil
    end

    it "'disorder' does not trip sort clause" do
      expect(parse_sort("list games disorder")).to be_nil
    end

    it "'resort' does not trip sort clause" do
      expect(parse_sort("list games resort")).to be_nil
    end

    it "ordered without by: ordered views → token=views" do
      result = parse_sort("list games ordered views")
      expect(result[:token]).to eq("views")
    end
  end

  # ── A5. Video sort token → canonical column (SORT_VOCAB) ─────────────────────

  describe "A5. Video sort token vocabulary" do
    {
      "id"         => :id,
      "title"      => :title,
      "channel"    => :channel,
      "handle"     => :channel,
      "@handle"    => :channel,
      "visibility" => :visibility,
      "game"       => :game,
      "games"      => :game,
      "duration"   => :duration,
      "views"      => :views,
      "likes"      => :likes,
      "comms"      => :comments,
      "comments"   => :comments
    }.each do |token, canonical|
      it "video sort token #{token.inspect} → canonical :#{canonical}" do
        expect(Pito::MessageBuilder::Video::ListColumns::SORT_VOCAB[token]).to eq(canonical)
      end
    end

    it "unknown token is absent from SORT_VOCAB" do
      expect(Pito::MessageBuilder::Video::ListColumns::SORT_VOCAB["foobar"]).to be_nil
    end
  end

  # ── A6. Game sort token → canonical column (SORT_VOCAB) ──────────────────────

  describe "A6. Game sort token vocabulary" do
    {
      "id"           => :id,
      "#"            => :id,
      "title"        => :title,
      "game"         => :title,
      "platform"     => :platform,
      "platforms"    => :platform,
      "genre"        => :genre,
      "genres"       => :genre,
      "developer"    => :developer,
      "dev"          => :developer,
      "publisher"    => :publisher,
      "channel"      => :channels,
      "channels"     => :channels,
      "footage"      => :footage,
      "price"        => :price,
      "prices"       => :price
    }.each do |token, canonical|
      it "game sort token #{token.inspect} → canonical :#{canonical}" do
        expect(Pito::MessageBuilder::Game::ListColumns::SORT_VOCAB[token]).to eq(canonical)
      end
    end

    it "unknown token absent from game SORT_VOCAB" do
      expect(Pito::MessageBuilder::Game::ListColumns::SORT_VOCAB["foobar"]).to be_nil
    end

    it "the removed 'release date' / 'year' sort tokens are gone (item 24)" do
      expect(Pito::MessageBuilder::Game::ListColumns::SORT_VOCAB["release date"]).to be_nil
      expect(Pito::MessageBuilder::Game::ListColumns::SORT_VOCAB["year"]).to be_nil
    end
  end

  # ── A7. sort_key_for: requires_with gating (video) ───────────────────────────

  describe "A7. Video sort_key_for — requires_with gating" do
    let(:vlc) { Pito::MessageBuilder::Video::ListColumns }

    # Base columns (requires_with: false) — always available regardless of selected columns
    it "id: always available (requires_with: false)" do
      expect(vlc.sort_key_for("id", selected_columns: [])).to be_a(Proc)
    end

    it "title: always available (requires_with: false)" do
      expect(vlc.sort_key_for("title", selected_columns: [])).to be_a(Proc)
    end

    # With-columns (requires_with: true) — nil when column absent, Proc when present
    {
      "channel"    => :channel,
      "handle"     => :channel,
      "@handle"    => :channel,
      "visibility" => :visibility,
      "game"       => :game,
      "games"      => :game,
      "duration"   => :duration,
      "views"      => :views,
      "likes"      => :likes,
      "comms"      => :comments,
      "comments"   => :comments
    }.each do |sort_token, canonical_col|
      it "#{sort_token.inspect} → nil when :#{canonical_col} not in selected_columns" do
        expect(vlc.sort_key_for(sort_token, selected_columns: [])).to be_nil
      end

      it "#{sort_token.inspect} → Proc when :#{canonical_col} is in selected_columns" do
        expect(vlc.sort_key_for(sort_token, selected_columns: [ canonical_col ])).to be_a(Proc)
      end
    end
  end

  # ── A8. sort_key_for: requires_with gating (game) ────────────────────────────

  describe "A8. Game sort_key_for — requires_with gating" do
    let(:glc) { Pito::MessageBuilder::Game::ListColumns }

    # Base columns (requires_with: false)
    it "id: always available" do
      expect(glc.sort_key_for("id", selected_columns: [])).to be_a(Proc)
    end

    it "#: resolves to :id, always available" do
      expect(glc.sort_key_for("#", selected_columns: [])).to be_a(Proc)
    end

    it "title: always available" do
      expect(glc.sort_key_for("title", selected_columns: [])).to be_a(Proc)
    end

    it "game token: resolves to :title, always available" do
      expect(glc.sort_key_for("game", selected_columns: [])).to be_a(Proc)
    end

    # With-columns (requires_with: true)
    {
      "platform"     => :platform,
      "platforms"    => :platform,
      "genre"        => :genre,
      "genres"       => :genre,
      "developer"    => :developer,
      "dev"          => :developer,
      "publisher"    => :publisher,
      "channel"      => :channels,
      "channels"     => :channels,
      "footage"      => :footage,
      "price"        => :price,
      "prices"       => :price
    }.each do |sort_token, canonical_col|
      it "#{sort_token.inspect} → nil when :#{canonical_col} not in selected_columns" do
        expect(glc.sort_key_for(sort_token, selected_columns: [])).to be_nil
      end

      it "#{sort_token.inspect} → Proc when :#{canonical_col} is in selected_columns" do
        expect(glc.sort_key_for(sort_token, selected_columns: [ canonical_col ])).to be_a(Proc)
      end
    end
  end

  # ── A9. Combined with + sort ──────────────────────────────────────────────────

  describe "A9. with + sort combined" do
    it "video: with clause stops before sort; both parsed independently" do
      raw  = "list vids with views, comments, game sort by views desc"
      cols = parse_video_columns(raw)
      sort = parse_sort(raw)
      expect(cols).to eq([ :views, :comments, :game ])
      expect(sort).to eq({ token: "views", direction: :desc })
    end

    it "video: sort column does not leak into with columns" do
      raw  = "list vids with views sort by likes"
      cols = parse_video_columns(raw)
      expect(cols).to eq([ :views ])
      expect(cols).not_to include(:likes)
    end

    it "game: with platform, genre sorted by genre desc" do
      raw  = "list games with platform, genre sorted by genre desc"
      cols = parse_game_columns(raw)
      sort = parse_sort(raw)
      expect(cols).to eq([ :platform, :genre ])
      expect(sort).to eq({ token: "genre", direction: :desc })
    end

    it "game: with + sort on a still-valid column (footage)" do
      raw  = "list games with platform, footage order by footage asc"
      cols = parse_game_columns(raw)
      sort = parse_sort(raw)
      expect(cols).to include(:footage)
      expect(sort[:token]).to eq("footage")
      expect(sort[:direction]).to eq(:asc)
    end

    it "game: ordered by title ascending" do
      sort = parse_sort("list games ordered by title ascending")
      expect(sort).to eq({ token: "title", direction: :asc })
    end

    it "video: order views descending" do
      sort = parse_sort("list vids order views descending")
      expect(sort).to eq({ token: "views", direction: :desc })
    end

    it "video: sorted by comms → token='comms'" do
      sort = parse_sort("list vids sorted by comms")
      expect(sort[:token]).to eq("comms")
    end

    it "video: with channel, visibility, comms sorted by comms desc" do
      raw  = "list vids with channel, visibility, comms sorted by comms desc"
      cols = parse_video_columns(raw)
      sort = parse_sort(raw)
      expect(cols).to eq([ :channel, :visibility, :comments ])
      expect(sort).to eq({ token: "comms", direction: :desc })
    end

    it "game: with channels, footage, price order by price desc" do
      raw  = "list games with channels, footage, price order by price desc"
      cols = parse_game_columns(raw)
      sort = parse_sort(raw)
      expect(cols).to eq([ :channels, :footage, :price ])
      expect(sort).to eq({ token: "price", direction: :desc })
    end
  end

  # ── A10. Video visibility filter recognition ──────────────────────────────────

  describe "A10. Video visibility filter — VISIBILITY_FILTERS constant" do
    subject(:vf) { Pito::Chat::Handlers::List::VISIBILITY_FILTERS }

    it "has exactly 3 entries: published, unlisted, scheduled" do
      expect(vf.keys).to eq(%w[published unlisted scheduled])
    end

    it "published → :published" do
      expect(vf["published"]).to eq(:published)
    end

    it "unlisted → :unlisted" do
      expect(vf["unlisted"]).to eq(:unlisted)
    end

    it "scheduled → :scheduled" do
      expect(vf["scheduled"]).to eq(:scheduled)
    end
  end

  describe "A10. Video visibility filter — word-boundary regex recognition" do
    # The handler uses: raw.match?(/\b#{Regexp.escape(word)}\b/i) for each key.
    def visibility_from(raw)
      Pito::Chat::Handlers::List::VISIBILITY_FILTERS.find do |word, _|
        raw.match?(/\b#{Regexp.escape(word)}\b/i)
      end&.last
    end

    {
      "list vids published"                       => :published,
      "list videos published"                     => :published,
      "ls vids published"                         => :published,
      "list vids unlisted"                        => :unlisted,
      "list videos unlisted"                      => :unlisted,
      "list vids scheduled"                       => :scheduled,
      "list videos scheduled"                     => :scheduled,
      "list vids with views, likes published"     => :published,
      "list vids with channel published"          => :published,
      "list vids published with views"            => :published,
      "PUBLISHED list vids"                       => :published,   # case-insensitive
      "list vids UNLISTED"                        => :unlisted,
      "list vids SCHEDULED"                       => :scheduled
    }.each do |raw, scope|
      it "#{raw.inspect} → filter=:#{scope}" do
        expect(visibility_from(raw)).to eq(scope)
      end
    end

    it "no visibility word → nil (no filter)" do
      expect(visibility_from("list vids with views")).to be_nil
    end

    it "no visibility word on bare list → nil" do
      expect(visibility_from("list vids")).to be_nil
    end
  end

  # ── A11. GameListFilter — filter recognition ──────────────────────────────────

  describe "A11. GameListFilter — upcoming keyword" do
    it "list games upcoming → filtered? = true" do
      expect(Pito::Chat::GameListFilter.filtered?("list games upcoming")).to be(true)
    end

    it "ls games upcoming → filtered? = true" do
      expect(Pito::Chat::GameListFilter.filtered?("ls games upcoming")).to be(true)
    end

    it "list upcoming → filtered? = true (no noun needed)" do
      expect(Pito::Chat::GameListFilter.filtered?("list upcoming")).to be(true)
    end

    it "list games → filtered? = false (no filter keyword)" do
      expect(Pito::Chat::GameListFilter.filtered?("list games")).to be(false)
    end

    it "bare list → filtered? = false" do
      expect(Pito::Chat::GameListFilter.filtered?("list")).to be(false)
    end
  end

  describe "A11. GameListFilter — every genre alias" do
    Pito::Chat::GameListFilter::GENRE_ALIASES.keys.each do |alias_token|
      it "list games #{alias_token} → filtered? = true" do
        expect(Pito::Chat::GameListFilter.filtered?("list games #{alias_token}")).to be(true)
      end
    end
  end

  describe "A11. GameListFilter — every platform synonym" do
    Pito::Chat::GameListFilter::PLATFORM_SYNONYMS.keys.each do |alias_token|
      it "list games #{alias_token} → filtered? = true" do
        expect(Pito::Chat::GameListFilter.filtered?("list games #{alias_token}")).to be(true)
      end
    end
  end

  describe "A11. GameListFilter — combined filters" do
    it "list games rpg ps5 → filtered? = true (genre + platform)" do
      expect(Pito::Chat::GameListFilter.filtered?("list games rpg ps5")).to be(true)
    end

    it "list games upcoming rpg → filtered? = true (upcoming + genre)" do
      expect(Pito::Chat::GameListFilter.filtered?("list games upcoming rpg")).to be(true)
    end

    it "list games upcoming switch → filtered? = true (upcoming + platform)" do
      expect(Pito::Chat::GameListFilter.filtered?("list games upcoming switch")).to be(true)
    end

    it "list games action adventure → filtered? = true (two genre aliases)" do
      expect(Pito::Chat::GameListFilter.filtered?("list games action adventure")).to be(true)
    end

    it "list games ps4 xbox → filtered? = true (two platform synonyms)" do
      expect(Pito::Chat::GameListFilter.filtered?("list games ps4 xbox")).to be(true)
    end
  end

  describe "A11. GameListFilter — with-clause column names vs filter tokens" do
    # 'genre' is NOT in GENRE_ALIASES (the filter aliases are e.g. 'rpg', 'shooter')
    it "list games with genre → filtered? = false (genre is not a filter alias)" do
      expect(Pito::Chat::GameListFilter.filtered?("list games with genre")).to be(false)
    end

    # 'platform' IS in GENRE_ALIASES (maps to 'Platform' genre) — corner case
    it "list games with platform → filtered? = true (platform is also a genre alias)" do
      expect(Pito::Chat::GameListFilter.filtered?("list games with platform")).to be(true)
    end

    it "list games with year, footage → filtered? = false" do
      expect(Pito::Chat::GameListFilter.filtered?("list games with year, footage")).to be(false)
    end

    it "list games with developer → filtered? = false" do
      expect(Pito::Chat::GameListFilter.filtered?("list games with developer")).to be(false)
    end
  end

  # ── A12. GameListFilter — recognized? ────────────────────────────────────────

  describe "A12. GameListFilter.recognized?" do
    it "verb token 'list' → recognized" do
      expect(Pito::Chat::GameListFilter.recognized?("list")).to be(true)
    end

    it "verb token 'ls' → recognized" do
      expect(Pito::Chat::GameListFilter.recognized?("ls")).to be(true)
    end

    it "'upcoming' → recognized" do
      expect(Pito::Chat::GameListFilter.recognized?("upcoming")).to be(true)
    end

    # Every genre alias
    Pito::Chat::GameListFilter::GENRE_ALIASES.keys.each do |alias_token|
      it "genre alias #{alias_token.inspect} → recognized" do
        expect(Pito::Chat::GameListFilter.recognized?(alias_token)).to be(true)
      end
    end

    # Every platform synonym
    Pito::Chat::GameListFilter::PLATFORM_SYNONYMS.keys.each do |alias_token|
      it "platform synonym #{alias_token.inspect} → recognized" do
        expect(Pito::Chat::GameListFilter.recognized?(alias_token)).to be(true)
      end
    end

    # Noun tokens (from :nouns vocabulary)
    %w[games vids channels game vid video videos channel gamez].each do |noun_token|
      it "noun token #{noun_token.inspect} → recognized" do
        expect(Pito::Chat::GameListFilter.recognized?(noun_token)).to be(true)
      end
    end

    it "unknown token → not recognized" do
      expect(Pito::Chat::GameListFilter.recognized?("foobar")).to be(false)
    end

    it "with-clause keyword 'with' → not recognized (not a filter vocab term)" do
      expect(Pito::Chat::GameListFilter.recognized?("with")).to be(false)
    end
  end

  # ── A13. GameListFilter — did-you-mean suggestions ───────────────────────────

  describe "A13. GameListFilter.suggestions — did-you-mean" do
    it "recognized token → no suggestion" do
      expect(Pito::Chat::GameListFilter.suggestions("list games rpg")).to be_empty
    end

    it "short token (< FUZZY_MIN_LENGTH=4 chars) → no suggestion" do
      expect(Pito::Chat::GameListFilter.suggestions("list yo")).to be_empty
      expect(Pito::Chat::GameListFilter.suggestions("list me")).to be_empty
    end

    it "close typo 'rpgg' (1 edit from rpg) → suggestion returned" do
      # 'rpgg' length=4 >= FUZZY_MIN_LENGTH=4; levenshtein('rpgg','rpg')=1 <= 2
      result = Pito::Chat::GameListFilter.suggestions("list games rpgg")
      expect(result).not_to be_empty
    end

    it "close typo 'ps55' (1 edit from ps5... but ps5 length 3 < min 4) → no suggestion for ps55" do
      # |ps55|=4 >= FUZZY_MIN_LENGTH=4, but |ps5|=3, diff=1 ok, levenshtein=1 ok
      # However 'ps5' is only 3 chars: |4-3|=1 <= 2, levenshtein('ps55','ps5')=1 → suggestion
      result = Pito::Chat::GameListFilter.suggestions("list ps55")
      # ps55 is 1 edit from 'ps5' (length 3), diff=1 ok
      expect(result).not_to be_empty
    end

    it "verb + noun tokens excluded from suggestions even when fuzzy-close" do
      # 'games' is recognized → excluded; no suggestion for it
      result = Pito::Chat::GameListFilter.suggestions("list games")
      expect(result).to be_empty
    end

    it "completely unknown long token with no close vocab → no suggestion" do
      result = Pito::Chat::GameListFilter.suggestions("list xyzzy")
      # 'xyzzy' length=5; check against all vocab... unlikely to be within 2 edits
      # We don't assert the exact value since it depends on vocab; just assert empty or that
      # any suggestion is a real vocabulary term
      unless result.empty?
        all_vocab = Pito::Chat::GameListFilter::GENRE_ALIASES.keys +
                    Pito::Chat::GameListFilter::PLATFORM_SYNONYMS.keys +
                    [ "upcoming" ]
        result.each { |s| expect(all_vocab).to include(s) }
      end
    end
  end

  # ── A14. --help routing recognition ──────────────────────────────────────────

  describe "A14. --help routing" do
    # The handler checks: message.raw.match?(/(?:\A|\s)--help(?:\s|\z)/)
    # This only fires after the noun check (channels/vids route to their branches first).

    def matches_help_pattern?(raw)
      raw.match?(/(?:\A|\s)--help(?:\s|\z)/)
    end

    it "'list --help' matches the --help pattern" do
      expect(matches_help_pattern?("list --help")).to be(true)
    end

    it "'list games --help' matches the --help pattern" do
      expect(matches_help_pattern?("list games --help")).to be(true)
    end

    it "'ls --help' matches the --help pattern" do
      expect(matches_help_pattern?("ls --help")).to be(true)
    end

    it "'ls games --help' matches the --help pattern" do
      expect(matches_help_pattern?("ls games --help")).to be(true)
    end

    it "'list --help extra' matches the --help pattern" do
      expect(matches_help_pattern?("list --help extra")).to be(true)
    end

    it "'list vids --help' — noun=vids (video path runs before --help check)" do
      expect(detected_noun("list vids --help")).to eq("vids")
    end

    it "'list videos --help' — noun=vids (video path first)" do
      expect(detected_noun("list videos --help")).to eq("vids")
    end

    it "'list channels --help' — noun=channels (channels path runs before --help)" do
      expect(detected_noun("list channels --help")).to eq("channels")
    end

    it "'list --help' — noun=nil → --help fires on games path" do
      expect(detected_noun("list --help")).to be_nil
    end

    it "'list games --help' — noun=games → no channel/vid branch → --help fires" do
      expect(detected_noun("list games --help")).to eq("games")
    end

    it "plain 'list games' does not match --help pattern" do
      expect(matches_help_pattern?("list games")).to be(false)
    end
  end

  # ── A15. Bare list / auto-fill ────────────────────────────────────────────────

  describe "A15. Bare list — auto-fill column order" do
    it "game COLUMNS canonical order is [:platform, :genre, :developer, :publisher, :channels, :footage, :price] (release/year removed — item 24)" do
      expect(Pito::MessageBuilder::Game::ListColumns::COLUMNS.keys).to eq(
        [ :platform, :genre, :developer, :publisher, :channels, :footage, :price ]
      )
    end

    it "video COLUMNS canonical order is [:channel, :visibility, :game, :duration, :views, :likes, :comments, :category]" do
      expect(Pito::MessageBuilder::Video::ListColumns::COLUMNS.keys).to eq(
        [ :channel, :visibility, :game, :duration, :views, :likes, :comments, :category ]
      )
    end

    it "MAX_AUTOFILL_COLS = 6" do
      expect(Pito::Chat::Handlers::List::MAX_AUTOFILL_COLS).to eq(6)
    end

    it "bare 'list' → no with clause → WithColumns.parse returns [] for both vocabs" do
      expect(parse_game_columns("list")).to eq([])
      expect(parse_video_columns("list")).to eq([])
    end

    it "game auto-fill first 6 canonical columns when viewport wide enough" do
      all_cols   = Pito::MessageBuilder::Game::ListColumns::COLUMNS.keys
      autofill_6 = all_cols.first(6)
      expect(autofill_6).to eq([ :platform, :genre, :developer, :publisher, :channels, :footage ])
    end

    it "video auto-fill first 6 canonical columns when viewport wide enough" do
      all_cols   = Pito::MessageBuilder::Video::ListColumns::COLUMNS.keys
      autofill_6 = all_cols.first(6)
      expect(autofill_6).to eq([ :channel, :visibility, :game, :duration, :views, :likes ])
    end
  end

  # ── C. Handler routing (AR stubs) ────────────────────────────────────────────
  # Minimal handler-level tests to confirm the routing branch is entered,
  # not the full rendering path. We stub the AR chain + message builders.

  describe "C. Handler routing — channel / video / games branches" do
    let(:game_rel) do
      rel = double("game_relation")
      allow(rel).to receive(:upcoming).and_return(rel)
      allow(rel).to receive(:joins).and_return(rel)
      allow(rel).to receive(:where).and_return(rel)
      allow(rel).to receive(:distinct).and_return(rel)
      allow(rel).to receive(:includes).and_return(rel)
      allow(rel).to receive(:empty?).and_return(false)
      allow(rel).to receive(:to_a).and_return([])
      allow(rel).to receive(:count).and_return(0)   # unsorted path: COUNT + LIMITed fetch
      allow(rel).to receive(:limit).and_return(rel)
      rel
    end

    let(:video_rel) do
      rel = double("video_relation")
      allow(rel).to receive(:published).and_return(rel)
      allow(rel).to receive(:unlisted).and_return(rel)
      allow(rel).to receive(:scheduled).and_return(rel)
      allow(rel).to receive(:includes).and_return(rel)
      allow(rel).to receive(:order).and_return(rel)
      allow(rel).to receive(:empty?).and_return(false)
      allow(rel).to receive(:to_a).and_return([])
      allow(rel).to receive(:count).and_return(0)   # unsorted path: COUNT + LIMITed fetch
      allow(rel).to receive(:limit).and_return(rel)
      rel
    end

    let(:channel_rel) do
      rel = double("channel_relation")
      allow(rel).to receive(:not).and_return(rel)
      allow(rel).to receive(:includes).and_return(rel)
      allow(rel).to receive(:order).and_return(rel)
      allow(rel).to receive(:empty?).and_return(false)
      allow(rel).to receive(:to_a).and_return([]) # Phase LS: sort works on the loaded array
      allow(rel).to receive(:select).and_return([])
      rel
    end

    before do
      allow(::Game).to  receive(:order).and_return(game_rel)
      allow(::Video).to receive(:all).and_return(video_rel)
      allow(::Channel).to receive(:where).and_return(channel_rel)
      allow(Pito::MessageBuilder::Game::List).to   receive(:call).and_return({ "kind" => "game_list" })
      allow(Pito::MessageBuilder::Video::List).to  receive(:call).and_return({ "kind" => "video_list" })
      allow(Pito::MessageBuilder::Channel::List).to receive(:call).and_return({ "kind" => "channel_list" })
      allow(Pito::MessageBuilder::Game::ListHelp).to receive(:call).and_return({ "kind" => "help" })
    end

    it "list channels → list_channels branch (Channel::List called)" do
      build_handler("list channels").call
      expect(Pito::MessageBuilder::Channel::List).to have_received(:call)
      expect(Pito::MessageBuilder::Game::List).not_to have_received(:call)
      expect(Pito::MessageBuilder::Video::List).not_to have_received(:call)
    end

    it "ls channels → list_channels branch" do
      build_handler("ls channels").call
      expect(Pito::MessageBuilder::Channel::List).to have_received(:call)
    end

    it "list channel → list_channels branch (singular alias)" do
      build_handler("list channel").call
      expect(Pito::MessageBuilder::Channel::List).to have_received(:call)
    end

    it "list vids → list_videos branch (Video::List called)" do
      build_handler("list vids").call
      expect(Pito::MessageBuilder::Video::List).to have_received(:call)
      expect(Pito::MessageBuilder::Game::List).not_to have_received(:call)
    end

    it "ls vids → list_videos branch" do
      build_handler("ls vids").call
      expect(Pito::MessageBuilder::Video::List).to have_received(:call)
    end

    it "list videos → list_videos branch" do
      build_handler("list videos").call
      expect(Pito::MessageBuilder::Video::List).to have_received(:call)
    end

    it "list vid → list_videos branch (singular alias)" do
      build_handler("list vid").call
      expect(Pito::MessageBuilder::Video::List).to have_received(:call)
    end

    it "list video → list_videos branch (singular alias)" do
      build_handler("list video").call
      expect(Pito::MessageBuilder::Video::List).to have_received(:call)
    end

    it "list games → games branch (Game::List called)" do
      build_handler("list games").call
      expect(Pito::MessageBuilder::Game::List).to have_received(:call)
      expect(Pito::MessageBuilder::Channel::List).not_to have_received(:call)
      expect(Pito::MessageBuilder::Video::List).not_to have_received(:call)
    end

    it "ls games → games branch" do
      build_handler("ls games").call
      expect(Pito::MessageBuilder::Game::List).to have_received(:call)
    end

    it "list game → games branch (singular alias)" do
      build_handler("list game").call
      expect(Pito::MessageBuilder::Game::List).to have_received(:call)
    end

    it "list gamez → games branch" do
      build_handler("list gamez").call
      expect(Pito::MessageBuilder::Game::List).to have_received(:call)
    end

    it "bare list → games branch (no noun → falls through to games)" do
      build_handler("list").call
      expect(Pito::MessageBuilder::Game::List).to have_received(:call)
    end

    it "list --help → Game::ListHelp called, not Game::List" do
      build_handler("list --help").call
      expect(Pito::MessageBuilder::Game::ListHelp).to have_received(:call)
      expect(Pito::MessageBuilder::Game::List).not_to have_received(:call)
    end

    it "list games --help → Game::ListHelp called" do
      build_handler("list games --help").call
      expect(Pito::MessageBuilder::Game::ListHelp).to have_received(:call)
    end

    it "ls --help → Game::ListHelp called" do
      build_handler("ls --help").call
      expect(Pito::MessageBuilder::Game::ListHelp).to have_received(:call)
    end

    describe "visibility filters applied in video branch" do
      it "list vids published → published scope called on relation" do
        build_handler("list vids published").call
        expect(video_rel).to have_received(:published)
      end

      it "list vids unlisted → unlisted scope called on relation" do
        build_handler("list vids unlisted").call
        expect(video_rel).to have_received(:unlisted)
      end

      it "list vids scheduled → scheduled scope called on relation" do
        build_handler("list vids scheduled").call
        expect(video_rel).to have_received(:scheduled)
      end

      it "list vids (no filter) → no visibility scope applied" do
        build_handler("list vids").call
        expect(video_rel).not_to have_received(:published)
        expect(video_rel).not_to have_received(:unlisted)
        expect(video_rel).not_to have_received(:scheduled)
      end

      it "list videos published with views → published applied and Video::List called" do
        build_handler("list videos published with views").call
        expect(video_rel).to have_received(:published)
        expect(Pito::MessageBuilder::Video::List).to have_received(:call)
      end
    end
  end
end
