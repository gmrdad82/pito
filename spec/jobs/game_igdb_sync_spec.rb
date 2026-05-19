require "rails_helper"

RSpec.describe GameIgdbSync, type: :job do
  describe "#perform" do
    let!(:game) { create(:game, igdb_id: 7346) }

    it "invokes Igdb::SyncGame for the given game id" do
      syncer = instance_double(Igdb::SyncGame, call: game)
      allow(Igdb::SyncGame).to receive(:new).and_return(syncer)

      described_class.new.perform(game.id)
      expect(syncer).to have_received(:call).with(game)
    end

    it "is a no-op when the game does not exist" do
      expect { described_class.new.perform(0) }.not_to raise_error
    end

    it "raises (so Sidekiq retries) on RateLimited" do
      allow_any_instance_of(Igdb::SyncGame).to receive(:call)
        .and_raise(Igdb::Client::RateLimited.new(retry_after: 1))
      allow_any_instance_of(described_class).to receive(:sleep) # don't actually sleep
      expect { described_class.new.perform(game.id) }.to raise_error(Igdb::Client::RateLimited)
    end

    it "raises (so Sidekiq retries) on ServerError" do
      allow_any_instance_of(Igdb::SyncGame).to receive(:call)
        .and_raise(Igdb::Client::ServerError.new("500"))
      expect { described_class.new.perform(game.id) }.to raise_error(Igdb::Client::ServerError)
    end

    it "swallows ValidationError (no Sidekiq retry)" do
      allow_any_instance_of(Igdb::SyncGame).to receive(:call)
        .and_raise(Igdb::Client::ValidationError.new("not found"))
      expect { described_class.new.perform(game.id) }.not_to raise_error
    end

    # Phase 14 §1 polish (2026-05-10) — `games.resyncing` mutex flag.
    describe "resyncing mutex" do
      it "flips resyncing true while SyncGame is running" do
        captured = nil
        allow(Igdb::SyncGame).to receive(:new).and_wrap_original do |orig, *args|
          syncer = orig.call(*args)
          allow(syncer).to receive(:call) do |g|
            captured = Game.find(g.id).resyncing?
            g
          end
          syncer
        end

        described_class.new.perform(game.id)
        expect(captured).to eq(true)
      end

      it "clears resyncing back to false after success" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call) { |_, g| g }
        described_class.new.perform(game.id)
        expect(game.reload.resyncing?).to eq(false)
      end

      it "clears resyncing back to false after a non-retryable error" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call)
          .and_raise(Igdb::Client::ValidationError.new("not found"))
        described_class.new.perform(game.id)
        expect(game.reload.resyncing?).to eq(false)
      end

      it "clears resyncing back to false even when a retryable error re-raises" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call)
          .and_raise(Igdb::Client::ServerError.new("500"))
        expect { described_class.new.perform(game.id) }.to raise_error(Igdb::Client::ServerError)
        expect(game.reload.resyncing?).to eq(false)
      end

      # 2026-05-18 — controller-owned mutex flip. `GamesController#resync`
      # now stamps `resyncing = true` SYNCHRONOUSLY before enqueuing and
      # short-circuits duplicate clicks with the "already resyncing."
      # flash. The legacy `return if game.resyncing?` early-bail inside
      # the job was retired so console / rake callers that bypass the
      # controller still get a full sync. This test pins the new shape:
      # the job runs SyncGame even when the flag was already true on
      # entry, and clears the flag in `ensure` as usual.
      it "runs SyncGame even when resyncing is already true on entry" do
        game.update_column(:resyncing, true)
        syncer = instance_double(Igdb::SyncGame, call: game)
        allow(Igdb::SyncGame).to receive(:new).and_return(syncer)

        described_class.new.perform(game.id)

        expect(syncer).to have_received(:call).with(game)
        expect(game.reload.resyncing?).to eq(false)
      end
    end

    # Phase 27 v2 spec 03 / Phase 27 follow-up (2026-05-17) — bundle
    # cover-art fan-out on the success path. The job calls
    # `Bundles::CompositeRebuildQueue#enqueue_for_game_resync(game)`
    # AFTER `Igdb::SyncGame#call` returns and BEFORE the `resyncing`
    # flag flips back to false in `ensure`.
    describe "bundle cover-art fan-out" do
      let(:queue) { instance_double(Bundles::CompositeRebuildQueue, enqueue_for_game_resync: []) }

      before do
        allow(Bundles::CompositeRebuildQueue).to receive(:new).and_return(queue)
        allow_any_instance_of(Igdb::SyncGame).to receive(:call) { |_, g| g }
      end

      it "calls enqueue_for_game_resync with the reloaded game on success" do
        described_class.new.perform(game.id)
        expect(queue).to have_received(:enqueue_for_game_resync) do |g|
          expect(g).to be_a(Game)
          expect(g.id).to eq(game.id)
        end
      end

      it "does NOT call enqueue_for_game_resync on ValidationError" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call)
          .and_raise(Igdb::Client::ValidationError.new("not found"))

        described_class.new.perform(game.id)
        expect(queue).not_to have_received(:enqueue_for_game_resync)
      end

      it "does NOT call enqueue_for_game_resync on RateLimited (retryable)" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call)
          .and_raise(Igdb::Client::RateLimited.new(retry_after: 1))
        allow_any_instance_of(described_class).to receive(:sleep)

        expect { described_class.new.perform(game.id) }.to raise_error(Igdb::Client::RateLimited)
        expect(queue).not_to have_received(:enqueue_for_game_resync)
      end

      it "does NOT call enqueue_for_game_resync on ServerError (retryable)" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call)
          .and_raise(Igdb::Client::ServerError.new("500"))

        expect { described_class.new.perform(game.id) }.to raise_error(Igdb::Client::ServerError)
        expect(queue).not_to have_received(:enqueue_for_game_resync)
      end

      it "still clears the resyncing flag if the fan-out raises" do
        allow(queue).to receive(:enqueue_for_game_resync).and_raise(StandardError.new("redis hiccup"))
        described_class.new.perform(game.id)
        expect(game.reload.resyncing?).to eq(false)
      end

      it "does not re-raise when the fan-out raises (no Sidekiq retry on a successful sync)" do
        allow(queue).to receive(:enqueue_for_game_resync).and_raise(StandardError.new("redis hiccup"))
        expect { described_class.new.perform(game.id) }.not_to raise_error
      end
    end

    # Wave A (2026-05-18) — the dedicated sync pane / banner and the
    # `_sync_status` partial were REMOVED from `/games/:id`. UI feedback
    # while a resync is in flight is now handled entirely on the show
    # page by the page-level `auto-refresh` Stimulus controller (polls
    # every ~5 s while `@game.resyncing?` is true). The job therefore
    # no longer broadcasts a Turbo-Stream replace — the polling refresh
    # picks up the cleared flag and re-renders the breadcrumb idle state.
    describe "live broadcast (removed in Wave A)" do
      before do
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        allow_any_instance_of(Igdb::SyncGame).to receive(:call) { |_, g| g }
      end

      it "does NOT broadcast on success (auto-refresh polling replaces this surface)" do
        described_class.new.perform(game.id)
        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
      end

      it "does NOT broadcast on ValidationError" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call)
          .and_raise(Igdb::Client::ValidationError.new("not found"))

        described_class.new.perform(game.id)
        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
      end

      it "does NOT broadcast on retryable failure" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call)
          .and_raise(Igdb::Client::ServerError.new("500"))

        expect { described_class.new.perform(game.id) }.to raise_error(Igdb::Client::ServerError)
        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
      end
    end

    # Phase 27 v2 spec 03 — flaw guard. Ownership-sourced columns must
    # be untouched by the sync. The actual partition is enforced by
    # `Igdb::SyncGame#call` (it only writes IGDB columns); this test
    # is paranoid coverage at the job's entry surface.
    # 2026-05-17 — `Collection` model + `games.collection_id` column
    # were dropped along with the `belongs_to :collection`. The Bundle
    # + bundle_members many-to-many replaces the single-pointer pattern.
    # The partition spec still verifies the ownership-sourced columns
    # plus the platform-ownership join survive a no-op SyncGame call;
    # bundle membership is exercised in dedicated specs and not needed
    # here (no field on `games` to mirror it).
    describe "ownership-sourced field partition" do
      let!(:platform) { create(:platform, name: "PS5", igdb_id: 167) }
      let!(:loaded_game) do
        g = create(:game,
                   :synced,
                   played_at: Time.zone.local(2024, 1, 15),
                   notes: "loved it",
                   hours_of_footage_manual: 12,
                   manual_date_override: true)
        g.game_platform_ownerships.create!(platform: platform)
        g
      end

      it "does not change ownership-sourced columns when SyncGame is a no-op" do
        # Stub SyncGame as a no-op so the partition-by-omission shape
        # is visible: the only mutation the job does on its own is
        # the resyncing flag, which is whitelisted.
        allow_any_instance_of(Igdb::SyncGame).to receive(:call) { |_, g| g }

        ownership_keys = %w[
          played_at notes hours_of_footage_manual hours_of_footage_cached
          manual_date_override version_parent_id version_title
        ]
        before_hash = loaded_game.reload.attributes.slice(*ownership_keys)
        ownership_ids = loaded_game.game_platform_ownerships.pluck(:platform_id).sort

        described_class.new.perform(loaded_game.id)
        loaded_game.reload

        after_hash = loaded_game.attributes.slice(*ownership_keys)
        after_ids = loaded_game.game_platform_ownerships.pluck(:platform_id).sort

        expect(after_hash).to eq(before_hash)
        expect(after_ids).to eq(ownership_ids)
      end
    end

    # Phase 27 v2 spec 03 — edge: deleted game id mid-flight is a no-op.
    describe "edge cases" do
      it "is a no-op when the game id refers to a deleted row" do
        deleted_id = game.id
        game.destroy!
        expect { described_class.new.perform(deleted_id) }.not_to raise_error
      end
    end
  end

  describe "Sidekiq options" do
    it "is enqueued on the default queue" do
      described_class.clear
      described_class.perform_async(123)
      expect(described_class.jobs.last["queue"]).to eq("default")
    end

    it "retries up to 5 times" do
      expect(described_class.sidekiq_options["retry"]).to eq(5)
    end

    # Phase 27 v2 spec 03 — Sidekiq uniqueness intent. Pito runs on
    # Sidekiq OSS without `sidekiq-unique-jobs`, so these options are
    # a NO-OP intent declaration — the `games.resyncing` Boolean is
    # the real safety net. The keys are in place so the gem starts
    # enforcing them if it is ever added.
    it "declares the sidekiq lock as :until_executed (intent)" do
      expect(described_class.sidekiq_options["lock"]).to eq(:until_executed)
    end

    it "declares the sidekiq on_conflict policy as :log (intent)" do
      expect(described_class.sidekiq_options["on_conflict"]).to eq(:log)
    end
  end
end
