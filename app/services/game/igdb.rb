# IGDB API v4 top-level helpers + lazy credential lookup via Pito::Credentials
# (AppSetting-backed, cached). Set via: /config igdb client_id=… client_secret=…
#
# `credentials!` raises MissingCredentials on the first network call that needs
# credentials — tests stub HTTP via WebMock before that point.
class Game
  module Igdb
    module_function

    def credentials
      client_id     = Pito::Credentials.igdb_client_id
      client_secret = Pito::Credentials.igdb_client_secret
      return nil if client_id.blank? && client_secret.blank?

      { client_id: client_id, client_secret: client_secret }
    end

    def credentials!
      creds = credentials
      raise Game::Igdb::Client::MissingCredentials, "IGDB credentials not configured — run: /config igdb client_id=… client_secret=…" if creds.blank? || creds[:client_id].blank? || creds[:client_secret].blank?

      creds
    end
  end
end
