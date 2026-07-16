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
  # does not appear in the zone at all — so every game scores the exact
  # same non-anchored 2-token run ([0, 2]), a real tie. With the embedder
  # unconfigured (stubbed above), `embedding_rank` returns nil and the tie
  # falls back to `library`'s `order(:title)` — deterministic alphabetical
  # order — capped at MAX_SUGGESTIONS (5 of the 6 tied games survive).
  it "caps a genuine multi-way tie at MAX_SUGGESTIONS" do
    tied_games = %w[Alpha Beta Charlie Delta Echo Foxtrot].map do |suffix|
      create(:game, title: "Super Mode #{suffix}")
    end
    video = create(:video, title: "Super Mode Highlights Compilation Video")

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
end
