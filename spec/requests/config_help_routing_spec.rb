# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

# Regression coverage for the `--help` interceptor routing of
# `/config <provider> --help`.
#
# The dispatcher intercepts `--help` BEFORE the handler runs and delegates to
# `Pito::Slash::HelpBuilder`. Previously the interceptor rendered a generic
# provider man page for toggle/enum providers (fx, motion), so the dedicated
# fx live-showcase page and the motion on/off page were never reached. These
# specs exercise the full POST /chat dispatch path end-to-end.
RSpec.describe "POST /chat — /config <provider> --help routing", type: :request do
  include ActionCable::TestHelper

  let(:conversation) { Conversation.singleton }

  before do
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
    conversation.turns.destroy_all
  end

  # Runs the command through the full dispatch (echo + job) and returns the html
  # body of the resulting `system` man-page event.
  def help_body(input)
    perform_enqueued_jobs { post "/chat", params: { input:, uuid: conversation.uuid } }
    event = Turn.last.events.detect { |e| e.kind == "system" && e.payload["html"] }
    expect(event).to be_present, "expected an html man-page system event for #{input.inspect}"
    event.payload["body"]
  end


  describe "/config google --help (sanity — other providers still work)" do
    subject(:body) { help_body("/config google --help") }

    it "still shows google's keys and the /connect hint" do
      expect(body).to include("pito-help-block")
      expect(body).to include("client_id=")
      expect(body).to include("client_secret=")
      expect(body).to include("redirect_uri=")
      expect(body).to include("api_key=")
      expect(body).to include("/connect")
    end
  end
end
