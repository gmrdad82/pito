# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Discord + Slack webhook URLs are delivery secrets.
  :webhook_url,
  # Mask sensitive slash-command values in `input` param logs:
  #   /authenticate <totp_code>  →  /authenticate ******
  #   /config google client_id=x client_secret=y  →  /config google client_id=*** client_secret=***
  lambda do |key, value|
    next unless key.to_s == "input" && value.is_a?(String)
    # /authenticate — mask everything after the verb
    if value.strip.match?(%r{\A/authenticate(\s|\z)}i)
      verb, rest = value.strip.split(/\s+/, 2)
      value.replace("#{verb} #{'*' * rest.to_s.length}") if rest.present?
    # /config — mask sensitive kwargs
    elsif value.strip.match?(%r{\A/config(\s|\z)}i)
      %w[client_id client_secret api_key].each do |sensitive_key|
        value.gsub!(/(?<=\b#{sensitive_key}=)\S+/, "***")
      end
    end
  end
]
