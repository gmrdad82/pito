require "rails_helper"

# Phase 7.5 §11d — Channel multi-layout preview component.
#
# Three layout panels (desktop / mobile / TV), each rendering the
# same set of sections in the same order. The `pending:` hash
# overrides individual channel attributes so the Stimulus-driven
# debounced preview can stream in pending edits without writing to
# the database.
#
# Branch coverage:
#   * banner-present / banner-absent
#   * avatar-present / avatar-absent
#   * description-present / description-absent
#   * links-present / links-empty
#   * real-videos / static-fallback / empty-thumbnails fallback
#   * pending-edits override each attribute
RSpec.describe ChannelPreviewComponent, type: :component do
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcabcabcabcabcabcabcA",
           title: "Cached Title",
           handle: "@cached",
           description: "Cached description.",
           banner_url: "https://example.com/banner.jpg",
           avatar_url: "https://example.com/avatar.jpg",
           subscriber_count: 12_345,
           links: [ { "title" => "site", "url" => "https://example.com/" } ])
  end

  describe "structure" do
    it "renders the wrapper at #channel-preview with all three panels" do
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css("#channel-preview")
      expect(page).to have_css("#preview-layout-desktop", visible: :all)
      expect(page).to have_css("#preview-layout-mobile", visible: :all)
      expect(page).to have_css("#preview-layout-tv", visible: :all)
    end

    it "marks desktop as the active panel by default" do
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css("#preview-layout-desktop.active")
      expect(page).to have_css("#preview-layout-mobile[hidden]", visible: :all)
      expect(page).to have_css("#preview-layout-tv[hidden]", visible: :all)
    end

    it "honors a custom active_layout argument" do
      render_inline(described_class.new(channel: channel, active_layout: "mobile"))

      expect(page).to have_css("#preview-layout-mobile.active")
      expect(page).to have_css("#preview-layout-desktop[hidden]", visible: :all)
    end

    it "falls back to desktop on an unknown active_layout value" do
      render_inline(described_class.new(channel: channel, active_layout: "watch"))

      expect(page).to have_css("#preview-layout-desktop.active")
    end
  end

  describe "banner rendering" do
    it "uses channel.banner_url when present" do
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css("img.preview-banner-img[src='https://example.com/banner.jpg']")
      expect(page).to have_no_css(".preview-banner--placeholder")
    end

    it "falls back to a muted placeholder block when banner_url is blank" do
      channel.update_column(:banner_url, nil)
      render_inline(described_class.new(channel: channel))

      expect(page).to have_no_css("img.preview-banner-img", visible: :all)
      expect(page).to have_css(".preview-banner--placeholder", count: 3, visible: :all) # one per layout
    end

    it "honors pending[:banner_url] override" do
      render_inline(described_class.new(channel: channel,
                                        pending: { banner_url: "https://example.com/over.jpg" }))

      expect(page).to have_css("img.preview-banner-img[src='https://example.com/over.jpg']")
    end

    it "renders the placeholder when pending[:banner_url] is an empty string (user cleared the field)" do
      render_inline(described_class.new(channel: channel, pending: { banner_url: "" }))

      expect(page).to have_no_css("img.preview-banner-img", visible: :all)
      expect(page).to have_css(".preview-banner--placeholder", count: 3, visible: :all)
    end
  end

  describe "avatar rendering" do
    it "uses channel.avatar_url when present" do
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css("img.preview-avatar[src='https://example.com/avatar.jpg']",
                               count: 3, visible: :all)
    end

    it "falls back to a circular placeholder with the first character upcased" do
      channel.update_columns(avatar_url: nil, title: "studio")
      render_inline(described_class.new(channel: channel))

      expect(page).to have_no_css("img.preview-avatar", visible: :all)
      expect(page).to have_css(".preview-avatar--placeholder", text: "S", visible: :all)
    end

    it "honors pending[:avatar_url] override" do
      render_inline(described_class.new(channel: channel,
                                        pending: { avatar_url: "https://example.com/over.png" }))

      expect(page).to have_css("img.preview-avatar[src='https://example.com/over.png']")
    end
  end

  describe "title / handle / subscriber count" do
    it "uses channel.title, channel.handle, and channel.subscriber_count by default" do
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css(".preview-title--desktop", text: "Cached Title")
      expect(page).to have_css(".preview-handle", text: "@cached")
      expect(page).to have_css(".preview-subs", text: /12\s*(K|Thousand)/i)
    end

    it "renders the placeholder title when the resolved title is blank" do
      channel.update_column(:title, nil)
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css(".preview-title--desktop", text: "untitled channel")
    end

    it "honors pending[:title] override" do
      render_inline(described_class.new(channel: channel, pending: { title: "Override Title" }))

      expect(page).to have_css(".preview-title--desktop", text: "Override Title")
    end

    it "honors pending[:handle] override" do
      render_inline(described_class.new(channel: channel, pending: { handle: "@override" }))

      expect(page).to have_css(".preview-handle", text: "@override")
    end

    it "hides the handle line when both channel and pending hand back blank" do
      channel.update_column(:handle, nil)
      render_inline(described_class.new(channel: channel))

      expect(page).to have_no_css(".preview-handle")
    end

    it "renders 'Hidden' for hidden_subscriber_count" do
      channel.update_columns(hidden_subscriber_count: true, subscriber_count: 100)
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css(".preview-subs", text: /Hidden subscribers/)
    end

    it "renders an em-dash when subscriber_count is nil" do
      channel.update_column(:subscriber_count, nil)
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css(".preview-subs", text: "— subscribers")
    end
  end

  describe "description rendering" do
    it "renders the description block when present" do
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css(".preview-description--desktop", text: /Cached description\./)
    end

    it "renders no description element when blank" do
      channel.update_column(:description, nil)
      render_inline(described_class.new(channel: channel))

      expect(page).to have_no_css(".preview-description--desktop")
      expect(page).to have_no_css(".preview-description--mobile")
      expect(page).to have_no_css(".preview-description--tv")
    end

    it "honors pending[:description] override" do
      render_inline(described_class.new(channel: channel,
                                        pending: { description: "Streamed in." }))

      expect(page).to have_css(".preview-description--desktop", text: /Streamed in\./)
    end

    it "hides the description block when pending[:description] is empty" do
      render_inline(described_class.new(channel: channel, pending: { description: "" }))

      expect(page).to have_no_css(".preview-description--desktop")
    end
  end

  describe "links rendering" do
    it "renders one bracketed link per entry when channel.links is non-empty" do
      render_inline(described_class.new(channel: channel))

      desktop = page.find("#preview-layout-desktop")
      expect(desktop).to have_css(".preview-links--desktop a.bracketed", text: "site")
    end

    it "renders no links row when channel.links is empty" do
      channel.update_column(:links, [])
      render_inline(described_class.new(channel: channel))

      expect(page).to have_no_css(".preview-links--desktop")
    end

    it "honors pending[:links] override (Ruby Array of Hashes)" do
      render_inline(described_class.new(channel: channel,
                                        pending: { links: [ { "title" => "over", "url" => "https://o.test/" } ] }))

      desktop = page.find("#preview-layout-desktop")
      expect(desktop).to have_css(".preview-links--desktop a.bracketed", text: "over")
      expect(desktop).to have_no_css(".preview-links--desktop a.bracketed", text: "site")
    end

    it "honors pending[:links] override (JSON-encoded string from a query param)" do
      payload = JSON.dump([ { "title" => "json-link", "url" => "https://j.test/" } ])
      render_inline(described_class.new(channel: channel, pending: { links: payload }))

      expect(page).to have_css(".preview-links--desktop a.bracketed", text: "json-link")
    end

    it "renders no links row when pending[:links] is an explicitly empty array" do
      render_inline(described_class.new(channel: channel, pending: { links: [] }))

      expect(page).to have_no_css(".preview-links--desktop")
    end
  end

  describe "videos row" do
    context "with ≥6 titled real videos" do
      before do
        6.times do |i|
          create(:video, channel: channel, title: "Real video #{i}")
        end
      end

      it "renders the real-video branch" do
        render_inline(described_class.new(channel: channel))

        expect(page).to have_css(".preview-videos--desktop[data-videos-kind='real']", visible: :all)
        expect(page).to have_css(".preview-video--desktop", count: 6, visible: :all)
        expect(page).to have_css(".preview-video-title--desktop", text: "Real video 0", visible: :all)
      end
    end

    context "with fewer than 6 titled videos and thumbnails available" do
      before do
        # Create a Rails public preview thumbnails dir for this test scope.
        FileUtils.mkdir_p(PreviewHelper::THUMBNAILS_DIR)
        @created_files = []
        %w[thumb-01.jpg thumb-02.jpg].each do |name|
          path = PreviewHelper::THUMBNAILS_DIR.join(name)
          unless File.exist?(path)
            File.write(path, "")
            @created_files << path
          end
        end
      end

      after do
        @created_files.each { |path| File.delete(path) if File.exist?(path) }
      end

      it "renders the static-fallback branch with sample titles and thumbnails" do
        render_inline(described_class.new(channel: channel))

        expect(page).to have_css(".preview-videos--desktop[data-videos-kind='static']", visible: :all)
        expect(page).to have_css(".preview-video--desktop", count: 6, visible: :all)
        expect(page).to have_css("img.preview-thumb--desktop[src^='/preview/video_thumbnails/thumb-']",
                                 visible: :all)
        # The wrapping sample seeds off channel.id so the rendered
        # title set is a subset of the canonical title pool. Strip
        # surrounding whitespace because Capybara's element `.text`
        # call returns "" inside `hidden` parents — we need the raw
        # native content via `text(:all)`.
        rendered_titles = page.all(".preview-video-title--desktop", visible: :all)
                              .map { |el| el.text(:all).strip }
        expect(rendered_titles).not_to be_empty
        # Verify at least one rendered title is drawn from the canonical pool.
        intersection = rendered_titles & PreviewHelper::RANDOM_VIDEO_TITLES
        expect(intersection).not_to be_empty
      end
    end

    context "with fewer than 6 titled videos and no thumbnails on disk" do
      before do
        # Force an empty thumbnails dir for this scope.
        allow(PreviewHelper).to receive(:available_thumbnail_files).and_return([])
      end

      it "renders the [ no preview thumbnails yet ] empty-state copy" do
        render_inline(described_class.new(channel: channel))

        expect(page).to have_css(".preview-videos--desktop[data-videos-kind='empty']")
        expect(page).to have_css(".preview-videos-empty", text: "[ no preview thumbnails yet ]")
      end
    end
  end

  describe "Stimulus wiring" do
    it "exposes the frame target on the outer wrapper" do
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css("#channel-preview[data-channel-preview-target='frame']")
    end

    it "exposes the panel target on every layout panel" do
      render_inline(described_class.new(channel: channel))

      expect(page).to have_css("[data-channel-preview-target='panel']", count: 3, visible: :all)
    end

    it "carries the active layout on the wrapper for the Stimulus controller to mirror" do
      render_inline(described_class.new(channel: channel, active_layout: "tv"))

      expect(page).to have_css("#channel-preview[data-active-layout='tv']")
    end
  end

  describe "hard-rule hygiene" do
    it "does not introduce a JS confirm / alert / data-turbo-confirm" do
      render_inline(described_class.new(channel: channel))
      rendered = page.native.to_html

      expect(rendered).not_to include("data-turbo-confirm")
      expect(rendered).not_to include("window.confirm")
      expect(rendered).not_to include("alert(")
      expect(rendered).not_to include("prompt(")
    end
  end
end
