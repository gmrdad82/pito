# frozen_string_literal: true

require "rails_helper"

# POST /chat with a JSON body — the message path for non-browser clients
# (pito-tui). JSON requests get 201 {uuid, turn_id} (the web's Turbo form
# posts keep their 204), and the web-only sidebar/navigate fast-paths refuse
# with a printable web_only error instead of a turbo-stream.

RSpec.describe "POST /chat (JSON)", type: :request do
  let!(:conversation) { Conversation.create! }

  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  describe "a message to an existing conversation" do
    before { login! }

    it "responds 201 with the uuid and the created turn's id" do
      post "/chat", params: { input: "ls games", uuid: conversation.uuid }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["uuid"]).to eq(conversation.uuid)
      expect(body["turn_id"]).to eq(conversation.turns.order(:position).last.id)
    end

    it "still enqueues the dispatch job like any other message" do
      expect {
        post "/chat", params: { input: "ls games", uuid: conversation.uuid }, as: :json
      }.to have_enqueued_job(ChatDispatchJob)
    end
  end

  describe "the home-transition create (blank input, no uuid)" do
    it "keeps its {uuid, signed_stream_name} 201 shape" do
      post "/chat", params: { input: "" }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["uuid"]).to be_present
      expect(response.parsed_body["signed_stream_name"]).to be_present
    end
  end

  describe "/authenticate through chat (JSON)" do
    it "mints the cookie and responds 201 with the login turn id (no navigate)" do
      seed = ROTP::Base32.random_base32
      AppSetting.enroll_totp!(seed: seed)

      post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}", uuid: conversation.uuid }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["turn_id"]).to be_present

      get "/resume", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "the web-only fast-paths" do
    before { login! }

    it "refuses /themes with a printable web_only error" do
      post "/chat", params: { input: "/themes", uuid: conversation.uuid }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("web_only")
      expect(response.parsed_body["message"]).to be_present
    end

    it "refuses every sidebar/navigate verb uniformly" do
      [ "/connect", "/new", "/resume", "show game", "show vids", "/games import", "import games" ].each do |input|
        post "/chat", params: { input:, uuid: conversation.uuid }, as: :json

        expect(response).to have_http_status(:unprocessable_content), "expected #{input.inspect} to be web_only"
        expect(response.parsed_body["error"]).to eq("web_only")
      end
    end

    it "creates no turn for a refused verb" do
      expect {
        post "/chat", params: { input: "/themes", uuid: conversation.uuid }, as: :json
      }.not_to change(Turn, :count)
    end
  end
end
