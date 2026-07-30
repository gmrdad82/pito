# frozen_string_literal: true

# Owner order: purge the unauthenticated Google (YouTube Data v3) API-key
# concept — chat only ever talks to the owner's own OAuth-connected
# channels, so the public-key path had no reason to exist. Delete the
# now-orphaned key/value row from app_settings (never a column — see
# AppSetting's plain key/value rows).
class DeleteGoogleApiKeyAppSetting < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM app_settings WHERE key = 'google_api_key'"
  end

  def down
    # No-op: the Google API key concept was removed outright; nothing to restore.
  end
end
