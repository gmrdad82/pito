module Pito
  module Test
    class SimpleSidekiqJob
      include Sidekiq::Job

      def perform
        # Simulate work for status bar testing
        sleep(rand(2..5))
      end
    end
  end
end
