require "rails_helper"

# 2026-05-11 polish (Games list-mode bulk actions, Fix 5) —
# per-game Sidekiq deletion job dispatched by BulkDeleteJob when the
# target_type is "Game". Adds a Postgres advisory lock keyed on
# `(:game, game_id)`, graceful StandardError handling, and a
# last-one-out finalization call back into BulkDeleteJob.
RSpec.describe GameDeletion, type: :job do
  let!(:game) { create(:game) }
  let!(:operation) do
    create(:bulk_operation, kind: :bulk_delete, status: :running)
  end
  let!(:op_item) do
    operation.bulk_operation_items.create!(
      target: game, target_type: "Game", target_id: game.id, status: :pending
    )
  end

  describe "#perform — happy path" do
    it "destroys the target game" do
      expect { described_class.new.perform(game.id, op_item.id) }.to change(Game, :count).by(-1)
    end

    it "marks its BulkOperationItem succeeded" do
      described_class.new.perform(game.id, op_item.id)
      expect(op_item.reload.status).to eq("succeeded")
    end

    it "finalizes the parent operation when this is the last terminal item" do
      described_class.new.perform(game.id, op_item.id)
      operation.reload
      expect(operation.status).to eq("completed")
      expect(operation.completed_at).to be_present
    end
  end

  describe "#perform — graceful failure" do
    it "swallows StandardError raised by destroy" do
      allow_any_instance_of(Game).to receive(:destroy).and_raise(StandardError, "boom")

      expect { described_class.new.perform(game.id, op_item.id) }.not_to raise_error
    end

    it "marks the BulkOperationItem failed with the exception class + message" do
      allow_any_instance_of(Game).to receive(:destroy).and_raise(StandardError, "boom")

      described_class.new.perform(game.id, op_item.id)
      expect(op_item.reload.status).to eq("failed")
      expect(op_item.error_message).to include("boom")
    end

    it "marks the operation failed when at least one item failed" do
      allow_any_instance_of(Game).to receive(:destroy).and_raise(StandardError, "boom")

      described_class.new.perform(game.id, op_item.id)
      operation.reload
      expect(operation.status).to eq("failed")
    end

    it "marks the item failed with not_found when the game does not exist" do
      described_class.new.perform(999_999, op_item.id)
      expect(op_item.reload.status).to eq("failed")
      expect(op_item.error_message).to eq("not_found")
    end
  end

  describe "#perform — advisory lock" do
    it "acquires a Postgres advisory lock keyed on game_id" do
      sql_seen = []
      original_execute = ActiveRecord::Base.connection.method(:execute)
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql, *rest|
        sql_seen << sql
        original_execute.call(sql, *rest)
      end

      described_class.new.perform(game.id, op_item.id)
      expect(sql_seen.any? { |s| s.include?("pg_try_advisory_xact_lock") }).to be(true)
      expect(sql_seen.any? { |s| s.include?(game.id.to_s) }).to be(true)
    end

    it "marks the item failed (advisory_lock_busy) when another worker holds the lock" do
      # Pretend the advisory lock acquisition returns false.
      original_execute = ActiveRecord::Base.connection.method(:execute)
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql, *rest|
        if sql.is_a?(String) && sql.include?("pg_try_advisory_xact_lock")
          [ { "acquired" => false } ]
        else
          original_execute.call(sql, *rest)
        end
      end

      expect { described_class.new.perform(game.id, op_item.id) }.not_to change(Game, :count)
      expect(op_item.reload.status).to eq("failed")
      expect(op_item.error_message).to eq("advisory_lock_busy")
    end
  end

  describe "#perform — multi-row batch" do
    let!(:game2) { create(:game) }
    let!(:op_item2) do
      operation.bulk_operation_items.create!(
        target: game2, target_type: "Game", target_id: game2.id, status: :pending
      )
    end

    it "does NOT finalize the operation while sibling items are still pending" do
      described_class.new.perform(game.id, op_item.id)

      operation.reload
      # Sibling item op_item2 is still pending → operation stays
      # `running` (not terminal yet).
      expect(operation.status).to eq("running")
      expect(operation.completed_at).to be_nil
    end

    it "finalizes the operation once every sibling is terminal" do
      described_class.new.perform(game.id, op_item.id)
      described_class.new.perform(game2.id, op_item2.id)

      operation.reload
      expect(operation.status).to eq("completed")
    end

    it "finalizes as `failed` when any sibling is failed" do
      allow_any_instance_of(Game).to receive(:destroy).and_raise(StandardError, "boom")
      described_class.new.perform(game.id, op_item.id)

      # Second item finishes cleanly via the unstubbed path.
      allow_any_instance_of(Game).to receive(:destroy).and_call_original
      described_class.new.perform(game2.id, op_item2.id)

      operation.reload
      expect(operation.status).to eq("failed")
    end
  end

  describe "#perform — bulk_operation_item_id omitted" do
    it "is a no-op when game_id is nil" do
      expect { described_class.new.perform(nil) }.not_to raise_error
    end

    it "destroys the game without raising even if no op_item is supplied" do
      expect { described_class.new.perform(game.id) }.to change(Game, :count).by(-1)
    end
  end
end
