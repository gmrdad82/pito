# Phase 25 — 01a (LD-2). Privacy-preserving fingerprint composer.
#
# Composes a deterministic SHA256 hex digest from a fixed input set:
#
#   - `User-Agent` request header
#   - `Accept` request header
#   - `Accept-Language` request header
#   - `Accept-Encoding` request header
#   - `Sec-Ch-Ua-Platform` (when present)
#   - `Sec-Ch-Ua-Mobile`   (when present)
#   - screen hint posted by the login-page Stimulus controller
#     (`<screen.width>x<screen.height>@<devicePixelRatio>`)
#   - locale hint posted by the same controller
#     (`<IANA timezone>/<navigator.language>`)
#
# **Forbidden inputs** (raises `ArgumentError`): canvas, AudioContext,
# WebGL, font enumeration, battery / network info. The Stimulus
# controller doesn't collect these, and the server-side composer
# defensively rejects them so a future regression can't slip them in.
#
# Inputs are joined with a fixed-order separator ("|") so the same
# inputs produce the same hash regardless of the order they were
# passed in. Missing fields render as empty strings — never raise —
# so the hash stays computable from a partial input set (a curl
# request with no headers still produces a deterministic hash; the
# entropy is just lower).
require "digest"

module Auth
  class FingerprintComposer
    SEPARATOR = "|".freeze
    FORBIDDEN_KWARGS = %i[canvas_hash audio_hash webgl_renderer font_list battery_level].freeze

    # Public entry: pass either an `ActionDispatch::Request`
    # (controller path) or a bag of named arguments (spec path).
    # Returns the SHA256 hex (64 chars).
    def self.call(request: nil,
                  user_agent: nil,
                  accept: nil,
                  accept_language: nil,
                  accept_encoding: nil,
                  sec_ch_ua_platform: nil,
                  sec_ch_ua_mobile: nil,
                  screen_hint: nil,
                  locale_hint: nil,
                  **forbidden)
      reject_forbidden!(forbidden)

      if request
        user_agent         ||= request.user_agent
        accept             ||= header(request, "Accept")
        accept_language    ||= header(request, "Accept-Language")
        accept_encoding    ||= header(request, "Accept-Encoding")
        sec_ch_ua_platform ||= header(request, "Sec-Ch-Ua-Platform")
        sec_ch_ua_mobile   ||= header(request, "Sec-Ch-Ua-Mobile")
        # Stimulus posts these as form params; the controller forwards
        # them via the explicit kwargs above, so we don't reach into
        # request.params here.
      end

      payload = [
        normalize(user_agent),
        normalize(accept),
        normalize(accept_language),
        normalize(accept_encoding),
        normalize(sec_ch_ua_platform),
        normalize(sec_ch_ua_mobile),
        "screen=" + normalize(screen_hint),
        "lang=" + normalize(locale_hint)
      ].join(SEPARATOR)

      Digest::SHA256.hexdigest(payload)
    end

    def self.reject_forbidden!(kwargs)
      return if kwargs.empty?

      offenders = kwargs.keys & FORBIDDEN_KWARGS
      return if offenders.empty?

      raise ArgumentError,
            "FingerprintComposer rejects privacy-invasive inputs: #{offenders.inspect}"
    end

    # Force UTF-8 encoding so non-ASCII Accept-Language values (`he-IL`,
    # emojis injected by malformed clients) hash without raising. Strip
    # to defang trailing newlines / leading whitespace from header
    # munging proxies.
    def self.normalize(value)
      value.to_s.dup.force_encoding(Encoding::UTF_8).strip
    end

    def self.header(request, name)
      env_key = "HTTP_" + name.tr("-", "_").upcase
      request.headers[env_key] || request.headers[name]
    end
  end
end
