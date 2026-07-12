# frozen_string_literal: true

module Pito
  # The running build's identity, shown after the connection dot in the
  # mini-status (e.g. `■ 1.6.0` in production, `■ dev` everywhere else).
  #
  #   production → the image TAG it was built/pulled as. First present of
  #     ENV["PITO_VERSION"] (baked into the image by CI — authoritative) then
  #     ENV["PITO_TAG"] (forwarded by docker-compose from .env — the operator's
  #     chosen tag). A leading `v` is stripped; `"latest"` (rolling/edge) is
  #     treated as no meaningful tag.
  #   dev / test → the literal "dev" (owner fat-cut 2026-07-12: not a host,
  #     not localhost — just where you are).
  #
  # No request context needed (deterministic for specs); one place for the env reads.
  module Version
    module_function

    # @return [String, nil] the tag to render after the dot, or nil when none.
    def suffix
      Rails.env.production? ? production_tag : "dev"
    end

    def production_tag
      raw = ENV["PITO_VERSION"].presence || ENV["PITO_TAG"].presence
      return nil if raw.nil?

      tag = raw.sub(/\Av/, "")
      return nil if tag.blank? || tag == "latest"

      tag
    end
  end
end
