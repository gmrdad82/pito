# Phase 14 §1 — IGDB API v4 client.
#
# Top-level helpers + lazy credential lookup. The credential block
# may be absent in development / test boots; the lazy reader raises
# `Igdb::Client::MissingCredentials` only on the first network call
# that needs it. Tests stub HTTP via WebMock before that point.
module Igdb
  module_function

  def credentials
    Rails.application.credentials.igdb
  end

  def credentials!
    creds = credentials
    raise Igdb::Client::MissingCredentials, "Rails.application.credentials.igdb is missing client_id/client_secret" if creds.blank? || creds[:client_id].blank? || creds[:client_secret].blank?

    creds
  end
end
