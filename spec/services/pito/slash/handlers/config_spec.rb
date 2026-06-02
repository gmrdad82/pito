# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Config, type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(args: [], kwargs: {})
    invocation = Pito::Slash::Invocation.new(
      verb:   :config,
      args:   args,
      kwargs: kwargs,
      raw:    "/config #{args.join(' ')}"
    )
    described_class.new(invocation:, conversation:)
  end

  before { Pito::Credentials.invalidate! }
  after  { Pito::Credentials.invalidate! }

  describe "#call — unknown provider" do
    it "returns an error" do
      result = build_handler(args: [ "unknown_service" ]).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_provider")
    end
  end

  describe "#call — /config google (getter)" do
    before do
      AppSetting.singleton_row.update!(
        google_oauth_client_id:     "my-id",
        google_oauth_client_secret: "my-secret"
      )
      Pito::Credentials.invalidate!
    end

    it "returns a Result::Ok with status line containing OK flags" do
      result = build_handler(args: [ "google" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.length).to eq(1)
      event = result.events.first
      expect(event[:kind]).to eq("assistant_text")
      # Text format: "Client ID: OK · Client Secret: OK · ..."
      expect(event[:payload][:text]).to include("Client ID: OK", "Client Secret: OK")
    end

    it "returns a status line even when credentials are absent" do
      AppSetting.singleton_row.update!(
        google_oauth_client_id:     nil,
        google_oauth_client_secret: nil
      )
      Pito::Credentials.invalidate!

      result = build_handler(args: [ "google" ]).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      # In test env both fall back to placeholders, so still "OK"
      expect(result.events.first[:payload][:text]).to be_present
    end
  end

  describe "#call — /config google client_id=x client_secret=y (setter)" do
    it "persists credentials to AppSetting" do
      build_handler(args: [ "google" ], kwargs: { client_id: "new-id", client_secret: "new-secret" }).call

      AppSetting.singleton_row.reload
      expect(AppSetting.singleton_row.google_oauth_client_id).to eq("new-id")
      expect(AppSetting.singleton_row.google_oauth_client_secret).to eq("new-secret")
    end

    it "returns a Result::Ok confirming the updated keys" do
      result = build_handler(args: [ "google" ], kwargs: { client_id: "id" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:message_key]).to eq("pito.slash.config.updated")
    end

    it "accepts a single key" do
      result = build_handler(args: [ "google" ], kwargs: { redirect_uri: "http://localhost/callback" }).call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(AppSetting.google_oauth_redirect_uri).to eq("http://localhost/callback")
    end

    it "returns an error for unknown keys" do
      result = build_handler(args: [ "google" ], kwargs: { invalid_key: "val" }).call
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.config.errors.unknown_keys")
    end
  end

  describe "echo masking in ChatController" do
    it "masks client_id and client_secret but shows redirect_uri" do
      ctrl = ChatController.new
      input = "/config google client_id=myid client_secret=myscret redirect_uri=http://localhost/cb"
      masked = ctrl.send(:mask_config_credentials, input)
      expect(masked).to eq("/config google client_id=*** client_secret=*** redirect_uri=http://localhost/cb")
    end

    it "is a no-op when no sensitive keys are present" do
      ctrl = ChatController.new
      input = "/config google redirect_uri=http://localhost/cb"
      expect(ctrl.send(:mask_config_credentials, input)).to eq(input)
    end
  end
end
