# frozen_string_literal: true

module Pito
  module Jobs
    # Runs a recurring task on demand for `/jobs run <key>`, without waiting for
    # its cron time. Resolves the key → job class from config/recurring.yml (the
    # current environment's block) and enqueues it via ActiveJob, so it works
    # even in dev where the SolidQueue recurring scheduler is off and no
    # SolidQueue::RecurringTask rows exist.
    #
    # Returns the enqueued job class name (String) on success, or:
    #   :unknown             — no recurring task with that key in this env
    #   :command_unsupported — the task is a raw `command:` (not a job class)
    class RunRecurring
      def self.call(key:) = new(key).call

      def initialize(key)
        @key = key.to_s.strip
      end

      def call
        spec = recurring_config[@key.to_sym] || recurring_config[@key]
        return :unknown unless spec.is_a?(Hash)

        class_name = spec[:class] || spec["class"]
        return :command_unsupported if class_name.blank?

        class_name.constantize.perform_later
        class_name
      end

      private

      def recurring_config
        Rails.application.config_for(:recurring)
      rescue StandardError
        {}
      end
    end
  end
end
