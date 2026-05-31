# Phase 14 §1 — IGDB API v4 client.
#
# Top-level helpers + lazy credential lookup. The ENV vars
# may be absent in development / test boots; the lazy reader raises
# `Game::Igdb::Client::MissingCredentials` only on the first network call
# that needs it. Tests stub HTTP via WebMock before that point.
class Game
  module Igdb
    module_function

    def credentials
      client_id     = ENV["PITO_IGDB_CLIENT_ID"].presence
      client_secret = ENV["PITO_IGDB_CLIENT_SECRET"].presence
      return nil if client_id.blank? && client_secret.blank?
      { client_id: client_id, client_secret: client_secret }
    end

    def credentials!
      creds = credentials
      raise Game::Igdb::Client::MissingCredentials, "PITO_IGDB_CLIENT_ID / PITO_IGDB_CLIENT_SECRET is missing" if creds.blank? || creds[:client_id].blank? || creds[:client_secret].blank?

      creds
    end
  end
end
