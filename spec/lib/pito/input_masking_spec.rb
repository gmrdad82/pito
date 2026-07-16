# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::InputMasking do
  describe ".config_command?" do
    it "matches /config (verb-bounded, any case, trimmed)" do
      expect(described_class.config_command?("/config google client_id=abc")).to be(true)
      expect(described_class.config_command?("/CONFIG")).to be(true)
      expect(described_class.config_command?("  /config  ")).to be(true)
    end

    it "does not match other commands" do
      expect(described_class.config_command?("/configure x")).to be(false)
      expect(described_class.config_command?("list games")).to be(false)
    end
  end

  describe ".config_credential_command?" do
    it "is true for the secret-bearing providers" do
      %w[google igdb webhook].each do |provider|
        expect(described_class.config_credential_command?("/config #{provider} k=v")).to be(true)
        expect(described_class.config_credential_command?("/config #{provider.upcase}")).to be(true)
      end
    end

    it "is false for non-credential /config forms" do
      non_credential = [
        "/config fx comet", "/config motion off",
        "/config sound on", "/config timezone Europe/Madrid", "/config"
      ]
      non_credential.each do |input|
        expect(described_class.config_credential_command?(input)).to be(false)
      end
    end

    it "is false for non-config commands" do
      expect(described_class.config_credential_command?("list games")).to be(false)
    end
  end

  describe ".login_command?" do
    it "matches /login" do
      expect(described_class.login_command?("/login 123456")).to be(true)
      expect(described_class.login_command?("/login")).to be(true)
    end

    it "matches the /authenticate alias (any case)" do
      expect(described_class.login_command?("/authenticate 123456")).to be(true)
      expect(described_class.login_command?("/AUTHENTICATE")).to be(true)
    end

    it "does not match other commands" do
      expect(described_class.login_command?("/logout")).to be(false)
      expect(described_class.login_command?("/authenticated")).to be(false)
    end

    it "masks the /authenticate code in history (security)" do
      expect(described_class.for_history("/authenticate 123456")).to eq("/authenticate ******")
    end
  end

  describe ".mask_config_credentials" do
    it "masks ALL credential kwarg values (incl redirect_uri) to ***" do
      input  = "/config google client_id=abc client_secret=xyz api_key=k redirect_uri=http://x"
      masked = described_class.mask_config_credentials(input)
      expect(masked).to eq("/config google client_id=*** client_secret=*** api_key=*** redirect_uri=***")
    end

    it "masks webhook delivery URLs (slack / discord)" do
      input  = "/config webhook slack=https://hooks.slack.com/x discord=https://discord.com/y"
      expect(described_class.mask_config_credentials(input))
        .to eq("/config webhook slack=*** discord=***")
    end


    it "is a no-op for non-config input" do
      expect(described_class.mask_config_credentials("list games")).to eq("list games")
    end
  end

  describe ".mask_secret" do
    it "masks the entire payload after the verb" do
      expect(described_class.mask_secret("/login 123456")).to eq("/login ******")
    end

    it "returns the input unchanged when there is no payload" do
      expect(described_class.mask_secret("/login")).to eq("/login")
    end
  end

  describe ".for_history" do
    it "masks /config credential values" do
      expect(described_class.for_history("/config google client_secret=xyz"))
        .to eq("/config google client_secret=***")
    end

    it "masks /login payloads" do
      expect(described_class.for_history("/login 123456")).to eq("/login ******")
    end

    it "returns non-secret input verbatim" do
      expect(described_class.for_history("list games")).to eq("list games")
      expect(described_class.for_history("#alpha-1 show")).to eq("#alpha-1 show")
    end
  end
end
