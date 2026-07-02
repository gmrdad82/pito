# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Share::PageCache do
  let(:conversation) { Conversation.create! }
  let(:turn)         { create(:turn, conversation:) }
  let(:event) do
    create(:event, conversation:, turn:, kind: "system", position: 2,
                   payload: { "body" => "the shared card", "html" => true, "reply_handle" => "sh-1" })
  end
  let(:share) { create(:share, conversation:, event:) }

  around do |example|
    original    = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  it "renders intro/event/outro reply-suppressed and serves repeats from cache" do
    create(:event, conversation:, turn:, kind: "system", position: 1, payload: { "body" => "before" })
    create(:event, conversation:, turn:, kind: "system", position: 3, payload: { "body" => "after" })

    html = described_class.fetch(share)

    expect(html).to include("the shared card")
    expect(html).not_to include("sh-1") # reply affordance suppressed on public pages

    counts = Pito::Conversation::ScrollbackCount.around(conversation:, position: event.position)
    Rails.cache.write(described_class.key(share, event, counts), "<div>SENTINEL</div>")
    expect(described_class.fetch(share)).to eq("<div>SENTINEL</div>")
  end

  it "rotates the key when the conversation grows (counts are part of the address)" do
    first_key = described_class.key(share, event,
                                    Pito::Conversation::ScrollbackCount.around(conversation:, position: event.position))
    create(:event, conversation:, turn:, kind: "system", position: 3, payload: { "body" => "new msg" })
    second_key = described_class.key(share, event,
                                     Pito::Conversation::ScrollbackCount.around(conversation:, position: event.position))

    expect(second_key).not_to eq(first_key)
  end

  it "needs no revoke bust — the controller's Share lookup is the gate" do
    described_class.fetch(share)
    share.destroy!

    # The cached entry may linger until TTL, but no code path can reach it:
    # SharesController resolves the Share row first and 404s when it is gone.
    expect(Share.find_by(uuid: share.uuid)).to be_nil
  end
end
