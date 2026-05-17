# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # 2026-05-17 webhook URL hardening. Discord + Slack webhook URLs are
  # delivery secrets — anyone with the URL can post to the channel. The
  # form params (`discord_webhook_url`, `slack_webhook_url`) plus the
  # model column (`webhook_url`) all match this filter via partial-name
  # match, so any request-log line touching either surface scrubs the
  # value as `[FILTERED]` rather than spilling the live URL.
  :webhook_url
]
