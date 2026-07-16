# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Discord + Slack webhook URLs are delivery secrets.
  :webhook_url,
  # Mask sensitive slash-command values in `input` param logs:
  #   /login <totp_code>  →  /login ******
  #   /config google client_id=x client_secret=y  →  /config google client_id=*** client_secret=***
  lambda do |key, value|
    next unless key.to_s == "input" && value.is_a?(String)
    # /login — mask everything after the verb
    if value.strip.match?(%r{\A/login(\s|\z)}i)
      verb, rest = value.strip.split(/\s+/, 2)
      value.replace("#{verb} #{'*' * rest.to_s.length}") if rest.present?
    # /config google|igdb|webhook — mask ALL credential kwarg values
    # (client_id/secret/api_key, google redirect_uri, webhook slack/discord URLs).
    # Mirrors Pito::InputMasking.mask_config_credentials, kept inline so this
    # initializer carries no app-code (autoload) dependency.
    elsif value.strip.match?(%r{\A/config\s+(?:google|igdb|webhook)(?:\s|\z)}i)
      value.gsub!(/(?<==)\S+/, "***")
    end
  end
]
