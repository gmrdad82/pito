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

      it "renders a muted separator dot between channel and period groups" do
        node = render_inline(described_class.new(
          filter: { channel: "@gaming", period: "7d" }
        ))
        dot_spans = node.css("span.text-fg-faded").select { |s| s.text.strip == "·" }
        expect(dot_spans).not_to be_empty
      end

      it "does NOT render the visible filter line when state is :start" do
        node = render_inline(described_class.new(
          state: :start,
          filter: { channel: "@gaming", period: "7d" }
        ))
        expect(node.css(".pito-chatbox__filter")).to be_empty
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

      it "renders the suggestHint target wrapper hidden by default" do
        node = render_inline(described_class.new(
          filter: { channel: "@all", period: "7d" }
        ))
        suggest = node.css('[data-pito--chatbox-hints-target="suggestHint"]').first
        expect(suggest).not_to be_nil
        expect(suggest["class"]).to include("hidden")
        expect(suggest.to_html).to include("tab")
        expect(suggest.to_html).to include("suggest")
      end

      it "renders the chatHint target wrapper hidden by default" do
        node = render_inline(described_class.new(
          filter: { channel: "@all", period: "7d" }
        ))
        chat = node.css('[data-pito--chatbox-hints-target="chatHint"]').first
        expect(chat).not_to be_nil
        expect(chat["class"]).to include("hidden")
        expect(chat.to_html).to include(">m<")
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

      it "renders a separator after the title and before the channel display" do
        node = render_inline(described_class.new(
          filter:             { channel: "@all", period: "7d" },
          conversation_title: "My Chat"
        ))
        html = node.to_html
        title_idx    = html.index("My Chat")
        channel_idx  = html.index("channelDisplay")
        expect(title_idx).not_to be_nil
        expect(channel_idx).not_to be_nil
        # Separator (·) must appear between title and channel display
        separator_idx = html.index("·", title_idx)
        expect(separator_idx).not_to be_nil
        expect(separator_idx).to be < channel_idx
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

      it "renders the field-wrap div with the terminal-caret Stimulus controller" do
        node = render_inline(described_class.new)
        field_wrap = node.css("div.pito-chatbox__field-wrap").first
        expect(field_wrap).not_to be_nil
        expect(field_wrap["data-controller"]).to include("pito--terminal-caret")
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

      it "renders the textarea with the terminal-caret field target" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea[data-pito--terminal-caret-target='field']").first
        expect(textarea).not_to be_nil
      end

      it "renders the terminal-caret span with the block target" do
        node = render_inline(described_class.new)
        caret = node.css("span.terminal-caret[data-pito--terminal-caret-target='block']").first
        expect(caret).not_to be_nil
      end

      it "does not render a pito-cursor span in the chatbox" do
        node = render_inline(described_class.new)
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
