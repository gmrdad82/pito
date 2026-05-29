module Pito
  module Test
    class SimpleSidekiqJob < ApplicationJob
      def perform(seconds = 5)
        sleep(seconds)
      end
    end

    class FailingJob < ApplicationJob
      def perform
        raise "intentional failure for status bar testing"
      end
    end
  end
end
