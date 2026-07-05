# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::StartScreen::Component do
  let(:defaults) { { repo_url: "https://github.com/gmrdad82/pito", license_url: "https://www.gnu.org/licenses/agpl-3.0.html" } }

  describe "#initialize" do
    it "accepts repo_url and license_url" do
      expect(described_class.new(**defaults)).to be_a(described_class)
    end
  end

  describe "rendered output" do
    subject(:node) { render_inline(described_class.new(**defaults)) }

    it "renders the ASCII logo" do
      expect(node.css("pre.pito-start-screen__logo")).not_to be_empty
    end

    describe "logo broken-neon reveal (Q4)" do
      it "mounts the pito--logo-reveal controller on the logo <pre>" do
        pre = node.css("pre.pito-logo").first
        expect(pre).to be_present
        expect(pre["data-controller"]).to eq("pito--logo-reveal")
      end

      it "renders each glyph as its own .pito-logo__cell (blocks pito, connectors muted)" do
        cells = node.css(".pito-logo__cell")
        expect(cells.length).to be > 50 # ~120 non-space glyphs
        expect(cells.all? { |c| c.text.length == 1 && c.text != " " }).to be(true)
        blocks     = cells.select { |c| c.text == "█" }
        connectors = cells.reject { |c| c.text == "█" }
        expect(blocks).to all(satisfy { |c| c["class"].include?("text-pito") })
        expect(connectors).to all(satisfy { |c| c["class"].include?("text-fg-dim") })
      end

      it "preserves the exact art (per-glyph split did not corrupt alignment)" do
        expect(node.css("pre.pito-logo").first.text).to eq(described_class::LOGO_LINES.join("\n"))
      end
    end

    # G62: an open palette must OWN Enter on the start screen too — without the
    # suggestions keydown, a highlighted row under "/resu" submitted the raw
    # partial and the backend errored. Order is the contract (mirrors
    # chatbox_component.html.erb): suggestions FIRST so accepting a row
    # stopImmediatePropagation()s before home-transition/chat-form run; every
    # non-palette key (incl. "/login <code>" — palette closed at arg stage, and
    # exact-complete verbs, deliberately let through) still reaches
    # interceptEnter → chat-form untouched. chat-form must not be duplicated —
    # a past change doubled it and broke /login here.
    it "wires the palette keydown FIRST, then the home-transition Enter flow, unduplicated" do
      action = node.css("textarea").first["data-action"].to_s
      expect(action).to include("input->pito--suggestions#onInput")          # palette shows
      expect(action.index("keydown->pito--suggestions#handleKeydown"))
        .to be < action.index("keydown->pito--home-transition#interceptEnter")
      expect(action.index("keydown->pito--home-transition#interceptEnter"))
        .to be < action.index("keydown->pito--chat-form#handleKeydown")
      expect(action.scan("chat-form#handleKeydown").size).to eq(1)           # not duplicated
      expect(action.scan("suggestions#handleKeydown").size).to eq(1)
    end

    it "renders the tip prefix translation" do
      expect(node.to_html).to include("Tip")
    end

    it "renders a random tip from the dictionary" do
      tips = I18n.t("pito.copy.start_screen.tips")
      expect(tips).not_to be_empty
      expect(tips.any? { |tip| node.to_html.include?(tip) }).to be true
    end

    it "does not render the old placeholder text" do
      expect(node.to_html).not_to include("[placeholder for tips]")
    end

    it "preserves the tip colors (orange exclamation, yellow prefix, faded text)" do
      tip_html = node.css("[data-pito--home-transition-target='tip']").first.to_html
      expect(tip_html).to include("text-orange") # exclamation mark
      expect(tip_html).to include("text-yellow")  # "Tip" prefix
      expect(tip_html).to include("text-fg-faded") # body text
      expect(tip_html).to include("!") # ASCII exclamation mark
    end

    it "renders a full-viewport flex container" do
      expect(node.css("div.min-h-screen")).not_to be_empty
    end

    it "does not render a version string" do
      expect(node.to_html).not_to match(/v\d+\.\d+/)
    end
  end

  describe "bottom corner links" do
    subject(:node) { render_inline(described_class.new(**defaults)) }

    it "renders the repo link with the correct label" do
      link = node.css("a[href='https://github.com/gmrdad82/pito']").first
      expect(link).not_to be_nil
      expect(link.text.strip).to eq("GitHub Source")
    end

    it "renders the license link with the correct label" do
      link = node.css("a[href='https://www.gnu.org/licenses/agpl-3.0.html']").first
      expect(link).not_to be_nil
      expect(link.text.strip).to eq("AGPL-3.0")
    end

    it "opens corner links in a new tab" do
      links = node.css("[data-pito--home-transition-target='fadeOut'] a")
      links.each { |a| expect(a["target"]).to eq("_blank") }
    end
  end

  describe "mini status auth state" do
    context "when the session is absent (anonymous)" do
      before { allow(Current).to receive(:session).and_return(nil) }

      it "renders ● tarnished (red) in the start-mode mini status" do
        node = render_inline(described_class.new(**defaults))
        chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
        expect(chatbox_area.to_html).to include("● tarnished")
        expect(chatbox_area.css("span.text-red").map(&:text).join).to include("● tarnished")
      end

      it "does not render ■ gmrdad82 in the start-mode mini status" do
        node = render_inline(described_class.new(**defaults))
        chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
        expect(chatbox_area.to_html).not_to include("■ gmrdad82")
      end

      it "sets data-authenticated to false on chatboxArea" do
        node = render_inline(described_class.new(**defaults))
        chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
        expect(chatbox_area["data-authenticated"]).to eq("false")
      end
    end

    context "when the session is present (authenticated)" do
      let(:fake_session) { double("Session") }

      before { allow(Current).to receive(:session).and_return(fake_session) }

      it "renders ■ (green) in the start-mode mini status" do
        node = render_inline(described_class.new(**defaults))
        chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
        expect(chatbox_area.to_html).to include("■")
        expect(chatbox_area.css("span.pito-me-shimmer").map(&:text).join).to include("■")
      end

      it "does not render ● tarnished in the start-mode mini status" do
        node = render_inline(described_class.new(**defaults))
        chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
        expect(chatbox_area.to_html).not_to include("● tarnished")
      end

      it "sets data-authenticated to true on chatboxArea" do
        node = render_inline(described_class.new(**defaults))
        chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
        expect(chatbox_area["data-authenticated"]).to eq("true")
      end
    end
  end

  describe "home-transition wiring" do
    subject(:node) { render_inline(described_class.new(**defaults)) }

    it "mounts pito--home-transition on the outer wrapper" do
      expect(node.css("[data-controller='pito--home-transition']")).not_to be_empty
    end

    it "has a chatboxArea target" do
      expect(node.css("[data-pito--home-transition-target='chatboxArea']")).not_to be_empty
    end

    it "has named animation targets for tip and corners" do
      %w[tip corners].each do |target|
        expect(node.css("[data-pito--home-transition-target='#{target}']")).not_to be_empty,
          "expected a #{target} target"
      end
    end

    it "has logoRow targets for the per-row unstable dissolve" do
      rows = node.css("[data-pito--home-transition-target='logoRow']")
      expect(rows.length).to eq(6)
    end

    it "chatboxArea carries the width constraint directly (max-w-600)" do
      chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
      expect(chatbox_area["class"]).to include("max-w-[600px]")
    end

    it "mini-status is inside chatboxArea so it animates as one unit" do
      chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
      expect(chatbox_area.to_html).to include("● tarnished")
    end

    it "has a hidden conversationChrome target" do
      chrome = node.css("[data-pito--home-transition-target='conversationChrome']").first
      expect(chrome).not_to be_nil
      expect(chrome["style"]).to include("display:none")
    end

    it "has a miniStatusSlide target inside conversationChrome for the post-expand slide-in" do
      chrome = node.css("[data-pito--home-transition-target='conversationChrome']").first
      slide = chrome.css("[data-pito--home-transition-target='miniStatusSlide']").first
      expect(slide).not_to be_nil
      expect(slide["style"]).to include("margin-left: auto")
    end

    it "pre-renders the full mini status (with real notification count) in conversationChrome" do
      # The notification count only renders for an authenticated session.
      allow(Current).to receive(:session).and_return(double("Session"))
      create(:notification)
      create(:notification)
      # Re-render after creating 2 unread notifications so the count is real.
      chrome = render_inline(described_class.new(**defaults))
                 .css("[data-pito--home-transition-target='conversationChrome']").first
      expect(chrome.to_html).to include("2*")
    end
  end

  # ── SHOWCASE-START-NOTFOUND: auth-gated hints ────────────────────────────────
  # When suggestions are passed (authenticated path), the hints data script tag
  # carries the suggestions JSON, which pito--placeholder-rotate cycles through
  # the field's native placeholder. When suggestions is [] (unauthenticated
  # path), the script tag is empty and the native login hint shows.

  describe "showcase suggestions (SHOWCASE-START-NOTFOUND)" do
    let(:suggestions) { %w[list\ games show\ last\ vid list\ vids] }

    context "with suggestions (authenticated path)" do
      subject(:node) { render_inline(described_class.new(**defaults, suggestions: suggestions)) }

      it "embeds the suggestions in the #pito-showcase-data script tag" do
        script = node.css("script#pito-showcase-data").first
        expect(script).not_to be_nil
        parsed = JSON.parse(script.text)
        expect(parsed).to eq(suggestions)
      end

      it "renders the textarea with a non-empty sampled placeholder (rotated by placeholder-rotate)" do
        expect(node.css("textarea").first["placeholder"]).to be_present
      end
    end

    context "without suggestions (unauthenticated path, [])" do
      subject(:node) { render_inline(described_class.new(**defaults, suggestions: [])) }

      it "embeds an empty array in the #pito-showcase-data script tag" do
        script = node.css("script#pito-showcase-data").first
        expect(script).not_to be_nil
        parsed = JSON.parse(script.text)
        expect(parsed).to eq([])
      end

      it "renders the textarea with the login hint placeholder" do
        expect(node.css("textarea").first["placeholder"]).to include("/login")
      end
    end
  end

  describe "channels nil-safety (authenticated not-found path)" do
    # render_not_found renders this component with `channels: @channels`, which
    # is nil when before_actions (set_channels) didn't run — e.g. via
    # exceptions_app. Authenticated, the template builds a filter from
    # `@channels.any?`, which must not blow up (regression: 500 NoMethodError).
    before { allow(Current).to receive(:session).and_return(double("Session")) }

    it "renders without raising when channels is explicitly nil" do
      expect { render_inline(described_class.new(**defaults, channels: nil)) }
        .not_to raise_error
    end

    it "still renders the chatbox area" do
      node = render_inline(described_class.new(**defaults, channels: nil))
      expect(node.css("[data-pito--home-transition-target='chatboxArea']")).not_to be_empty
    end
  end
end
