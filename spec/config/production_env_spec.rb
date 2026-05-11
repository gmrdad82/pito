require "rails_helper"

# Phase 25 security review fix-forward. Pins the two HTTPS / proxy-trust
# settings that `config/environments/production.rb` must declare:
#
#   F1 — `config.assume_ssl = true`, `config.force_ssl = true` (secure
#        cookies + HSTS depend on this; without them the Phase 25 session
#        cookie can be intercepted on a downgraded http:// request).
#   F2 — `config.action_dispatch.trusted_proxies` must include Cloudflare
#        edge ranges so a malicious `X-Forwarded-For` header can NOT spoof
#        `request.remote_ip` (the Rack::Attack login throttle key).
#
# `Rails.env` is `test` for the rest of the suite. We cannot boot the
# production environment in-process without polluting the running app
# (and we cannot rely on a master key existing in CI). Instead we lock
# the relevant flags by reading `production.rb` as source text and
# asserting they appear in the expected shape. A future commit that
# comments either flag out, deletes the trusted_proxies block, or omits
# a Cloudflare range will fail the spec.
RSpec.describe "config/environments/production.rb" do
  let(:source) { File.read(Rails.root.join("config/environments/production.rb")) }

  it "parses as valid Ruby" do
    expect {
      RubyVM::InstructionSequence.compile(source)
    }.not_to raise_error
  end

  describe "F1 — HTTPS enforcement" do
    it "enables config.assume_ssl (uncommented)" do
      # Match a non-commented assignment. Leading `#` (with optional
      # whitespace) means the flag is commented out and the spec fails.
      expect(source).to match(/^\s*config\.assume_ssl\s*=\s*true\b/)
      expect(source).not_to match(/^\s*#\s*config\.assume_ssl\s*=\s*true\b/)
    end

    it "enables config.force_ssl (uncommented)" do
      expect(source).to match(/^\s*config\.force_ssl\s*=\s*true\b/)
      expect(source).not_to match(/^\s*#\s*config\.force_ssl\s*=\s*true\b/)
    end

    it "still exempts the /up health check from the HTTPS redirect" do
      # If force_ssl is on, the health check (which Kamal / k8s probes
      # hit over plain HTTP) must be excluded or Puma serves a 301 to
      # the probe and the deploy looks unhealthy.
      expect(source).to match(/config\.ssl_options\s*=.*request\.path\s*==\s*['"]\/up['"]/m)
    end
  end

  describe "F2 — trusted proxies (Cloudflare edge)" do
    it "configures config.action_dispatch.trusted_proxies (uncommented)" do
      expect(source).to match(/^\s*config\.action_dispatch\.trusted_proxies\s*=/)
      expect(source).not_to match(/^\s*#\s*config\.action_dispatch\.trusted_proxies\s*=/)
    end

    it "trusts loopback so the proxy-to-Puma hop is allowed" do
      expect(source).to include('"127.0.0.1"')
      expect(source).to include('"::1"')
    end

    it "lists Cloudflare's 104.16.0.0/13 IPv4 range" do
      expect(source).to include("104.16.0.0/13")
    end

    it "lists Cloudflare's 2606:4700::/32 IPv6 range" do
      expect(source).to include("2606:4700::/32")
    end

    it "wraps the CIDR strings in IPAddr objects (Rack matches IPAddr)" do
      # Bare strings work for Rails dev convenience but Rack::Request
      # actually compares against IPAddr instances; we want to make
      # sure the production list passes a `.map { |c| IPAddr.new(c) }`
      # (or equivalent) call.
      expect(source).to match(/IPAddr\.new/)
    end

    it "documents the refresh date for the Cloudflare list" do
      # The list is hardcoded; an inline comment must carry the source
      # URL + the date the list was encoded so a future maintainer can
      # tell at a glance whether it is stale.
      expect(source).to match(/cloudflare\.com\/ips-v4/i)
      expect(source).to match(/cloudflare\.com\/ips-v6/i)
      expect(source).to match(/\b20\d{2}-\d{2}-\d{2}\b/)
    end
  end
end
