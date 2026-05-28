# frozen_string_literal: true

# Register all slash command handlers at boot.
# This runs on every request in development (code reload) and once in production.
Rails.application.config.to_prepare do
  Pito::Slash::Registry.register_all!
end
