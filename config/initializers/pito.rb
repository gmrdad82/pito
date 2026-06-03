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
end
