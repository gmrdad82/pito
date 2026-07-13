# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::AiComponent do
  # REGRESSION (2026-07-13): the Segment's `fx:` kwarg had been swallowed
  # INTO the msg_bg string literal — ai messages rendered without
  # data-fx-context, the dominance watcher never enrolled them, and the
  # living background answered every AI message with the bare sky. This
  # spec pins the wiring so the mangling can't silently return.
  it "hands the payload's fx stamp to the Segment (data-fx-context on the message root)" do
    node = render_inline(described_class.new(payload: {
      status: "done",
      blocks: [ { type: "text", text: "hello" } ],
      fx: { "context" => "ai", "covers" => [] }
    }))
    root = node.css("[data-scrollback-message]").first
    expect(root).not_to be_nil
    expect(root["data-fx-context"]).to eq("ai")
  end

  it "keeps the surface's msg_bg an intact CSS var (not the mangled literal)" do
    node = render_inline(described_class.new(payload: {
      status: "done",
      blocks: [ { type: "text", text: "hello" } ],
      fx: { "context" => "ai", "covers" => [] }
    }))
    style = node.css("[data-scrollback-message] .pito-segment__content").first["style"].to_s
    expect(style).to include("var(--bg-surface)")
    expect(style).not_to include("fx:")
  end
end
