# frozen_string_literal: true

# FCM push sender (R2 — sender only; R3 wires the fanout job that loops
# DeviceToken rows and prunes dead ones on #unregistered?).
#
# Sends a single data-only push to a single device token via Firebase Cloud
# Messaging's HTTP v1 API, authenticated with a service-account OAuth token
# (googleauth + jwt are already in the bundle, transitive via the
# google-apis-* gems — see Gemfile.lock).
#
# DATA-ONLY on purpose: the payload carries only a `data` block, never a
# `notification` block. A "notification"-type FCM message is rendered by the
# OS tray directly and bypasses the app's own message handler whenever the
# app is backgrounded — the Android side always wants to build its own
# notification from `data`, so a `notification` block would silently break
# that path. Do not add one.
#
# Configuration: `ENV["PITO_FCM_CREDENTIALS_PATH"]` — filesystem path to a
# Google service-account JSON key, kept OUTSIDE this repo at runtime. A
# blank env var or an unreadable path means "not configured" and mirrors
# Pito::Embedding::Client's PITO_EMBEDDER_URL guard exactly: the forgiving
# path no-ops to a disabled Outcome with no HTTP call, nothing crashes,
# nothing bad persists.
#
# OAuth token lifecycle: the service-account credentials object is memoized
# at the CLASS level (not per instance — R3's fanout instantiates a fresh
# Sender per device token, so per-instance memoization would refetch a token
# for every push) and its access token is refreshed via #fetch_access_token!
# only when missing or expired; the credentials object itself is what caches
# the token between calls, exactly like every other Signet-based Google
# client in this bundle.
#
# Outcome contract (for R3's pruning): #call never raises — a transport
# failure, a non-2xx response, or "not configured" all collapse to a small
# Outcome value object instead. #unregistered? is the ONE signal R3 needs:
# true only when FCM says the token is dead (HTTP 404, or a 200-shaped error
# body whose status/errorCode is "UNREGISTERED") — a plain transport error
# (timeout, DNS, 5xx) is a failed-but-NOT-unregistered outcome, so R3 must
# never prune a token just because the network hiccupped.
module Pito
  module Fcm
    class Sender
      SCOPE             = "https://www.googleapis.com/auth/firebase.messaging"
      SEND_URL_TEMPLATE = "https://fcm.googleapis.com/v1/projects/%<project_id>s/messages:send"

      # Mirrors Pito::Embedding::Client's #perform_request timeouts in
      # spirit (short open, generous-but-bounded read) — this is a single
      # small JSON POST, not a bulk embedding request, so both are tighter.
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      # The FCM v1 error-detail signature for a dead/uninstalled token. Seen
      # either as the top-level error `status` or as an `errorCode` inside
      # `error.details` (FcmError detail objects) — #unregistered_response?
      # checks both shapes.
      UNREGISTERED_STATUS = "UNREGISTERED"

      # Small value object — deliberately NOT an exception. `ok` mirrors
      # #success?, `unregistered` mirrors #unregistered? (see file header
      # for what each means to R3's pruning), `disabled` flags the
      # not-configured no-op path distinctly from a real send failure.
      Outcome = Struct.new(:ok, :unregistered, :disabled, keyword_init: true) do
        def success? = !!ok
        def unregistered? = !!unregistered
        def disabled? = !!disabled
      end

      # Sends one data-only push to `token`. `message` and `level` ride in
      # the `data` block verbatim (the Android side reads them to build its
      # own notification). Never raises — see file header Outcome contract.
      def call(token:, message:, level: "info")
        return disabled_outcome unless configured?

        creds = self.class.credentials
        return disabled_outcome if creds.nil?

        response = post_message(creds, token: token, message: message, level: level)
        outcome_for(response)
      rescue StandardError => e
        Rails.logger.warn("[Pito::Fcm::Sender] send failed: #{e.class}: #{e.message}")
        Outcome.new(ok: false, unregistered: false, disabled: false)
      end

      private

      def configured?
        credentials_path.present? && File.readable?(credentials_path)
      end

      def credentials_path
        ENV["PITO_FCM_CREDENTIALS_PATH"]
      end

      def disabled_outcome
        Outcome.new(ok: false, unregistered: false, disabled: true)
      end

      def post_message(creds, token:, message:, level:)
        uri = URI.parse(format(SEND_URL_TEMPLATE, project_id: creds.project_id))
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"]  = "application/json"
        request["Authorization"] = "Bearer #{creds.access_token}"
        request.body = JSON.generate(
          message: {
            token: token,
            data: {
              message: message,
              level:   level
            },
            android: { priority: "high" }
          }
        )

        Net::HTTP.start(uri.hostname, uri.port,
                        use_ssl: uri.scheme == "https",
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request)
        end
      end

      def outcome_for(response)
        return Outcome.new(ok: true, unregistered: false, disabled: false) if response.is_a?(Net::HTTPSuccess)

        if unregistered_response?(response)
          Rails.logger.warn("[Pito::Fcm::Sender] token unregistered: #{response.code} #{response.message}")
          return Outcome.new(ok: false, unregistered: true, disabled: false)
        end

        Rails.logger.warn("[Pito::Fcm::Sender] non-2xx response: #{response.code} #{response.message} — body: #{response.body.to_s[0, 300]}")
        Outcome.new(ok: false, unregistered: false, disabled: false)
      end

      # See UNREGISTERED_STATUS doc — checks both the plain 404 and the two
      # documented FCM v1 error-body shapes. Any unparsable body is just an
      # ordinary failure, not an unregistered signal.
      def unregistered_response?(response)
        return true if response.code.to_i == 404

        parsed = JSON.parse(response.body.to_s)
        return true if parsed.dig("error", "status") == UNREGISTERED_STATUS

        Array(parsed.dig("error", "details")).any? { |detail| detail.is_a?(Hash) && detail["errorCode"] == UNREGISTERED_STATUS }
      rescue JSON::ParserError, TypeError
        false
      end

      class << self
        # Class-level memoized credentials — see file header. Returns nil
        # (never raises) when unconfigured or the OAuth handshake fails, so
        # #call's disabled/failure path takes over.
        def credentials
          path = ENV["PITO_FCM_CREDENTIALS_PATH"]
          return nil if path.blank? || !File.readable?(path)

          @credentials ||= File.open(path) { |io| Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: io, scope: Sender::SCOPE) }
          @credentials.fetch_access_token! if @credentials.access_token.nil? || @credentials.expired?
          @credentials
        rescue StandardError => e
          Rails.logger.warn("[Pito::Fcm::Sender] credential setup failed: #{e.class}: #{e.message}")
          @credentials = nil
        end
      end
    end
  end
end
