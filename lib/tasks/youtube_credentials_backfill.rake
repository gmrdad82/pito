# 2026-05-11 — one-shot, idempotent backfill task. Reads the
# `Rails.application.credentials.google_oauth` block (if present)
# and writes any unset YouTube columns on the AppSetting singleton.
# Never overwrites an existing AppSetting value — re-runs are safe.
#
# Credential → column mapping mirrors the lookup paths the old
# `youtube_credentials_status` helper used (so an install that was
# correctly populated under `:google_oauth` migrates over cleanly):
#
#   :google_oauth, :api_key       → youtube_api_key
#   :google_oauth, :client_id     → youtube_client_id
#   :google_oauth, :client_secret → youtube_client_secret
#   :google_oauth, :redirect_uri  → youtube_redirect_uri
#
# The credentials block is NOT removed from credentials.yml.enc;
# the task leaves it in place as a manual revert path (see
# AppSetting header comment).
namespace :pito do
  desc "Backfill the AppSetting singleton's YouTube columns from " \
       "Rails.application.credentials.google_oauth. Idempotent — never " \
       "overwrites a value already set on the singleton."
  task backfill_youtube_credentials: :environment do
    creds = Rails.application.credentials
    block = creds.google_oauth || {}

    if block.respond_to?(:to_h)
      block = block.to_h
    end

    mapping = {
      youtube_api_key:       block[:api_key],
      youtube_client_id:     block[:client_id],
      youtube_client_secret: block[:client_secret],
      youtube_redirect_uri:  block[:redirect_uri]
    }

    # Bootstrap a singleton if the table is empty. Matches the
    # `update_voyage` controller's bootstrap path so the task is
    # safe on a greenfield install (pre-`db:seed`).
    if AppSetting.none?
      AppSetting.set("pane_title_length", ENV.fetch("PANE_TITLE_LENGTH", 14).to_s)
    end

    setting = AppSetting.first
    attrs = {}

    mapping.each do |column, credential_value|
      current = setting.public_send(column)
      next if current.to_s.strip.present?
      next if credential_value.to_s.strip.empty?
      attrs[column] = credential_value.to_s.strip
    end

    if attrs.empty?
      puts "youtube credentials backfill: nothing to do " \
           "(all columns already populated, or credentials block empty)."
      next
    end

    setting.update!(attrs)

    written = attrs.keys.map(&:to_s).sort.join(", ")
    puts "youtube credentials backfill: wrote #{attrs.size} column(s): #{written}."
  end
end
