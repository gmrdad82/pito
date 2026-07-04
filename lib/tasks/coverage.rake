# frozen_string_literal: true

# Coverage floor (G59/G60 — the pito-tui parity gate).
#
# The floor is enforced HERE, on the MERGED result, never per-process: under
# parallel_rspec each process only executes a slice of the suite, so a
# per-process minimum_coverage would false-fail on partial coverage. Every
# group records into coverage/.resultset.json under its own command_name
# (spec_helper); once they have all finished, this task collates the merged
# resultset and exits non-zero below the floor.
#
#   CI:      runs right after parallel_rspec (COVERAGE is on via CI env).
#   Locally: COVERAGE=1 bundle exec rspec && bundle exec rake coverage:floor
#
# Override the floor for a one-off check with FLOOR=NN.
namespace :coverage do
  # The honest numbers: measured 87.67% (15424/17593 lines, full suite,
  # 2026-07-04); floor 80 per the owner — ~7.7 points of headroom. Raise it
  # as coverage grows, never lower it to make a red build green.
  FLOOR_DEFAULT = 80.0

  desc "Enforce the merged coverage floor (FLOOR=#{FLOOR_DEFAULT} by default)"
  task :floor do
    require "simplecov"

    floor = Float(ENV.fetch("FLOOR", FLOOR_DEFAULT))
    resultset = File.expand_path("../../coverage/.resultset.json", __dir__)
    abort "coverage:floor: no #{resultset} — run the suite with COVERAGE=1 first" unless File.exist?(resultset)

    SimpleCov.collate([ resultset ], "rails") do
      minimum_coverage floor
    end
  end
end
