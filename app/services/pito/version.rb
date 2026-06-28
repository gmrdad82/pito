# frozen_string_literal: true

require "uri"

module Pito
  # The running build's identity, shown as the muted `@suffix` after the nickname
  # in the mini-status (e.g. `gmrdad82@0.8.5` / `gmrdad82@localhost`).
  #
  #   production → the image TAG it was built/pulled as. First present of
  #     ENV["PITO_VERSION"] (baked into the image by CI — authoritative) then
  #     ENV["PITO_TAG"] (forwarded by docker-compose from .env — the operator's
  #     chosen tag). A leading `v` is stripped; `"latest"` (rolling/edge) is
  #     treated as no meaningful tag.
  #   dev / test → the HOST you're running against, from PITO_APP_BASE_URL
  #     (default `http://localhost`) → `localhost` or your configured host.
  #
  # No request context needed (deterministic for specs); one place for the env reads.
  module Version
    module_function

    # @return [String, nil] the suffix to render after `@`, or nil when none.
    def suffix
      Rails.env.production? ? production_tag : dev_host
    end

    def production_tag
      raw = ENV["PITO_VERSION"].presence || ENV["PITO_TAG"].presence
      return nil if raw.nil?

      tag = raw.sub(/\Av/, "")
      return nil if tag.blank? || tag == "latest"

      tag
    end

    def dev_host
      base = ENV["PITO_APP_BASE_URL"].presence || "http://localhost"
      URI(base).host || "localhost"
    rescue URI::InvalidURIError
      "localhost"
    end
  end
end
