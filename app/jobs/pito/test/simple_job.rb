module Pito
  module Test
    class SimpleJob < ApplicationJob
      def perform(seconds = 5)
        sleep(seconds)
      end
    end
  end
end
