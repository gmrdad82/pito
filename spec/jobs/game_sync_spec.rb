require "rails_helper"

# 2026-05-11 polish (Games list-mode bulk actions, Fix 5) —
# per-game Sidekiq sync job dispatched by BulkSyncJob via the
# `<TargetType>Sync` convention. Adds a Postgres advisory lock keyed
# on `(:game, game_id)` and graceful StandardError handling so a
# single failure does not crash the surrounding batch.
RSpec.describe GameSync, type: :job do
  describe "#perform" do
    let!(:game) { create(:game, igdb_id: 7346) }

    it "is a no-op when game_id is nil" do
      expect { described_class.new.perform(nil) }.not_to raise_error
    end

    it "delegates to GameIgdbSync.new.perform(game_id)" do
      delegate = instance_double(GameIgdbSync, perform: nil)
      allow(GameIgdbSync).to receive(:new).and_return(delegate)

      described_class.new.perform(game.id)
      expect(delegate).to have_received(:perform).with(game.id)
    end

    it "acquires a Postgres advisory lock keyed on game_id" do
      # Stub the inner IGDB sync so this test doesn't reach for a
      # real Twitch token. The advisory-lock SQL we want to observe
      # fires before `GameIgdbSync#perform`, so the stub doesn't
      # affect the lock path.
      allow_any_instance_of(GameIgdbSync).to receive(:perform).and_return(nil)

      sql_seen = []
      original_execute = ActiveRecord::Base.connection.method(:execute)
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql, *rest|
        sql_seen << sql
        original_execute.call(sql, *rest)
      end

      described_class.new.perform(game.id)
      expect(sql_seen.any? { |s| s.is_a?(String) && s.include?("pg_try_advisory_xact_lock") }).to be(true)
      expect(sql_seen.any? { |s| s.is_a?(String) && s.include?(game.id.to_s) }).to be(true)
    end

    it "swallows StandardError raised by GameIgdbSync (graceful failure)" do
      allow_any_instance_of(GameIgdbSync).to receive(:perform).and_raise(StandardError, "boom")

      expect { described_class.new.perform(game.id) }.not_to raise_error
    end

    it "writes the error message to the row's last_sync_error column on failure" do
      allow_any_instance_of(GameIgdbSync).to receive(:perform).and_raise(StandardError, "igdb melted")

      described_class.new.perform(game.id)
      expect(game.reload.last_sync_error).to include("igdb melted")
    end

    it "no-ops when the advisory lock is unavailable (held by another worker)" do
      # Force pg_try_advisory_xact_lock to return false by replacing
      # the SQL with a literal `SELECT FALSE AS acquired`. The job
      # MUST NOT invoke its inner sync work.
      allow(ActiveRecord::Base.connection).to receive(:execute)
        .with(/pg_try_advisory_xact_lock/)
        .and_return([ { "acquired" => false } ])

      sync_double = instance_double(GameIgdbSync, perform: :ran)
      allow(GameIgdbSync).to receive(:new).and_return(sync_double)

      described_class.new.perform(game.id)
      expect(sync_double).not_to have_received(:perform)
    end
  end
end
