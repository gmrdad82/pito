# Phase 27 follow-up (2026-05-17) — `public/<sub>` → assets-volume symlinks.
#
# Wires `public/covers` and `public/thumbnails` to the `pito-assets`
# named volume so Rails' built-in static-file middleware can serve the
# normalized cover masters (and future thumbnails) without a dedicated
# controller. The symlink target resolves through `Pito::AssetsRoot`,
# which honors `PITO_ASSETS_PATH` (relative values anchor to
# `Rails.root` — `tmp/pito-assets` in dev, `/var/lib/pito-assets` in
# production). The task is idempotent:
#
#   - If the link already points at the correct target, it is left alone.
#   - If the link points elsewhere, it is replaced.
#   - If the path exists as a real directory or file, the task SKIPS
#     it with a warning and leaves the data alone — operator must move
#     the directory out of the way before re-running.
#
# Both target directories are `mkdir_p`'d before the link is created so
# the symlink never dangles on a fresh checkout.
require "fileutils"

namespace :pito do
  namespace :assets do
    desc "Create symlinks public/covers + public/thumbnails to assets volume (idempotent)"
    task setup_symlinks: :environment do
      pairs = [
        [ "covers",     Pito::AssetsRoot.path("covers") ],
        [ "thumbnails", Pito::AssetsRoot.path("thumbnails") ]
      ]

      pairs.each do |public_subdir, target|
        link_path = Rails.root.join("public", public_subdir)
        FileUtils.mkdir_p(target)

        if File.symlink?(link_path)
          existing = File.readlink(link_path)
          resolved = File.expand_path(existing, File.dirname(link_path))
          if resolved == target.to_s
            puts "[symlink] #{public_subdir} -> #{target} (already linked, OK)"
            next
          else
            puts "[symlink] #{public_subdir} -> #{existing} (REPLACING — points elsewhere)"
            File.unlink(link_path)
          end
        elsif File.directory?(link_path)
          puts "[symlink] WARNING: #{link_path} exists as a directory (not a symlink). Skipping to avoid data loss. Move/clear it manually if you want the symlink."
          next
        elsif File.exist?(link_path)
          puts "[symlink] WARNING: #{link_path} exists as a file. Skipping."
          next
        end

        File.symlink(target, link_path)
        puts "[symlink] #{public_subdir} -> #{target} (created)"
      end

      puts ""
      puts "[pito:assets:setup_symlinks] done"
    end
  end
end
