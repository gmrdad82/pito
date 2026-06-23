# frozen_string_literal: true

module Pito
  module Jobs
    # Snapshot of the SolidQueue state for `/jobs status`. Reads the SolidQueue
    # models directly (the queue lives in the same Postgres DB). Pure read — no
    # side effects.
    #
    # Returns a Hash the handler formats into a system table:
    #   ready / scheduled / claimed / failed — execution-state counts
    #   processes        — live SolidQueue supervisor/worker processes (liveness)
    #   paused_queues    — queue names with an active Pause
    #   recurring        — [{ key:, schedule:, class_name: }] from config/recurring.yml
    #   recent_failed    — up to 5 most-recent failures [{ id:, job_class:, error: }]
    class Status
      RECENT_FAILED_LIMIT = 5

      def self.call = new.call

      def call
        {
          ready:         SolidQueue::ReadyExecution.count,
          scheduled:     SolidQueue::ScheduledExecution.count,
          claimed:       SolidQueue::ClaimedExecution.count,
          failed:        SolidQueue::FailedExecution.count,
          processes:     SolidQueue::Process.count,
          paused_queues: SolidQueue::Pause.pluck(:queue_name),
          recurring:     recurring_tasks,
          recent_failed: recent_failed
        }
      end

      private

      # Recurring schedule for the CURRENT environment, read from
      # config/recurring.yml (works whether or not the supervisor is running, so
      # it's accurate in dev where the scheduler is off).
      def recurring_tasks
        Rails.application.config_for(:recurring).filter_map do |key, spec|
          next unless spec.is_a?(Hash)

          {
            key:        key.to_s,
            schedule:   spec[:schedule] || spec["schedule"],
            class_name: spec[:class] || spec["class"] || spec[:command] || spec["command"]
          }
        end
      rescue StandardError
        []
      end

      def recent_failed
        SolidQueue::FailedExecution
          .includes(:job)
          .order(created_at: :desc)
          .limit(RECENT_FAILED_LIMIT)
          .map do |fe|
            {
              id:        fe.job_id,
              job_class: fe.job&.class_name,
              error:     fe.respond_to?(:message) ? fe.message : nil
            }
          end
      end
    end
  end
end
