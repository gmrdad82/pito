# frozen_string_literal: true

require "rails_helper"

# Hard-case coverage for the scoring ladder documented at the top of
# `Video::GameLinkSuggester` — digit-binding vs prefix, alternative_names
# participation, zero-overlap, and the MAX_SUGGESTIONS cap on a genuine tie.
#
# The suggester never calls `Pito::TitleResolve` (that ladder — including its
# acronym-of-initials tier 4 — is a SEPARATE consumer of `Pito::TitleMatch`;
# see `lib/pito/title_resolve.rb`). Every case below runs purely through
# `Pito::TitleMatch`'s anchored-token-run DP over each game's title +
# `alternative_names`, so a "KCD" / "KCD II" style match works only because
# those strings are literal `alternative_names` entries participating in the
# same run-length scorer as any other name — not because the suggester has
# its own acronym tier.
#
# Cases 1-6 exercise the RANKING pipeline (unchanged); cases 7+ exercise the
# PRECISION GATE (pipeline step 0) that now runs before any of them — a game
# only reaches scoring once one of its names is COMPLETE in the title zone
# or the description zone (see the class docstring). Every game named below
# already satisfies the gate via its title alone unless a case says
# otherwise, so cases 1-6 needed no fixture changes — except case 5, whose
# tied games only ever partially overlapped the title; it now carries a
# description naming every tied game in full so the gate lets all six
# through, exactly as before the gate existed.
RSpec.describe Video::GameLinkSuggester, type: :service do
  def set_embedder_url(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PITO_EMBEDDER_URL").and_return(value)
  end

  before { set_embedder_url(nil) }

  # Case 1 — MK2 vs MK: digit binding beats prefix. Straight from the
  # class docstring's own worked example: "Mortal Kombat 2" anchors a
  # 3-token run ([anchor, 3]) against the lead segment, "Mortal Kombat"
  # only a 2-token run ([anchor, 2]) — not a tie, the numbered game wins
  # outright with no embedding tiebreak needed.
  it "binds MK2 titles to the numbered game over the base game" do
    mk = create(:game, title: "Mortal Kombat")
    mk2 = create(:game, title: "Mortal Kombat 2")
    video = create(:video, title: "Mortal Kombat 2: Was it really that good?")

    expect(described_class.call(video)).to eq([ mk2 ])
    expect(described_class.call(video)).not_to include(mk)
  end

  # Case 2 — KCD vs KCD II: the digit/numeral-run logic from case 1 also
  # decides ties between acronym-style `alternative_names`. "KCD" alone
  # scores an anchored 1-token run; "KCD II" scores an anchored 2-token
  # run against the same zone, so it outright outranks "KCD" — same DP,
  # same anchored-beats-shorter rule, just fed acronym strings instead of
  # full titles.
  it "distinguishes the sequel from the base game via alternative_names acronyms" do
    kcd = create(:game, title: "Kingdom Come: Deliverance", alternative_names: [ "KCD" ])
    kcd2 = create(:game, title: "Kingdom Come: Deliverance II", alternative_names: [ "KCD II" ])
    video = create(:video, title: "KCD II Review")

    expect(described_class.call(video)).to eq([ kcd2 ])
    expect(described_class.call(video)).not_to include(kcd)
  end

  # Case 3 — a bare trailing digit with no numbered game in the library
  # does not spawn a phantom candidate: it simply finds no token to bind
  # to (per the class docstring's "Hades 2" example) and is dropped as
  # vid-sequence noise, while the base game still anchors normally.
  it "drops an unmatched trailing digit as noise and still anchors the base game" do
    hades = create(:game, title: "Hades")
    video = create(:video, title: "Hades 2 Boss Rush Highlights")

    expect(described_class.call(video)).to eq([ hades ])
  end

  # Case 4 — genuine zero-overlap: no library game shares a single token
  # with the video's title, so `score_games` comes back empty and `call`
  # returns `[]` rather than guessing.
  it "returns no suggestions when nothing in the library overlaps the title" do
    create(:game, title: "Elden Ring")
    video = create(:video, title: "Weekly Vlog Update")

    expect(described_class.call(video)).to eq([])
  end

  # Case 5 — MAX_SUGGESTIONS cap on a genuine tie. Six games share the
  # leading "Super Mode" tokens but diverge on their third word, which
  # does not appear in the TITLE zone at all — so every game's title-zone
  # score is the exact same non-anchored 2-token run ([0, 2]). None of the
  # six has a COMPLETE name in the title, so the precision gate would shut
  # all six out; the description spells out every tied game's full name so
  # each clears the gate via the description zone, and — since the
  # description mentions all six identically (same prefix, same
  # non-anchored position) — the description-zone score ([0, 3]) is ALSO
  # tied across all six, so the higher of the two zone-scores per game
  # ([0, 3]) still leaves a genuine 6-way tie, unchanged from before the
  # gate existed. With the embedder unconfigured (stubbed above),
  # `embedding_rank` returns nil and the tie falls back to `library`'s
  # `order(:title)` — deterministic alphabetical order — capped at
  # MAX_SUGGESTIONS (5 of the 6 tied games survive).
  it "caps a genuine multi-way tie at MAX_SUGGESTIONS" do
    tied_games = %w[Alpha Beta Charlie Delta Echo Foxtrot].map do |suffix|
      create(:game, title: "Super Mode #{suffix}")
    end
    video = create(:video,
                    title: "Super Mode Highlights Compilation Video",
                    description: "Full playlist: Super Mode Alpha, Super Mode Beta, Super Mode Charlie, " \
                                  "Super Mode Delta, Super Mode Echo, and Super Mode Foxtrot")

    result = described_class.call(video)

    expect(result.size).to eq(Video::GameLinkSuggester::MAX_SUGGESTIONS)
    expect(result).to eq(tied_games.first(5))
    expect(result).not_to include(tied_games.last)
  end

  # Case 6 — alternative_names participate in matching even when the
  # game's title itself shares nothing with the video's title.
  it "matches via alternative_names when the title alone has no overlap" do
    game = create(:game, title: "Iron Fist Tournament", alternative_names: [ "Tekken" ])
    video = create(:video, title: "Tekken 8 New Trailer Reaction")

    expect(described_class.call(video)).to eq([ game ])
  end

  # Case 7 — the precision gate's core motivation: a single-token game name
  # ("Dispatch") must not be read out of ordinary prose that merely uses the
  # word as a verb. The description zone only accepts a single-token name as
  # a case-sensitive whole word spelled EXACTLY as the library entry — the
  # lowercase verb use below never qualifies, however much it "overlaps".
  it "does not suggest a single-token game name used as a lowercase verb in the description" do
    create(:game, title: "Dispatch")
    video = create(:video, title: "Weekly Gameplay Update", description: "i dispatch my enemies")

    expect(described_class.call(video)).to eq([])
  end

  # Case 8 — the flip side of case 7: the same single-token name, spelled
  # exactly as the library entry and standing as its own whole word, DOES
  # qualify via the description.
  it "suggests a single-token game name spelled exactly as a whole word in the description" do
    game = create(:game, title: "Dispatch")
    video = create(:video, title: "Weekly Gameplay Update", description: "Playing Dispatch today")

    expect(described_class.call(video)).to eq([ game ])
  end

  # Case 9 — description-only hit for a multi-token name: no title overlap
  # at all, but the game's full name appears as a complete run in the
  # description, so it both clears the gate AND earns a real score there
  # (score_game maxes the title-zone and description-zone scores).
  it "suggests a game named only in the description via a complete multi-token run" do
    game = create(:game, title: "Ghost of Tsushima")
    create(:game, title: "Unrelated Game")
    video = create(:video,
                    title: "Best Moments Compilation",
                    description: "Today's stream: Ghost of Tsushima chapter 3")

    expect(described_class.call(video)).to eq([ game ])
  end

  # Case 10 — the gate does not regress a plain, unambiguous title hit.
  it "still suggests a game via a complete name in the title zone" do
    game = create(:game, title: "Cyberpunk 2077")
    video = create(:video, title: "Cyberpunk 2077 First Impressions")

    expect(described_class.call(video)).to eq([ game ])
  end

  # Case 11 — a gameless vid stays silent even with an unrelated
  # description in play (both zones checked, neither names a library game).
  it "returns no suggestions when neither the title nor the description name a library game" do
    create(:game, title: "Some Other Game")
    video = create(:video, title: "Random Vlog", description: "Just talking about my day, no games mentioned.")

    expect(described_class.call(video)).to eq([])
  end

  # Case 12 — a partial name never qualifies: the video's text only ever
  # contains "Mortal Shell", never the complete "Mortal Shell II", so the
  # sequel-only library entry is never suggested (the DP's partial-overlap
  # score is irrelevant once the gate excludes the game outright).
  it "does not suggest a sequel when only the base name appears (partial name)" do
    create(:game, title: "Mortal Shell II")
    video = create(:video, title: "Mortal Shell Review")

    expect(described_class.call(video)).to eq([])
  end

  # Case 13 — alternative_names participate in the description-zone gate
  # too, not just the title zone (already covered by case 6).
  it "qualifies via alternative_names in the description zone" do
    game = create(:game, title: "Obscure RPG Adventure", alternative_names: [ "Chrono Quest" ])
    video = create(:video, title: "Random Highlights Reel", description: "Been grinding Chrono Quest all week")

    expect(described_class.call(video)).to eq([ game ])
  end
end
