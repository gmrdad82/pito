# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::BrailleHeart do
  def grid(score:, cols: 17, rows: 10)
    described_class.call(score:, cols:, rows:)
  end

  def states(g) = g.flatten.map { |c| c[:state] }

  it "returns a rows × cols grid of { char:, state: } cells" do
    g = grid(score: 50, cols: 17, rows: 10)
    expect(g.size).to eq(10)
    expect(g).to all(have_attributes(size: 17))
    expect(g.flatten).to all(include(:char, :state))
  end

  it "marks every in-heart cell :filled at score 100" do
    g = grid(score: 100)
    in_heart = g.flatten.reject { |c| c[:state] == :outside }
    expect(in_heart).to be_present
    expect(in_heart.map { |c| c[:state] }).to all(eq(:filled))
  end

  it "has no :filled cells at score 0 (only outline / interior / outside)" do
    expect(states(grid(score: 0))).not_to include(:filled)
  end

  it "produces a hollow rim above the waterline at a partial score" do
    g = grid(score: 50)
    expect(states(g)).to include(:filled)   # bottom half solid
    expect(states(g)).to include(:outline)  # rim above the fill
    expect(states(g)).to include(:interior) # hollow inside above the fill
  end

  it "fills more of the canvas as the score rises" do
    low  = states(grid(score: 25)).count(:filled)
    high = states(grid(score: 90)).count(:filled)
    expect(high).to be > low
  end

  it "renders a symmetric heart (left/right mirror of in-heart columns)" do
    g = grid(score: 100, cols: 17, rows: 10)
    g.each do |row|
      in_heart = row.map { |c| c[:state] != :outside }
      expect(in_heart).to eq(in_heart.reverse)
    end
  end

  it "every cell char is a braille glyph (U+2800..U+28FF)" do
    chars = grid(score: 60).flatten.map { |c| c[:char] }
    expect(chars).to all(satisfy { |ch| ch.ord.between?(0x2800, 0x28FF) })
  end
end
