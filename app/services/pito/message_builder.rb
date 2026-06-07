# frozen_string_literal: true

module Pito
  # Namespace for all message-payload builders.
  #
  # Every chat / slash / hashtag / follow-up message is produced by a
  # Pito::MessageBuilder::* builder — one per message type — that returns a
  # string-keyed payload Hash. Handlers and jobs ONLY: resolve the domain
  # object, call the builder, and emit an event with the correct chrome kind.
  #
  # == Shape contract
  #
  # Each builder is a module with +module_function+; public +.call(...) -> Hash+
  # returning a string-keyed payload. Builders set ONLY content + flags:
  #   body        — HTML string (requires html: true to be rendered as HTML)
  #   html        — Boolean (true = body is HTML)
  #   table_rows  — Array of row hashes
  #   sections    — Array of section hashes
  #   text        — Plain text string
  # Plus follow-up stamping when applicable (builders call
  # Pito::FollowUp.make_followupable! directly). Builders NEVER choose the
  # kind/border — the caller does.
  #
  # == Helpers
  #
  # Pito::MessageBuilder::Helpers provides:
  #   render_component(component)           — renders a ViewComponent to HTML
  #   html_payload(body:, **extra)          — returns { "body" => body, "html" => true, ... }
  module MessageBuilder
  end
end
