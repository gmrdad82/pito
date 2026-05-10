# Phase 13.2 — Analytics sync engine. Rake wrapper around
# `Backfill::AnalyticsRange.call` so a developer can recover from a
# missed range from the shell.
#
# Usage:
#   bin/rails "analytics:backfill[<connection_id>,<from>,<to>]"
#
# Dates are parsed with `Date.parse` so YYYY-MM-DD is the canonical
# input. Example:
#   bin/rails "analytics:backfill[1,2026-04-01,2026-04-30]"
namespace :analytics do
  desc "Backfill analytics for a connection over a date range. Usage: analytics:backfill[connection_id,from,to]"
  task :backfill, [ :connection_id, :from, :to ] => :environment do |_t, args|
    cid = args[:connection_id].to_s
    abort "connection_id required" if cid.empty?

    connection = YoutubeConnection.find_by(id: cid.to_i)
    abort "no YoutubeConnection with id=#{cid}" if connection.nil?

    from_str = args[:from].to_s
    to_str   = args[:to].to_s
    abort "from required" if from_str.empty?
    abort "to required"   if to_str.empty?

    from = Date.parse(from_str)
    to   = Date.parse(to_str)

    enqueued = Backfill::AnalyticsRange.call(
      connection: connection,
      from: from,
      to: to
    )
    puts "enqueued #{enqueued} jobs for connection #{connection.id} (#{from}..#{to})"
  end
end
