module Pito
  module Test
    class SimpleSidekiqJob
      include Sidekiq::Job

      def perform(seconds = 5)
        sleep(seconds)
      end
    end

    class FailingJob
      include Sidekiq::Job
      sidekiq_options retry: 2

      def perform
        raise "intentional failure for status bar testing"
      end
    end
  end
end
