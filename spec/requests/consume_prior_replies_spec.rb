# frozen_string_literal: true

require "rails_helper"

# P17 — sending a NEW (non-reply) command consumes every PRIOR live #hashtag
# affordance in the conversation. The new command's OWN result events (streamed
# in later by ChatDispatchJob, under the new turn) keep their handles live.
RSpec.describe "Consuming prior live replies on a new message", type: :request do
  let(:conversation) { Conversation.singleton }

  before do
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed:)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
    conversation.turns.destroy_all
  end

  # A persisted, live (non-consumed) follow-up-able event on its own turn.
  def live_repliable_event(handle:)
    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: "list games"
    )
    Event.create_with_position!(
      conversation:, turn:, kind: "system",
      payload: {
        "reply_handle" => handle,
        "reply_target" => "game_list",
        "body"         => "<div>games</div>",
        "html"         => true
      }
    )
  end

  it "marks a prior live repliable event consumed" do
    event = live_repliable_event(handle: "alpha-1111")

    post "/chat", params: { input: "list games", uuid: conversation.uuid }

    expect(response).to have_http_status(:no_content)
    expect(Pito::FollowUp.consumed?(event.reload.payload)).to be(true)
  end

  it "makes a later reply to the old handle route to :not_found" do
    live_repliable_event(handle: "alpha-1111")

    post "/chat", params: { input: "list games", uuid: conversation.uuid }

    result = Pito::FollowUp::Router.call(input: "#alpha-1111 show 1", conversation:)
    expect(result[:status]).to eq(:not_found)
  end

  it "never consumes the new command's OWN events (only PRIOR turns are swept)" do
    create(:game)
    prior = live_repliable_event(handle: "alpha-1111")

    post "/chat", params: { input: "list games", uuid: conversation.uuid }

    # The new turn's result events stream in LATER (perform_later in prod).
    new_turn = conversation.turns.order(:id).last
    ChatDispatchJob.perform_now(new_turn.id, channel: "@all")

    # P17 scopes consumption to turns BEFORE the new one: the prior handle is
    # consumed, and NOTHING the new command emits on its own turn ever is —
    # regardless of how that turn's messages happen to render.
    expect(Pito::FollowUp.consumed?(prior.reload.payload)).to be(true)
    consumed_on_new_turn = new_turn.events.reload.select { |e| Pito::FollowUp.consumed?(e.payload) }
    expect(consumed_on_new_turn).to be_empty
  end

  it "does NOT consume other live handles on the #handle reply path" do
    target = live_repliable_event(handle: "beta-2222")
    other  = live_repliable_event(handle: "gamma-3333")

    post "/chat", params: { input: "##{target.payload['reply_handle']} show 1", uuid: conversation.uuid }

    expect(Pito::FollowUp.consumed?(other.reload.payload)).to be(false)
  end
end
