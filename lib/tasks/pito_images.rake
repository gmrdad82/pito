# frozen_string_literal: true

# Maintenance for ActiveStorage images (game covers + video thumbnails +
# channel avatars) whose backing file went missing from the storage service
# (e.g. a wiped `storage/` or a migration to a new storage root), leaving a
# broken <img>. See Pito::Maintenance::ImageSweep.
#
#   rake pito:images:sweep   # report games/videos/channels with a missing blob file
#   rake pito:images:fix     # re-attach them from source (IGDB / YouTube)

# Every named-variant attachment definition `pito:images:purge_orphans` audits,
# mapped to the NAME of the model class that declares it — the only
# `has_one_attached do |attachable| attachable.variant ... end` blocks in the
# app: Channel avatar/banner, Video thumbnail, Game cover_art. Keep this in
# sync if a model ever adds/removes a named variant. Values are strings
# (constantized lazily, inside the task body) rather than the constants
# themselves: `Rails.application.load_tasks` evaluates every `.rake` file's
# top-level code before the `:environment` task runs, i.e. before Zeitwerk
# autoloading is available, so a bare `Channel`/`Video`/`Game` reference here
# raises `NameError: uninitialized constant` on EVERY rake invocation
# (`rake -T` included), not just when this task runs.
PITO_IMAGES_PURGE_ORPHANS_ATTACHMENTS = {
  [ "Channel", "avatar" ]  => "Channel",
  [ "Channel", "banner" ]  => "Channel",
  [ "Video", "thumbnail" ] => "Video",
  [ "Game", "cover_art" ]  => "Game"
}.freeze

# Every variation_digest currently reachable via `attachment.variant(:name)`
# for the attachments above, keyed by blob id. Resolved the same way
# ActiveStorage itself resolves a named variant (Attachment#variant →
# Blob#variant → Variation#digest, which folds in the blob's own default
# format) instead of reimplementing the hashing — so this can never drift from
# how Rails actually looks up a variant. Only called from inside a task body
# (after `:environment` has loaded), so `constantize` here is safe.
def pito_images_valid_digests_by_blob_id
  valid = Hash.new { |h, k| h[k] = Set.new }

  PITO_IMAGES_PURGE_ORPHANS_ATTACHMENTS.each do |(record_type, name), class_name|
    klass = class_name.constantize
    named_variants = klass.reflect_on_attachment(name).named_variants

    ActiveStorage::Attachment.where(record_type: record_type, name: name).find_each do |attachment|
      blob = attachment.blob
      next unless blob&.variable?

      named_variants.each_value do |named_variant|
        valid[blob.id] << blob.variant(named_variant.transformations).variation.digest
      end
    end
  end

  valid
end

namespace :pito do
  namespace :images do
    desc "Report game covers / video thumbnails / channel avatars whose blob file is missing on disk"
    task sweep: :environment do
      m = Pito::Maintenance::ImageSweep.missing
      puts "Games with a missing cover file:    #{m[:games].size}"
      m[:games].each    { |g| puts "  game    ##{g.id} — #{g.title}" }
      puts "Videos with a missing thumb file:   #{m[:videos].size}"
      m[:videos].each   { |v| puts "  video   ##{v.id} — #{v.title}" }
      puts "Channels with a missing avatar file: #{m[:channels].size}"
      m[:channels].each { |c| puts "  channel ##{c.id} — #{c.title}" }
      all_empty = m[:games].empty? && m[:videos].empty? && m[:channels].empty?
      puts(all_empty ? "All image files present. Nothing to fix." : "Run `rake pito:images:fix` to re-attach.")
    end

    desc "Re-attach game covers / video thumbnails / channel avatars whose blob file is missing"
    task fix: :environment do
      result = Pito::Maintenance::ImageSweep.repair
      puts "Covers re-attached:      #{result[:games_fixed]}"
      puts "Thumbnails re-attached:  #{result[:videos_fixed]}"
      puts "Avatars re-attached:     #{result[:channels_fixed]}"
      puts "Videos skipped (no/reauth connection):   #{result[:videos_skipped]}"   if result[:videos_skipped].positive?
      puts "Channels skipped (no/reauth connection): #{result[:channels_skipped]}" if result[:channels_skipped].positive?
    end

    # Re-derive every DISPLAY VARIANT from the stored MASTER blob. Run this after
    # re-syncing channels / videos / games (which fetch + attach the raw masters),
    # or any time the variant dimensions change. Idempotent + safe to re-run; runs
    # in the pito Docker CLI / production. (13.26)
    #   rake pito:images:regenerate
    desc "Regenerate all display variants (banner/avatar/thumbnail/cover) from their master blobs"
    task regenerate: :environment do
      count = 0

      Channel.find_each do |c|
        if c.banner.attached?
          c.banner.variant(:display).processed
          count += 1
        end
        if c.avatar.attached?
          c.avatar.variant(:sm).processed
          c.avatar.variant(:xs).processed
          count += 2
        end
      end

      Video.find_each do |v|
        next unless v.thumbnail.attached?

        v.thumbnail.variant(:display).processed
        count += 1
      end

      Game.find_each do |g|
        next unless g.cover_art.attached?

        g.cover_art.variant(:detail).processed
        g.cover_art.variant(:strip).processed
        count += 2
      end

      puts "Regenerated #{count} image variants from masters."
    end

    # Deletes ActiveStorage::VariantRecord rows (and their transformed image
    # blob) that no longer match any CURRENT named-variant definition — e.g.
    # the 3.0.0 `:strip` resize (180×240→432×576) and the removed `:lg`
    # avatar variant both left old rows behind: never rendered again, never
    # garbage-collected on their own. DRY-RUN by default (report only); pass
    # PURGE=1 to actually delete.
    #
    #   rake pito:images:purge_orphans          # report what would be purged
    #   PURGE=1 rake pito:images:purge_orphans  # actually delete
    desc "Report (PURGE=1 to delete) orphaned image ActiveStorage::VariantRecord rows"
    task purge_orphans: :environment do
      purge = ENV["PURGE"] == "1"
      valid_digests_by_blob_id = pito_images_valid_digests_by_blob_id

      orphans = ActiveStorage::VariantRecord
        .where(blob_id: valid_digests_by_blob_id.keys)
        .reject { |vr| valid_digests_by_blob_id[vr.blob_id].include?(vr.variation_digest) }

      puts "Orphaned image variants found: #{orphans.size}"
      orphans.each { |vr| puts "  variant_record ##{vr.id} — blob ##{vr.blob_id} digest=#{vr.variation_digest}" }

      if orphans.empty?
        puts "Nothing to purge."
      elsif purge
        orphans.each do |vr|
          vr.image.purge if vr.image.attached?
          vr.destroy!
        end
        puts "Purged #{orphans.size} orphaned variant(s)."
      else
        puts "Dry run — re-run with PURGE=1 to delete."
      end
    end
  end
end
