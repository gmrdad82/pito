# Disk cleanup tasks for artifacts that were no longer tracked after model drops.
#
# Purpose: operator-run tasks to remove on-disk files whose parent models have
#   been dropped from the codebase. Idempotent — each task is safe to run
#   multiple times and no-ops when the target directory is already absent.
# Related: R1 sweep dropped the Bundle model + Bundle::Composite::* services.
#   The compound covers those services wrote to disk are removed here.
namespace :pito do
  namespace :cleanup do
    desc "Recursively remove bundle composite covers + tile caches from disk " \
         "(R1 dropped the model + services; this drops the files)."
    task drop_compound_covers: :environment do
      root = Pito::AssetsRoot.root.join("covers", "bundles")
      if root.exist?
        size = `du -sh #{root.to_s.shellescape}`.split.first rescue "?"
        FileUtils.rm_rf(root)
        puts "Removed #{root} (#{size})"
      else
        puts "Already clean — #{root} not present."
      end
    end
  end
end
