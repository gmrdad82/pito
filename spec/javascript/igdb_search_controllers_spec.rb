require "rails_helper"

# 2026-05-18 — Static-source regression guard for the IGDB-search
# Stimulus pair:
#
#   - `igdb_search_controller.js` — the in-page (non-modal) type-ahead
#     used by the original `/games/new` flow. Debounces input, fires
#     `GET /games/search?q=…` into the `igdb_search_results` Turbo
#     Frame.
#
#   - `igdb_search_modal_controller.js` — the global `[+]` chrome
#     modal (Phase 14 §1 polish). Same debounced search, plus full
#     dialog lifecycle (open / close / clickOutside / Escape) and
#     immediate-fire on Enter, with a documented min-chars gate.
#
# Both controllers share the `igdb_search_results` Turbo Frame
# contract — locking that here keeps the server-side partial id and
# the JS lookup in sync.
RSpec.describe "igdb_search controllers" do
  let(:in_page_source) do
    File.read(Rails.root.join("app/javascript/controllers/igdb_search_controller.js"))
  end

  let(:modal_source) do
    File.read(Rails.root.join("app/javascript/controllers/igdb_search_modal_controller.js"))
  end

  let(:in_page_source_without_comments) do
    in_page_source.gsub(%r{//[^\n]*}, "")
  end

  let(:modal_source_without_comments) do
    modal_source.gsub(%r{//[^\n]*}, "")
  end

  describe "igdb_search_controller.js (in-page type-ahead)" do
    it "extends the Stimulus Controller base class" do
      expect(in_page_source).to include('import { Controller } from "@hotwired/stimulus"')
      expect(in_page_source).to match(/export default class extends Controller/)
    end

    it "declares the `input` target" do
      expect(in_page_source).to match(/static targets = \[\s*"input"\s*\]/)
    end

    it "declares url + debounce (default 300) values" do
      expect(in_page_source).to match(/\burl:\s*String\b/)
      expect(in_page_source).to match(/\bdebounce:\s*\{\s*type:\s*Number,\s*default:\s*300\s*\}/)
    end

    it "initializes the debounce timer in connect() and clears it in disconnect()" do
      expect(in_page_source).to match(/connect\(\)\s*\{[^}]*this\._timer\s*=\s*null/m)
      expect(in_page_source).to match(/disconnect\(\)\s*\{[^}]*clearTimeout\(this\._timer\)/m)
    end

    it "defines a `search` action that schedules a debounced `_fire` via setTimeout" do
      expect(in_page_source).to match(/^\s*search\(\)\s*\{/)
      expect(in_page_source).to match(/setTimeout\(\(\)\s*=>\s*this\._fire\(\),\s*this\.debounceValue\)/)
    end

    it "_fire builds the request URL from urlValue + the trimmed input and writes it to the igdb_search_results frame" do
      fire_block = in_page_source[/^\s*async _fire\(\)\s*\{(.+?)\n\s{2}\}/m].to_s
      expect(fire_block).to include("new URL(this.urlValue, window.location.origin)")
      expect(fire_block).to include('url.searchParams.set("q", q)')
      expect(fire_block).to include('document.getElementById("igdb_search_results")')
      expect(fire_block).to match(/frame\.src\s*=\s*url\.toString\(\)/)
    end

    it "no-ops _fire when the Turbo Frame is not present in the DOM" do
      expect(in_page_source).to match(/if \(!frame\) return/)
    end

    it "carries no forbidden alert/confirm/prompt calls (CLAUDE.md hard rule)" do
      expect(in_page_source_without_comments).not_to match(/\b(?:alert|confirm|prompt)\s*\(/)
    end
  end

  describe "igdb_search_modal_controller.js (global [+] modal)" do
    it "extends the Stimulus Controller base class" do
      expect(modal_source).to include('import { Controller } from "@hotwired/stimulus"')
      expect(modal_source).to match(/export default class extends Controller/)
    end

    it "declares the `input` target" do
      expect(modal_source).to match(/static targets = \[\s*"input"\s*\]/)
    end

    it "declares url, debounce (default 250), and minChars (default 1) values" do
      expect(modal_source).to match(/^\s*url:\s*String/)
      expect(modal_source).to match(/^\s*debounce:\s*\{\s*type:\s*Number,\s*default:\s*250\s*\}/)
      expect(modal_source).to match(/^\s*minChars:\s*\{\s*type:\s*Number,\s*default:\s*1\s*\}/)
    end

    it "initializes the debounce timer in connect() and clears it in disconnect()" do
      expect(modal_source).to match(/connect\(\)\s*\{[^}]*this\._timer\s*=\s*null/m)
      expect(modal_source).to match(/disconnect\(\)\s*\{[^}]*clearTimeout\(this\._timer\)/m)
    end

    it "defines open(), close(), clickOutside(), keydown(), and search() action methods" do
      %w[open close clickOutside keydown search].each do |method|
        expect(modal_source).to match(/^\s*#{Regexp.escape(method)}\(/),
          "expected `#{method}` to be defined as an action method"
      end
    end

    it "opens the dialog via showModal" do
      expect(modal_source).to match(/typeof this\.element\.showModal === "function"[^{]*\{\s*this\.element\.showModal\(\)/m)
    end

    it "defers input focus via setTimeout 0 after open" do
      expect(modal_source).to match(/setTimeout\(\(\)\s*=>\s*this\.inputTarget\.focus\(\),\s*0\)/)
    end

    it "closes via close action only when the dialog is open" do
      close_block = modal_source[/^\s*close\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
      expect(close_block).to include("this.element.open")
      expect(close_block).to match(/this\.element\.close\(\)/)
    end

    it "closes on click-outside when the click target is the dialog itself" do
      co_block = modal_source[/^\s*clickOutside\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
      expect(co_block).to match(/event\.target === this\.element/)
      expect(co_block).to include("this.element.close()")
    end

    it "treats Escape as a close" do
      keydown_block = modal_source[/^\s*keydown\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
      expect(keydown_block).to include('event.key === "Escape"')
      expect(keydown_block).to include("this.element.close()")
    end

    it "Enter bypasses the debounce and fires _fire immediately" do
      search_block = modal_source[/^\s*search\(event\)\s*\{(.+?)\n\s{2}\}/m].to_s
      expect(search_block).to match(/event\.key === "Enter"/)
      expect(search_block).to match(/this\._fire\(q\)/)
    end

    it "respects the min-chars gate for non-Enter inputs" do
      expect(modal_source).to match(/q\.length < this\.minCharsValue/)
    end

    it "schedules the debounced fire via setTimeout using debounceValue" do
      expect(modal_source).to match(/setTimeout\(\(\)\s*=>\s*this\._fire\(q\),\s*this\.debounceValue\)/)
    end

    it "_fire writes the URL into the shared igdb_search_results Turbo Frame" do
      fire_block = modal_source[/^\s*_fire\(q\)\s*\{(.+?)\n\s{2}\}/m].to_s
      expect(fire_block).to include("new URL(this.urlValue, window.location.origin)")
      expect(fire_block).to include('url.searchParams.set("q", q)')
      expect(fire_block).to include('document.getElementById("igdb_search_results")')
      expect(fire_block).to match(/frame\.src\s*=\s*url\.toString\(\)/)
    end

    it "carries no forbidden alert/confirm/prompt calls (CLAUDE.md hard rule)" do
      expect(modal_source_without_comments).not_to match(/\b(?:alert|confirm|prompt)\s*\(/)
    end
  end
end
