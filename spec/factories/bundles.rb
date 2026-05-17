FactoryBot.define do
  # Phase 27 follow-up (2026-05-17) — after the simplification a Bundle
  # has only `name` (plus the composite-cover artifact columns, which
  # the composer writes on its own). The legacy `:series` / `:collection`
  # / `:genre` traits are gone along with the `bundle_type` /
  # `igdb_source_*` columns.
  factory :bundle do
    sequence(:name) { |n| "Bundle #{n}" }
  end
end
