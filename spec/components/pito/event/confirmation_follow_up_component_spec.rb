# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ConfirmationFollowUpComponent do
  let(:pending_payload) do
    { body: "Disconnect from @gmrdad82?", confirmation_handle: "alpha-1322" }
  end

  it "inherits orange accent from ConfirmationComponent" do
    node = render_inline(described_class.new(payload: pending_payload))
    expect(node.css("[data-accent='orange']")).not_to be_empty
  end

  it "has an elevated background" do
    comp = described_class.new(payload: pending_payload)
    expect(comp.background).to eq("var(--bg-elevated)")
  end

  it "does NOT render a meta line (no timestamp, no handle)" do
    event = build_stubbed_event(id: 99)
    node = render_inline(described_class.new(payload: pending_payload, event:))
    expect(node.css(".pito-echo__meta")).to be_empty
    expect(node.text).not_to include("#alpha-1322")
  end

  it "renders body text" do
    node = render_inline(described_class.new(payload: pending_payload))
    expect(node.css("span.text-fg").first.text).to include("@gmrdad82")
  end

  it "renders resolved outcome when resolved: true" do
    payload = pending_payload.merge(resolved: true, outcome: "confirmed", outcome_text: "Done.")
    node = render_inline(described_class.new(payload:))
    expect(node.css(".border-t").first.text).to include("Done.")
  end

  private

  def build_stubbed_event(id:)
    double("Event", id: id, created_at: Time.zone.now)
  end
end
