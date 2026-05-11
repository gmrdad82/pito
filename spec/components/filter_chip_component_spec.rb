require "rails_helper"

RSpec.describe FilterChipComponent, type: :component do
  it "renders [ ] label when not checked" do
    render_inline(described_class.new(label: "starred", param: "star"))
    expect(page).to have_css("a.filter-chip")
    expect(page).to have_css("span.md-check-static", text: "[ ]")
    expect(page).to have_css("span.md-check-static-label", text: "starred")
  end

  it "renders [x] label when checked" do
    render_inline(described_class.new(label: "starred", param: "star", current_params: { "star" => "yes" }))
    expect(page).to have_css("span.md-check-static", text: "[x]")
    expect(page).to have_css("span.md-check-static-label", text: "starred")
  end

  it "treats symbol keys in current_params equivalently to string keys" do
    render_inline(described_class.new(label: "starred", param: "star", current_params: { star: "yes" }))
    expect(page).to have_css("span.md-check-static", text: "[x]")
  end

  it "generates an href that adds the param when toggling on" do
    render_inline(described_class.new(label: "starred", param: "star"))
    expect(page).to have_css('a.filter-chip[href="?star=yes"]')
  end

  it "generates an href that removes the param when toggling off" do
    render_inline(described_class.new(label: "starred", param: "star", current_params: { "star" => "yes" }))
    expect(page).to have_css('a.filter-chip[href="?"]')
  end

  it "preserves other URL params when toggling on" do
    render_inline(described_class.new(
      label: "connected",
      param: "connected",
      current_params: { "star" => "yes", "page" => "2" }
    ))
    href = page.find("a.filter-chip")["href"]
    expect(href).to start_with("?")
    pairs = href.delete_prefix("?").split("&")
    expect(pairs).to contain_exactly("star=yes", "page=2", "connected=yes")
  end

  it "preserves other URL params when toggling off" do
    render_inline(described_class.new(
      label: "connected",
      param: "connected",
      current_params: { "star" => "yes", "connected" => "yes", "page" => "2" }
    ))
    href = page.find("a.filter-chip")["href"]
    pairs = href.delete_prefix("?").split("&")
    expect(pairs).to contain_exactly("star=yes", "page=2")
  end

  it "supports a custom value" do
    render_inline(described_class.new(label: "size", param: "size", value: "lg", current_params: { "size" => "lg" }))
    expect(page).to have_css("span.md-check-static", text: "[x]")
    expect(page).to have_css('a.filter-chip[href="?"]')
  end

  it "uses the design-system filter-chip class for styling" do
    # The filter-chip CSS rule applies the design-system link color.
    render_inline(described_class.new(label: "starred", param: "star"))
    expect(page).to have_css("a.filter-chip")
  end

  # Polish-3 (2026-05-06) — opt-in Turbo Frame navigation. When the
  # `frame:` kwarg is set, the chip carries
  # `data-turbo-frame="<id>"` + `data-turbo-action="advance"` so a
  # click only swaps the matching frame on the page (rather than
  # navigating the whole page) AND updates the URL bar so back /
  # forward and deep-linking still work.
  describe "frame: kwarg (Turbo Frame opt-in)" do
    it "does not emit data-turbo-frame when frame: is not given" do
      render_inline(described_class.new(label: "starred", param: "star"))
      anchor = page.find("a.filter-chip")
      expect(anchor["data-turbo-frame"]).to be_nil
      expect(anchor["data-turbo-action"]).to be_nil
    end

    it "emits data-turbo-frame=<id> + data-turbo-action=advance when frame: is set" do
      render_inline(described_class.new(label: "starred", param: "star", frame: "footage-table"))
      anchor = page.find("a.filter-chip")
      expect(anchor["data-turbo-frame"]).to eq("footage-table")
      expect(anchor["data-turbo-action"]).to eq("advance")
    end
  end

  # Phase 7.5 — Step 04. The keyboard controller's `f s` / `f c`
  # bindings click the filter chip whose `data-keyboard-filter-chip`
  # matches the chip label. Tagging is by visible label so Rails
  # mirrors the CLI's `f s` (starred) / `f c` (connected) without
  # leaking the URL `param` name (which is `star`, not `starred`).
  describe "keyboard hook" do
    it "carries data-keyboard-filter-chip=<label> for the keyboard controller" do
      render_inline(described_class.new(label: "starred", param: "star"))
      expect(page).to have_css('a.filter-chip[data-keyboard-filter-chip="starred"]')
    end

    it "uses the connected label for the connected chip" do
      render_inline(described_class.new(label: "connected", param: "connected"))
      expect(page).to have_css('a.filter-chip[data-keyboard-filter-chip="connected"]')
    end
  end

  # Phase 15 calendar UX restructure — `csv:` mode lets a chip
  # participate in a comma-separated multi-value list (`?types=a,b,c`).
  describe "csv: mode (multi-value lists)" do
    it "treats absent param as none-checked (URL is the source of truth)" do
      render_inline(described_class.new(label: "video", param: "types", value: "video", csv: true))
      expect(page).to have_css("span.md-check-static", text: "[ ]")
    end

    it "is checked when the value is in the comma list" do
      render_inline(described_class.new(label: "video", param: "types", value: "video", csv: true,
        current_params: { "types" => "video,custom" }))
      expect(page).to have_css("span.md-check-static", text: "[x]")
    end

    it "is not checked when the value is absent from the comma list" do
      render_inline(described_class.new(label: "video", param: "types", value: "video", csv: true,
        current_params: { "types" => "game,custom" }))
      expect(page).to have_css("span.md-check-static", text: "[ ]")
    end

    it "toggling on adds the value, preserving other csv members" do
      render_inline(described_class.new(label: "video", param: "types", value: "video", csv: true,
        current_params: { "types" => "game" }))
      anchor = page.find("a.filter-chip")
      expect(anchor["href"]).to eq("?types=game%2Cvideo")
    end

    it "toggling off removes the value, leaving the others" do
      render_inline(described_class.new(label: "video", param: "types", value: "video", csv: true,
        current_params: { "types" => "video,game" }))
      anchor = page.find("a.filter-chip")
      expect(anchor["href"]).to eq("?types=game")
    end

    it "toggling off the last value yields an empty types= (preserves the param sentinel)" do
      render_inline(described_class.new(label: "video", param: "types", value: "video", csv: true,
        current_params: { "types" => "video" }))
      anchor = page.find("a.filter-chip")
      expect(anchor["href"]).to eq("?types=")
    end
  end

  # 2026-05-11 Turbo Frame content-missing sweep — `path:` opt-in for
  # absolute-URL hrefs. Required by surfaces (notifications inbox) that
  # can be loaded into a Turbo Frame whose `src` differs from the
  # document URL. A relative `?…` href resolves against the document
  # URL (browser behavior), NOT the frame's src — a chip inside the
  # notifications modal opened from /channels would otherwise navigate
  # to `/channels?filter=unread&modal=yes`, which has no matching
  # modal frame in its response and Turbo renders "Content missing".
  describe "path: kwarg (absolute-URL hrefs)" do
    it "defaults to relative ?-prefixed hrefs when path: is not given" do
      render_inline(described_class.new(label: "starred", param: "star"))
      expect(page).to have_css('a.filter-chip[href="?star=yes"]')
    end

    it "prefixes the href with path: when set" do
      render_inline(described_class.new(label: "unread", param: "filter", value: "unread",
                                         path: "/notifications"))
      expect(page).to have_css('a.filter-chip[href="/notifications?filter=unread"]')
    end

    it "preserves current_params alongside path:" do
      render_inline(described_class.new(label: "unread", param: "filter", value: "unread",
                                         current_params: { "modal" => "yes" },
                                         path: "/notifications"))
      anchor = page.find("a.filter-chip")
      pairs = anchor["href"].split("?", 2).last.split("&")
      expect(anchor["href"]).to start_with("/notifications?")
      expect(pairs).to contain_exactly("filter=unread", "modal=yes")
    end

    it "yields a bare path (no trailing ?) when all params are removed" do
      render_inline(described_class.new(label: "unread", param: "filter", value: "unread",
                                         current_params: { "filter" => "unread" },
                                         path: "/notifications"))
      expect(page).to have_css('a.filter-chip[href="/notifications"]')
    end
  end
end
