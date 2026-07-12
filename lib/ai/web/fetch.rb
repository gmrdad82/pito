# frozen_string_literal: true

require "net/http"
require "ipaddr"
require "resolv"

module Ai
  module Web
    # The AI's web_fetch tool backend — pito fetches ONE result URL
    # server-side and returns readable text. The model never touches the
    # network; it only picks a URL (normally from web_search results).
    #
    # Hard guards, in order:
    #   * http/https only, and the resolved address must be PUBLIC — every
    #     redirect hop re-resolves and re-checks (SSRF: no loopback, no
    #     RFC1918/link-local/ULA, no metadata endpoints).
    #   * MAX_REDIRECTS hops, OPEN/READ timeouts, MAX_BYTES read cap.
    #   * Text extraction strips script/style/nav/header/footer/aside and
    #     squeezes whitespace; output capped at MAX_CHARS.
    #
    # Returns { title:, url:, text: } or { error: } — never raises into the
    # loop. Fetched pages are UNTRUSTED DATA: the toolset description forces
    # the never-instructions framing.
    module Fetch
      module_function

      MAX_REDIRECTS = 3
      OPEN_TIMEOUT  = 5
      READ_TIMEOUT  = 10
      MAX_BYTES     = 500_000
      MAX_CHARS     = 8_000
      STRIP_NODES   = "script, style, nav, header, footer, aside, noscript, svg, form"

      def call(url:)
        target = url.to_s.strip
        MAX_REDIRECTS.downto(0) do |hops_left|
          uri = parse_and_guard!(target)
          return uri if uri.is_a?(Hash) # guard error

          response = get(uri)
          case response
          when Net::HTTPRedirection
            return { error: "too many redirects" } if hops_left.zero?

            target = URI.join(uri, response["location"].to_s).to_s
            next
          when Net::HTTPSuccess
            return extract(uri, response)
          else
            return { error: "fetch failed (HTTP #{response.code})" }
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[Ai::Web::Fetch] #{e.class}: #{e.message}")
        { error: "fetch failed (#{e.class})" }
      end

      # ── guards ──────────────────────────────────────────────────────────

      def parse_and_guard!(raw)
        uri = URI.parse(raw)
        return { error: "only http(s) urls" } unless uri.is_a?(URI::HTTP) && uri.host.present?

        address = Resolv.getaddress(uri.host)
        return { error: "address not allowed" } unless public_address?(address)

        uri
      rescue URI::InvalidURIError, Resolv::ResolvError
        { error: "unreachable url" }
      end

      # Public-internet addresses only — everything private, loopback,
      # link-local, ULA, or unspecified is refused (SSRF wall).
      def public_address?(address)
        ip = IPAddr.new(address)
        !(ip.loopback? || ip.private? || ip.link_local? ||
          ip == IPAddr.new("0.0.0.0") || ip == IPAddr.new("::") ||
          (ip.ipv6? && IPAddr.new("fc00::/7").include?(ip)))
      rescue IPAddr::InvalidAddressError
        false
      end

      # ── transport + extraction ──────────────────────────────────────────

      def get(uri)
        Net::HTTP.start(uri.hostname, uri.port,
                        use_ssl: uri.scheme == "https",
                        open_timeout: OPEN_TIMEOUT,
                        read_timeout: READ_TIMEOUT) do |http|
          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = "pito (+self-hosted; single owner)"
          request["Accept"]     = "text/html,application/xhtml+xml,text/plain"
          http.request(request)
        end
      end

      def extract(uri, response)
        body = response.body.to_s.byteslice(0, MAX_BYTES).to_s
        doc  = Nokogiri::HTML(body)
        doc.css(STRIP_NODES).each(&:remove)

        title = doc.at_css("title")&.text.to_s.strip
        text  = doc.text.gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip[0, MAX_CHARS]
        return { error: "no readable text" } if text.blank?

        { title: title, url: uri.to_s, text: text }
      end
    end
  end
end
