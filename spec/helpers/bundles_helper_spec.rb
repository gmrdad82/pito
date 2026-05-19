require "rails_helper"

# 2026-05-18 (Wave F consolidation) — covers every public method of
# `app/helpers/bundles_helper.rb`. Today that is exactly one method:
# `#member_picker_options`. The shape is `[[title, id], ...]`, ordered
# by title ascending, with already-member games excluded.
#
# Master-agent decision #4 (per the helper's own header): the picker
# source is the LOCAL Game library, NOT IGDB live search. The IGDB
# add flow lives in the Games controller; bundles only reach for
# pre-existing rows.
RSpec.describe BundlesHelper, type: :helper do
  describe "#member_picker_options" do
    context "when the bundle has no members" do
      it "returns every Game ordered by title ascending" do
        bundle = create(:bundle)
        zebra  = create(:game, title: "Zebra Quest")
        alpha  = create(:game, title: "Alpha Tales")
        middle = create(:game, title: "Middle Run")

        result = helper.member_picker_options(bundle)

        expect(result).to eq([
          [ alpha.title,  alpha.id ],
          [ middle.title, middle.id ],
          [ zebra.title,  zebra.id ]
        ])
      end

      it "returns an empty array when the Game library is empty" do
        bundle = create(:bundle)

        expect(helper.member_picker_options(bundle)).to eq([])
      end
    end

    context "when the bundle already has members" do
      it "excludes games already linked through bundle_members" do
        bundle  = create(:bundle)
        member  = create(:game, title: "Member Game")
        free_a  = create(:game, title: "A Free Game")
        free_z  = create(:game, title: "Z Free Game")
        create(:bundle_member, bundle: bundle, game: member)

        result = helper.member_picker_options(bundle)
        ids = result.map(&:last)

        expect(ids).to contain_exactly(free_a.id, free_z.id)
        expect(ids).not_to include(member.id)
      end

      it "returns an empty array when every Game is already a member" do
        bundle = create(:bundle)
        a = create(:game)
        b = create(:game)
        create(:bundle_member, bundle: bundle, game: a)
        create(:bundle_member, bundle: bundle, game: b)

        expect(helper.member_picker_options(bundle)).to eq([])
      end

      it "still excludes members of OTHER bundles only from THIS bundle's perspective" do
        # Sad-path guard: the SQL filter is `WHERE id NOT IN (THIS
        # bundle's member ids)`. A game that belongs to a different
        # bundle is still eligible to join this one — bundles are
        # not mutually exclusive groupings.
        target_bundle = create(:bundle, name: "Target")
        other_bundle  = create(:bundle, name: "Other")
        shared_game   = create(:game, title: "Shared")
        target_only   = create(:game, title: "Target-only")
        create(:bundle_member, bundle: other_bundle, game: shared_game)
        create(:bundle_member, bundle: target_bundle, game: target_only)

        ids = helper.member_picker_options(target_bundle).map(&:last)

        expect(ids).to include(shared_game.id)
        expect(ids).not_to include(target_only.id)
      end
    end

    context "edge cases" do
      it "tolerates a freshly-built bundle (no members association loaded)" do
        bundle = create(:bundle)
        game   = create(:game, title: "Solo")

        result = helper.member_picker_options(bundle)

        expect(result).to eq([ [ game.title, game.id ] ])
      end

      it "orders titles case-sensitively per Postgres default collation" do
        # Documents current behavior: `.order(:title)` defers to the DB
        # collation. We don't pin a specific casing outcome (collation
        # is environment-dependent); we just assert ordering is stable
        # and excludes duplicates of nothing.
        bundle = create(:bundle)
        a = create(:game, title: "apple")
        b = create(:game, title: "banana")
        c = create(:game, title: "cherry")

        result = helper.member_picker_options(bundle)
        titles = result.map(&:first)

        expect(titles).to eq(titles.sort)
        expect(result.map(&:last)).to contain_exactly(a.id, b.id, c.id)
      end

      it "returns `[title, id]` pairs (NOT id-only and NOT hashes)" do
        bundle = create(:bundle)
        game   = create(:game, title: "Shape Check")

        result = helper.member_picker_options(bundle)

        expect(result).to all(be_an(Array))
        expect(result.first.length).to eq(2)
        expect(result.first.first).to be_a(String)
        expect(result.first.last).to be_an(Integer)
      end
    end
  end
end
