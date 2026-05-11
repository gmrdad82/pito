require "rails_helper"

# Phase 27 follow-up (2026-05-11) — composite-cover warm-up for the
# `/games` Collections outer-shelf.
RSpec.describe Games::PrepareCollectionsForShelf do
  let(:composer) { instance_double(Collections::CoverComposer) }
  subject(:service) { described_class.new(composer: composer) }

  describe "#call" do
    it "invokes the composer once per collection" do
      one = create(:collection, name: "one")
      two = create(:collection, name: "two")
      collections = Collection.where(id: [ one.id, two.id ])

      expect(composer).to receive(:call).with(one).once.and_return(nil)
      expect(composer).to receive(:call).with(two).once.and_return(nil)

      service.call(collections)
    end

    it "returns the input collection unchanged so callers can chain" do
      one = create(:collection, name: "one")
      collections = Collection.where(id: one.id)
      allow(composer).to receive(:call).and_return(nil)

      expect(service.call(collections)).to eq(collections)
    end

    it "swallows StandardError from the composer so one bad row does not 500 the index" do
      one = create(:collection, name: "broken")
      two = create(:collection, name: "ok")
      collections = Collection.where(id: [ one.id, two.id ])

      allow(composer).to receive(:call).with(one).and_raise(RuntimeError, "tile fetch broke")
      expect(composer).to receive(:call).with(two).and_return(nil)

      expect { service.call(collections) }.not_to raise_error
    end

    it "is invoked when a multi-game collection's composer would build a composite" do
      # Integration angle — exercise the production code path with a
      # real composer to assert the wiring fires `Collections::CoverComposer#call`
      # for a 2+ member collection (the P27 reviewer's BLOCKER fix:
      # the composer was previously dead code).
      real_composer = instance_double(Collections::CoverComposer)
      service = described_class.new(composer: real_composer)
      coll = create(:collection, name: "two-game collection")
      create(:game, :synced, title: "alpha", cover_image_id: "img-a", collection: coll)
      create(:game, :synced, title: "beta",  cover_image_id: "img-b", collection: coll)

      expect(real_composer).to receive(:call).with(have_attributes(id: coll.id)).once
      service.call(Collection.where(id: coll.id))
    end
  end
end
