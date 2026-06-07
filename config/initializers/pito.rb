# frozen_string_literal: true

# Register all slash command handlers at boot.
# This runs on every request in development (code reload) and once in production.
Rails.application.config.to_prepare do
  # Grammar registry must go first: it composes vocabularies + central specs +
  # handler-declared grammar. The slash/chat/hashtag runtime registries do not
  # depend on grammar, so the order is safe in both directions.
  Pito::Grammar::Registry.register_all!

  Pito::Slash::Registry.register_all!
  Pito::Chat::Registry.register_all!
  Pito::Hashtag::Registry.register_all!

  # Follow-up handlers auto-register via an `inherited` hook when loaded; force
  # them to load so the registry is populated for callers that may run before any
  # follow-up reply (e.g. the suggestions engine resolving #handle → actions).
  Pito::FollowUp::Registry.register_all!
end
