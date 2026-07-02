# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stream::ScrollbackCache do
  let(:conversation) { Conversation.create! }
  let(:turn)         { create(:turn, conversation:) }

  around do |example|
    original    = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  def add_event(kind: "system", payload: { "body" => "hello", "html" => true }, position: 1)
    create(:event, conversation:, turn:, kind:, payload:, position:)
  end

  def assemble!
    described_class.fetch(conversation) do
      described_class.assemble(conversation.events.includes(:turn).order(:position).to_a)
    end
  end

  it "assembles turn containers with rendered events and serves repeats from cache" do
    event = add_event
    html  = assemble!

    expect(html).to include(%(id="turn_#{turn.id}"))
    expect(html).to include("hello")

    Rails.cache.write(described_class.key(conversation), "<div>SENTINEL</div>")
    expect(assemble!).to eq("<div>SENTINEL</div>")
    expect(event).to be_persisted
  end

  it "is busted by broadcast_event (a new message invalidates the snapshot)" do
    add_event
    assemble!
    expect(Rails.cache.exist?(described_class.key(conversation))).to be(true)

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.broadcast_event(add_event(payload: { "body" => "fresh" }, position: 2))

    expect(Rails.cache.exist?(described_class.key(conversation))).to be(false)
  end

  it "is busted by replace_event (mutations rebuild on next read)" do
    event = add_event(payload: { "body" => "before", "html" => true, "reply_handle" => "h-1" })
    expect(assemble!).to include("h-1")

    event.update!(payload: event.payload.merge("reply_consumed" => true))
    Pito::Stream::Broadcaster.new(conversation:).replace_event(event)

    expect(assemble!).not_to include("h-1") # rebuilt with the handle retired
  end

  it "handles an empty conversation and a multi-turn one through the same path" do
    expect(assemble!).to eq("")
    described_class.bust(conversation)

    add_event
    turn2 = create(:turn, conversation:)
    create(:event, conversation:, turn: turn2, kind: "system", payload: { "body" => "t2" }, position: 2)

    html = assemble!
    expect(html.scan("pito-turn").size).to eq(2)
  end
end
