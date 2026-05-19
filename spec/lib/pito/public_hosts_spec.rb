require "rails_helper"

# Phase 7.5 — `Pito::PublicHosts` exposes a canonical absolute base URL
# for `app.pitomd.com`. The read honours the `PITO_APP_BASE_URL`
# environment override used by request specs and CI, and strips a
# trailing slash so callers can safely concatenate paths.
#
# Phase 29 (MCP cut, 2026-05-19) — `DEFAULT_MCP_BASE` / `.mcp_base` were
# removed alongside the MCP surface.
RSpec.describe Pito::PublicHosts do
  # Swap an env var for the duration of the block, restoring exactly
  # whatever was there before (including "unset").
  def with_env(key, value)
    had_key = ENV.key?(key)
    original = ENV[key]
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
    yield
  ensure
    if had_key
      ENV[key] = original
    else
      ENV.delete(key)
    end
  end

  describe "constants" do
    it "declares the canonical app base" do
      expect(described_class::DEFAULT_APP_BASE).to eq("https://app.pitomd.com")
    end
  end

  describe ".app_base" do
    it "returns the default when the env var is unset" do
      with_env("PITO_APP_BASE_URL", nil) do
        expect(described_class.app_base).to eq("https://app.pitomd.com")
      end
    end

    it "returns the env-var value when set" do
      with_env("PITO_APP_BASE_URL", "https://example.test") do
        expect(described_class.app_base).to eq("https://example.test")
      end
    end

    it "chomps a single trailing slash" do
      with_env("PITO_APP_BASE_URL", "https://example.test/") do
        expect(described_class.app_base).to eq("https://example.test")
      end
    end

    it "leaves no-trailing-slash values untouched" do
      with_env("PITO_APP_BASE_URL", "https://example.test") do
        expect(described_class.app_base).to eq("https://example.test")
      end
    end
  end

  describe "flaw — empty-string env var (chomp leaves it empty)" do
    it "returns an empty string for app_base when set to ''" do
      with_env("PITO_APP_BASE_URL", "") do
        # `ENV.fetch` only treats unset as missing; an empty string
        # flows through and chomp leaves it empty. Callers shouldn't
        # configure this, but documenting the contract surfaces any
        # future regression that adds a fallback.
        expect(described_class.app_base).to eq("")
      end
    end
  end
end
