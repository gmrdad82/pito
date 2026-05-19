require "rails_helper"

# Phase 27 task #260 — `GenresHelper` renders IGDB-canonical genre
# names VERBATIM. The cosmetic-rename map shrank to a single entry
# (`"Role-playing (RPG)" => "RPG"`). All other IGDB genre names pass
# through unchanged; distinct IGDB genres stay distinct. Nil / blank
# input returns nil so callers can chain `.presence` or pass the
# result to view helpers without guarding.
#
# `genre_short_name` is kept as a backwards-compatible alias of
# `genre_display_name`.
RSpec.describe GenresHelper, type: :helper do
  describe "GENRE_DISPLAY_RENAMES constant" do
    it "is frozen so call sites cannot mutate the table" do
      expect(GenresHelper::GENRE_DISPLAY_RENAMES).to be_frozen
    end

    it "maps the canonical Role-playing (RPG) name to the RPG acronym" do
      expect(GenresHelper::GENRE_DISPLAY_RENAMES).to include(
        "Role-playing (RPG)" => "RPG"
      )
    end

    it "holds exactly one cosmetic rename (verbatim is the default)" do
      expect(GenresHelper::GENRE_DISPLAY_RENAMES.size).to eq(1)
    end
  end

  describe "#genre_short_name with a String input" do
    it "returns the locked short label for the one mapped IGDB name" do
      expect(helper.genre_short_name("Role-playing (RPG)")).to eq("RPG")
    end

    it "returns the IGDB canonical name unchanged for an unmapped genre" do
      expect(helper.genre_short_name("Pumpkin Spice Latte"))
        .to eq("Pumpkin Spice Latte")
    end

    it "returns Shooter unchanged (proves the rename map shrank — no FPS collapse)" do
      expect(helper.genre_short_name("Shooter")).to eq("Shooter")
    end
  end

  describe "#genre_short_name with a Genre instance" do
    it "reads the genre's name and looks it up in the rename map" do
      genre = build(:genre, name: "Role-playing (RPG)")
      expect(helper.genre_short_name(genre)).to eq("RPG")
    end

    it "returns the canonical name when the genre's name is unmapped" do
      genre = build(:genre, name: "Pumpkin Spice Latte")
      expect(helper.genre_short_name(genre)).to eq("Pumpkin Spice Latte")
    end

    it "works on a persisted Genre record (verbatim passthrough)" do
      genre = build_stubbed(:genre, name: "Visual Novel", igdb_id: 9_001)
      expect(helper.genre_short_name(genre)).to eq("Visual Novel")
    end
  end

  describe "#genre_short_name edge cases" do
    it "returns nil when the input is nil" do
      expect(helper.genre_short_name(nil)).to be_nil
    end

    it "returns nil when the input is an empty string" do
      expect(helper.genre_short_name("")).to be_nil
    end

    it "returns nil when the genre's name is blank" do
      genre = Genre.new(name: "")
      expect(helper.genre_short_name(genre)).to be_nil
    end

    it "returns nil when the genre's name is nil" do
      genre = Genre.new(name: nil)
      expect(helper.genre_short_name(genre)).to be_nil
    end

    it "coerces non-string non-Genre input via #to_s and looks up the result" do
      expect(helper.genre_short_name(:Adventure)).to eq("Adventure")
    end
  end
end
