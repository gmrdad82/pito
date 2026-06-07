# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/disconnect @handle|<id>`.
      #
      # Resolves the target channel via two strategies (in order):
      # - `@handle` (with or without `@` prefix) — `LIKE %fragment%` match on
      #   `Channel#handle`; **case-sensitive** (`@Foo` ≠ `@foo`).
      # - Bare integer — exact `Channel.find_by(id:)`.
      #
      # Returns `Result::Ok` with:
      # - `kind: "confirmation"` and `expand_detail` (channel stats + video breakdown)
      #   when the channel is found.
      # - `kind: "error"` (not `Result::Error`) when the target is missing or
      #   the channel is not found, so the error appears inline in the scrollback.
      #
      # The confirmation payload is follow-up-able: stamped with
      # `reply_handle` + `reply_target:"confirmation"` so the follow-up engine
      # routes `#<handle> confirm|cancel` to
      # `Pito::FollowUp::Handlers::Confirmation`.
      class Disconnect < Pito::Slash::Handler
        self.verb = :disconnect
        self.description_key = "pito.slash.disconnect.descriptions.disconnect"

        grammar do
          enum :channel, source: :channels, optional: true
          auth :authenticated_only
          description_key "pito.grammar.slash.disconnect"
        end

        def call
          target = parse_target
          return missing_target_error if target.blank?

          channel = resolve_channel(target)
          return not_found_error(target) if channel.nil?

          confirmation_event(channel)
        end

        private

        def parse_target
          parts = invocation.raw.strip.split(/\s+/, 2)
          parts.length == 2 ? parts.last.strip.presence : nil
        end

        # Case-sensitive: @Johndoe and @johnDoe are distinct channels.
        def resolve_channel(target)
          if target.start_with?("@")
            fragment = target.delete_prefix("@")
            ::Channel.where("handle LIKE ?", "%#{fragment}%").first
          elsif target.match?(/\A\d+\z/)
            ::Channel.find_by(id: target.to_i)
          else
            ::Channel.where("handle LIKE ?", "%#{target}%").first
          end
        end

        def missing_target_error
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "error",
              payload: { text: Pito::Copy.render("pito.copy.disconnect.missing_target") }
            }
          ])
        end

        def not_found_error(target)
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "error",
              payload: { text: Pito::Copy.render("pito.copy.disconnect.not_found", { target: target }) }
            }
          ])
        end

        def confirmation_event(channel)
          payload = Pito::MessageBuilder::Channel::DisconnectConfirmation.call(channel, conversation:)

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "confirmation",
              payload: payload
            }
          ])
        end
      end
    end
  end
end
