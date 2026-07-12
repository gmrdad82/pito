# frozen_string_literal: true

module Pito
  module Jobs
    # Re-enqueues failed jobs for `/jobs requeue <job-id|all>`.
    #
    # `SolidQueue::FailedExecution#retry` resets the job's execution counters,
    # re-prepares it for execution, and destroys the failed record. `target` is
    # the SolidQueue::Job id (what `/jobs status` lists) or the string "all".
    #
    # Returns the number of jobs requeued, or :not_found when a given id has no
    # failed execution.
    class RequeueFailed
      def self.call(target:) = new(target).call

      def initialize(target)
        @target = target.to_s.strip
      end

      def call
        return requeue_all if @target.casecmp?("all")

        fe = SolidQueue::FailedExecution.find_by(job_id: @target)
        return :not_found if fe.nil?

        fe.retry
        1
      end

      private

      def requeue_all
        count = 0
        SolidQueue::FailedExecution.includes(:job).find_each do |fe|
          fe.retry
          count += 1
        end
        count
      end
    end
  end
end
