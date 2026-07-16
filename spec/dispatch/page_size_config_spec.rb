# frozen_string_literal: true

require "rails_helper"

# ── Pager page-size regression suite ─────────────────────────────────────────
#
# config/pito/tools.yml declares a `concerns.pager` block on every tool whose
# chat/slash/cursor surface paginates. The exact page sizes are load-bearing —
# clients (the chatbox pager, pito-tui's viewport feeds) are tuned against
# them, and `list`/`search` in particular are the owner's named invariants
# (list: 50, search: 20). This spec pins the CURRENT values, read through
# Pito::Dispatch::Config's public accessors (not raw YAML), so a future edit
# to tools.yml that silently changes a page size — or drops a pager block
# entirely — fails loudly here instead of surfacing as a client-side surprise.
RSpec.describe "tools.yml pager page-size config", type: :dispatch do
  before(:all) { Pito::Dispatch::Config.reload! }

  # Every tool that currently declares a `concerns.pager` block, with its
  # exact page_size / max_page_size / more_tool as found in tools.yml today.
  # `max_page_size` is nil where the YAML declares none — Config.max_page_size
  # falls back to page_size in that case (asserted separately below).
  PAGER_TOOLS = {
    list: {
      page_size:     50,
      max_page_size: nil,
      more_tool:     "next"
    },
    search: {
      page_size:     20,
      max_page_size: 100,
      more_tool:     "next"
    },
    resume: {
      page_size:     50,
      max_page_size: 100,
      more_tool:     "next"
    },
    games: {
      page_size:     10,
      max_page_size: 50,
      more_tool:     "next"
    },
    notifications: {
      page_size:     50,
      max_page_size: 100,
      more_tool:     "next"
    }
  }.freeze

  # ── Named invariants (the owner's explicit pins) ────────────────────────────
  describe "the owner's named invariants" do
    it "list pages at 50" do
      expect(Pito::Dispatch::Config.pager(tool: :list)[:page_size]).to eq(50)
    end

    it "search pages at 20" do
      expect(Pito::Dispatch::Config.pager(tool: :search)[:page_size]).to eq(20)
    end
  end

  # ── Table-driven: every configured tool, read through Config accessors ─────
  describe "pager(tool:) — the raw concern hash, per tool" do
    PAGER_TOOLS.each do |tool, expected|
      it "pager(tool: #{tool.inspect}) carries its declared page_size/more_tool" do
        pager = Pito::Dispatch::Config.pager(tool: tool)

        expect(pager).not_to(be_nil, "#{tool} lost its pager concern entirely")
        expect(pager[:page_size]).to eq(expected[:page_size])
        expect(pager[:more_tool]).to eq(expected[:more_tool])

        if expected[:max_page_size]
          expect(pager[:max_page_size]).to eq(expected[:max_page_size])
        else
          expect(pager).not_to have_key(:max_page_size)
        end
      end
    end
  end

  describe "max_page_size(tool:) — the resolved client-facing ceiling, per tool" do
    PAGER_TOOLS.each do |tool, expected|
      it "max_page_size(tool: #{tool.inspect}) resolves to the declared cap (or page_size fallback)" do
        resolved = expected[:max_page_size] || expected[:page_size]
        expect(Pito::Dispatch::Config.max_page_size(tool: tool)).to eq(resolved)
      end
    end
  end

  # ── Negative guard: a tool with NO pager concern reports nil, not a crash ──
  describe "tools without a pager concern" do
    it "pager(tool: :show) is nil — show declares no pager" do
      expect(Pito::Dispatch::Config.pager(tool: :show)).to be_nil
    end

    it "max_page_size(tool: :show) is nil — no pager to derive a ceiling from" do
      expect(Pito::Dispatch::Config.max_page_size(tool: :show)).to be_nil
    end
  end

  # ── Drift guard: no OTHER tool has quietly grown a pager concern ───────────
  # If this fails, a new pager was added in tools.yml without a corresponding
  # entry (and explicit review) in PAGER_TOOLS above.
  it "PAGER_TOOLS is the exact set of tools declaring a pager concern" do
    configured = Pito::Dispatch::Config.data[:tools].filter_map do |tool, body|
      tool if body.dig(:concerns, :pager)
    end
    expect(configured).to match_array(PAGER_TOOLS.keys)
  end
end
