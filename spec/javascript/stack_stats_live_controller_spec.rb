require "rails_helper"

# 2026-05-18 — Static-source structural lock for the
# `stack-stats-live` Stimulus controller
# (`app/javascript/controllers/stack_stats_live_controller.js`).
#
# Rack_test has no JS engine, so the runtime ActionCable subscription
# and DOM-patch behavior can't be exercised directly via Capybara.
# What we CAN lock is the source text of the controller — Stimulus
# target declarations, the connect()/disconnect() lifecycle, and the
# payload-shape contract between the controller and `StackStatsChannel`.
#
# Drift in any of these (a renamed target, a dropped subscription
# teardown, a forgotten payload branch) silently breaks the live
# /settings stack pane — the user sees stale numbers and no error.
# This spec is the early-warning trip wire.
RSpec.describe "stack_stats_live_controller.js" do
  let(:controller_source) do
    File.read(
      Rails.root.join("app/javascript/controllers/stack_stats_live_controller.js")
    )
  end

  describe "controller declaration" do
    it "exports a default Stimulus Controller subclass" do
      expect(controller_source).to match(
        /export\s+default\s+class\s+extends\s+Controller/
      )
    end

    it "imports createConsumer from @rails/actioncable" do
      # The live transport is ActionCable — the controller MUST pull the
      # consumer factory in. If a refactor swaps to fetch() polling the
      # whole "push, don't poll" architecture (per user direction) is gone.
      expect(controller_source).to match(
        /import\s*\{\s*createConsumer\s*\}\s*from\s*"@rails\/actioncable"/
      )
    end
  end

  describe "Stimulus targets" do
    # The targets array names every cell the controller patches.
    # Adding/removing a cell on the server must be mirrored here or the
    # corresponding `updateXxx` helper silently no-ops via the
    # `hasXxxTarget && this.xxxTarget` short-circuit.
    %w[
      busy scheduled enqueued retry dead successful failed
      voyageEmbedded voyageTotal voyageBundlesEmbedded voyageBundlesTotal
      voyageBundlesCoveragePct voyagePct voyageLast voyageStorage voyage24h
      postgresGamesRows postgresGamesSize postgresBundlesRows postgresBundlesSize
      meilisearchGamesDocs meilisearchGamesSize meilisearchBundlesDocs meilisearchBundlesSize
      assetsCoverArtsFiles assetsCoverArtsSize assetsCompositesFiles assetsCompositesSize
    ].each do |target_name|
      it "declares `#{target_name}` as a Stimulus target" do
        expect(controller_source).to match(/"#{Regexp.escape(target_name)}"/),
          "expected `#{target_name}` in the static targets array"
      end
    end

    it "declares the targets via `static targets = [...]`" do
      expect(controller_source).to match(/static\s+targets\s*=\s*\[/)
    end
  end

  describe "connect() — ActionCable subscription wiring" do
    let(:connect_body) do
      controller_source[/connect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a connect() lifecycle hook" do
      expect(controller_source).to match(/connect\s*\(\s*\)\s*\{/)
    end

    it "creates an ActionCable consumer via createConsumer()" do
      expect(connect_body).to include("createConsumer()"),
        "expected connect() to instantiate the ActionCable consumer"
    end

    it "subscribes to the StackStatsChannel" do
      expect(connect_body).to match(/channel:\s*"StackStatsChannel"/),
        "expected connect() to subscribe to StackStatsChannel by name"
    end

    it "wires the `received` callback to applyPayload" do
      # The wire shape must hand the broadcast payload straight to the
      # apply method — that's the single funnel for every payload branch.
      expect(connect_body).to match(
        /received:\s*\(\s*data\s*\)\s*=>\s*this\.applyPayload\(\s*data\s*\)/
      )
    end

    it "caches both the consumer and subscription on the instance" do
      # Both refs are needed in disconnect() to tear down cleanly. A
      # refactor that drops either reference leaks listeners on Turbo
      # morphs.
      expect(connect_body).to match(/this\.consumer\s*=/)
      expect(connect_body).to match(/this\.subscription\s*=/)
    end
  end

  describe "disconnect() — clean teardown" do
    let(:disconnect_body) do
      controller_source[/disconnect\s*\(\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines a disconnect() lifecycle hook" do
      expect(controller_source).to match(/disconnect\s*\(\s*\)\s*\{/)
    end

    it "unsubscribes the subscription when present" do
      expect(disconnect_body).to include("this.subscription.unsubscribe()"),
        "expected disconnect() to call unsubscribe() on the subscription"
    end

    it "guards the unsubscribe behind a subscription presence check" do
      # The guard prevents a NPE on a controller that never finished
      # connect() (e.g. failed channel resolution).
      expect(disconnect_body).to match(/if\s*\(\s*this\.subscription\s*\)/)
    end

    it "disconnects the ActionCable consumer" do
      expect(disconnect_body).to include("this.consumer.disconnect()"),
        "expected disconnect() to disconnect the cached consumer"
    end

    it "nulls the cached references so a re-mount starts clean" do
      expect(disconnect_body).to match(/this\.subscription\s*=\s*null/)
      expect(disconnect_body).to match(/this\.consumer\s*=\s*null/)
    end
  end

  describe "applyPayload — broadcast funnel" do
    let(:apply_body) do
      controller_source[/applyPayload\s*\(\s*data\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "defines applyPayload(data)" do
      expect(controller_source).to match(/applyPayload\s*\(\s*data\s*\)\s*\{/)
    end

    it "bails early on a falsy payload" do
      # Guard against a broadcast with no body (server-side bug, channel
      # restart) silently dereferencing `data.redis`.
      expect(apply_body).to match(/if\s*\(\s*!data\s*\)\s*return/)
    end

    it "branches on `redis`, `voyage`, `postgres`, `meilisearch`, `assets`" do
      # Each top-level payload key dispatches into its dedicated updater.
      # Drop one and the corresponding pane section goes stale silently.
      %w[redis voyage postgres meilisearch assets].each do |key|
        expect(apply_body).to match(/if\s*\(\s*data\.#{key}\s*\)\s*this\.update#{key.capitalize}/),
          "expected applyPayload to dispatch on data.#{key}"
      end
    end
  end

  describe "updateRedis — Sidekiq / Redis counters" do
    let(:body) do
      controller_source[/updateRedis\s*\(\s*redis\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "is defined as updateRedis(redis)" do
      expect(controller_source).to match(/updateRedis\s*\(\s*redis\s*\)\s*\{/)
    end

    it "patches busy / scheduled / enqueued / retry / dead with setNumber" do
      %w[busy scheduled enqueued retry dead].each do |cell|
        expect(body).to match(/setNumber\([^,]*#{cell}Target,\s*redis\.#{cell}\)/i),
          "expected updateRedis to call setNumber for `#{cell}`"
      end
    end

    it "patches successful / failed via setDelimited (thousands separator)" do
      # Lifetime counters get a comma separator; in-flight gauges don't.
      expect(body).to match(/setDelimited\([^,]*successfulTarget,\s*redis\.processed\)/)
      expect(body).to match(/setDelimited\([^,]*failedTarget,\s*redis\.failed\)/)
    end
  end

  describe "updateVoyage — embedding stats" do
    let(:body) do
      controller_source[/updateVoyage\s*\(\s*voyage\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "is defined as updateVoyage(voyage)" do
      expect(controller_source).to match(/updateVoyage\s*\(\s*voyage\s*\)\s*\{/)
    end

    it "patches the games coverage cells from `embedded_games_count` and `total_games_count`" do
      expect(body).to match(/voyageEmbeddedTarget,\s*voyage\.embedded_games_count/)
      expect(body).to match(/voyageTotalTarget,\s*voyage\.total_games_count/)
    end

    it "patches the bundles coverage cells from `embedded_bundles_count` and `total_bundles_count`" do
      expect(body).to match(/voyageBundlesEmbeddedTarget,\s*voyage\.embedded_bundles_count/)
      expect(body).to match(/voyageBundlesTotalTarget,\s*voyage\.total_bundles_count/)
    end

    it "guards coverage_pct against undefined/null before writing" do
      # The percentage write skips the cell entirely on a missing value
      # so the existing server-rendered text survives.
      expect(body).to match(/voyage\.coverage_pct\s*!==\s*undefined/)
      expect(body).to match(/voyage\.coverage_pct\s*!==\s*null/)
    end

    it "guards bundle_coverage_pct against undefined/null before writing" do
      # The bundle-coverage cell is nil-safe because the underlying
      # column may not exist; skipping the write preserves the ERB
      # guard's hidden-parenthetical behavior.
      expect(body).to match(/voyage\.bundle_coverage_pct\s*!==\s*undefined/)
      expect(body).to match(/voyage\.bundle_coverage_pct\s*!==\s*null/)
    end

    it "patches the last-indexed timestamp from `last_indexed_at_formatted`" do
      expect(body).to match(/voyage\.last_indexed_at_formatted/)
    end

    it "patches storage and 24h cells via setDelimited" do
      expect(body).to match(/setDelimited\([^,]*voyageStorageTarget,\s*voyage\.storage_kb\)/)
      expect(body).to match(/setDelimited\([^,]*voyage24hTarget,\s*voyage\.embeddings_last_24h\)/)
    end
  end

  describe "updatePostgres — per-row Postgres breakdown" do
    let(:body) do
      controller_source[/updatePostgres\s*\(\s*postgres\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "is defined as updatePostgres(postgres)" do
      expect(controller_source).to match(/updatePostgres\s*\(\s*postgres\s*\)\s*\{/)
    end

    it "patches games row count + size from flat `games_rows` / `games_size_bytes`" do
      expect(body).to match(/postgresGamesRowsTarget,\s*postgres\.games_rows/)
      expect(body).to match(/setFilesize\([^,]*postgresGamesSizeTarget,\s*postgres\.games_size_bytes\)/)
    end

    it "patches bundles row count + size from flat `bundles_rows` / `bundles_size_bytes`" do
      expect(body).to match(/postgresBundlesRowsTarget,\s*postgres\.bundles_rows/)
      expect(body).to match(/setFilesize\([^,]*postgresBundlesSizeTarget,\s*postgres\.bundles_size_bytes\)/)
    end
  end

  describe "updateMeilisearch — per-row Meilisearch breakdown" do
    let(:body) do
      controller_source[/updateMeilisearch\s*\(\s*meilisearch\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "is defined as updateMeilisearch(meilisearch)" do
      expect(controller_source).to match(/updateMeilisearch\s*\(\s*meilisearch\s*\)\s*\{/)
    end

    it "patches games docs + size from flat `games_docs` / `games_size_bytes`" do
      expect(body).to match(/meilisearchGamesDocsTarget,\s*meilisearch\.games_docs/)
      expect(body).to match(/setFilesize\([^,]*meilisearchGamesSizeTarget,\s*meilisearch\.games_size_bytes\)/)
    end

    it "patches bundles docs + size from flat `bundles_docs` / `bundles_size_bytes`" do
      expect(body).to match(/meilisearchBundlesDocsTarget,\s*meilisearch\.bundles_docs/)
      expect(body).to match(/setFilesize\([^,]*meilisearchBundlesSizeTarget,\s*meilisearch\.bundles_size_bytes\)/)
    end
  end

  describe "updateAssets — per-row assets breakdown" do
    let(:body) do
      controller_source[/updateAssets\s*\(\s*assets\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
    end

    it "is defined as updateAssets(assets)" do
      expect(controller_source).to match(/updateAssets\s*\(\s*assets\s*\)\s*\{/)
    end

    it "patches cover-arts files + size from flat `cover_arts_*` keys" do
      expect(body).to match(/assetsCoverArtsFilesTarget,\s*assets\.cover_arts_files/)
      expect(body).to match(/setFilesize\([^,]*assetsCoverArtsSizeTarget,\s*assets\.cover_arts_size_bytes\)/)
    end

    it "patches composites files + size from flat `composites_*` keys" do
      expect(body).to match(/assetsCompositesFilesTarget,\s*assets\.composites_files/)
      expect(body).to match(/setFilesize\([^,]*assetsCompositesSizeTarget,\s*assets\.composites_size_bytes\)/)
    end
  end

  describe "DOM-patch helpers" do
    it "setNumber bails on a missing target or nullish value" do
      body = controller_source[/setNumber\s*\(\s*target,\s*value\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/if\s*\(\s*!target\s*\|\|\s*value\s*===\s*undefined\s*\|\|\s*value\s*===\s*null\s*\)\s*return/)
      expect(body).to include("target.textContent = value")
    end

    it "setDelimited bails on missing target/value and formats via Number().toLocaleString()" do
      body = controller_source[/setDelimited\s*\(\s*target,\s*value\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      expect(body).to match(/if\s*\(\s*!target\s*\|\|\s*value\s*===\s*undefined\s*\|\|\s*value\s*===\s*null\s*\)\s*return/)
      expect(body).to match(/Number\(value\)\.toLocaleString\(\)/)
    end

    it "setFilesize mirrors `human_filesize_int` (KB-minimum, em-dash on nil, `0 KB` on non-positive)" do
      body = controller_source[/setFilesize\s*\(\s*target,\s*bytes\s*\)\s*\{[\s\S]*?\n\s{2}\}/m].to_s
      # nil → em-dash so the cell stays consistent with the server render.
      expect(body).to match(/textContent\s*=\s*"—"/)
      # Non-positive / NaN → "0 KB" so we never paint a negative or NaN cell.
      expect(body).to match(/textContent\s*=\s*"0 KB"/)
      # KB / MB / GB / TB unit walk.
      expect(body).to match(/\[\s*"KB",\s*"MB",\s*"GB",\s*"TB"\s*\]/)
    end
  end
end
