# 2026-05-11 — YouTube OAuth + API credentials move from
# `Rails.application.credentials.google_oauth` into the AppSetting
# singleton so the operator can rotate them from the Settings UI
# without a deploy (mirrors the Voyage pattern landed by
# RevampVoyageAppSettingColumns, 2026-05-04).
#
# Four columns:
#
# 1. `youtube_api_key` (text, encrypted via Active Record Encryption).
#    The public/server API key used by `Youtube::PublicClient`. Text
#    (not string) because AR Encryption ciphertext can run past 255
#    chars depending on the encryptor configuration. Sensitive — never
#    echoed in the UI.
#
# 2. `youtube_client_id` (text, NOT encrypted). The OAuth client ID
#    is treated as semi-public by Google (it's visible to anyone who
#    completes an OAuth round-trip) and benefits from being readable
#    in the Settings pane so the operator can verify it at a glance.
#
# 3. `youtube_client_secret` (text, encrypted via Active Record
#    Encryption). Sensitive — never echoed in the UI.
#
# 4. `youtube_redirect_uri` (text, NOT encrypted). Public callback
#    URL (registered with the Google Cloud Console). Visible in the
#    UI; omniauth falls back to a hard-coded default when blank.
#
# All four are nullable; existing installs migrate via the
# `pito:backfill_youtube_credentials` rake task which reads
# `Rails.application.credentials.google_oauth` once and writes any
# unset AppSetting columns. The credentials block is kept on-disk as
# a manual revert path (see `app/models/app_setting.rb` header
# comment).
class AddYoutubeCredentialsToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :youtube_api_key, :text
    add_column :app_settings, :youtube_client_id, :text
    add_column :app_settings, :youtube_client_secret, :text
    add_column :app_settings, :youtube_redirect_uri, :text
  end
end
