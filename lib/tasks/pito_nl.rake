# frozen_string_literal: true

# Operator entry point for Pito::Nl::Router's materialized example cache
# (`nl_examples` table) — the same `sync!` NightlyReindexJob now calls
# automatically before its games/videos pass (3.0.1 P11), exposed here for an
# on-demand run: right after editing a tool's `nl_examples:` in
# config/pito/tools.yml, or to force a re-embed sweep of any row a prior sync
# left nil (sidecar was down at the time — see Pito::Nl::Router#embed_pending!).
#
# No top-level app-constant references outside the task body below — Rails'
# `Rails.application.load_tasks` evaluates every `.rake` file's top-level code
# BEFORE the `:environment` task runs (i.e. before Zeitwerk autoloading is
# available), so a bare `Pito::Nl::Router` reference outside `task … do … end`
# would raise `NameError` on EVERY rake invocation, `rake -T` included (the
# same load-order lesson `lib/tasks/pito_images.rake`'s `purge_orphans` task
# already documents).
#
#   rake pito:nl:sync
namespace :pito do
  namespace :nl do
    desc "Sync the NL router's embedded example cache from config/pito/tools.yml (prints upserted/pruned/embedded counts)"
    task sync: :environment do
      result = Pito::Nl::Router.sync!

      puts "Upserted: #{result[:upserted]}"
      puts "Pruned:   #{result[:pruned]}"
      puts "Embedded: #{result[:embedded]}"
    end
  end
end
