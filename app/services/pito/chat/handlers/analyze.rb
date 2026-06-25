# frozen_string_literal: true

# Handler for the `analyze` chat verb (aliases: `analytics`, `stats`).
#
# Entry point for interval-aware YouTube analytics scoped to a channel, vid,
# or game. The shift+tab channel scope (`self.channel`) and shift+space period
# (`self.period`) will feed the fan-out logic landing in later 0.8.0 tasks.
#
# STUB — scope resolution + fan-out land in later 0.8.0 tasks (T1.3+).
module Pito
  module Chat
    module Handlers
      class Analyze < Pito::Chat::Handler
        self.verb = :analyze
        self.description_key = "pito.chat.analyze.descriptions.analyze"

        def call
          # STUB — scope resolution + fan-out land in later 0.8.0 tasks (T1.3+).
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.analyze.stub") }
          ])
        end
      end
    end
  end
end
