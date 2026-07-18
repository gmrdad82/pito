# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::WithColumns, type: :service do
  # A representative vocabulary with aliases + a multi-word column.
  VOCAB = {
    "platform"     => :platform,
    "platforms"    => :platform,
    "genre"        => :genre,
    "genres"       => :genre,
    "developer"    => :developer,
    "dev"          => :developer,
    "release date" => :release_date,
    "year"         => :year
  }.freeze

  def parse(raw)
    described_class.parse(raw, vocabulary: VOCAB)
  end

  it "returns [] when there is no `with` clause" do
    expect(parse("list games")).to eq([])
  end

  it "extracts a single column" do
    expect(parse("list games with platform")).to eq([ :platform ])
  end

  it "splits on `,` and `, ` and preserves order" do
    expect(parse("list games with genre, platform")).to eq([ :genre, :platform ])
    expect(parse("list games with genre,platform")).to eq([ :genre, :platform ])
  end

  it "canonicalizes aliases" do
    expect(parse("list games with platforms, genres, dev")).to eq([ :platform, :genre, :developer ])
  end

  it "keeps multi-word columns intact" do
    expect(parse("list games with release date, year")).to eq([ :release_date, :year ])
  end

  it "de-duplicates canonical values preserving first-seen order" do
    expect(parse("list games with platform, platforms, genre")).to eq([ :platform, :genre ])
  end

  it "drops unknown tokens" do
    expect(parse("list games with platform, bogus, year")).to eq([ :platform, :year ])
  end

  it "is case-insensitive on the magic word and tokens" do
    expect(parse("list games WITH Platform, GENRE")).to eq([ :platform, :genre ])
  end

  it "stops the clause at `sorted by` / `ordered by`" do
    expect(parse("list games with platform, genre sorted by year")).to eq([ :platform, :genre ])
    expect(parse("list games with platform ordered by year desc")).to eq([ :platform ])
  end

  it "stops at bare sort/order verbs without `by`" do
    expect(parse("list games with platform sort by year")).to eq([ :platform ])
    expect(parse("list games with platform order by year")).to eq([ :platform ])
    expect(parse("list games with platform sort year")).to eq([ :platform ])
    expect(parse("list games with platform, genre sort by year desc")).to eq([ :platform, :genre ])
  end

  it "bare sort verbs and inflected `sorted by` / `ordered by` yield the same result" do
    expect(parse("list games with platform sort by year")).to \
      eq(parse("list games with platform sorted by year"))
    expect(parse("list games with platform, genre sort by year desc")).to \
      eq(parse("list games with platform, genre sorted by year desc"))
  end

  it "returns [] when `with` is present but names no known column" do
    expect(parse("list games with bogus")).to eq([])
  end

  # ── .unrecognized (F-2) — the caller-facing half of the silent drop ────────

  def unrecognized(raw)
    described_class.unrecognized(raw, vocabulary: VOCAB)
  end

  it "returns [] when there is no `with` clause" do
    expect(unrecognized("list games")).to eq([])
  end

  it "returns [] when every token maps to a known column" do
    expect(unrecognized("list games with genre, platform")).to eq([])
  end

  it "reports a single unmapped token" do
    expect(unrecognized("list games with bogus")).to eq([ "bogus" ])
  end

  it "reports only the unmapped tokens out of a mixed list" do
    expect(unrecognized("list games with genre, bogus")).to eq([ "bogus" ])
  end

  it "reports an unmapped multi-word remainder as ONE token (no internal comma)" do
    expect(unrecognized("list games with hard bosses")).to eq([ "hard bosses" ])
  end

  it "is case-insensitive on the magic word and tokens" do
    expect(unrecognized("list games WITH Bogus")).to eq([ "bogus" ])
  end

  it "stops the clause at `sorted by` — a bogus token after it is not reported" do
    expect(unrecognized("list games with genre sorted by bogus")).to eq([])
  end
end
