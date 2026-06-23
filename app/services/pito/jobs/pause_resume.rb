# frozen_string_literal: true

module Pito
  module Jobs
    # Pauses or resumes job processing for `/jobs pause` / `/jobs resume`.
    #
    # SolidQueue pausing is per-queue (a `SolidQueue::Pause` row per queue_name);
    # there is no global switch. `SolidQueue::Queue.all` derives the live queues
    # from existing jobs, so:
    #   :pause  → pause every known queue; returns the paused queue names.
    #   :resume → clear ALL pauses; returns the count cleared.
    #
    # When there are no known queues yet (no jobs have ever been enqueued),
    # :pause returns an empty array — there is nothing to pause.
    class PauseResume
      def self.call(action:) = new(action).call

      def initialize(action)
        @action = action.to_sym
      end

      def call
        case @action
        when :pause  then pause_all
        when :resume then resume_all
        else :unknown_action
        end
      end

      private

      def pause_all
        queues = SolidQueue::Queue.all
        queues.each(&:pause)
        queues.map(&:name)
      end

      def resume_all
        SolidQueue::Pause.delete_all
      end
    end
  end
end
