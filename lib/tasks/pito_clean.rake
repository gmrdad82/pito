# frozen_string_literal: true

# Operator hygiene: clear regenerable Rails tmp artifacts + dev logs.
#
# Usage:
#   bin/rails pito:clean   # native dev
#   pito clean             # Docker stack (runs this in the web container)
#
# Conservative by design — see Pito::Tools::Clean. Never a blanket tmp wipe;
# never touches Active Storage, pidfiles, or the owner's own tmp/ files.

namespace :pito do
  desc "Clear tmp/ scratch (keeps storage, pids, .keep) + truncate dev log/*.log. Dev blobs live in public/pito-storage, not tmp."
  task clean: :environment do
    cleared = Pito::Tools::Clean.call
    puts cleared.empty? ? "Nothing to clean." : "Cleaned: #{cleared.join(', ')}"
  end
end
