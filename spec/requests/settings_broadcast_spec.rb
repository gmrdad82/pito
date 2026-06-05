# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

# P55 — POST /settings/expand_all broadcasts #pito-settings to pito:global
# so all open tabs update data-expand-all without a reload.

RSpec.describe "POST /settings/expand_all — global settings broadcast", type: :request do
  include ActionCable::TestHelper

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: Conversation.singleton.uuid }
  end

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "broadcasts #pito-settings replace to pito:global when expand_all is toggled to true" do
      AppSetting.expand_all = false

      expect {
        post settings_toggle_expand_all_path,
             params:  { expand_all: true },
             headers: { "Accept" => "application/json" }
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(html).to include('action="replace"')
        expect(html).to include("pito-settings")
        expect(html).to include('data-expand-all="true"')
      }
    end

    it "broadcasts #pito-settings replace to pito:global when expand_all is toggled to false" do
      AppSetting.expand_all = true

      expect {
        post settings_toggle_expand_all_path,
             params:  { expand_all: false },
             headers: { "Accept" => "application/json" }
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(html).to include('data-expand-all="false"')
      }
    end

    it "persists expand_all and returns 204" do
      AppSetting.expand_all = false

      post settings_toggle_expand_all_path,
           params:  { expand_all: true },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:no_content)
      expect(AppSetting.expand_all?).to be true
    end
  end
end
