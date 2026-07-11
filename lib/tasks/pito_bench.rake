# frozen_string_literal: true

# READONLY performance baseline for the 0.9.0 caching release.
#
# Runs every registered Pito::Bench step under a network kill switch (any
# outbound socket raises) and a read-only DB session (any app-data write
# raises), prints an aligned table, and writes a diffable JSON snapshot to
# tmp/bench/. Safe to run in production (`bin/pito rake pito:bench`).
#
#   UUID=<conversation uuid>  scope the replay step (default: most events)
#   N=<iterations>            microbench loop count (default: 50)
namespace :pito do
  desc "READONLY render/API-plan benchmark — table + tmp/bench/<ts>.json snapshot (UUID=…, N=…)"
  task bench: :environment do
    Pito::Bench::Runner.call(
      uuid:       ENV["UUID"].presence,
      iterations: ENV.fetch("N", "50").to_i
    )
  end
end
