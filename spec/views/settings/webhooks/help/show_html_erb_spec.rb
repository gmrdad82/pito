require "rails_helper"

# Phase 26 — 01d. The help-modal fragment view. The controller assigns
# `@provider` (the validated slug) and `@markdown` (the raw .md file
# contents); the template renders the Markdown via
# `ApplicationHelper#render_markdown` (Commonmarker, hardbreaks: true)
# and wraps the result in the layout's `<turbo-frame>` id so Turbo
# swaps it into the dialog.
RSpec.describe "settings/webhooks/help/show.html.erb", type: :view do
  describe "Slack guide" do
    before do
      assign(:provider, "slack")
      assign(:markdown,
        Rails.root.join("app", "views", "settings", "webhooks", "help", "slack.md").read)
      render template: "settings/webhooks/help/show", layout: false
    end

    it "renders the Slack heading as <h1>" do
      expect(rendered).to include("<h1>Slack webhook setup</h1>")
    end

    it "renders the four step <h2> headings" do
      expect(rendered).to include("Step 1")
      expect(rendered).to include("Step 2")
      expect(rendered).to include("Step 3")
      expect(rendered).to include("Step 4")
    end

    it "renders the indented code block for the webhook URL example" do
      # Markdown's four-space-indented `https://hooks.slack.com/...`
      # block becomes `<pre><code>` after rendering.
      expect(rendered).to include("<pre>")
      expect(rendered).to include("hooks.slack.com")
    end

    it "wraps content in the modal Turbo Frame" do
      expect(rendered).to include('id="webhook_help_modal_frame"')
    end

    it "carries the per-provider data attribute" do
      expect(rendered).to include('data-webhook-help="slack"')
    end
  end

  describe "Discord guide" do
    before do
      assign(:provider, "discord")
      assign(:markdown,
        Rails.root.join("app", "views", "settings", "webhooks", "help", "discord.md").read)
      render template: "settings/webhooks/help/show", layout: false
    end

    it "renders the Discord heading as <h1>" do
      expect(rendered).to include("<h1>Discord webhook setup</h1>")
    end

    it "renders the three step <h2> headings" do
      expect(rendered).to include("Step 1")
      expect(rendered).to include("Step 2")
      expect(rendered).to include("Step 3")
    end

    it "renders the indented code block for the webhook URL example" do
      expect(rendered).to include("<pre>")
      expect(rendered).to include("discord.com/api/webhooks")
    end

    it "carries the per-provider data attribute" do
      expect(rendered).to include('data-webhook-help="discord"')
    end
  end

  describe "Markdown source files" do
    it "ships the Slack guide as an on-disk `.md` file" do
      path = Rails.root.join("app", "views", "settings", "webhooks", "help", "slack.md")
      expect(path).to exist
      content = path.read
      # Key phrases the beginner-friendly contract requires.
      expect(content).to include("Create a Slack app")
      expect(content).to include("Add New Webhook to Workspace")
      expect(content).to include("hooks.slack.com")
    end

    it "ships the Discord guide as an on-disk `.md` file" do
      path = Rails.root.join("app", "views", "settings", "webhooks", "help", "discord.md")
      expect(path).to exist
      content = path.read
      expect(content).to include("Create the webhook")
      expect(content).to include("Copy Webhook URL")
      expect(content).to include("discord.com/api/webhooks")
    end
  end

  # Phase 26 — 01d acceptance: the spec mandates a Troubleshooting
  # section in each guide covering invalid-URL meaning, ping-failed
  # meaning, the channel-deleted scenario, and (Discord-only)
  # permission errors. These specs lock that surface in so guide
  # drift can't silently drop the safety-net.
  describe "Slack troubleshooting section" do
    before do
      assign(:provider, "slack")
      assign(:markdown,
        Rails.root.join("app", "views", "settings", "webhooks", "help", "slack.md").read)
      render template: "settings/webhooks/help/show", layout: false
    end

    it "renders a Troubleshooting heading" do
      expect(rendered).to include("Troubleshooting")
    end

    it "covers the invalid-URL error path" do
      expect(rendered).to include("URL invalid")
    end

    it "covers the ping-failed / channel-deleted error path" do
      expect(rendered).to include("test ping 404")
      expect(rendered).to match(/404|410|deleted/)
    end

    it "tells the reader how to start over" do
      expect(rendered).to match(/start over|clear the .*webhook URL/i)
    end
  end

  describe "Discord troubleshooting section" do
    before do
      assign(:provider, "discord")
      assign(:markdown,
        Rails.root.join("app", "views", "settings", "webhooks", "help", "discord.md").read)
      render template: "settings/webhooks/help/show", layout: false
    end

    it "renders a Troubleshooting heading" do
      expect(rendered).to include("Troubleshooting")
    end

    it "covers the invalid-URL error path" do
      expect(rendered).to include("URL invalid")
    end

    it "covers the ping-failed / channel-deleted error path" do
      expect(rendered).to include("test ping 404")
    end

    it "covers the Manage Webhooks permission error specific to Discord" do
      expect(rendered).to include("Manage Webhooks")
    end

    it "documents that both discord.com and discordapp.com hosts are accepted" do
      # Phase 26 — 01c's URL regex accepts both host forms; the guide
      # should call this out so beginners with the older URL don't
      # think they have a bad webhook.
      expect(rendered).to include("discordapp.com")
    end
  end

  # Polish 2026-05-11 (URL enrichment). Per user direction, both guides
  # should link to canonical Discord / Slack official docs at first
  # mention of each concept. Locking the canonical URLs in here so a
  # future content tweak can't silently drop them or swap to a
  # third-party blog.
  describe "Slack guide canonical URLs" do
    before do
      assign(:provider, "slack")
      assign(:markdown,
        Rails.root.join("app", "views", "settings", "webhooks", "help", "slack.md").read)
      render template: "settings/webhooks/help/show", layout: false
    end

    it "links to the Slack apps directory" do
      expect(rendered).to include("https://api.slack.com/apps")
    end
  end

  # 2026-05-16 polish — outbound-link safety. Per the pito hard rule
  # ("External links — new tab convention" in `docs/design.md`), any
  # link to a non-pito URL opens in a new tab and carries
  # `rel="noopener noreferrer"` so the destination can't reach back
  # into the opener window or learn the originating pito URL via the
  # Referer header. The help-modal view passes
  # `target_external_links: true` into `render_markdown` so every
  # `<a href="http(s)://...">` in the guides is rewritten.
  #
  # These specs lock the rewrite in for both providers and at the
  # representative anchor level — if a future change either drops the
  # `target_external_links:` flag at the view layer or alters the
  # renderer's anchor-decoration behavior, the suite goes red.
  describe "external link safety (new-tab + noopener noreferrer)" do
    # Only the Slack guide currently ships an outbound canonical-docs
    # anchor (`[Slack apps directory](https://api.slack.com/apps)`). The
    # Discord guide references URLs inside code blocks only, so there
    # are no `<a href>` elements to rewrite.
    %w[slack].each do |provider|
      context "for the #{provider} guide" do
        before do
          assign(:provider, provider)
          assign(:markdown,
            Rails.root.join("app", "views", "settings", "webhooks", "help", "#{provider}.md").read)
          render template: "settings/webhooks/help/show", layout: false
        end

        it "rewrites every absolute http(s) anchor to target=_blank" do
          doc = Nokogiri::HTML5.fragment(rendered)
          external_anchors = doc.css("a[href]").select do |a|
            a["href"].to_s.match?(/\Ahttps?:\/\//i)
          end
          # Guides ship at least one outbound canonical-docs link.
          expect(external_anchors).not_to be_empty
          external_anchors.each do |anchor|
            expect(anchor["target"]).to eq("_blank"),
              "expected target=_blank on #{anchor['href']}, got #{anchor['target'].inspect}"
            rel_tokens = anchor["rel"].to_s.split
            expect(rel_tokens).to include("noopener"),
              "expected rel to include 'noopener' on #{anchor['href']}, got #{anchor['rel'].inspect}"
            expect(rel_tokens).to include("noreferrer"),
              "expected rel to include 'noreferrer' on #{anchor['href']}, got #{anchor['rel'].inspect}"
          end
        end
      end
    end
  end

  describe "polish — no emoji + lowercase prose convention" do
    %w[slack discord].each do |provider|
      it "ships the #{provider} guide with no emoji glyphs" do
        path = Rails.root.join("app", "views", "settings", "webhooks", "help", "#{provider}.md")
        content = path.read
        # Emoji are blocked by the project copy convention. The
        # regex covers the Misc Symbols / Pictographs and Emoticons
        # ranges that cover ~99% of common emoji.
        emoji_re = /[\u{1F300}-\u{1F6FF}\u{1F900}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/
        expect(content).not_to match(emoji_re)
      end
    end
  end

  # FB-43 (2026-05-20). The help-modal fragment was previously wrapped
  # in a `Tui::FramedPanelComponent` with a brand-suffixed in-body title
  # (`webhook help — Slack` / `webhook help — Discord`) and a bottom
  # `[close]` muted bracketed link. Per FB-43 the dialog now adopts the
  # canonical `.tui-dialog-frame` pattern on the host `<dialog>` in
  # `shared/_webhook_help_modal.html.erb` (1px hairline + corner-flush
  # title + `[Esc] to close` hint at the top-right). The fragment
  # therefore renders ONLY the markdown content — no parallel framed
  # panel, no in-body header, no in-content [close] affordance.
  #
  # The per-brand identity is conveyed by the rendered `<h1>` ("Slack
  # webhook setup" / "Discord webhook setup"). Dismissal is via Esc
  # (native + Stimulus keydown guard) or backdrop click; the title-right
  # hint advertises that path.
  describe "FB-43 — canonical .tui-dialog-frame adoption (fragment renders markdown only)" do
    %w[slack discord].each do |provider|
      context "for the #{provider} guide" do
        before do
          assign(:provider, provider)
          assign(:markdown,
            Rails.root.join("app", "views", "settings", "webhooks", "help", "#{provider}.md").read)
          render template: "settings/webhooks/help/show", layout: false
        end

        it "does NOT wrap the body in a parallel `section.tui-framed-panel`" do
          expect(rendered).not_to have_css("section.tui-framed-panel")
        end

        it "does NOT render a brand-suffixed in-body header" do
          brand = provider == "discord" ? "Discord" : "Slack"
          expect(rendered).not_to include("webhook help — #{brand}")
        end

        it "does NOT render an in-content [close] muted bracketed link (dismissal lives in the dialog frame)" do
          expect(rendered).not_to have_css("a.bracketed.bracketed-muted-link span.bl", text: "close")
        end

        it "does NOT wire any element to the webhook-help-modal#close Stimulus action (single dismiss path = Esc / backdrop)" do
          expect(rendered).not_to match(
            /data-action="click-(?:&gt;|>)webhook-help-modal#close"/
          )
        end

        it "renders the markdown content wrapper directly inside the turbo frame" do
          expect(rendered).to have_css(
            "turbo-frame#webhook_help_modal_frame > div.webhook-help-content.markdown-body"
          )
        end
      end
    end
  end

  # Phase 26 — 01d (polish 2026-05-11). User feedback: "have better
  # spacing by having a clear row before each title… use some
  # horizontal lines… use tables when needed. Same goes for the Slack
  # one." The polish work rewrites the .md sources with `---`
  # separators between sections and tables in Troubleshooting /
  # Notifications behavior. These specs lock in the rendered HTML
  # so a future content tweak can't silently drop the structure.
  %w[slack discord].each do |provider|
    describe "#{provider} guide rendered structure" do
      before do
        assign(:provider, provider)
        assign(:markdown,
          Rails.root.join("app", "views", "settings", "webhooks", "help", "#{provider}.md").read)
        render template: "settings/webhooks/help/show", layout: false
      end

      it "renders `<hr>` separators between sections" do
        expect(rendered.scan(/<hr\s*\/?>/).size).to be >= 3
      end

      it "renders the troubleshooting matrix as a `<table>` with header cells" do
        expect(rendered).to include("<table>")
        expect(rendered).to include("<thead>")
        expect(rendered).to include("<th>Error</th>")
        expect(rendered).to include("<th>Fix</th>")
      end

      it "does NOT escape table tags (raw `&lt;table&gt;` would indicate a renderer regression)" do
        expect(rendered).not_to include("&lt;table&gt;")
      end

      it "renders code blocks for the webhook URL example without inline style" do
        expect(rendered).to include("<pre>")
        expect(rendered).not_to match(/<pre[^>]*style=/)
      end

      it "renders the Step headings as `<h2>` (so the CSS can space them out)" do
        expect(rendered).to match(/<h2>Step 1/)
      end
    end
  end
end
