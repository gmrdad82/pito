# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::RefreshNudgeComponent, type: :component do
  before { allow(Current).to receive(:session).and_return(double("Session")) }

  # The layout must stay free of scrollback-shaped markup for anonymous
  # visitors (the conversations_spec anonymous-leak guard counts .pito-turn).
  it "renders nothing for an anonymous session" do
    allow(Current).to receive(:session).and_return(nil)
    expect(render_inline(described_class.new).to_html.strip).to be_empty
  end

  it "renders an inert <template> with the stable id the cable-health clone targets" do
    node = render_inline(described_class.new)
    expect(node.css("template#pito-refresh-nudge")).not_to be_empty
  end

  # G71: the nudge is chrome, not a message — yellow bar to spot it, nothing
  # to reply to or share (no handle can exist; it is never persisted).
  it "wears the yellow segment accent inside the template" do
    node = render_inline(described_class.new)
    template = node.css("template#pito-refresh-nudge").first
    expect(template.inner_html).to include('data-accent="yellow"')
  end

  # The clone lands as a DIRECT scrollback child — without the .pito-turn
  # wrapper it sprawls the full viewport instead of centering in the column.
  it "wraps the segment in a .pito-turn so the clone centers like any message" do
    node = render_inline(described_class.new)
    template = node.css("template#pito-refresh-nudge").first
    expect(template.inner_html).to match(/<div class="pito-turn[ "]/)
  end

  it "resolves the copy with the reload combo interpolated (no leftover placeholder)" do
    node = render_inline(described_class.new)
    inner = node.css("template#pito-refresh-nudge").first.inner_html
    expect(inner).not_to include("%{combo}")
    expect(inner).to include("Ctrl+R").or include("⌘R")
  end

  describe "the OS-aware combo" do
    it "offers Ctrl+R (or F5) to non-Mac visitors" do
      vc_test_request.env["HTTP_USER_AGENT"] = "Mozilla/5.0 (X11; Linux x86_64)"
      component = described_class.new
      render_inline(component)
      expect(component.combo).to eq("Ctrl+R (or F5)")
    end

    it "offers ⌘R to Macs" do
      vc_test_request.env["HTTP_USER_AGENT"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
      component = described_class.new
      render_inline(component)
      expect(component.combo).to eq("⌘R")
    end

    # G73: touch devices (the Android shell included — no keyboard, no refresh
    # button) are pointed at the nudge itself, which is tappable.
    it "offers 'Tap here' to Android — including the Hotwire Native shell" do
      vc_test_request.env["HTTP_USER_AGENT"] =
        "Mozilla/5.0 (Linux; Android 14) PITO; v1.0.0; Hotwire Native Android"
      component = described_class.new
      render_inline(component)
      expect(component.combo).to eq("Tap here")
    end
  end

  # G73: the whole nudge is the reload button — yellow is the action class.
  describe "tappability (G73)" do
    it "wires the pito--refresh-nudge controller with a click reload action" do
      node = render_inline(described_class.new)
      inner = node.css("template#pito-refresh-nudge").first.inner_html
      expect(inner).to include('data-controller="pito--refresh-nudge"')
      expect(inner).to include('data-action="click-&gt;pito--refresh-nudge#reload"')
        .or include('data-action="click->pito--refresh-nudge#reload"')
    end

    it "shows the pointer cursor on the clone" do
      node = render_inline(described_class.new)
      expect(node.css("template#pito-refresh-nudge").first.inner_html).to include("cursor-pointer")
    end
  end
end
