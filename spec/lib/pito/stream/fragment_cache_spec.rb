# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stream::FragmentCache do
  let(:conversation) { Conversation.create! }
  let(:turn)         { create(:turn, conversation:) }

  # The suite runs on :null_store (isolation); L1 semantics need a real store.
  around do |example|
    original    = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  def event_with(kind: "system", payload: { "body" => "hello", "html" => true }, position: 1)
    create(:event, conversation:, turn:, kind:, payload:, position:)
  end

  it "serves the second render from the cache (sentinel round-trip)" do
    event = event_with
    Pito::Stream::EventRenderer.render(event)
    key = described_class.key(event)
    expect(Rails.cache.exist?(key)).to be(true)

    Rails.cache.write(key, "<div>SENTINEL</div>")
    expect(Pito::Stream::EventRenderer.render(event)).to include("SENTINEL")
  end

  it "does not cache thinking or confirmation kinds (multi-state lifecycles)" do
    thinking     = event_with(kind: "thinking", payload: { "dictionary" => "chat", "order" => [ 0 ] })
    confirmation = event_with(kind: "confirmation", payload: { "body" => "sure?", "reply_handle" => "c-1" }, position: 2)

    expect(described_class.cacheable?(thinking)).to be(false)
    expect(described_class.cacheable?(confirmation)).to be(false)
  end

  it "does not cache events still carrying a pending analytics/analyze marker" do
    pending = event_with(payload: { "body" => "…", "analytics" => { "status" => "pending" } })
    expect(described_class.cacheable?(pending)).to be(false)

    ready = event_with(payload: { "body" => "…", "analytics" => { "status" => "ready" } }, position: 2)
    expect(described_class.cacheable?(ready)).to be(true)
  end

  it "rotates the key when the payload changes (natural invalidation)" do
    event = event_with
    key_before = described_class.key(event)
    event.update!(payload: event.payload.merge("body" => "changed"))

    expect(described_class.key(event)).not_to eq(key_before)
  end

  it "does NOT rotate the key on handle consumption (the meta slot serves it)" do
    event = event_with(payload: { "body" => "x", "reply_handle" => "h-1" })
    key_before = described_class.key(event)
    event.update!(payload: event.payload.merge("reply_consumed" => true))

    expect(described_class.key(event)).to eq(key_before)
  end

  it "keys by time zone (the HH:MM prefix renders in the configured zone)" do
    event = event_with
    utc_key = described_class.key(event)
    madrid_key = Time.use_zone("Europe/Madrid") { described_class.key(event) }

    expect(madrid_key).not_to eq(utc_key)
  end
end
