# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::ChatboxComponent do
  describe "rendered output" do
    context "without a placeholder_key" do
      it "renders the chatbox-wrapper div" do
        node = render_inline(described_class.new)
        expect(node.css("div.chatbox-wrapper")).not_to be_empty
      end

      it "renders the textarea with the sampled auth hint (unauthenticated → login)" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea")
        expect(textarea).not_to be_empty
        expect(textarea.first["placeholder"]).to include("/login")
      end

      # The placeholder is always a real sampled hint — it is the field's initial
      # native placeholder, which pito--placeholder-rotate then cycles through the
      # command suggestions. (The normal native caret is fine over placeholder text.)
      context "suggestions present (placeholder-rotate active)" do
        let(:suggestions) { %w[list\ games show\ last\ vid list\ vids] }

        it "still renders the sampled hint placeholder (unauthenticated → login)" do
          node = render_inline(described_class.new(suggestions: suggestions))
          expect(node.css("textarea").first["placeholder"]).to include("/login")
        end

        it "renders a non-empty sampled placeholder with authenticated: true" do
          node = render_inline(described_class.new(authenticated: true, suggestions: suggestions))
          expect(node.css("textarea").first["placeholder"]).to be_present
        end
      end

      context "suggestions absent (unauthenticated path)" do
        it "renders the login hint placeholder when suggestions are empty" do
          node = render_inline(described_class.new(suggestions: []))
          expect(node.css("textarea").first["placeholder"]).to include("/login")
        end
      end

      it "wires the suggestions controller actions on the input by default" do
        action = render_inline(described_class.new).css("textarea").first["data-action"]
        expect(action).to include("input->pito--suggestions#onInput")
        expect(action).to include("keydown->pito--suggestions#handleKeydown")
      end
    end

    context "with a placeholder_key" do
      it "renders the textarea with the translated placeholder" do
        node = render_inline(described_class.new(placeholder_key: "pito.shell.chatbox.placeholder"))
        textarea = node.css("textarea")
        expect(textarea.first["placeholder"]).to include("Type a command or message")
      end
    end

    context "filter line (line 2)" do
      it "shows channel and period values when filter is given and state is :default" do
        node = render_inline(described_class.new(
          filter: { channel: "@gaming", period: "last 7d" }
        ))
        html = node.to_html
        expect(html).to include("@gaming")
        expect(html).to include("last 7d")
      end

      it "renders channel and period values inside shimmer spans" do
        node = render_inline(described_class.new(
          filter: { channel: "@sports", period: "30d" }
        ))
        shimmer_texts = node.css("span.pito-token-shimmer").map(&:text)
        expect(shimmer_texts).to include("@sports")
        expect(shimmer_texts).to include("30d")
      end

      it "renders 'none' in red when no channels are connected" do
        node = render_inline(described_class.new(
          filter: { channel: "none", period: "7d" }
        ))
        red = node.css("span.text-red").first
        expect(red).not_to be_nil
        expect(red.text).to eq("none")
      end

      it "drops the middot separators from the meta row (owner 2026-06-29, item 10)" do
        node = render_inline(described_class.new(
          filter: { channel: "@gaming", period: "7d" }
        ))
        dot_spans = node.css("span.text-fg-faded").select { |s| s.text.strip == "·" }
        expect(dot_spans).to be_empty
      end

      it "renders the `c to chat` hint (not the cyclers) when state is :start" do
        node = render_inline(described_class.new(
          state: :start,
          filter: { channel: "@gaming", period: "7d" }
        ))
        row = node.css(".pito-chatbox__filter")
        expect(row).not_to be_empty
        expect(node.to_html).to include("to chat")
        # No channel/period cyclers on the start row.
        expect(node.css('[data-pito--chatbox-hints-target="shiftTabHint"]')).to be_empty
        expect(node.css('[data-pito--chatbox-hints-target="shiftSpaceHint"]')).to be_empty
      end

      it "does NOT render the filter line when filter is nil" do
        node = render_inline(described_class.new(filter: nil))
        expect(node.css("span.pito-token-shimmer")).to be_empty
      end

      it "wraps the filter line with data-pito--chat-form-target attributes" do
        node = render_inline(described_class.new(
          filter: { channel: "@all", period: "7d" }
        ))
        expect(node.css('[data-pito--chat-form-target="channelDisplay"]')).not_to be_empty
        expect(node.css('[data-pito--chat-form-target="periodDisplay"]')).not_to be_empty
      end

      it "does NOT render 'Channel' or 'Period' as label words (removed in new design)" do
        node = render_inline(described_class.new(
          filter: { channel: "@all", period: "7d" }
        ))
        faded_texts = node.css("span.text-fg-faded").map(&:text)
        expect(faded_texts).not_to include("Channel")
        expect(faded_texts).not_to include("Period")
      end

      it "renders shift+tab and shift+space in bold yellow within the filter row" do
        node = render_inline(described_class.new(
          filter: { channel: "@all", period: "7d" }
        ))
        yellow_texts = node.css("span.font-bold.text-yellow").map(&:text)
        expect(yellow_texts).to include("shift+tab")
        expect(yellow_texts).to include("shift+space")
      end

      it "keeps a shimmer span inside channelDisplay for the cycling hook" do
        node = render_inline(described_class.new(
          filter: { channel: "@all", period: "7d" }
        ))
        channel_display = node.css('[data-pito--chat-form-target="channelDisplay"]').first
        expect(channel_display).not_to be_nil
        expect(channel_display.css("span.pito-token-shimmer").first).not_to be_nil
      end

      it "keeps a shimmer span inside periodDisplay for the cycling hook" do
        node = render_inline(described_class.new(
          filter: { channel: "@all", period: "7d" }
        ))
        period_display = node.css('[data-pito--chat-form-target="periodDisplay"]').first
        expect(period_display).not_to be_nil
        expect(period_display.css("span.pito-token-shimmer").first).not_to be_nil
      end

      it "renders the chatHint target wrapper hidden by default" do
        node = render_inline(described_class.new(
          filter: { channel: "@all", period: "7d" }
        ))
        chat = node.css('[data-pito--chatbox-hints-target="chatHint"]').first
        expect(chat).not_to be_nil
        expect(chat["class"]).to include("hidden")
        expect(chat.to_html).to include(">c<")
        expect(chat.to_html).to include("chat")
      end
    end

    context "conversation_title (purple name in filter row)" do
      it "renders the conversation name in purple when conversation_title is present" do
        node = render_inline(described_class.new(
          filter:             { channel: "@all", period: "7d" },
          conversation_title: "My Gaming Session"
        ))
        purple_span = node.css("span.text-purple").first
        expect(purple_span).not_to be_nil
        expect(purple_span.text).to eq("My Gaming Session")
      end

      it "does NOT render a purple name span when conversation_title is nil" do
        node = render_inline(described_class.new(
          filter:             { channel: "@all", period: "7d" },
          conversation_title: nil
        ))
        expect(node.css("span.text-purple")).to be_empty
      end

      it "does NOT render a purple name span when conversation_title is blank" do
        node = render_inline(described_class.new(
          filter:             { channel: "@all", period: "7d" },
          conversation_title: "   "
        ))
        expect(node.css("span.text-purple")).to be_empty
      end

      it "renders NO separator after the title (middots dropped — owner 2026-06-29, item 10)" do
        node = render_inline(described_class.new(
          filter:             { channel: "@all", period: "7d" },
          conversation_title: "My Chat"
        ))
        html = node.to_html
        expect(html).to include("My Chat")
        expect(html).to include("channelDisplay")
        expect(html).not_to include("·")
      end
    end

    context "hidden inputs" do
      it "renders hidden inputs for channel and period when filter is given" do
        node = render_inline(described_class.new(
          filter: { channel: "@all", period: "7d" }
        ))
        channel_input = node.css('input[name="channel"]').first
        period_input = node.css('input[name="period"]').first
        expect(channel_input).not_to be_nil
        expect(channel_input["value"]).to eq("@all")
        expect(channel_input["data-pito--chat-form-target"]).to eq("channelInput")
        expect(period_input).not_to be_nil
        expect(period_input["value"]).to eq("7d")
        expect(period_input["data-pito--chat-form-target"]).to eq("periodInput")
      end

      it "does NOT render hidden inputs when filter is nil" do
        node = render_inline(described_class.new(filter: nil))
        expect(node.css('input[name="channel"]')).to be_empty
        expect(node.css('input[name="period"]')).to be_empty
      end

      it "renders hidden inputs even when state is :start" do
        node = render_inline(described_class.new(
          state: :start,
          filter: { channel: "@all", period: "7d" }
        ))
        expect(node.css('input[name="channel"]')).not_to be_empty
        expect(node.css('input[name="period"]')).not_to be_empty
      end
    end

    context "input_data attributes" do
      it "merges custom data attributes onto the textarea" do
        node = render_inline(described_class.new(
          input_data: { pito__chat_form_target: "inputField" }
        ))
        textarea = node.css("textarea").first
        expect(textarea["data-pito--chat-form-target"]).to eq("inputField")
      end
    end

    context "structural checks" do
      it "renders a flex column wrapper for the two-line layout" do
        node = render_inline(described_class.new)
        expect(node.css("div.flex.flex-col")).not_to be_empty
      end

      it "renders the field-wrap div with the autosize Stimulus controller (+ autofocus)" do
        node = render_inline(described_class.new)
        field_wrap = node.css("div.pito-chatbox__field-wrap").first
        expect(field_wrap).not_to be_nil
        expect(field_wrap["data-controller"]).to include("pito--autosize")
        expect(field_wrap["data-pito--autosize-autofocus-value"]).to eq("true")
      end

      it "renders the field-wrap div with the type-fx Stimulus controller" do
        node = render_inline(described_class.new)
        field_wrap = node.css("div.pito-chatbox__field-wrap").first
        expect(field_wrap).not_to be_nil
        expect(field_wrap["data-controller"]).to include("pito--type-fx")
      end

      it "renders the textarea with the type-fx field target" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea[data-pito--type-fx-target='field']").first
        expect(textarea).not_to be_nil
      end

      it "renders the textarea with the autosize field target" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea[data-pito--autosize-target='field']").first
        expect(textarea).not_to be_nil
      end

      it "uses the normal native caret on the textarea (no block-caret)" do
        node = render_inline(described_class.new)
        expect(node.css("textarea.pito-block-caret")).to be_empty
        expect(node.css("textarea.pito-chatbox__input")).not_to be_empty
      end

      it "renders no bespoke caret/trail machinery in the chatbox" do
        node = render_inline(described_class.new)
        expect(node.css("[data-controller~='pito--terminal-caret']")).to be_empty
        expect(node.css("[data-controller~='pito--cursor-trail']")).to be_empty
        expect(node.css("span.terminal-caret")).to be_empty
        expect(node.css("[data-pito--terminal-caret-target]")).to be_empty
        expect(node.css("span.pito-cursor")).to be_empty
      end
    end

    context "suggestions integration" do
      it "renders #pito-chatbox with the pito--suggestions Stimulus controller" do
        node = render_inline(described_class.new)
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper).not_to be_nil
        expect(wrapper["data-controller"]).to include("pito--suggestions")
      end

      it "renders #pito-chatbox with the pito--chatbox-hints Stimulus controller" do
        node = render_inline(described_class.new)
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper).not_to be_nil
        expect(wrapper["data-controller"]).to include("pito--chatbox-hints")
      end

      it "contains a catalog script tag with parseable JSON including slash and vocabularies keys" do
        node = render_inline(described_class.new)
        script = node.css("script[type='application/json'][data-pito--suggestions-target='catalog']").first
        expect(script).not_to be_nil
        catalog = JSON.parse(script.text)
        expect(catalog).to have_key("slash")
        expect(catalog).to have_key("vocabularies")
      end

      context "authenticated: false" do
        it "embeds a catalog whose slash list includes /login" do
          node = render_inline(described_class.new(authenticated: false))
          script = node.css("script[type='application/json'][data-pito--suggestions-target='catalog']").first
          catalog = JSON.parse(script.text)
          slash_inserts = catalog["slash"].map { |e| e["insert"] }
          expect(slash_inserts).to include("/login ")
        end
      end

      context "authenticated: true" do
        it "embeds a catalog whose slash list includes /config" do
          node = render_inline(described_class.new(authenticated: true))
          script = node.css("script[type='application/json'][data-pito--suggestions-target='catalog']").first
          catalog = JSON.parse(script.text)
          slash_inserts = catalog["slash"].map { |e| e["insert"] }
          expect(slash_inserts).to include("/config ")
        end
      end

      it "contains the hidden palette container with the correct target and classes" do
        node = render_inline(described_class.new)
        palette = node.css("div.pito-suggestions-palette[data-pito--suggestions-target='palette']").first
        expect(palette).not_to be_nil
        expect(palette["class"]).to include("hidden")
      end

      it "renders the textarea with the suggestions field target" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea[data-pito--suggestions-target='field']").first
        expect(textarea).not_to be_nil
      end

      it "renders the textarea data-action with suggestions keydown first" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea").first
        action = textarea["data-action"]
        expect(action).to start_with("keydown->pito--suggestions#handleKeydown")
        expect(action).to include("keydown->pito--chat-form#handleKeydown")
        expect(action).to include("input->pito--suggestions#onInput")
      end
    end

    # ── initial_value + draft_uuid ─────────────────────────────────────────────

    context "initial_value param" do
      it "renders the given value in the textarea" do
        node = render_inline(described_class.new(initial_value: "my draft text"))
        textarea = node.css("textarea").first
        expect(textarea.text).to include("my draft text")
      end

      it "renders an empty textarea by default" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea").first
        expect(textarea.text.strip).to eq("")
      end
    end

    context "draft_uuid param" do
      it "adds pito--draft to data-controller when draft_uuid is present" do
        node = render_inline(described_class.new(draft_uuid: "some-uuid-1234"))
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).to include("pito--draft")
      end

      it "adds the uuid as data-pito--draft-uuid-value when draft_uuid is present" do
        node = render_inline(described_class.new(draft_uuid: "some-uuid-1234"))
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-pito--draft-uuid-value"]).to eq("some-uuid-1234")
      end

      it "does NOT add pito--draft when draft_uuid is nil" do
        node = render_inline(described_class.new(draft_uuid: nil))
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).not_to include("pito--draft")
      end

      it "does NOT add the uuid value attribute when draft_uuid is nil" do
        node = render_inline(described_class.new(draft_uuid: nil))
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-pito--draft-uuid-value"]).to be_nil
      end

      it "still includes pito--suggestions in data-controller with draft_uuid" do
        node = render_inline(described_class.new(draft_uuid: "abc-123"))
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).to include("pito--suggestions")
      end
    end

    # ── Reduced mode (share pages) ────────────────────────────────────────────

    context "reduced: true (share page affordance)" do
      subject(:node) { render_inline(described_class.new(reduced: true)) }

      it "does NOT render the suggestions catalog script tag" do
        scripts = node.css("script[data-pito--suggestions-target='catalog']")
        expect(scripts).to be_empty
      end

      it "does NOT render the showcase data script tag" do
        scripts = node.css("script#pito-showcase-data")
        expect(scripts).to be_empty
      end

      it "does NOT render the suggestions palette div" do
        expect(node.css("div.pito-suggestions-palette")).to be_empty
      end

      it "does NOT include pito--suggestions in the chatbox controller list" do
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).not_to include("pito--suggestions")
      end

      it "does NOT include pito--chatbox-hints in the chatbox controller list" do
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).not_to include("pito--chatbox-hints")
      end

      it "does NOT include pito--history in the chatbox controller list" do
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).not_to include("pito--history")
      end

      it "does NOT include pito--placeholder-rotate in the chatbox controller list" do
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"].to_s).not_to include("pito--placeholder-rotate")
      end

      it "does NOT include pito--draft in the chatbox controller list (even if draft_uuid were passed)" do
        node2 = render_inline(described_class.new(reduced: true, draft_uuid: "some-uuid"))
        wrapper = node2.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).not_to include("pito--draft")
      end

      it "includes pito--autosize in the chatbox field-wrap controller list" do
        field_wrap = node.css("div.pito-chatbox__field-wrap").first
        expect(field_wrap["data-controller"]).to include("pito--autosize")
      end

      it "includes pito--type-fx in the chatbox field-wrap controller list" do
        field_wrap = node.css("div.pito-chatbox__field-wrap").first
        expect(field_wrap["data-controller"]).to include("pito--type-fx")
      end

      it "renders no bespoke caret/trail machinery" do
        expect(node.css("[data-controller~='pito--terminal-caret']")).to be_empty
        expect(node.css("[data-controller~='pito--cursor-trail']")).to be_empty
        expect(node.css("span.terminal-caret")).to be_empty
      end

      it "does NOT render the showcase ghost div" do
        expect(node.css("div.pito-showcase-ghost")).to be_empty
      end

      it "renders the `c to chat` hint (not the channel/period cyclers) in reduced mode" do
        node2 = render_inline(described_class.new(reduced: true, filter: { channel: "@all", period: "7d" }))
        # The reduced/share row shows only the always-on `c to chat` hint — no cyclers.
        expect(node2.css('[data-pito--chatbox-hints-target="shiftTabHint"]')).to be_empty
        expect(node2.css('[data-pito--chatbox-hints-target="shiftSpaceHint"]')).to be_empty
        expect(node2.css("span.pito-token-shimmer")).to be_empty
      end

      it "does NOT carry suggestions-related data actions on the textarea" do
        textarea = node.css("textarea").first
        action = textarea["data-action"]
        expect(action.to_s).not_to include("pito--suggestions")
      end

      it "still renders the autosize target on the textarea" do
        textarea = node.css("textarea[data-pito--autosize-target='field']").first
        expect(textarea).not_to be_nil
      end

      it "still renders the type-fx target on the textarea" do
        textarea = node.css("textarea[data-pito--type-fx-target='field']").first
        expect(textarea).not_to be_nil
      end

      it "still renders the chatbox-wrapper div" do
        expect(node.css("div.chatbox-wrapper")).not_to be_empty
      end
    end

    context "reduced: false (default, full-featured mode)" do
      subject(:node) { render_inline(described_class.new(reduced: false)) }

      it "renders the catalog script tag" do
        expect(node.css("script[data-pito--suggestions-target='catalog']")).not_to be_empty
      end

      it "renders the suggestions palette" do
        expect(node.css("div.pito-suggestions-palette")).not_to be_empty
      end

      it "includes pito--suggestions in the chatbox controller list" do
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).to include("pito--suggestions")
      end

      it "renders the placeholder-rotate hints data script" do
        expect(node.css("script#pito-showcase-data[data-pito--placeholder-rotate-target='data']")).not_to be_empty
      end

      it "includes pito--placeholder-rotate in the chatbox controller list" do
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).to include("pito--placeholder-rotate")
      end
    end

    # ── Input history (up/down) ────────────────────────────────────────────────

    context "history param" do
      it "always mounts pito--history on #pito-chatbox" do
        node = render_inline(described_class.new)
        wrapper = node.css("div#pito-chatbox").first
        expect(wrapper["data-controller"]).to include("pito--history")
      end

      it "encodes an empty JSON array when history is omitted" do
        node = render_inline(described_class.new)
        wrapper = node.css("div#pito-chatbox").first
        raw = wrapper["data-pito--history-entries-value"]
        expect(JSON.parse(raw)).to eq([])
      end

      it "encodes the given history array as JSON in data-pito--history-entries-value" do
        history = [ "/help", "what is my top channel?", "/config sound off" ]
        node = render_inline(described_class.new(history: history))
        wrapper = node.css("div#pito-chatbox").first
        raw = wrapper["data-pito--history-entries-value"]
        expect(JSON.parse(raw)).to eq(history)
      end

      it "still renders an empty JSON array on the start screen (no history passed)" do
        node = render_inline(described_class.new(state: :start))
        wrapper = node.css("div#pito-chatbox").first
        raw = wrapper["data-pito--history-entries-value"]
        expect(JSON.parse(raw)).to eq([])
      end
    end
  end
end
