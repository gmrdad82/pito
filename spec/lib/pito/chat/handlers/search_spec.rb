# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Search do
  let(:conversation) { Conversation.singleton }

  def search(raw)
    msg = Pito::Chat::Parser.call(Pito::Lex::Lexer.call(raw), raw:, conversation:)
    described_class.new(message: msg, conversation:).call
  end

  def stub_similar(results)
    allow(Pito::Recommendation::GameSimilarity).to receive(:call).and_return(results)
  end

  def result_for(game, score:, breakdown: {})
    Pito::Recommendation::GameSimilarity::Result.new(game: game, score: score, breakdown: breakdown)
  end

  it "asks for a seed on a bare `search`" do
    expect(search("search").events.first[:payload]["text"]).to include("Search for what")
  end

  it "reports seed-not-found for an unknown title" do
    result = search("search games like nonexistent")
    expect(result.events.first[:payload]["text"]).to include("nonexistent")
  end

  context "with a seed that has a genre" do
    let!(:seed) { create(:game, title: "Tekken 7") }
    let!(:high_g) { create(:game, title: "Street Fighter 6") }
    let!(:low_g)  { create(:game, title: "Mortal Kombat 1") }
    let!(:no_g)   { create(:game, title: "Katamari Damacy") }

    before { seed.genres << create(:genre) }

    it "keeps only genre-overlapping results that also clear the relevance floor, seed first" do
      stub_similar([
        result_for(high_g, score: 68, breakdown: { g: 100 }),
        result_for(low_g,  score: 34, breakdown: { g: 33 }), # shares a genre but under RELEVANCE_FLOOR (40) — dropped since 3.1.1
        result_for(no_g,   score: 51, breakdown: { g: 0, pp: 100 })
      ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["reply_target"]).to eq("game_list")
      expect(payload["game_ids"]).to eq([ seed.id, high_g.id ])
    end

    it "drops a genre-sharing candidate whose blended score doesn't clear the relevance floor (3.1.1 tightening)" do
      stub_similar([ result_for(low_g, score: 34, breakdown: { g: 33 }) ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["game_ids"]).to eq([ seed.id ])
    end

    it "resolves the seed fuzzily (search games like tekken → Tekken 7) and leads with it" do
      stub_similar([ result_for(high_g, score: 68, breakdown: { g: 100 }) ])
      payload = search("search games like tekken").events.first[:payload]
      expect(Pito::Recommendation::GameSimilarity).to have_received(:call).with(seed, limit: nil)
      expect(payload["game_ids"].first).to eq(seed.id)
    end

    it "renders just the seed row when nothing is relevant" do
      stub_similar([ result_for(no_g, score: 51, breakdown: { g: 0, pp: 100 }) ])
      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["reply_target"]).to eq("game_list")
      expect(payload["game_ids"]).to eq([ seed.id ])
    end

    it "stamps a ranked_ids cursor + more footer when results exceed a page" do
      allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :search)
        .and_return(page_size: 1, more_tool: "next")
      stub_similar([
        result_for(high_g, score: 68, breakdown: { g: 100 }),
        result_for(low_g,  score: 34, breakdown: { g: 33 }) # under RELEVANCE_FLOOR — dropped, not part of the ranked_ids cursor
      ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["game_ids"]).to eq([ seed.id ])
      expect(payload["list_cursor"]["ranked_ids"]).to eq([ seed.id, high_g.id ])
      expect(payload["list_cursor"]["offset"]).to eq(1)
      expect(payload["list_footer"].to_s).to include("next")
    end
  end

  context "with a seed that has no genres" do
    let!(:seed) { create(:game, title: "Tekken 7") }
    let!(:above_floor) { create(:game, title: "Street Fighter 6") }
    let!(:below_floor) { create(:game, title: "Mortal Kombat 1") }

    it "keeps only results at or above the no-genre score floor" do
      stub_similar([
        result_for(above_floor, score: 45, breakdown: {}),
        result_for(below_floor, score: 35, breakdown: {})
      ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["game_ids"]).to eq([ seed.id, above_floor.id ])
    end
  end

  context "search games for <title> (exact-name match)" do
    let!(:tekken8)    { create(:game, title: "Tekken 8") }
    let!(:tekken_tag) { create(:game, title: "Tekken Tag Tournament") }
    let!(:decoy)      { create(:game, title: "Street Fighter 6") }

    it "returns only title-matching games, title-ascending" do
      payload = search("search games for tekken").events.first[:payload]
      expect(payload["reply_target"]).to eq("game_list")
      expect(payload["game_ids"]).to eq([ tekken8.id, tekken_tag.id ])
    end

    it "matches via alternative_names when the title itself doesn't contain the term" do
      aliased = create(:game, title: "Iron Fist Tournament", alternative_names: [ "Tekken" ])

      payload = search("search games for tekken").events.first[:payload]
      expect(payload["game_ids"]).to include(aliased.id)
      expect(payload["game_ids"]).not_to include(decoy.id)
    end

    it "routes a bare query to the vectors (the 3.1.2 catch-all — bare = `about`, no longer `for`)" do
      allow(Pito::Search::Semantic).to receive(:call).and_return([])

      search("search games forcing skillful play")
      expect(Pito::Search::Semantic).to have_received(:call)
        .with(hash_including(query: "forcing skillful play"))
    end

    it "keeps `for` as the explicit literal path a bare query no longer takes" do
      allow(Pito::Search::Semantic).to receive(:call)

      for_ids = search("search games for tekken").events.first[:payload]["game_ids"]
      expect(for_ids).to eq([ tekken8.id, tekken_tag.id ])
      expect(Pito::Search::Semantic).not_to have_received(:call)
    end

    it "renders the list-filter-empty copy for a `for` query with no matches" do
      expected = Pito::Copy.render("pito.copy.games.list_filter_empty")
      result   = search("search games for nonexistent")
      expect(result.events.first[:payload]["text"]).to eq(expected)
    end
  end

  context "search games for <title> beyond a page" do
    let!(:many) { (1..21).map { |n| create(:game, title: "Tekken #{n}") } }

    it "caps page 1 at 20 rows and stamps a more cursor + footer" do
      payload = search("search games for tekken").events.first[:payload]
      expect(payload["game_ids"].size).to eq(20)
      expect(payload["list_cursor"]["ranked_ids"].size).to eq(21)
      expect(payload["list_cursor"]["offset"]).to eq(20)
      expect(payload["list_footer"].to_s).to include("next")
    end
  end

  context "search games for <x> multi-field matching (SUX7)" do
    let!(:decoy) { create(:game, title: "Decoy Game") }

    it "surfaces a game whose genre (not its title/summary) carries the term" do
      hit = create(:game, title: "Mystery Title")
      hit.genres << create(:genre, name: "Beat 'em Up")

      payload = search("search games for beat 'em up").events.first[:payload]
      expect(payload["game_ids"]).to include(hit.id)
      expect(payload["game_ids"]).not_to include(decoy.id)
    end

    it "surfaces a game whose developer company name (not its title/summary) carries the term" do
      hit = create(:game, title: "Mystery Title")
      create(:game_developer, game: hit, company: create(:company, name: "Capcom"))

      payload = search("search games for capcom").events.first[:payload]
      expect(payload["game_ids"]).to include(hit.id)
      expect(payload["game_ids"]).not_to include(decoy.id)
    end

    it "surfaces a game whose publisher company name (not its title/summary) carries the term" do
      hit = create(:game, title: "Mystery Title")
      create(:game_publisher, game: hit, company: create(:company, name: "Bandai Namco"))

      payload = search("search games for bandai namco").events.first[:payload]
      expect(payload["game_ids"]).to include(hit.id)
      expect(payload["game_ids"]).not_to include(decoy.id)
    end

    it "surfaces a game whose summary (not its title) carries the term" do
      hit = create(:game, title: "Mystery Title", summary: "A gritty survival horror experience")

      payload = search("search games for gritty survival horror").events.first[:payload]
      expect(payload["game_ids"]).to include(hit.id)
      expect(payload["game_ids"]).not_to include(decoy.id)
    end

    it "surfaces a game whose platforms array (not its title) carries the term" do
      hit = create(:game, title: "Mystery Title", platforms: [ "Nintendo Switch" ])

      payload = search("search games for nintendo switch").events.first[:payload]
      expect(payload["game_ids"]).to include(hit.id)
      expect(payload["game_ids"]).not_to include(decoy.id)
    end

    it "surfaces a game whose themes array (not its title) carries the term" do
      hit = create(:game, title: "Mystery Title", themes: [ "Horror" ])

      payload = search("search games for horror").events.first[:payload]
      expect(payload["game_ids"]).to include(hit.id)
      expect(payload["game_ids"]).not_to include(decoy.id)
    end

    it "surfaces a game whose player_perspectives array (not its title) carries the term" do
      hit = create(:game, title: "Mystery Title", player_perspectives: [ "Bird view / Isometric" ])

      payload = search("search games for isometric").events.first[:payload]
      expect(payload["game_ids"]).to include(hit.id)
      expect(payload["game_ids"]).not_to include(decoy.id)
    end

    it "does not surface any game when the term appears nowhere on its detail surfaces" do
      create(:game, title: "Mystery Title", summary: "Nothing to see here")

      expected = Pito::Copy.render("pito.copy.games.list_filter_empty")
      result   = search("search games for zzznotpresentanywhere")
      expect(result.events.first[:payload]["text"]).to eq(expected)
    end
  end

  context "search games like <title> score threading (SUX11)" do
    let!(:seed)   { create(:game, title: "Tekken 7") }
    let!(:high_g) { create(:game, title: "Street Fighter 6") }

    before { seed.genres << create(:genre) }

    it "carries a Match heading and { score: } cells: seed=100, others = their GameSimilarity score" do
      stub_similar([ result_for(high_g, score: 68, breakdown: { g: 100 }) ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["table_heading"]).to include("Match")

      rows     = payload["table_rows"]
      seed_row = rows.find { |r| r[:cells][0][:text] == "##{seed.id}" }
      high_row = rows.find { |r| r[:cells][0][:text] == "##{high_g.id}" }
      expect(seed_row[:cells].last).to eq(score: 100)
      expect(high_row[:cells].last).to eq(score: 68)
    end
  end

  context "search games about <text> (free-text semantic search)" do
    let!(:hit) { create(:game, title: "Nine Sols") }

    it "routes the raw query through Pito::Search::Semantic, scoped to Game.summary_embedding, fetching the deep pageable ranking" do
      allow(Pito::Search::Semantic).to receive(:call)
        .with(scope: ::Game, column: ::Game::EMBEDDING_COLUMN, query: "brutal but worth every second",
              limit: Pito::Chat::Handlers::Search::SEARCH_MAX_RESULTS)
        .and_return([ { record: hit, similarity: 0.612 } ])

      payload = search("search games about brutal but worth every second").events.first[:payload]
      expect(payload["reply_target"]).to eq("game_list")
      expect(payload["game_ids"]).to eq([ hit.id ])
    end

    it "scores the top hit 100 — the set's best similarity IS the bar's ceiling (#owner 2026-07-18)" do
      allow(Pito::Search::Semantic).to receive(:call).and_return([ { record: hit, similarity: 0.612 } ])

      payload = search("search games about anything").events.first[:payload]
      row     = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{hit.id}" }
      expect(row[:cells].last).to eq(score: 100)
    end

    it "scales the rest band-relative to the top (close second reads close, distant second reads distant)" do
      other = create(:game, title: "Runner Up")
      allow(Pito::Search::Semantic).to receive(:call).and_return([
        { record: hit,   similarity: 0.70 },
        { record: other, similarity: 0.60 }
      ])

      payload = search("search games about anything").events.first[:payload]
      top_row = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{hit.id}" }
      second  = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{other.id}" }
      expect(top_row[:cells].last).to eq(score: 100)
      # (0.60 - 0.55) / (0.70 - 0.55) = 33% of the band above the floor
      expect(second[:cells].last).to eq(score: 33)
    end

    it "wins when typed first, even when the query text contains `like`/`for` (positional precedence)" do
      allow(Pito::Search::Semantic).to receive(:call).and_return([ { record: hit, similarity: 0.7 } ])

      search("search games about a game like this one, not for anyone else")
      expect(Pito::Search::Semantic).to have_received(:call)
        .with(hash_including(query: "a game like this one, not for anyone else"))
    end

    it "loses to an explicitly-typed earlier `for` — `about` mid-query stays part of the lexical term" do
      allow(Pito::Search::Semantic).to receive(:call)

      search("search games for the one about dragons")
      expect(Pito::Search::Semantic).not_to have_received(:call)
    end

    it "treats a bare dangling keyword (`search games about`) as an empty query, not a lexical search for the word" do
      allow(Pito::Search::Semantic).to receive(:call)

      result = search("search games about")
      expect(Pito::Search::Semantic).not_to have_received(:call)
      expect(result.events.first[:payload]["text"]).to eq(Pito::Copy.render("pito.chat.search.needs_seed"))
    end

    it "returns a Result::Error with the embedder-unavailable copy when the embedder is unreachable" do
      allow(Pito::Search::Semantic).to receive(:call).and_return(nil)

      result = search("search games about anything")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expected = Pito::Copy.render("pito.copy.search.about_unavailable")
      expect(result.message_key).to eq(expected)
    end

    it "renders the about-empty copy (not the strict-filters copy) when nothing clears the floor" do
      allow(Pito::Search::Semantic).to receive(:call).and_return([])

      expected = Pito::Copy.render("pito.copy.search.about_empty")
      result   = search("search games about anything")
      expect(result.events.first[:payload]["text"]).to eq(expected)
      expect(result.events.first[:payload]["text"]).not_to eq(Pito::Copy.render("pito.copy.games.list_filter_empty"))
    end

    it "stamps a ranked_ids cursor + more footer when results exceed a page" do
      allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :search)
        .and_return(page_size: 1, more_tool: "next")
      other = create(:game, title: "Second Hit")
      allow(Pito::Search::Semantic).to receive(:call)
        .and_return([ { record: hit, similarity: 0.7 }, { record: other, similarity: 0.6 } ])

      payload = search("search games about anything").events.first[:payload]
      expect(payload["game_ids"]).to eq([ hit.id ])
      expect(payload["list_cursor"]["ranked_ids"]).to eq([ hit.id, other.id ])
      expect(payload["list_footer"].to_s).to include("next")
    end
  end

  context "search vids like <title> (SUX5)" do
    # `dim0`/`dim1` weighted (not one-hot) so the seed/close/far cosine
    # similarities can be placed deliberately on either side of
    # Pito::Recommendation::DisplayScore::VID_FLOOR (0.85) — proving the
    # rescale actually discriminates, unlike the pre-rescale formula where
    # near-orthogonal test vectors were enough (every raw cosine looked
    # similar in the real embedding space too, which was the whole bug).
    def weighted_vec(dim0:, dim1: 0.0)
      Array.new(768, 0.0).tap { |a| a[0] = dim0; a[1] = dim1 }
    end

    def cosine_distance(a, b)
      dot    = a.zip(b).sum { |x, y| x * y }
      norm_a = Math.sqrt(a.sum { |x| x**2 })
      norm_b = Math.sqrt(b.sum { |x| x**2 })
      1 - (dot / (norm_a * norm_b))
    end

    let!(:seed)  { create(:video, title: "Boss Rush Marathon") }
    let!(:close) { create(:video, title: "Speedrun Special") }
    let!(:far)   { create(:video, title: "Cooking Stream") }

    let(:seed_vec)  { weighted_vec(dim0: 1.0) }
    let(:close_vec) { weighted_vec(dim0: 1.0, dim1: 0.2) } # cosine ≈ .981 — above VID_FLOOR
    let(:far_vec)   { weighted_vec(dim0: 1.0, dim1: 2.0) } # cosine ≈ .447 — below VID_FLOOR

    before do
      seed.update_column(:summary_embedding, seed_vec)
      close.update_column(:summary_embedding, close_vec)
      far.update_column(:summary_embedding, far_vec)
    end

    it "orders similar vids by cosine distance with floor-rescaled scores, seed at 100, sub-floor neighbors dropped (3.1.1)" do
      payload = search("search vids like boss rush marathon").events.first[:payload]

      expect(payload["reply_target"]).to eq("video_search")
      # `far` sits below VID_FLOOR — it used to render a zero-length bar;
      # since 3.1.1 the floor FILTERS, honoring the honest-miss contract.
      expect(payload["video_ids"]).to eq([ seed.id, close.id ])
      expect(payload["table_heading"]).to include("Similarity")

      rows      = payload["table_rows"]
      seed_row  = rows.find { |r| r[:cells][0][:text] == "##{seed.id}" }
      close_row = rows.find { |r| r[:cells][0][:text] == "##{close.id}" }

      expect(rows.find { |r| r[:cells][0][:text] == "##{far.id}" }).to be_nil
      expect(seed_row[:cells].last).to eq(score: 100)
      expect(close_row[:cells].last).to eq(
        score: Pito::Recommendation::DisplayScore.display_score(
          1.0 - cosine_distance(seed_vec, close_vec), floor: Pito::Recommendation::DisplayScore::VID_FLOOR
        ).round
      )
    end

    it "drops a below-VID_FLOOR neighbor entirely — the 3.1.1 successor to clamping its score to 0 (the original SUX fix)" do
      payload = search("search vids like boss rush marathon").events.first[:payload]

      expect(payload["video_ids"]).not_to include(far.id)
      expect(payload["table_rows"].find { |r| r[:cells][0][:text] == "##{far.id}" }).to be_nil
    end

    it "renders the list-filter-empty copy when the seed has no embedding" do
      create(:video, title: "No Vector Vid")

      expected = Pito::Copy.render("pito.copy.games.list_filter_empty")
      result   = search("search vids like no vector vid")
      expect(result.events.first[:payload]["text"]).to eq(expected)
    end

    it "renders the vid not-found reply when the title resolves to no vid" do
      result = search("search vids like zzznonexistentvid")
      expect(result.events.first[:payload]["text"]).to include("zzznonexistentvid")
    end

    it "stamps a ranked_ids cursor + more footer when results exceed a page (pager parity with games)" do
      allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :search)
        .and_return(page_size: 1, more_tool: "next")

      payload = search("search vids like boss rush marathon").events.first[:payload]
      expect(payload["reply_target"]).to eq("video_search")
      expect(payload["video_ids"]).to eq([ seed.id ])
      expect(payload["list_cursor"]["ranked_ids"]).to eq([ seed.id, close.id ])
      expect(payload["list_cursor"]["offset"]).to eq(1)
      expect(payload["list_cursor"]["tool"]).to eq("search")
      expect(payload["list_footer"].to_s).to include("next")
    end

    it "fetches a deep ranking (SEARCH_MAX_RESULTS) BEFORE the VID_FLOOR filter — a small page_size doesn't truncate genuine neighbors out of the running" do
      # A second above-floor neighbor, farther than `close` but still well
      # clear of VID_FLOOR — proves the DB-side limit is NOT page_size: were
      # the query still `.limit(page_size)`, a page_size of 1 would fetch
      # only the single nearest neighbor from the DB and this one would never
      # reach the Ruby-side floor filter at all, regardless of its own score.
      second = create(:video, title: "Runner's High")
      second.update_column(:summary_embedding, weighted_vec(dim0: 1.0, dim1: 0.25)) # cosine ≈ .970 — above VID_FLOOR, farther than close

      allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :search)
        .and_return(page_size: 1, more_tool: "next")

      payload = search("search vids like boss rush marathon").events.first[:payload]
      expect(payload["list_cursor"]["ranked_ids"]).to eq([ seed.id, close.id, second.id ])
    end
  end

  context "search vids for <x> (SUX5)" do
    let!(:decoy) { create(:video, title: "Decoy Vid") }

    it "surfaces a vid whose description (not its title) carries the term" do
      hit = create(:video, title: "Mystery Vid", description: "A deep dive into speedrun tech")

      payload = search("search vids for speedrun tech").events.first[:payload]
      expect(payload["video_ids"]).to include(hit.id)
      expect(payload["video_ids"]).not_to include(decoy.id)
    end

    it "surfaces a vid whose tags array (not its title) carries the term" do
      hit = create(:video, title: "Mystery Vid", tags: [ "boss rush" ])

      payload = search("search vids for boss rush").events.first[:payload]
      expect(payload["video_ids"]).to include(hit.id)
      expect(payload["video_ids"]).not_to include(decoy.id)
    end

    it "renders the list-filter-empty copy when nothing matches" do
      create(:video, title: "Mystery Vid")

      expected = Pito::Copy.render("pito.copy.games.list_filter_empty")
      result   = search("search vids for zzznotpresentanywhere")
      expect(result.events.first[:payload]["text"]).to eq(expected)
    end
  end

  context "search vids for <title> beyond a page" do
    let!(:many) { (1..21).map { |n| create(:video, title: "Boss Rush #{n}") } }

    it "caps page 1 at 20 rows and stamps a more cursor + footer" do
      payload = search("search vids for boss rush").events.first[:payload]
      expect(payload["video_ids"].size).to eq(20)
      expect(payload["list_cursor"]["ranked_ids"].size).to eq(21)
      expect(payload["list_cursor"]["offset"]).to eq(20)
      expect(payload["list_footer"].to_s).to include("next")
    end
  end

  context "search vids <bare> (3.1.2 catch-all)" do
    it "routes a keyword-less vids query to the vectors too" do
      allow(Pito::Search::Semantic).to receive(:call).and_return([])

      search("search vids where everything goes wrong")
      expect(Pito::Search::Semantic).to have_received(:call)
        .with(hash_including(scope: ::Video, query: "where everything goes wrong"))
    end
  end

  context "search vids about <text> (free-text semantic search)" do
    let!(:hit) { create(:video, title: "Speedrun Special") }

    it "routes the raw query through Pito::Search::Semantic, scoped to Video.summary_embedding, fetching the deep pageable ranking" do
      allow(Pito::Search::Semantic).to receive(:call)
        .with(scope: ::Video, column: ::Video::EMBEDDING_COLUMN, query: "brutal but worth every second",
              limit: Pito::Chat::Handlers::Search::SEARCH_MAX_RESULTS)
        .and_return([ { record: hit, similarity: 0.612 } ])

      payload = search("search vids about brutal but worth every second").events.first[:payload]
      expect(payload["reply_target"]).to eq("video_search")
      expect(payload["video_ids"]).to eq([ hit.id ])
    end

    it "stamps a ranked_ids cursor + more footer when results exceed a page" do
      allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :search)
        .and_return(page_size: 1, more_tool: "next")
      other = create(:video, title: "Second Hit")
      allow(Pito::Search::Semantic).to receive(:call)
        .and_return([ { record: hit, similarity: 0.7 }, { record: other, similarity: 0.6 } ])

      payload = search("search vids about anything").events.first[:payload]
      expect(payload["video_ids"]).to eq([ hit.id ])
      expect(payload["list_cursor"]["ranked_ids"]).to eq([ hit.id, other.id ])
      expect(payload["list_footer"].to_s).to include("next")
    end

    it "scores the top hit 100 (the set-relative bar, mirroring games)" do
      allow(Pito::Search::Semantic).to receive(:call).and_return([ { record: hit, similarity: 0.612 } ])

      payload = search("search vids about anything").events.first[:payload]
      row     = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{hit.id}" }
      expect(row[:cells].last).to eq(score: 100)
    end

    it "returns a Result::Error with the embedder-unavailable copy when the embedder is unreachable" do
      allow(Pito::Search::Semantic).to receive(:call).and_return(nil)

      result = search("search vids about anything")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expected = Pito::Copy.render("pito.copy.search.about_unavailable")
      expect(result.message_key).to eq(expected)
    end

    it "renders the about-empty copy (not the strict-filters copy) when nothing clears the floor" do
      allow(Pito::Search::Semantic).to receive(:call).and_return([])

      expected = Pito::Copy.render("pito.copy.search.about_empty")
      result   = search("search vids about anything")
      expect(result.events.first[:payload]["text"]).to eq(expected)
      expect(result.events.first[:payload]["text"]).not_to eq(Pito::Copy.render("pito.copy.games.list_filter_empty"))
    end
  end
end
