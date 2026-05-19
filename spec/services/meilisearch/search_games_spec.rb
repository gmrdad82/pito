require "rails_helper"

# Phase 34 (2026-05-18) — Meilisearch::SearchGames surface coverage.
#
# Coverage priorities (per lane C dispatch):
#   - Mixed games + bundles returned in Meilisearch hit order
#   - `kind` discriminator filtering (game vs bundle hits)
#   - `include_bundles: false` mode (search service / `:bundle_add`)
#   - `exclude_bundle` filter (drops already-in-bundle games)
#   - `resolve_bundles` accepts both new `bundle_` and legacy `bundle:` id
#     prefixes (FG defensive parser)
#   - Empty / blank query short-circuit
#   - Network failure swallow + log
#
# 2026-05-18 contract update — the Postgres ILIKE fallback ALWAYS runs
# (no `if hits.empty?` guard) and is merged into the Meilisearch hits
# via `merge_with_fallback`: Meilisearch order wins for the leading
# entries, fallback rows whose id is not already in `primary` are
# appended afterwards, capped at `@limit` total. Reproduces the
# user-reported bug where a freshly-added local game whose Meili
# indexing had not completed wouldn't surface.
RSpec.describe Meilisearch::SearchGames do
  let(:meili_url) { "http://127.0.0.1:7727" }
  let(:index_name) { "games_test" }
  let(:search_url) { "#{meili_url}/indexes/#{index_name}/search" }

  let(:game_a) { build_stubbed(:game, id: 101, title: "Alpha") }
  let(:game_b) { build_stubbed(:game, id: 102, title: "Bravo") }
  let(:game_c) { build_stubbed(:game, id: 103, title: "Charlie") }
  let(:bundle_x) { build_stubbed(:bundle, id: 201, name: "X") }
  let(:bundle_y) { build_stubbed(:bundle, id: 202, name: "Y") }

  def stub_meili_hits(hits)
    stub_request(:post, search_url).to_return(
      status: 200,
      body: JSON.generate(hits: hits),
      headers: { "Content-Type" => "application/json" }
    )
  end

  # Stubs both halves of the Game lookup so the always-runs fallback
  # contract doesn't fight the Meili-id resolution path:
  #   - `Game.where(id: [...])`   → returns `meili_rows` (resolve_games)
  #   - `Game.where("LOWER(title) ILIKE ?", ...)` → returns a chainable
  #     relation double whose `.order(:title).limit(n).to_a` yields
  #     `fallback_rows`. Empty by default so unrelated examples don't
  #     accidentally pad results.
  def stub_game_lookups(meili_rows:, fallback_rows: [])
    allow(Game).to receive(:where).and_call_original
    allow(Game).to receive(:where).with(hash_including(:id)).and_return(meili_rows)

    fallback_relation = double("Game::FallbackRelation")
    # Cover both `where(args)` and the zero-arg `where.not(...)` chain
    # the service uses when `exclude_bundle` is present.
    allow(fallback_relation).to receive(:where).and_return(fallback_relation)
    allow(fallback_relation).to receive(:not).and_return(fallback_relation)
    allow(fallback_relation).to receive(:order).with(:title).and_return(fallback_relation)
    allow(fallback_relation).to receive(:limit).and_return(fallback_relation)
    allow(fallback_relation).to receive(:to_a).and_return(fallback_rows)
    # Match the fallback `where(sql, *binds)` regardless of how many bind
    # params the SQL string carries — the 2026-05-18 slug-OR contract
    # passes TWO binds (`title_like, slug_like`), the legacy title-only
    # shape passed ONE. `any_args` after the SQL matcher covers both.
    allow(Game).to receive(:where).with(a_string_matching(/ILIKE/), any_args).and_return(fallback_relation)
  end

  # Same shape as `stub_game_lookups` but for `Bundle` + `LOWER(name)`.
  def stub_bundle_lookups(meili_rows:, fallback_rows: [])
    allow(Bundle).to receive(:where).and_call_original
    allow(Bundle).to receive(:where).with(hash_including(:id)).and_return(meili_rows)

    fallback_relation = double("Bundle::FallbackRelation")
    allow(fallback_relation).to receive(:order).with(:name).and_return(fallback_relation)
    allow(fallback_relation).to receive(:limit).and_return(fallback_relation)
    allow(fallback_relation).to receive(:to_a).and_return(fallback_rows)
    # Same slug-OR contract as `stub_game_lookups` — `any_args` covers
    # both the legacy one-bind shape and the two-bind name+slug shape.
    allow(Bundle).to receive(:where).with(a_string_matching(/ILIKE/), any_args).and_return(fallback_relation)
  end

  describe ".call" do
    context "with a blank query" do
      it "short-circuits and returns empty result sets without hitting Meilisearch" do
        result = described_class.call("   ")
        expect(result).to eq(games: [], bundles: [])
        expect(WebMock).not_to have_requested(:post, search_url)
      end
    end

    context "with a query and `include_bundles: false` (default)" do
      it "returns only games, in Meilisearch hit order, no bundles" do
        stub_meili_hits(
          [
            { "id" => 102, "kind" => "game" },
            { "id" => "bundle_201", "kind" => "bundle" },
            { "id" => 101, "kind" => "game" }
          ]
        )
        # Fallback runs unconditionally; here it returns no extras so the
        # final array reflects pure Meilisearch ordering.
        stub_game_lookups(meili_rows: [ game_a, game_b ], fallback_rows: [])

        result = described_class.call("any")
        expect(result[:games].map(&:id)).to eq([ 102, 101 ])
        expect(result[:bundles]).to eq([])
      end

      it "filters by kind == 'game' even when bundle hits are present" do
        stub_meili_hits(
          [
            { "id" => "bundle_201", "kind" => "bundle" },
            { "id" => "bundle_202", "kind" => "bundle" }
          ]
        )
        # No game hits AND no fallback rows → empty games array even
        # though the always-runs fallback was consulted.
        stub_game_lookups(meili_rows: [], fallback_rows: [])

        result = described_class.call("any")
        expect(result[:games]).to eq([])
        expect(result[:bundles]).to eq([])
      end
    end

    context "with `include_bundles: true`" do
      it "returns mixed games + bundles, each in hit order" do
        stub_meili_hits(
          [
            { "id" => 102, "kind" => "game" },
            { "id" => "bundle_201", "kind" => "bundle" },
            { "id" => 101, "kind" => "game" },
            { "id" => "bundle_202", "kind" => "bundle" }
          ]
        )
        stub_game_lookups(meili_rows: [ game_a, game_b ], fallback_rows: [])
        stub_bundle_lookups(meili_rows: [ bundle_x, bundle_y ], fallback_rows: [])

        result = described_class.call("any", include_bundles: true)
        expect(result[:games].map(&:id)).to eq([ 102, 101 ])
        expect(result[:bundles].map(&:id)).to eq([ 201, 202 ])
      end

      it "strips the new `bundle_` prefix to recover the bundle AR id" do
        stub_meili_hits([ { "id" => "bundle_201", "kind" => "bundle" } ])
        stub_game_lookups(meili_rows: [], fallback_rows: [])
        stub_bundle_lookups(meili_rows: [ bundle_x ], fallback_rows: [])

        result = described_class.call("any", include_bundles: true)
        expect(result[:bundles].map(&:id)).to eq([ 201 ])
      end

      it "defensively accepts the legacy `bundle:` colon prefix as well" do
        stub_meili_hits([ { "id" => "bundle:201", "kind" => "bundle" } ])
        stub_game_lookups(meili_rows: [], fallback_rows: [])
        stub_bundle_lookups(meili_rows: [ bundle_x ], fallback_rows: [])

        result = described_class.call("any", include_bundles: true)
        expect(result[:bundles].map(&:id)).to eq([ 201 ])
      end
    end

    context "with `exclude_bundle`" do
      it "filters out games that are already members of the given bundle" do
        members_relation = double(pluck: [ 102 ])
        excluded_bundle = double(bundle_members: members_relation)
        stub_meili_hits(
          [
            { "id" => 101, "kind" => "game" },
            { "id" => 102, "kind" => "game" },
            { "id" => 103, "kind" => "game" }
          ]
        )
        # The Meili-id resolution prunes id 102 before calling `.where`;
        # fallback is still consulted but its `where.not(id: members)`
        # branch also drops 102 — here we lean on the always-runs
        # contract by returning an empty fallback set.
        stub_game_lookups(meili_rows: [ game_a, game_c ], fallback_rows: [])

        result = described_class.call("any", exclude_bundle: excluded_bundle)
        expect(result[:games].map(&:id)).to eq([ 101, 103 ])
      end

      it "returns an empty games array when every hit is excluded" do
        members_relation = double(pluck: [ 101, 102, 103 ])
        excluded_bundle = double(bundle_members: members_relation)
        stub_meili_hits(
          [
            { "id" => 101, "kind" => "game" },
            { "id" => 102, "kind" => "game" }
          ]
        )
        stub_game_lookups(meili_rows: [], fallback_rows: [])

        result = described_class.call("any", exclude_bundle: excluded_bundle)
        expect(result[:games]).to eq([])
      end
    end

    context "with a non-2xx Meilisearch response" do
      it "returns empty result sets (no raise) when the fallback is also empty" do
        stub_request(:post, search_url).to_return(status: 500, body: "boom")
        # `fetch_hits` returns [] on non-2xx, then the always-runs
        # fallback consults `Game.where(LOWER(title) ILIKE …)`. With no
        # local matches the merged array stays empty.
        expect { described_class.call("any") }.not_to raise_error
        expect(described_class.call("any")).to eq(games: [], bundles: [])
      end
    end

    context "when the network call raises" do
      it "logs and returns empty result sets when the fallback is also empty" do
        stub_request(:post, search_url).to_raise(StandardError.new("net down"))
        expect(Rails.logger).to receive(:warn).with(/SearchGames.*query failed.*\"any\".*net down/)

        # On rescue the service still runs the Postgres fallback — with
        # no local matches for "any" the result stays empty.
        expect(described_class.call("any")).to eq(games: [], bundles: [])
      end
    end

    context "limit handling" do
      it "asks Meilisearch for 2x the per-kind limit (headroom for skewed results)" do
        stub_meili_hits([])
        stub_game_lookups(meili_rows: [], fallback_rows: [])

        described_class.call("any", limit: 7)
        expect(WebMock).to have_requested(:post, search_url).with { |req|
          JSON.parse(req.body)["limit"] == 14
        }
      end

      it "caps each per-kind array at the limit value" do
        hits = (1..50).map { |i| { "id" => i, "kind" => "game" } }
        stub_meili_hits(hits)

        all_games = (1..50).map { |i| build_stubbed(:game, id: i) }
        # Meili-id resolution returns all 50 games; the service slices
        # by `@limit` after `merge_with_fallback`. Fallback returns no
        # extras so the cap is enforced purely on the primary side.
        stub_game_lookups(meili_rows: all_games, fallback_rows: [])

        result = described_class.call("any", limit: 5)
        expect(result[:games].size).to eq(5)
      end

      it "still caps to @limit after merging Meilisearch hits with fallback rows" do
        # 3 Meilisearch hits + 5 fallback rows whose ids do not overlap →
        # 8 unique rows; cap at 4 means the first 3 are Meili-ordered
        # and the 4th is the first fallback row by title order.
        stub_meili_hits(
          [
            { "id" => 101, "kind" => "game" },
            { "id" => 102, "kind" => "game" },
            { "id" => 103, "kind" => "game" }
          ]
        )
        fallback = (201..205).map { |i| build_stubbed(:game, id: i) }
        stub_game_lookups(
          meili_rows: [ game_a, game_b, game_c ],
          fallback_rows: fallback
        )

        result = described_class.call("any", limit: 4)
        expect(result[:games].map(&:id)).to eq([ 101, 102, 103, 201 ])
      end
    end

    # 2026-05-18 — Postgres ILIKE fallback. The fallback ALWAYS runs and
    # is merged with the Meilisearch hits via `merge_with_fallback`.
    # Reproduces the user-reported bug where a freshly-added local game
    # whose Meilisearch indexing had not completed wouldn't surface
    # even though `LOWER(title) ILIKE %q%` clearly matches it.
    context "Postgres ILIKE fallback (always-runs + merged contract)" do
      it "returns matching local games via ILIKE on Game#title when Meili returns no hits" do
        create(:game, title: "Street Fighter 6")
        create(:game, title: "Hollow Knight")
        stub_meili_hits([])

        result = described_class.call("street")
        expect(result[:games].map(&:title)).to eq([ "Street Fighter 6" ])
      end

      it "is case-insensitive" do
        create(:game, title: "Pragmata")
        stub_meili_hits([])

        result = described_class.call("PRAG")
        expect(result[:games].map(&:title)).to eq([ "Pragmata" ])
      end

      it "honors `exclude_bundle` and drops games already in the bundle" do
        in_bundle = create(:game, title: "Street Fighter 6")
        free = create(:game, title: "Street Fighter 4")
        bundle = create(:bundle, name: "Fighters")
        bundle.bundle_members.create!(game_id: in_bundle.id)
        stub_meili_hits([])

        result = described_class.call("street", exclude_bundle: bundle)
        expect(result[:games].map(&:id)).to eq([ free.id ])
      end

      # 2026-05-18 — bug-fix contract. PREVIOUS behavior gated the
      # fallback behind `if games.empty?`; that masked the user-reported
      # bug where a freshly-added local game whose Meili indexing had
      # not finished wouldn't appear because some unrelated row already
      # populated the Meilisearch hits. Lock the NEW contract: the
      # fallback fires even when Meilisearch returns hits, and the
      # merged array contains BOTH sets ordered by Meili priority first,
      # deduped by id.
      it "fires the fallback EVEN when Meilisearch returns game hits and merges by Meili priority + dedup" do
        meili_game = create(:game, title: "Stardew Valley")
        local_only = create(:game, title: "Street Fighter 6")
        stub_meili_hits([ { "id" => meili_game.id, "kind" => "game" } ])

        result = described_class.call("st")
        # Meilisearch hit leads (Stardew Valley); the ILIKE fallback
        # then appends Street Fighter 6 (not in Meili). No duplication.
        expect(result[:games].map(&:id)).to eq([ meili_game.id, local_only.id ])
      end

      it "dedupes by id when the same row appears in both Meilisearch hits and the fallback" do
        shared = create(:game, title: "Street Fighter 6")
        stub_meili_hits([ { "id" => shared.id, "kind" => "game" } ])

        result = described_class.call("street")
        # The fallback also matches `shared` via ILIKE; merge_with_fallback
        # drops the duplicate so the row appears exactly once.
        expect(result[:games].map(&:id)).to eq([ shared.id ])
      end

      it "respects @limit when the merged primary + fallback exceeds the cap (end-to-end)" do
        meili_game = create(:game, title: "Stardew Valley")
        # Three extra local matches; cap of 2 means only the Meili hit
        # plus the first fallback row by title order survive.
        create(:game, title: "Street Fighter 4")
        create(:game, title: "Street Fighter 5")
        create(:game, title: "Street Fighter 6")
        stub_meili_hits([ { "id" => meili_game.id, "kind" => "game" } ])

        result = described_class.call("st", limit: 2)
        expect(result[:games].map(&:title)).to eq([ "Stardew Valley", "Street Fighter 4" ])
      end

      it "returns local bundles via ILIKE on Bundle#name when include_bundles is true" do
        create(:bundle, name: "Street Fighter Series")
        create(:bundle, name: "Roguelikes")
        stub_meili_hits([])

        result = described_class.call("street", include_bundles: true)
        expect(result[:bundles].map(&:name)).to eq([ "Street Fighter Series" ])
      end

      it "still runs the fallback when the Meilisearch network call raises" do
        create(:game, title: "Street Fighter 6")
        stub_request(:post, search_url).to_raise(StandardError.new("net down"))
        allow(Rails.logger).to receive(:warn)

        result = described_class.call("street")
        expect(result[:games].map(&:title)).to eq([ "Street Fighter 6" ])
      end

      it "escapes LIKE metacharacters in the query" do
        create(:game, title: "Plain Title")
        stub_meili_hits([])

        result = described_class.call("%plain%")
        # `%` is sanitized so the LIKE pattern is `%\%plain\%%` — matches
        # only a literal `%plain%` substring (none in the fixture).
        expect(result[:games]).to eq([])
      end
    end

    # 2026-05-18 — slug-match fallback. `fallback_games` / `fallback_bundles`
    # OR-match the dasherized query against `igdb_slug` / `slug` so games
    # whose `title` is the IGDB canonical form (e.g. "Street Fighter VI",
    # "Spider-Man: Miles Morales") still surface when the user types the
    # kebab-form English ("street fighter", "spider-man") — the slug is
    # always the IGDB canonical lowercased kebab-cased identifier, so the
    # dasherized query reliably substring-matches it.
    context "slug-match fallback (dasherized query OR-matched against slug column)" do
      it "finds a Game by `igdb_slug` when `title` does not match the query" do
        # The user typed "street fighter" but the local row's `title`
        # is a non-English alt-name (e.g. the Japanese release name) —
        # the TITLE branch does NOT match. The slug is the IGDB-canonical
        # kebab-form English, so the dasherized query matches the SLUG
        # branch alone. Reproduces the bug the impl agent fixed.
        match = create(:game, title: "ストリートファイター6", igdb_slug: "street-fighter-6")
        create(:game, title: "Hollow Knight", igdb_slug: "hollow-knight")
        stub_meili_hits([])

        result = described_class.call("street fighter")
        expect(result[:games].map(&:id)).to eq([ match.id ])
      end

      it "finds a Bundle by `slug` when `name` does not match the query" do
        # FriendlyId derives slug from name, so set the name to one shape
        # and overwrite the slug to the kebab-canonical the user types
        # against. Bundle persists the slug column directly (no after_save
        # regeneration on slug=).
        match = create(:bundle, name: "SF Anthology")
        match.update_column(:slug, "street-fighter-anthology")
        other = create(:bundle, name: "Roguelikes")
        stub_meili_hits([])

        result = described_class.call("street fighter", include_bundles: true)
        expect(result[:bundles].map(&:id)).to eq([ match.id ])
        expect(result[:bundles].map(&:id)).not_to include(other.id)
      end

      it "dasherizes a multi-word query so spaces become hyphens for the slug branch" do
        # "street fighter" → slug pattern `%street-fighter%`; this matches
        # `street-fighter-6` but NOT `streetfighter` (no hyphen).
        kebab_match = create(:game, title: "X1", igdb_slug: "street-fighter-6")
        no_hyphen   = create(:game, title: "X2", igdb_slug: "streetfighter")
        stub_meili_hits([])

        result = described_class.call("street fighter")
        ids = result[:games].map(&:id)
        expect(ids).to include(kebab_match.id)
        expect(ids).not_to include(no_hyphen.id)
      end

      it "treats a single-word query identically for title and slug branches (dasherize is a no-op)" do
        # Single-word "doom" → both `LOWER(title) ILIKE '%doom%'` and
        # `LOWER(igdb_slug) ILIKE '%doom%'` (no spaces, no hyphens added).
        # Either column matching the substring surfaces the row.
        by_title = create(:game, title: "DOOM Eternal", igdb_slug: "eternal-fps")
        by_slug  = create(:game, title: "Eternal FPS", igdb_slug: "doom-eternal")
        create(:game, title: "Hollow Knight", igdb_slug: "hollow-knight")
        stub_meili_hits([])

        result = described_class.call("doom")
        ids = result[:games].map(&:id)
        expect(ids).to contain_exactly(by_title.id, by_slug.id)
      end

      it "dasherizes a hyphenated query safely (existing hyphens stay, spaces become hyphens)" do
        # "Spider-Man" → downcased "spider-man" → tr ' ' '-' is a no-op
        # because the input had no spaces. The slug pattern stays
        # `%spider-man%` and matches IGDB slugs containing the substring.
        # Use a title that does NOT contain "spider-man" so we exercise
        # the slug branch in isolation (forces a slug-only hit).
        slug_only = create(:game, title: "MSM Remastered", igdb_slug: "spider-man-miles-morales")
        create(:game, title: "Hollow Knight", igdb_slug: "hollow-knight")
        stub_meili_hits([])

        result = described_class.call("Spider-Man")
        expect(result[:games].map(&:id)).to eq([ slug_only.id ])
      end

      # 2026-05-19 — alternative_names fallback. The `fallback_games`
      # ILIKE clause OR-matches an `EXISTS (SELECT 1 FROM unnest(
      # alternative_names) AS alt WHERE LOWER(alt) ILIKE ?)` branch so
      # IGDB-supplied alt names ("SF6", "FF7 Rebirth", "TotK", ...)
      # surface the canonical game even when neither `title` nor
      # `igdb_slug` matches the query. Bundle.fallback_bundles is
      # unaffected — bundles have no alt_names column.
      context "alt_names fallback (alternative_names text[] OR-match)" do
        it "finds a Game by an alt name when the title does not match" do
          # Local title is the IGDB canonical "Street Fighter 6"; user
          # types "SF6" — the alt-name ILIKE branch is the only one
          # that can fire (slug `street-fighter-6` does not contain
          # "sf6"). Reproduces the user-facing search behavior.
          match = create(:game, title: "Street Fighter 6", igdb_slug: "street-fighter-6", alternative_names: [ "SF6" ])
          create(:game, title: "Hollow Knight", igdb_slug: "hollow-knight", alternative_names: [])
          stub_meili_hits([])

          result = described_class.call("sf6")
          expect(result[:games].map(&:id)).to eq([ match.id ])
        end

        it "is case-insensitive on the alt_names branch" do
          match = create(:game, title: "Street Fighter 6", igdb_slug: "street-fighter-6", alternative_names: [ "SF6" ])
          stub_meili_hits([])

          [ "SF6", "sf6", "Sf6" ].each do |q|
            result = described_class.call(q)
            expect(result[:games].map(&:id)).to eq([ match.id ]), "expected query #{q.inspect} to match"
          end
        end

        it "matches a multi-word alt name via the dasherized + plain branches together" do
          # `alternative_names: ["Street Fighter VI"]`; user types
          # "street fighter". The title-form alt-name ILIKE pattern is
          # `%street fighter%` (un-dasherized — matches "Street Fighter VI").
          match = create(:game, title: "ストリートファイター6", igdb_slug: "sf6-jp", alternative_names: [ "Street Fighter VI" ])
          create(:game, title: "Hollow Knight", igdb_slug: "hollow-knight", alternative_names: [])
          stub_meili_hits([])

          result = described_class.call("street fighter")
          expect(result[:games].map(&:id)).to include(match.id)
        end

        it "still matches by title for games with no alt_names (regression guard)" do
          # Empty `alternative_names` must not break the title branch.
          match = create(:game, title: "Hollow Knight", igdb_slug: "hollow-knight", alternative_names: [])
          stub_meili_hits([])

          result = described_class.call("hollow")
          expect(result[:games].map(&:id)).to eq([ match.id ])
        end

        it "still matches by slug for games with no alt_names (regression guard)" do
          match = create(:game, title: "ストリートファイター6", igdb_slug: "street-fighter-6", alternative_names: [])
          stub_meili_hits([])

          result = described_class.call("street fighter")
          expect(result[:games].map(&:id)).to eq([ match.id ])
        end

        it "leaves Bundle.fallback_bundles unaffected (bundles have no alt_names column — regression guard)" do
          # Bundles match strictly via name + slug; the alt-name SQL
          # branch is games-only. This guards against a copy-paste
          # mistake that would add an alt-names clause to the bundle
          # SQL (the column does not exist on bundles).
          match = create(:bundle, name: "Street Fighter Series")
          create(:bundle, name: "Roguelikes")
          stub_meili_hits([])

          result = described_class.call("street", include_bundles: true)
          expect(result[:bundles].map(&:id)).to eq([ match.id ])
        end
      end

      it "short-circuits on an empty query without consulting either fallback branch" do
        # Regression guard: blank query must NOT hit `Game.where(LOWER...)`
        # NOR `Bundle.where(LOWER...)` — the early `return` in `#call`
        # bypasses both the Meilisearch request and the fallback path.
        # Local rows exist whose `title`/`name` would trivially match the
        # word "street" if the fallback fired; we then ask with a blank
        # query and expect EMPTY result sets (the rows must not appear).
        create(:game, title: "Street Fighter 6", igdb_slug: "street-fighter-6")
        create(:bundle, name: "Street Fighters")
        # The Meili HTTP request stub is NOT registered; if the service
        # accidentally called Meilisearch the WebMock unstubbed-request
        # error would fail this example.

        result = described_class.call("   ", include_bundles: true)
        expect(result).to eq(games: [], bundles: [])
        expect(WebMock).not_to have_requested(:post, search_url)
      end
    end
  end
end
