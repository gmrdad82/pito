# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # A suggested pito command inside an :ai message — the AI never executes
      # anything; it hands the owner a command to run. The command renders as a
      # `>`-prefixed line with the shared copy-to-clipboard widget; the optional
      # note explains why in dim text.
      class SuggestionBlockComponent < ViewComponent::Base
        def initialize(command:, note: nil)
          @command = command.to_s
          @note    = note.presence
        end

        attr_reader :command, :note
      end
    end
  end
end
