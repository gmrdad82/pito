# frozen_string_literal: true

# Operator tooling. Currently: a full local backup (db + Voyage embeddings +
# ActiveStorage assets) into a gzipped, timestamped backup/ folder.
#
# Usage:
#   bin/rails pito:tools:backup
#
# Restore is MANUAL — there is no restore task by design.

namespace :pito do
  namespace :tools do
    desc "Back up the database (incl. Voyage embeddings) + ActiveStorage assets → backup/<yyyy-mm-dd hh-mm-ss>/ (gzipped)"
    task backup: :environment do
      Pito::Tools::Backup.call
    end
  end
end
