module Pito
  module Test
    class FailingJob < ApplicationJob
      def perform
        raise "intentional failure for status bar testing"
      end
    end
  end
end
