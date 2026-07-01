# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

# /config carries credentials, so it is dispatched SYNCHRONOUSLY (its own routing,
# distinct from the async pipeline every other command uses): the turn stores the
# MASKED form so raw credentials never persist in the conversation, while the
# dispatcher receives the RAW input from memory to apply the real values. The
# on-screen flow (echo → thinking → result) is unchanged.
RSpec.describe "POST /chat — /config synchronous credential routing", type: :request do
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  let(:conversation) { Conversation.singleton }

  before do
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
    conversation.turns.destroy_all
  end

  let(:raw)    { "/config google client_id=myid client_secret=mysecret redirect_uri=http://localhost/cb" }
  let(:masked) { "/config google client_id=*** client_secret=*** redirect_uri=***" }

  it "does NOT enqueue ChatDispatchJob (handled inline)" do
    expect {
      post "/chat", params: { input: raw, uuid: conversation.uuid }
    }.not_to have_enqueued_job(ChatDispatchJob)
  end

  it "stores the turn input_text MASKED — raw credentials never persist" do
    post "/chat", params: { input: raw, uuid: conversation.uuid }
    expect(Turn.last.input_text).to eq(masked)
  end

  it "broadcasts a masked echo" do
    post "/chat", params: { input: raw, uuid: conversation.uuid }
    echo = Turn.last.events.find { |e| e.kind == "echo" }
    expect(echo.payload["text"]).to eq(masked)
  end

  it "produces a result event synchronously (no job run needed)" do
    post "/chat", params: { input: raw, uuid: conversation.uuid }
    kinds = Turn.last.events.map(&:kind)
    expect(kinds).to include("system").or include("error")
  end

  it "passes the RAW input to the dispatcher so the real credentials are applied" do
    allow(Pito::Slash::Dispatcher).to receive(:call).and_call_original
    post "/chat", params: { input: raw, uuid: conversation.uuid }
    expect(Pito::Slash::Dispatcher).to have_received(:call)
      .with(input: raw, conversation: anything, authenticated: true)
  end

  it "still routes /config --help through the async path (help, no credentials)" do
    expect {
      post "/chat", params: { input: "/config google --help", uuid: conversation.uuid }
    }.to have_enqueued_job(ChatDispatchJob)
  end

  it "routes a NON-credential /config (sound) through the async path" do
    expect {
      post "/chat", params: { input: "/config sound off", uuid: conversation.uuid }
    }.to have_enqueued_job(ChatDispatchJob)
  end

  describe "webhook (slack/discord URLs are secrets too)" do
    let(:raw)    { "/config webhook slack=https://hooks.slack.com/services/T/B/zzz" }
    let(:masked) { "/config webhook slack=***" }

    it "routes webhook synchronously" do
      expect {
        post "/chat", params: { input: raw, uuid: conversation.uuid }
      }.not_to have_enqueued_job(ChatDispatchJob)
    end

    it "stores the webhook URL masked" do
      post "/chat", params: { input: raw, uuid: conversation.uuid }
      expect(Turn.last.input_text).to eq(masked)
    end
  end
end
