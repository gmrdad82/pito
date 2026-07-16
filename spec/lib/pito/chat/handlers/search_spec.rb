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

    it "keeps only genre-overlapping results, seed first" do
      stub_similar([
        result_for(high_g, score: 68, breakdown: { g: 100 }),
        result_for(low_g,  score: 34, breakdown: { g: 33 }),
        result_for(no_g,   score: 51, breakdown: { g: 0, pp: 100 })
      ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["reply_target"]).to eq("game_list")
      expect(payload["game_ids"]).to eq([ seed.id, high_g.id, low_g.id ])
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
        result_for(low_g,  score: 34, breakdown: { g: 33 })
      ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["game_ids"]).to eq([ seed.id ])
      expect(payload["list_cursor"]["ranked_ids"]).to eq([ seed.id, high_g.id, low_g.id ])
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

    it "treats a bare query exactly like the `for` form" do
      for_ids  = search("search games for tekken").events.first[:payload]["game_ids"]
      bare_ids = search("search games tekken").events.first[:payload]["game_ids"]
      expect(bare_ids).to eq(for_ids)
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

    it "orders similar vids by cosine distance and carries a floor-rescaled Similarity score, seed leading at 100" do
      payload = search("search vids like boss rush marathon").events.first[:payload]

      expect(payload["reply_target"]).to eq("video_search")
      expect(payload["video_ids"]).to eq([ seed.id, close.id, far.id ])
      expect(payload["table_heading"]).to include("Similarity")

      rows      = payload["table_rows"]
      seed_row  = rows.find { |r| r[:cells][0][:text] == "##{seed.id}" }
      close_row = rows.find { |r| r[:cells][0][:text] == "##{close.id}" }
      far_row   = rows.find { |r| r[:cells][0][:text] == "##{far.id}" }

      expect(seed_row[:cells].last).to eq(score: 100)
      expect(close_row[:cells].last).to eq(
        score: Pito::Recommendation::DisplayScore.display_score(
          1.0 - cosine_distance(seed_vec, close_vec), floor: Pito::Recommendation::DisplayScore::VID_FLOOR
        ).round
      )
      expect(far_row[:cells].last).to eq(
        score: Pito::Recommendation::DisplayScore.display_score(
          1.0 - cosine_distance(seed_vec, far_vec), floor: Pito::Recommendation::DisplayScore::VID_FLOOR
        ).round
      )
    end

    it "clamps a below-VID_FLOOR similarity's score to 0 rather than a misleadingly high raw-cosine number (the SUX bug this fixes)" do
      payload = search("search vids like boss rush marathon").events.first[:payload]
      far_row = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{far.id}" }

      expect(far_row[:cells].last).to eq(score: 0)
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

    it "does not stamp a list_cursor or a next/more footer even when results exceed a page (deliberately single-page, unlike games)" do
      allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :search)
        .and_return(page_size: 1, more_tool: "next")

      payload = search("search vids like boss rush marathon").events.first[:payload]
      expect(payload["video_ids"]).to eq([ seed.id ])
      expect(payload).not_to have_key("list_cursor")
      expect(payload["list_footer"].to_s).not_to include("next")
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
end
