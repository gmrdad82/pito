require "rails_helper"

# Phase 14 §1 polish (2026-05-10) — global search modal layout integration.
#
# Three modal partials live in the layout chrome and must render on
# every page (parity with the keyboard help modal):
#   - `shared/_search_modal`           (#global-search-modal)
#   - `shared/_igdb_search_modal`      (#igdb-search-modal)
#   - `shared/_igdb_overwrite_modal`   (#igdb-overwrite-modal)
#
# We exercise this at the request layer because the project does not
# run JS in specs; we lock the markup contract that the Stimulus
# controllers depend on.
RSpec.describe "Global search modal layout integration", type: :request do
  describe "every page renders the layout-level modals" do
    %w[/ /channels /videos /games /settings].each do |path|
      it "GET #{path} mounts the global search dialog" do
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="global-search-modal"')
        expect(response.body).to include('data-controller="global-search-modal"')
      end

      it "GET #{path} mounts the IGDB search dialog with a turbo-frame for results" do
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="igdb-search-modal"')
        expect(response.body).to include('data-controller="igdb-search-modal"')
        expect(response.body).to include('data-igdb-search-modal-url-value="/games/search"')
        expect(response.body).to include('id="igdb_search_results"')
      end

      it "GET #{path} mounts the IGDB overwrite-confirmation dialog" do
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="igdb-overwrite-modal"')
        expect(response.body).to include('data-controller="igdb-overwrite-confirm"')
        # The form action defaults to "#" (set per-trigger via JS).
        expect(response.body).to match(/<form[^>]*data-igdb-overwrite-confirm-target="form"[^>]*action="#"/)
      end

      it "GET #{path} retired the inline navbar search input" do
        get path
        # The pre-2026-05-10 chrome carried `<input class="search-input">`
        # in the navbar. The `/` keypress now opens the modal instead.
        expect(response.body).not_to include('class="search-input"')
        expect(response.body).not_to include('class="search-form"')
      end

      it "GET #{path} introduces no JS confirm/alert/prompt or data-turbo-confirm" do
        get path
        expect(response.body).not_to include("data-turbo-confirm")
        expect(response.body).not_to include("window.confirm")
      end
    end
  end

  describe "search modal copy" do
    it "renders an autocomplete-off search input that posts to /search" do
      get "/"
      expect(response.body).to match(%r{<form[^>]*action="/search"[^>]*method="get"})
      expect(response.body).to include('data-global-search-modal-target="input"')
    end
  end

  describe "IGDB search modal copy" do
    it "renders an autocomplete-off search input wired to the modal controller" do
      get "/"
      expect(response.body).to include('data-igdb-search-modal-target="input"')
      expect(response.body).to include('data-action="input->igdb-search-modal#search"')
    end

    # 2026-05-11 — the dialog inherited a 420px max-width from
    # `.confirm-modal`, which clipped the `[search]` button and produced
    # a horizontal scrollbar. The partial now sets an inline max-width
    # on the <dialog> and uses `width: min(...)` on the inner so the
    # layout stays roomy on desktop and fluid on narrow viewports.
    it "widens the dialog past the default confirm-modal 420px cap" do
      get "/"
      expect(response.body).to match(/id="igdb-search-modal"[^>]*style="max-width:\s*720px;?"/)
    end

    it "lets the inner container scale fluidly on narrow viewports" do
      get "/"
      expect(response.body).to include('style="width: min(720px, 92vw);"')
    end
  end

  describe "overwrite modal copy" do
    it "carries the project's standard re-sync caveat with the lead-paragraph <br>" do
      get "/"
      expect(response.body).to include("re-syncing overwrites igdb-sourced fields.<br>")
      expect(response.body).to include("local notes, played-on, footage hours, and platform-owned survive.")
    end

    it "uses bracketed-link copy for the confirm + cancel actions" do
      get "/"
      expect(response.body).to match(/\[<span class="bl">confirm overwrite<\/span>\]/)
      expect(response.body).to match(/\[<span class="bl">cancel<\/span>\]/)
    end
  end
end
