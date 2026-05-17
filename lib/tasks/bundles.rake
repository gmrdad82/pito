# Phase 14 §2 — Bundle composite-cover orphan reaper.
#
# Walks `<PITO_ASSETS_PATH>/composites/*.jpg` and removes any file
# that does NOT correspond to an existing Bundle's
# `composite_cover_path`. The on-disk file naming convention is
# `bundle-<bundle_id>.jpg` (formerly `<bundle_type>-<id>.jpg`; the
# discriminator column was dropped in the 2026-05-17 simplification).
# Orphans typically arise from:
#   - failed `before_destroy` sweeps (filesystem write fail or process
#     crash mid-destroy)
#   - schema-shape changes that altered the filename pattern.
#
# Idempotent. Runs in ~O(file count); safe on every deploy boot.
#
# Usage:
#   bin/rails pito:bundles:reap_orphans
namespace :pito do
  namespace :bundles do
    desc "Remove composite cover files that no longer correspond to any Bundle"
    task reap_orphans: :environment do
      composites_dir = Pito::AssetsRoot.path("composites")
      next unless Dir.exist?(composites_dir)

      keep = Bundle.where.not(composite_cover_path: nil)
                   .pluck(:composite_cover_path)
                   .map { |path| File.basename(path) }
                   .to_set

      reaped = 0
      Dir.glob(composites_dir.join("*.jpg")).each do |file|
        basename = File.basename(file)
        next if keep.include?(basename)

        File.delete(file)
        reaped += 1
      rescue Errno::ENOENT
        # File already gone — fine.
      end

      puts "reaped #{reaped} orphan composite cover#{'s' if reaped != 1}."
    end
  end
end
