# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::SystemComponent do
  describe "typewriter hook — plain-text body" do
    subject(:node) { render_inline(described_class.new(payload: { body: "Hello world" })) }

    it "wraps content in a div with data-controller='pito--typewriter'" do
      wrapper = node.css("div[data-controller~='pito--typewriter']").first
      expect(wrapper).not_to be_nil
    end

    it "sets data-pito--typewriter-target='body' on the body span inside the wrapper" do
      span = node.css("[data-controller~='pito--typewriter'] span[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
    end

    it "includes the body text in the body span" do
      span = node.css("span.text-fg[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
      expect(span.text).to include("Hello world")
    end
  end

  describe "typewriter hook — html body (html: true)" do
    subject(:node) { render_inline(described_class.new(payload: { body: "<b>bold</b>", html: true })) }

    it "does NOT add the typewriter controller when body is html" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end

    it "renders the raw html in a plain text-fg span" do
      span = node.css("span.text-fg").first
      expect(span).not_to be_nil
    end
  end

  describe "typewriter hook — empty body" do
    subject(:node) { render_inline(described_class.new(payload: { body: nil })) }

    it "does NOT add the typewriter controller when body is nil" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "typewriter hook — table_rows with plain-text body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Result",
        table_rows: [ { key: "Status", value: "OK" } ]
      }))
    end

    it "includes kv key span tagged as prose target inside the typewriter wrapper" do
      wrapper = node.css("div[data-controller~='pito--typewriter']").first
      expect(wrapper).not_to be_nil
      key_span = wrapper.css("span[data-pito--typewriter-target='prose']").first
      expect(key_span).not_to be_nil
    end

    it "key and value spans are both tagged as prose targets" do
      prose_spans = node.css("span[data-pito--typewriter-target='prose']")
      texts = prose_spans.map(&:text)
      expect(texts).to include("Status")
      expect(texts).to include("OK")
    end
  end

  describe "sections mode — plain-text body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Sections body text",
        sections: [ { title: "Section 1", rows: [] } ]
      }))
    end

    it "adds pito--typewriter controller to the prose wrapper div in sections mode" do
      wrapper = node.css("div[data-controller~='pito--typewriter']").first
      expect(wrapper).not_to be_nil
      span = wrapper.css("span[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
      expect(span.text).to include("Sections body text")
    end

    it "tags section header as a prose target" do
      header = node.css("[data-pito--typewriter-target='prose']").first
      expect(header).not_to be_nil
    end
  end

  describe "sections mode — section rows tagged as prose targets" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Help",
        sections: [ {
          title: "Navigation",
          rows: [ { key: "ctrl+l", value: "focus input" } ]
        } ]
      }))
    end

    it "tags section row key span as prose target" do
      key_span = node.css("span[data-pito--typewriter-target='prose']").first
      expect(key_span).not_to be_nil
      expect(key_span.text).to eq("ctrl+l")
    end

    it "tags section row value span as prose target" do
      value_span = node.css("span[data-pito--typewriter-target='prose']").last
      expect(value_span).not_to be_nil
      expect(value_span.text).to eq("focus input")
    end
  end

  describe "sections mode — html body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "<em>rich</em>",
        html: true,
        sections: [ { title: "Section 1", rows: [] } ]
      }))
    end

    it "does NOT add typewriter controller in sections mode when html" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "SystemFollowUpComponent (inherits system template via enhanced)" do
    it "renders pito--typewriter on plain-text body" do
      node = render_inline(Pito::Event::SystemFollowUpComponent.new(payload: { body: "Follow up text" }))
      expect(node.css("[data-controller~='pito--typewriter']")).not_to be_empty
    end
  end

  # ── T15.4: dom_id — generalized to reply_handle (follow-up engine) ──────────

  describe "dom_id — id on root Segment for follow-up-able messages" do
    let(:conversation) { Conversation.create! }
    let(:turn) { create(:turn, conversation:) }

    it "renders id='event_<id>' when payload has reply_handle present" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: { "reply_handle" => "beta-1234", "reply_target" => "theme_list", "body" => "Pick a theme" })
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      segment = node.css(".pito-segment").first
      expect(segment).not_to be_nil
      expect(segment["id"]).to eq("event_#{event.id}")
    end

    it "renders id='event_<id>' when payload has theme_diff: true (backward compat)" do
      diff_event = create(:event, conversation:, turn:, kind: "theme_diff", position: 2,
                          payload: { "theme_diff" => true, "phase" => "apply", "body" => "Done!" })
      node = render_inline(described_class.new(payload: diff_event.payload.with_indifferent_access, event: diff_event))
      segment = node.css(".pito-segment").first
      expect(segment["id"]).to eq("event_#{diff_event.id}")
    end

    it "does NOT render an id for a plain system message (no reply_handle or theme_diff)" do
      plain_event = create(:event, conversation:, turn:, kind: "system", position: 3,
                           payload: { "body" => "Regular system message" })
      node = render_inline(described_class.new(payload: plain_event.payload.with_indifferent_access, event: plain_event))
      segment = node.css(".pito-segment").first
      expect(segment["id"]).to be_nil
    end

    it "does NOT render an id when event is nil even if payload has reply_handle" do
      node = render_inline(described_class.new(payload: { reply_handle: "beta-1234", body: "Pick" }, event: nil))
      segment = node.css(".pito-segment").first
      expect(segment["id"]).to be_nil
    end
  end

  # ── T15.3: affordance rendered for follow-up-able system messages ─────────────

  describe "follow-up affordance" do
    let(:conversation) { Conversation.create! }
    let(:turn) { create(:turn, conversation:) }

    it "renders the affordance when payload has reply_handle + reply_target" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: {
                       "reply_handle" => "beta-1234",
                       "reply_target" => "theme_list",
                       "body" => "Pick a theme",
                       "sections" => []
                     })
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      expect(node.text).to include("beta-1234")
    end

    it "does NOT render the affordance when reply_consumed is true" do
      event = create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: {
                       "reply_handle"   => "beta-1234",
                       "reply_target"   => "theme_list",
                       "reply_consumed" => true,
                       "body"           => "Consumed message"
                     })
      node = render_inline(described_class.new(payload: event.payload.with_indifferent_access, event:))
      # The affordance should not render (followupable? is false)
      expect(node.css("div.mt-1.text-fg-faded")).to be_empty
    end

    it "does NOT render the affordance for plain system messages" do
      node = render_inline(described_class.new(payload: { body: "Regular system message" }))
      expect(node.css("div.mt-1.text-fg-faded")).to be_empty
    end
  end
end
