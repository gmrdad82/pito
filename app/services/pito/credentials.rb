# frozen_string_literal: true

# AppSetting-primary credential resolver with a Rails.cache layer so DB reads
# don't happen on every API call.
#
# Credential sources:
#   1. AppSetting (set via the `/config <provider>` slash commands)
#   2. Test-mode placeholder for Google OAuth (keeps spec suite functional
#      without a real AppSetting row)
#
# ENV vars are NOT a fallback in production. All credentials live in AppSetting.
#
# Cache TTL is 1 hour. AppSetting.after_save calls `Pito::Credentials.invalidate!`
# so a `/config` write is reflected on the next cache miss.
#
# Note: the omniauth middleware bakes credentials in at Rails boot — a Google
# OAuth credential change requires a Puma restart to take effect for new OAuth
# flows. All other credential reads happen per-call and pick up new values
# immediately after the cache expires or is invalidated.
module Pito
  module Credentials
    CACHE_NAMESPACE = "pito:credentials"
    CACHE_TTL       = 1.hour

    class << self
      def google_oauth_client_id
        fetch(:google_oauth_client_id) do
          AppSetting.google_oauth_client_id.presence ||
            (Rails.env.test? ? "test-google-oauth-client-id-not-a-secret" : nil)
        end
      end

      def google_oauth_client_secret
        fetch(:google_oauth_client_secret) do
          AppSetting.google_oauth_client_secret.presence ||
            (Rails.env.test? ? "test-google-oauth-client-secret-not-a-secret" : nil)
        end
      end

      def google_oauth_redirect_uri
        fetch(:google_oauth_redirect_uri) { AppSetting.google_oauth_redirect_uri.presence }
      end

      def google_api_key
        fetch(:google_api_key) { AppSetting.google_api_key.presence }
      end


      def igdb_client_id
        fetch(:igdb_client_id) { AppSetting.igdb_client_id.presence }
      end

      def igdb_client_secret
        fetch(:igdb_client_secret) { AppSetting.igdb_client_secret.presence }
      end

      def igdb_configured?
        igdb_client_id.present? && igdb_client_secret.present?
      end

      def slack_webhook_url
        fetch(:slack_webhook_url) { AppSetting.slack_webhook_url.presence }
      end

      def discord_webhook_url
        fetch(:discord_webhook_url) { AppSetting.discord_webhook_url.presence }
      end

      def google_oauth_configured?
        google_oauth_client_id.present? && google_oauth_client_secret.present?
      end

      def invalidate!
        %i[
          google_oauth_client_id
          google_oauth_client_secret
          google_oauth_redirect_uri
          google_api_key
          igdb_client_id
          igdb_client_secret
          slack_webhook_url
          discord_webhook_url
        ].each do |key|
          Rails.cache.delete(cache_key(key))
        end
      end

      private

      def fetch(key, &block)
        Rails.cache.fetch(cache_key(key), expires_in: CACHE_TTL, &block)
      end

      def cache_key(key)
        "#{CACHE_NAMESPACE}:#{key}"
      end
    end
  end
end
