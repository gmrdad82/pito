FactoryBot.define do
  factory :platform do
    sequence(:igdb_id) { |n| 2_000 + n }
    sequence(:name) { |n| "Platform #{n}" }
    sequence(:abbreviation) { |n| "P#{n}" }
    # FriendlyId on Platform regenerates the slug from `slug_candidates`
    # whenever `name` changes. Setting slug explicitly here would be
    # clobbered by the `before_validation :set_slug` callback. Leaving
    # slug unset lets FriendlyId derive it from name (which the
    # sequence guarantees is unique). Tests that need a specific slug
    # pass `slug:` AFTER `save!` via `update_column`, or pass `slug:`
    # AND a matching name (since the slug-from-name path produces the
    # same slug the test wants).
  end
end
