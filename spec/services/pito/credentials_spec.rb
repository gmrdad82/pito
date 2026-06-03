# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Credentials do
  before { described_class.invalidate! }
  after  { described_class.invalidate! }

  describe ".google_oauth_client_id" do
    context "when AppSetting has a value" do
      before { AppSetting.singleton_row.update!(google_oauth_client_id: "from-db-client-id") }

      it "returns the AppSetting value" do
        expect(described_class.google_oauth_client_id).to eq("from-db-client-id")
      end

      it "caches the value so repeated reads do not query AppSetting each time" do
        # Swap in a real memory store for this example (test.rb uses :null_store).
        original = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        described_class.invalidate!

        described_class.google_oauth_client_id
        expect(AppSetting).not_to receive(:singleton_row)
        described_class.google_oauth_client_id
      ensure
        Rails.cache = original
        described_class.invalidate!
      end
    end

    context "when AppSetting is blank" do
      before { AppSetting.singleton_row.update!(google_oauth_client_id: nil) }

      it "returns the test placeholder in test env" do
        expect(described_class.google_oauth_client_id).to eq("test-google-oauth-client-id-not-a-secret")
      end
    end
  end

  describe ".google_oauth_redirect_uri" do
    context "when AppSetting has a redirect URI" do
      before { AppSetting.google_oauth_redirect_uri = "https://example.com/auth/youtube/callback" }
      after  { AppSetting.set(AppSetting::GOOGLE_OAUTH_REDIRECT_URI_KEY, nil) }

      it "returns the stored URI" do
        expect(described_class.google_oauth_redirect_uri).to eq("https://example.com/auth/youtube/callback")
      end
    end

    context "when unset" do
      before { AppSetting.set(AppSetting::GOOGLE_OAUTH_REDIRECT_URI_KEY, nil) }

      it "returns nil" do
        expect(described_class.google_oauth_redirect_uri).to be_nil
      end
    end
  end

  describe ".voyage_api_key" do
    context "when AppSetting has a value" do
      before { AppSetting.singleton_row.update!(voyage_api_key: "pa-key-from-db") }

      it "returns the AppSetting value" do
        expect(described_class.voyage_api_key).to eq("pa-key-from-db")
      end
    end

    context "when unset" do
      before { AppSetting.singleton_row.update!(voyage_api_key: nil) }

      it "returns nil" do
        expect(described_class.voyage_api_key).to be_nil
      end
    end
  end

  describe ".google_oauth_configured?" do
    context "when both client_id and client_secret are present" do
      before do
        AppSetting.singleton_row.update!(
          google_oauth_client_id:     "id",
          google_oauth_client_secret: "secret"
        )
      end

      it "returns true" do
        expect(described_class.google_oauth_configured?).to be true
      end
    end

    context "when both columns are nil on the singleton row" do
      before do
        AppSetting.singleton_row.update!(
          google_oauth_client_id:     nil,
          google_oauth_client_secret: nil
        )
        described_class.invalidate!
      end

      it "returns true in test env (both test-mode placeholders are present)" do
        # Test mode injects placeholder strings so specs can exercise OAuth
        # flows without real credentials. google_oauth_configured? therefore
        # returns true in Rails.env.test? even with a blank AppSetting row.
        expect(described_class.google_oauth_configured?).to be true
      end
    end
  end

  describe ".invalidate! via AppSetting after_save" do
    it "is called automatically when AppSetting is saved" do
      AppSetting.singleton_row.update!(google_oauth_client_id: "cached-value")
      described_class.google_oauth_client_id # warm cache

      # After_save triggers invalidate!, so a subsequent read hits DB again
      AppSetting.singleton_row.update!(google_oauth_client_id: "new-value")
      expect(described_class.google_oauth_client_id).to eq("new-value")
    end
  end
end
