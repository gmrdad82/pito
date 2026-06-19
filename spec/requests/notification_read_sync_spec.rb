# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

# PATCH /notifications/:id broadcasts mini-status to pito:global
# so every open browser instance sees the updated unread count.

RSpec.describe "PATCH /notifications/:id — global cable sync", type: :request do
  include ActionCable::TestHelper

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: Conversation.create!.uuid }
  end

  describe "when authenticated" do
    before { authenticate_via_totp }

    let!(:notification) { create(:notification) }

    it "broadcasts a pito-mini-status replace to pito:global when marking read" do
      expect {
        patch notification_path(notification), params: { read: true }
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(html).to include('action="replace"')
        expect(html).to include("pito-mini-status")
      }
    end

    it "broadcasts a pito-mini-status replace to pito:global when marking unread" do
      notification.mark_read!

      expect {
        patch notification_path(notification), params: { read: false }
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(html).to include("pito-mini-status")
      }
    end

    it "persists the read state and returns 204" do
      patch notification_path(notification), params: { read: true }

      expect(response).to have_http_status(:no_content)
      expect(notification.reload.read?).to be true
    end
  end
end
