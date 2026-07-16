# frozen_string_literal: true

require "rails_helper"
require "rake"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:images rake tasks", type: :rake do
  before(:all) { load_tasks }

  before { reenable("pito:images:purge_orphans") }

  def attach_jpeg(attachable, filename:)
    attachable.attach(io: StringIO.new("fake-bytes"), filename: filename, content_type: "image/jpeg")
  end

  describe "pito:images:purge_orphans" do
    it "reports an orphaned variant record and leaves it untouched in dry-run" do
      game = create(:game)
      attach_jpeg(game.cover_art, filename: "cover.jpg")
      stale = game.cover_art.blob.variant_records.create!(variation_digest: "stale-digest-no-longer-defined")

      expect { suppress_output { Rake::Task["pito:images:purge_orphans"].invoke } }
        .not_to change { ActiveStorage::VariantRecord.exists?(stale.id) }
      expect(ActiveStorage::VariantRecord.exists?(stale.id)).to be(true)
    end

    it "deletes the orphaned record and its variant blob when PURGE=1" do
      game = create(:game)
      attach_jpeg(game.cover_art, filename: "cover.jpg")
      stale = game.cover_art.blob.variant_records.create!(variation_digest: "stale-digest-no-longer-defined")
      attach_jpeg(stale.image, filename: "stale-variant.jpg")
      stale_blob_id = stale.image.blob.id

      begin
        ENV["PURGE"] = "1"
        suppress_output { Rake::Task["pito:images:purge_orphans"].invoke }
      ensure
        ENV.delete("PURGE")
      end

      expect(ActiveStorage::VariantRecord.exists?(stale.id)).to be(false)
      expect(ActiveStorage::Blob.exists?(stale_blob_id)).to be(false)
    end

    it "leaves a variant record whose digest matches a current named variant untouched" do
      game = create(:game)
      attach_jpeg(game.cover_art, filename: "cover.jpg")
      current_digest = game.cover_art.variant(:detail).variation.digest
      current = game.cover_art.blob.variant_records.create!(variation_digest: current_digest)

      begin
        ENV["PURGE"] = "1"
        expect { suppress_output { Rake::Task["pito:images:purge_orphans"].invoke } }
          .not_to change { ActiveStorage::VariantRecord.exists?(current.id) }
      ensure
        ENV.delete("PURGE")
      end
      expect(ActiveStorage::VariantRecord.exists?(current.id)).to be(true)
    end
  end
end
