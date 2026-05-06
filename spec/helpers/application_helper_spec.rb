require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#nav_link" do
    it "returns a bracketed link when not on the current page" do
      allow(helper).to receive(:current_page?).with("/channels").and_return(false)
      result = helper.nav_link("channels", "/channels")
      expect(result).to include("<a")
      expect(result).to include("[<span")
      expect(result).to include("channels</span>")
      expect(result).to include("/channels")
      expect(result).to include("bracketed")
    end

    # Item 6 — On desktop, the full word renders inside .hide-mobile;
    # on mobile, the short label renders inside .show-mobile. Both
    # variants always live in the DOM so the toggle is pure CSS.
    it "renders both desktop full label and mobile short label spans" do
      allow(helper).to receive(:current_page?).with("/channels").and_return(false)
      result = helper.nav_link("channels", "/channels", short: "C")
      expect(result).to include('<span class="hide-mobile">channels</span>')
      expect(result).to include('<span class="show-mobile">C</span>')
    end

    it "defaults the short label to the uppercased first character of the full label" do
      allow(helper).to receive(:current_page?).with("/projects").and_return(false)
      result = helper.nav_link("projects", "/projects")
      expect(result).to include('<span class="show-mobile">P</span>')
    end

    it "returns a bracketed bold span when on the current page" do
      allow(helper).to receive(:current_page?).with("/").and_return(true)
      result = helper.nav_link("home", "/")
      expect(result).to include("bracketed-active")
      expect(result).to include("home")
      expect(result).not_to include("<a")
    end

    it "treats short: '' as desktop-only — no mobile label rendered" do
      # Used for the [home] nav link: the logo image already routes
      # home, so on mobile we omit the bracketed label entirely. The
      # helper still emits the desktop label inside .hide-mobile.
      allow(helper).to receive(:current_page?).with("/").and_return(false)
      result = helper.nav_link("home", "/", short: "")
      expect(result).to include('<span class="hide-mobile">home</span>')
      expect(result).not_to include('class="show-mobile"')
    end
  end

  describe "#breadcrumb" do
    it "renders bracketed linked segments and last segment bold" do
      helper.breadcrumb([ "channels", "/channels" ], "details")
      html = helper.content_for(:breadcrumbs)
      expect(html).to include("bracketed")
      expect(html).to include("channels")
      expect(html).to include("bracketed-active")
      expect(html).to include("details")
    end

    it "uses / separator" do
      helper.breadcrumb([ "a", "/a" ], "b")
      html = helper.content_for(:breadcrumbs)
      expect(html).to include(" / ")
    end

    it "truncates long non-last labels to 32 chars" do
      long_label = "A" * 50
      helper.breadcrumb([ long_label, "/somewhere" ], "last")
      html = helper.content_for(:breadcrumbs)
      expect(html).to include("A" * 31 + "…")
    end

    it "renders nothing when not called" do
      expect(helper.content_for?(:breadcrumbs)).to be false
    end
  end

  describe "#format_video_watch_time" do
    it "returns dash for nil" do
      expect(helper.format_video_watch_time(nil)).to eq("—")
    end

    it "returns dash for zero" do
      expect(helper.format_video_watch_time(0)).to eq("—")
    end

    it "rounds sub-30-minute totals to 0h" do
      expect(helper.format_video_watch_time(15)).to eq("0h")
    end

    it "rounds 30+ minutes up to 1h" do
      expect(helper.format_video_watch_time(30)).to eq("1h")
      expect(helper.format_video_watch_time(45)).to eq("1h")
    end

    it "rounds to nearest hour (half-up)" do
      expect(helper.format_video_watch_time(89)).to eq("1h")
      expect(helper.format_video_watch_time(90)).to eq("2h")
      expect(helper.format_video_watch_time(125)).to eq("2h")
    end

    it "formats large values with comma delimiter and h suffix" do
      expect(helper.format_video_watch_time(72_060)).to eq("1,201h")
      expect(helper.format_video_watch_time(1_066_983)).to eq("17,783h")
      expect(helper.format_video_watch_time(1_066_983 + 30)).to eq("17,784h")
    end
  end

  describe "#pane_breadcrumb_label" do
    let(:video1) { build_stubbed(:video, title: "alpha", channel: build_stubbed(:channel)) }
    let(:video2) { build_stubbed(:video, title: "beta", channel: build_stubbed(:channel)) }

    it "returns full title for single video pane" do
      expect(helper.pane_breadcrumb_label([ video1 ])).to eq("alpha")
    end

    it "joins multiple panes with dot separator" do
      result = helper.pane_breadcrumb_label([ video1, video2 ])
      expect(result).to include("alpha")
      expect(result).to include("·")
      expect(result).to include("beta")
    end

    it "truncates long names with ellipsis" do
      long = build_stubbed(:video, title: "a very long video name here", channel: build_stubbed(:channel))
      result = helper.pane_breadcrumb_label([ long, video2 ])
      expect(result).to include("…")
    end

    it "shows +N more for excess panes" do
      videos = 5.times.map { |i| build_stubbed(:video, title: "v#{i}", channel: build_stubbed(:channel)) }
      result = helper.pane_breadcrumb_label(videos)
      expect(result).to include("+2 more")
    end

    it "falls back to id-only label for channels (no title column)" do
      channel = build_stubbed(:channel)
      expect(helper.pane_breadcrumb_label([ channel ])).to eq("##{channel.id}")
    end
  end

  describe "#sort_link_to" do
    # The helper merges the sort + dir params into the existing query
    # string. The default param names are `sort` / `dir` (matches the
    # legacy callers); pages with two independently sortable tables
    # pass custom names (e.g. `notes_sort` / `notes_dir`) to keep each
    # table's URL state distinct.
    #
    # `link_to` builds URLs through `url_for`, which needs a known
    # route. We point the controller at `/projects` (a real route) and
    # stub `request.query_parameters` so the merge logic is
    # deterministic.
    before do
      controller.request.path_parameters = { controller: "projects", action: "index" }
      allow(helper.request).to receive(:query_parameters).and_return({})
    end

    it "uses the default `sort` / `dir` param names when not specified" do
      result = helper.sort_link_to("name", "name", current_sort: "created_at", current_dir: "desc")
      expect(result).to include("sort=name")
      expect(result).to include("dir=asc")
      expect(result).not_to include("notes_sort")
    end

    it "honors custom `sort_param` / `dir_param` kwargs" do
      result = helper.sort_link_to("title", "title",
        current_sort: "last_modified", current_dir: "desc",
        sort_param: "notes_sort", dir_param: "notes_dir")
      expect(result).to include("notes_sort=title")
      expect(result).to include("notes_dir=asc")
      # Must not leak the default param names through.
      expect(result).not_to match(/[?&]sort=/)
      expect(result).not_to match(/[?&]dir=/)
    end

    it "renders an ascending arrow on the active column when current_dir is asc" do
      result = helper.sort_link_to("name", "name", current_sort: "name", current_dir: "asc")
      expect(result).to include("▲")
    end

    it "renders a descending arrow on the active column when current_dir is desc" do
      result = helper.sort_link_to("name", "name", current_sort: "name", current_dir: "desc")
      expect(result).to include("▼")
    end

    it "renders no arrow on inactive columns" do
      result = helper.sort_link_to("created", "created_at", current_sort: "name", current_dir: "asc")
      expect(result).not_to include("▲")
      expect(result).not_to include("▼")
    end

    # Dual-arrow bug fix (2026-05-06). The active column's link gets a
    # `sort-asc` / `sort-desc` class so the CSS `:has()` rule can
    # suppress the neutral `::after` indicator on that header. Inactive
    # columns must NOT carry the class — otherwise the CSS would
    # suppress the neutral indicator everywhere and inactive headers
    # would show no arrow at all.
    it "stamps a `sort-asc` class on the active link when current_dir is asc" do
      result = helper.sort_link_to("name", "name", current_sort: "name", current_dir: "asc")
      expect(result).to include('class="sort-asc"')
    end

    it "stamps a `sort-desc` class on the active link when current_dir is desc" do
      result = helper.sort_link_to("name", "name", current_sort: "name", current_dir: "desc")
      expect(result).to include('class="sort-desc"')
    end

    it "does not stamp a sort-{asc,desc} class on inactive columns" do
      result = helper.sort_link_to("created", "created_at", current_sort: "name", current_dir: "asc")
      expect(result).not_to include("sort-asc")
      expect(result).not_to include("sort-desc")
    end

    it "preserves existing query parameters when building the link" do
      allow(helper.request).to receive(:query_parameters).and_return({ "sort" => "duration_seconds", "dir" => "desc" })
      result = helper.sort_link_to("title", "title",
        current_sort: "last_modified", current_dir: "desc",
        sort_param: "notes_sort", dir_param: "notes_dir")
      expect(result).to include("sort=duration_seconds")
      expect(result).to include("dir=desc")
      expect(result).to include("notes_sort=title")
      expect(result).to include("notes_dir=asc")
    end
  end

  # Server-side fixed-length middle truncation. Returns a single
  # string with a Unicode ellipsis (U+2026) joining the head and tail
  # halves. Used by the `/channels` and `/videos` URL cells (e.g.
  # `https://…jF7eS8r1`) and, via delegation, by the project show
  # footage filename column (`FootageHelper#filename_truncate_middle`).
  describe "#middle_truncate" do
    it "returns the input as-is when it is shorter than head + 1 + tail" do
      expect(helper.middle_truncate("short", head: 8, tail: 8)).to eq("short")
    end

    it "returns the input as-is when length equals exactly head + 1 + tail (boundary)" do
      # 8 + 1 + 8 = 17 — a 17-char string already fits without truncation.
      str = "a" * 17
      expect(helper.middle_truncate(str, head: 8, tail: 8)).to eq(str)
    end

    it "truncates the canonical YouTube channel URL to `https://…jF7eS8r1`" do
      url = "https://www.youtube.com/channel/UClSHvsAVzQ_GYsDjF7eS8r1"
      expect(helper.middle_truncate(url, head: 8, tail: 8)).to eq("https://…jF7eS8r1")
    end

    it "uses the U+2026 horizontal-ellipsis character (NOT three ASCII dots)" do
      url = "https://www.youtube.com/channel/UClSHvsAVzQ_GYsDjF7eS8r1"
      result = helper.middle_truncate(url, head: 8, tail: 8)
      expect(result).to include("…")
      expect(result).not_to include("...")
    end

    it "honors custom head / tail lengths" do
      # 29-char input, head=5 / tail=4. head+1+tail=10, so truncation
      # fires. Output: first 5 chars + ellipsis + last 4 chars.
      expect(helper.middle_truncate("hello-world-and-then-some.mkv", head: 5, tail: 4))
        .to eq("hello….mkv")
    end

    it "produces a result of length head + 1 + tail when truncating" do
      url = "https://www.youtube.com/channel/UClSHvsAVzQ_GYsDjF7eS8r1"
      expect(helper.middle_truncate(url, head: 8, tail: 8).length).to eq(17)
    end

    it "preserves multibyte characters in head / tail slices" do
      str = "café-prefix-tail-café"
      result = helper.middle_truncate(str, head: 4, tail: 4)
      expect(result).to start_with("café")
      expect(result).to end_with("café")
      expect(result).to include("…")
    end

    it "returns an empty string for nil input" do
      expect(helper.middle_truncate(nil, head: 8, tail: 8)).to eq("")
    end

    it "returns an empty string for a blank input" do
      expect(helper.middle_truncate("", head: 8, tail: 8)).to eq("")
    end
  end
end
