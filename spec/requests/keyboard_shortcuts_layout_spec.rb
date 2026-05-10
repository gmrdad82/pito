require "rails_helper"

# Phase 7.5 — Step 04. Layout-level integration. The keyboard
# controller is mounted on `<body>` for the full page lifetime, the
# help dialog renders once in the layout, and a `[?]` bracketed
# link sits in the header chrome so the surface is discoverable
# without keyboard knowledge.
#
# We exercise this at the request layer (no Selenium in the project)
# because the feature is HTML markup + a single global Stimulus
# controller — we can't test JS keystrokes here, but we can lock the
# layout contract that the controller depends on.
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

      it "GET #{path} renders the help <dialog> with the keyboard target" do
        get path
        expect(response.body).to include('data-keyboard-target="dialog"')
        expect(response.body).to include('class="pane-dialog"')
      end

      it "GET #{path} renders the visible [?] bracketed link in page chrome" do
        get path
        # The visible affordance moved from the header to the footer
        # row 1 in the 2026-05-10 navbar redesign; what matters here is
        # that the `[?]` link exists somewhere in the persistent chrome
        # so keyboard-only users have a discoverable on-screen anchor.
        # ERB escapes `->` in attribute values to `-&gt;`; matching the
        # encoded form keeps the assertion grounded in real bytes.
        expect(response.body).to include('data-action="click-&gt;keyboard#openHelp"')
        expect(response.body).to match(/\[<span class="bl">\?<\/span>\]/)
      end

      it "GET #{path} does not introduce data-turbo-confirm anywhere" do
        get path
        expect(response.body).not_to include("data-turbo-confirm")
      end
    end
  end

  describe "help modal section coverage" do
    before { get "/" }

    it "lists every g-prefix navigation binding" do
      body = response.body
      [ "go to dashboard", "go to channels", "go to videos", "go to saved views", "go to settings" ].each do |label|
        expect(body).to include(label)
      end
    end

    it "lists the f-prefix filter bindings" do
      body = response.body
      expect(body).to match(/filter:\s*starred/i)
      # `filter: connected (f c)` was retired alongside the derived
      # connected display surface — every channel is OAuth-linked by
      # definition now.
      expect(body).not_to match(/filter:\s*connected/i)
    end

    it "does NOT advertise the retired `f y` filter (Path A2)" do
      expect(response.body).not_to match(/filter:\s*syncing/i)
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
