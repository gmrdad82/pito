# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — Bundle composite-cover
# orphan reaper.
#
# Walks `<PITO_ASSETS_PATH>/covers/bundles/*/composite.jpg` and removes
# any file (and its now-empty parent directory) that does NOT correspond
# to an existing Bundle's `composite_cover_path`. The on-disk layout is
# `covers/bundles/<bundle_id>/composite.jpg` (formerly the flat
# `composites/bundle-<id>.jpg`; consolidated under the unified
# `/covers/` namespace 2026-05-17). Orphans typically arise from:
#   - failed `before_destroy` sweeps (filesystem write fail or process
#     crash mid-destroy)
#   - schema-shape changes that altered the path pattern.
#
# Idempotent. Runs in ~O(file count); safe on every deploy boot.
#
# Usage:
#   bin/rails pito:bundles:reap_orphans
namespace :pito do
  namespace :bundles do
    desc "Remove composite cover files that no longer correspond to any Bundle"
    task reap_orphans: :environment do
      assets_root = Pito::AssetsRoot.root
      bundles_dir = Pito::AssetsRoot.path("covers", "bundles")
      next unless Dir.exist?(bundles_dir)

      # `composite_cover_path` is stored as a relative path from the
      # assets root (e.g. `covers/bundles/12/composite.jpg`); resolve
      # each entry to an absolute path for comparison with the glob.
      keep = Bundle.where.not(composite_cover_path: nil)
                   .pluck(:composite_cover_path)
                   .map { |relative| File.expand_path(relative, assets_root.to_s) }
                   .to_set

      reaped = 0
      Dir.glob(bundles_dir.join("*", "composite.jpg")).each do |file|
        abs = File.expand_path(file)
        next if keep.include?(abs)

        File.delete(file)
        parent = File.dirname(file)
        Dir.rmdir(parent) if Dir.empty?(parent)
        reaped += 1
      rescue Errno::ENOENT
        # File already gone — fine.
      end

      puts "reaped #{reaped} orphan composite cover#{'s' if reaped != 1}."
    end
  end
end
