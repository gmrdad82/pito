require "rails_helper"

# Phase 7.5 — `Pito::PublicHosts` exposes canonical absolute base URLs
# for `app.pitomd.com` and `mcp.pitomd.com`. Both reads honour the
# `PITO_APP_BASE_URL` / `PITO_MCP_BASE_URL` environment overrides used
# by request specs and CI; both strip a trailing slash so callers can
# safely concatenate paths.
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

    it "declares the canonical mcp base" do
      expect(described_class::DEFAULT_MCP_BASE).to eq("https://mcp.pitomd.com")
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

  describe ".mcp_base" do
    it "returns the default when the env var is unset" do
      with_env("PITO_MCP_BASE_URL", nil) do
        expect(described_class.mcp_base).to eq("https://mcp.pitomd.com")
      end
    end

    it "returns the env-var value when set" do
      with_env("PITO_MCP_BASE_URL", "https://mcp.example.test") do
        expect(described_class.mcp_base).to eq("https://mcp.example.test")
      end
    end

    it "chomps a trailing slash" do
      with_env("PITO_MCP_BASE_URL", "https://mcp.example.test/") do
        expect(described_class.mcp_base).to eq("https://mcp.example.test")
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

    it "returns an empty string for mcp_base when set to ''" do
      with_env("PITO_MCP_BASE_URL", "") do
        expect(described_class.mcp_base).to eq("")
      end
    end
  end
end
