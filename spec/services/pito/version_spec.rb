# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Version do
  # Set/clear ENV for the block, restoring prior values (incl. absence) after.
  def with_env(**vars)
    saved = vars.keys.to_h { |k| [ k.to_s, ENV.key?(k.to_s) ? ENV[k.to_s] : :__absent__ ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : (ENV[k.to_s] = v) }
    yield
  ensure
    saved.each { |k, v| v == :__absent__ ? ENV.delete(k) : (ENV[k] = v) }
  end

  def as_env(name)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(name))
  end

  describe ".suffix in production" do
    before { as_env("production") }

    it "reports the CI-baked PITO_VERSION" do
      with_env(PITO_VERSION: "0.8.5", PITO_TAG: nil) { expect(described_class.suffix).to eq("0.8.5") }
    end

    it "strips a leading v" do
      with_env(PITO_VERSION: "v0.8.5", PITO_TAG: nil) { expect(described_class.suffix).to eq("0.8.5") }
    end

    it "treats 'latest' (rolling/edge) as no meaningful tag" do
      with_env(PITO_VERSION: "latest", PITO_TAG: nil) { expect(described_class.suffix).to be_nil }
    end

    it "falls back to PITO_TAG when PITO_VERSION is unset" do
      with_env(PITO_VERSION: nil, PITO_TAG: "0.8.4") { expect(described_class.suffix).to eq("0.8.4") }
    end

    it "is nil when neither version var is set" do
      with_env(PITO_VERSION: nil, PITO_TAG: nil) { expect(described_class.suffix).to be_nil }
    end
  end

  describe ".suffix in development" do
    before { as_env("development") }

    it "defaults to localhost" do
      with_env(PITO_APP_BASE_URL: nil) { expect(described_class.suffix).to eq("localhost") }
    end

    it "uses the configured PITO_APP_BASE_URL host" do
      with_env(PITO_APP_BASE_URL: "https://dev.pitomd.com") { expect(described_class.suffix).to eq("dev.pitomd.com") }
    end

    it "ignores PITO_VERSION outside production (host, not tag)" do
      with_env(PITO_APP_BASE_URL: "http://localhost:3027", PITO_VERSION: "0.8.5") do
        expect(described_class.suffix).to eq("localhost")
      end
    end
  end
end
