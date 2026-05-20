require "rails_helper"

# Phase 7.5 — Step 04. Layout-level integration. The keyboard
# controller is mounted on `<body>` for the full page lifetime; this
# spec locks the layout contract the controller depends on AND the
# downstream data-attribute hooks the controller queries on filter
# chips, detail pages, and the confirmation page.
#
# 2026-05-16 — the `?` keyboard-shortcuts help modal was retired.
# The leader-menu popup (SPACE keypress + `[_]` navbar link, relocated
# from the footer to the header on 2026-05-18 immediately after
# `[settings]`) is the sole keyboard-discovery surface now. This spec
# was trimmed to match — modal-rendering assertions are gone; the
# broader keyboard-hook assertions stay.
RSpec.describe "Keyboard shortcuts layout integration", type: :request do
  describe "every page" do
    # `/saved_views` HTML redirects to /channels (CLI-only JSON endpoint),
    # so it is not exercised here. The chrome we're testing renders on
    # the destination /channels page already.
    %w[/ /channels /videos /settings].each do |path|
      it "GET #{path} mounts data-controller=\"keyboard\" on the body" do
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to match(/<body[^>]*data-controller="[^"]*\bkeyboard\b[^"]*"/)
      end

      it "GET #{path} renders the new Tui::TopStatusBarComponent inside the header" do
        get path
        # Beta 4 — Phase F1 Lane D (2026-05-20). The visible `[_]`
        # bracketed link inside the navbar was dropped along with the
        # bracketed-nav layout. The leader menu is still reachable via
        # the SPACE keypress (the `leader-menu` controller mounted on
        # `<body>` registers a document keydown listener — covered by
        # the leader_menu_layout_spec). The header now hosts the
        # `Tui::TopStatusBarComponent`; this assertion locks the new
        # shape so we don't regress to the bracketed-nav structure.
        header = response.body.match(%r{<header\b.*?</header>}m)
        expect(header).not_to be_nil, "expected to find <header>...</header> in the response"
        expect(header[0]).to include('class="sb-bar"')
        expect(header[0]).to include('data-controller="tui-status-bar"')
      end

      it "GET #{path} does NOT wire the retired keyboard#openHelp action anywhere" do
        # 2026-05-16 — the `?` keyboard-shortcuts help modal was
        # retired alongside its component, dialog target, and the
        # `[_]` link's chained `keyboard#openHelp` action. No page
        # in the layout should still wire the dropped action.
        get path
        expect(response.body).not_to include("keyboard#openHelp")
        expect(response.body).not_to include("keyboard#close")
        expect(response.body).not_to include("keyboard#clickOutside")
        expect(response.body).not_to include("data-keyboard-target=\"dialog\"")
      end

      it "GET #{path} does not introduce data-turbo-confirm anywhere" do
        get path
        expect(response.body).not_to include("data-turbo-confirm")
      end

      # Phase 29 (settings refactor) — keyboard navigation is always
      # on. The install-level master toggle pane was dropped along
      # with the UI/UX settings pane; the layout no longer emits the
      # `data-keyboard-navigation-enabled` attribute and the Stimulus
      # controller registers its keydown listener unconditionally.
      it "GET #{path} does NOT render the dropped data-keyboard-navigation-enabled attribute" do
        get path
        expect(response.body).not_to include("data-keyboard-navigation-enabled")
      end
    end
  end

  describe "footer nav links are pure navigation (Bug 2 — 2026-05-16)" do
    # The footer nav links (home / calendar / channels / videos /
    # projects / games) must navigate ONLY — they must never carry a
    # modal-trigger `data-action` that would open the (now-retired)
    # keyboard-shortcuts help modal or any other layout dialog. The
    # one exception is the `[notifications]` link which intentionally
    # opens the layout-level notifications modal; we exclude it from
    # the assertion below.
    it "renders home / calendar / channels / videos / projects / games as plain link_to (no data-action)" do
      get "/"
      doc = Nokogiri::HTML(response.body)
      footer = doc.at_css("footer")
      expect(footer).not_to be_nil

      pure_nav_labels = %w[home calendar channels videos projects games]
      pure_nav_labels.each do |label|
        link = footer.at_xpath(".//a[contains(@class, 'bracketed')][.//span[normalize-space(text())='#{label}']]")
        # Either the link is rendered (inactive page) or the label is
        # the current page and rendered as a non-link `<span>`. When
        # the link is rendered, it must have no `data-action`.
        next if link.nil?
        expect(link["data-action"]).to be_nil, "footer [#{label}] link should not carry data-action (found: #{link['data-action'].inspect})"
      end
    end
  end

  describe "filter chips on /channels carry the keyboard hook" do
    it "tags the starred chip with data-keyboard-filter-chip" do
      get "/channels"
      expect(response.body).to include('data-keyboard-filter-chip="starred"')
      # The `connected` filter chip was retired alongside the derived
      # connected display surface.
      expect(response.body).not_to include('data-keyboard-filter-chip="connected"')
    end
  end

  describe "channel detail page exposes data-keyboard-external-url" do
    let(:channel_url) { "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv" }

    it "carries the channel's URL on the page so `v` opens it in a new tab" do
      channel = Channel.create!(channel_url: channel_url)
      get channel_path(channel)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-keyboard-external-url="#{channel_url}"))
    end
  end

  describe "action confirmation page wires the form for `y` confirm and Esc cancel" do
    let(:channel_url) { "https://www.youtube.com/channel/UCzyxwvutsrqponmlkjihgfe" }

    it "tags the form and the cancel link on /deletions/:type/:ids" do
      channel = Channel.create!(channel_url: channel_url)
      get "/deletions/channel/#{channel.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/<form[^>]*data-keyboard-confirmation="true"/)
      expect(response.body).to include('data-keyboard-confirmation-cancel="true"')
    end
  end
end
