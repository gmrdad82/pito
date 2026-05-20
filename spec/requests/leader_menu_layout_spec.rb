require "rails_helper"

# Layout integration for the unified leader-menu schema. The
# `<script type="application/json" id="pito-keybindings">` tag is
# the wire between the Ruby loader and the Stimulus
# `leader-menu_controller.js`; the controller parses it on `connect`
# and walks the menu tree in response to SPACE / Esc / Backspace /
# key presses. Source-of-truth doc:
#   docs/notes/2026-05-10-23-30-00-keybindings-unified-schema-proposal.md
#   (with the locked-decision block dated 2026-05-11 at the bottom).
RSpec.describe "Leader menu layout integration", type: :request do
  %w[/ /channels /videos /settings].each do |path|
    it "GET #{path} mounts data-controller leader-menu on <body>" do
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(
        /<body[^>]*data-controller="[^"]*\bleader-menu\b[^"]*"/
      )
    end

    it "GET #{path} renders the <script id=pito-keybindings> tag" do
      get path
      expect(response.body).to include('<script type="application/json" id="pito-keybindings">')
    end

    it "GET #{path} embeds a JSON payload with the leader + menus keys" do
      get path
      match = response.body.match(
        %r{<script type="application/json" id="pito-keybindings">(?<json>.*?)</script>}m
      )
      expect(match).not_to be_nil, "expected to find the keybindings <script> tag"
      payload = JSON.parse(match[:json])
      expect(payload).to include("leader", "menus")
      # 2026-05-18 — flat 2-key dispatch. Submenus (calendar / channels /
      # videos / projects / games / notifications) were folded into the
      # root menu as multi-char keys (`cs`, `Cl`, `Gl`, …); only `root`
      # survives in the `menus:` block.
      expect(payload.fetch("menus")).to include("root")
      expect(payload.fetch("menus").keys).to eq([ "root" ])
    end

    it "GET #{path} renders the popup placeholder div" do
      get path
      expect(response.body).to include('id="leader-menu-popup"')
      expect(response.body).to include('data-leader-menu-target="popup"')
    end

    it "GET #{path} renders the Tui::TopStatusBarComponent inside the header" do
      get path
      # Beta 4 — Phase F1 Lane D (2026-05-20). The `[_]` bracketed
      # leader trigger that used to live in the header's right
      # cluster (immediately after `[settings]`) was dropped along
      # with the bracketed-nav layout. The leader menu is still
      # reachable via the SPACE keypress because the `leader-menu`
      # Stimulus controller stays mounted on `<body>` and registers a
      # document keydown listener — see the "mounts data-controller
      # leader-menu on <body>" spec above. The header now hosts the
      # status bar; this assertion locks the new shape.
      header = response.body.match(%r{<header\b.*?</header>}m)
      expect(header).not_to be_nil, "expected to find <header>...</header> in the response"
      expect(header[0]).to include('class="sb-bar"')
      expect(header[0]).to include('data-controller="tui-status-bar"')
    end

    it "GET #{path} does NOT render the legacy [_] navbar link anywhere on the page" do
      get path
      # Beta 4 — Phase F1 Lane D. The bracketed `[_]` link wired to
      # `click->leader-menu#openRoot` is gone from BOTH the header and
      # the footer. SPACE keypress remains the discovery path.
      expect(response.body).not_to include("click-&gt;leader-menu#openRoot")
      expect(response.body).not_to match(/\[<span class="bl">_<\/span>\]/)
    end
  end

  describe "auth-chrome-hidden pages" do
    it "does NOT render the status bar on /login (content_for :hide_chrome)" do
      get "/login"
      expect(response).to have_http_status(:ok)
      # The header element is still emitted (the sticky-positioned
      # shell stays in the layout regardless of `:hide_chrome`), but
      # the `Tui::TopStatusBarComponent` inside it is gated by the
      # same `unless content_for?(:hide_chrome)` flag that previously
      # hid the bracketed nav. Auth pages should never render the
      # status bar's controller hook.
      header = response.body.match(%r{<header\b.*?</header>}m)
      expect(header).not_to be_nil
      expect(header[0]).not_to include('data-controller="tui-status-bar"')
    end

    it "still embeds the schema script tag even on chrome-hidden pages" do
      # The schema is harmless on chrome-hidden pages; keeping it
      # rendered means the Stimulus controller can no-op gracefully
      # (popup target missing) without complicated conditionals.
      get "/login"
      expect(response.body).to include('id="pito-keybindings"')
    end
  end

  describe "schema payload locked shape" do
    before { get "/" }

    def payload
      match = response.body.match(
        %r{<script type="application/json" id="pito-keybindings">(?<json>.*?)</script>}m
      )
      JSON.parse(match[:json])
    end

    it "exposes the SPACE leader with the underscore display glyph" do
      leader = payload.fetch("leader")
      expect(leader.fetch("key")).to eq(" ")
      expect(leader.fetch("display")).to eq("_")
    end

    it "filters the TUI-only [q] item out of the root menu" do
      # Divider rows (`{ divider: true }`) carry no `key`; skip them
      # before mapping so the assertion stays specific to binding rows.
      root_items = payload.fetch("menus").fetch("root").fetch("items")
      keys = root_items.reject { |i| i["divider"] }.map { |i| i.fetch("key") }
      expect(keys).not_to include("q")
    end

    # 2026-05-18 (revision 2) — the root menu was trimmed to /games +
    # /settings + logout only. The keys below were dropped from the
    # `menus.root.items` block; the layout payload should no longer
    # surface any of them.
    it "drops every out-of-scope binding from the root menu (calendar / channels / videos / projects / notifications / h home / G+)" do
      root_items = payload.fetch("menus").fetch("root").fetch("items")
      keys = root_items.reject { |i| i["divider"] }.map { |i| i.fetch("key") }
      dropped = %w[h cs cm ct c+ Cl C+ C- Cy Vl V+ V- Pl P+ P- Nl Nu Nm G+]
      offenders = keys & dropped
      expect(offenders).to be_empty,
        "expected the dropped keys to be absent from the root menu, found #{offenders.inspect}"
    end

    # 2026-05-19 — 2-letter prefix scheme. Every navigation binding now
    # uses a 2-letter form (`gC` channels, `gG` games, `gS` settings,
    # `qQ` logout) so the same key can also be reached via the flat-key
    # compact-menu mode. The earlier `Gl` / `S` / `Q` single-character
    # keys were retired in the rebinding pass.
    it "keeps the in-scope bindings (gC + gG + gS + qQ + ?) in the root menu" do
      root_items = payload.fetch("menus").fetch("root").fetch("items")
      keys = root_items.reject { |i| i["divider"] }.map { |i| i.fetch("key") }
      expect(keys).to include("gC", "gG", "gS", "qQ", "?")
    end
  end

  describe "games_index page_actions payload (`G+` + `Gb` create row)" do
    before { get "/games" }

    def payload
      match = response.body.match(
        %r{<script type="application/json" id="pito-keybindings">(?<json>.*?)</script>}m
      )
      JSON.parse(match[:json])
    end

    it "ships [G+] add game in page_actions.games_index" do
      rows = payload.fetch("page_actions").fetch("games_index")
      row = rows.find { |r| r["key"] == "G+" }
      expect(row).not_to be_nil
      expect(row.fetch("label")).to eq("add game")
      expect(row.fetch("action")).to eq(
        "type" => "open_modal_by_id",
        "target" => "omnisearch-modal-games-index"
      )
    end

    it "ships [Gb] add bundle in page_actions.games_index" do
      rows = payload.fetch("page_actions").fetch("games_index")
      row = rows.find { |r| r["key"] == "Gb" }
      expect(row).not_to be_nil
      expect(row.fetch("label")).to eq("add bundle")
      expect(row.fetch("action")).to eq("type" => "page_add_bundle")
    end

    it "carries two grid_2col dividers (filter chips block + create-row block)" do
      rows = payload.fetch("page_actions").fetch("games_index")
      grid_dividers = rows.select { |r| r["divider"] == true && r["layout"] == "grid_2col" }
      expect(grid_dividers.size).to eq(2)
    end
  end
end
