# frozen_string_literal: true

require "rails_helper"

# Unit spec for Pito::Dispatch::Matrix — the reply-availability matrix derived
# from config/pito/tools.yml. Pins every public API method: targets, actions_for,
# mode_for (alias-aware, base-mode derivation), tool_for, universal_tokens, reload!.
RSpec.describe Pito::Dispatch::Matrix, type: :dispatch do
  # Reload around each example so edits to Config in other specs don't leak.
  around do |example|
    described_class.reload!
    example.run
    described_class.reload!
  end

  # ── targets ────────────────────────────────────────────────────────────────────

  describe ".targets" do
    it "returns an Array of String reply_target ids" do
      expect(described_class.targets).to be_an(Array)
      expect(described_class.targets).to all(be_a(String))
    end

    it "includes the well-known targets from tools.yml" do
      expect(described_class.targets).to include(
        "game_list", "video_list", "channel_list",
        "game_detail", "video_detail", "channel_detail",
        "analytics_glance", "analyze_message",
        "confirmation", "resume_missing", "video_search"
      )
    end

    it "does not include invented target ids" do
      expect(described_class.targets).not_to include("nonexistent_target")
    end
  end

  # ── actions_for ────────────────────────────────────────────────────────────────

  describe ".actions_for" do
    it "returns [] for an unknown target" do
      expect(described_class.actions_for("unknown_target")).to eq([])
    end

    it "returns an Array of Strings for a known target" do
      expect(described_class.actions_for("game_list")).to be_an(Array)
      expect(described_class.actions_for("game_list")).to all(be_a(String))
    end

    it "includes canonical tool names for the target" do
      expect(described_class.actions_for("game_list")).to include("show", "delete", "analyze", "next")
      expect(described_class.actions_for("video_list")).to include("show", "delete", "schedule", "publish")
    end

    it "includes per-target aliases (del/rm on delete targets, order on sort targets, pub on publish targets)" do
      # del/rm are per-target aliases of delete on these targets (tool-level aliases
      # are NOT auto-expanded into actions_for — only per-target aliases are).
      expect(described_class.actions_for("game_list")).to include("del", "rm")
      expect(described_class.actions_for("game_list")).to include("order")
      expect(described_class.actions_for("video_list")).to include("del", "rm")
      expect(described_class.actions_for("video_list")).to include("order")
      expect(described_class.actions_for("video_list")).to include("pub")
      expect(described_class.actions_for("video_detail")).to include("del", "rm", "pub")
    end

    it "does NOT expand tool-level aliases (analytics/stats from analyze, yes/y from confirm)" do
      # Tool-level aliases are chat-context synonyms; they must not appear as
      # reply-target suggestions or they pollute the follow-up palette.
      expect(described_class.actions_for("analytics_glance")).not_to include("analytics", "stats")
      expect(described_class.actions_for("video_list")).not_to include("analytics", "stats")
      expect(described_class.actions_for("confirmation")).not_to include("yes", "y", "ok", "approve", "true")
      expect(described_class.actions_for("confirmation")).not_to include("no", "n", "false", "discard")
    end

    it "includes per-target aliases (new → resume_missing aliases: [create])" do
      expect(described_class.actions_for("resume_missing")).to include("new", "create")
    end

    # G92 (2026-07-05): `help` removed from universal_reply; universal tokens are
    # now only share / revoke / unshare.
    it "includes the full universal reply set on every known target" do
      %w[share revoke unshare].each do |token|
        expect(described_class.actions_for("game_list")).to include(token)
        expect(described_class.actions_for("video_list")).to include(token)
        expect(described_class.actions_for("analytics_glance")).to include(token)
        expect(described_class.actions_for("confirmation")).to include(token)
        expect(described_class.actions_for("channel_visit")).to include(token)
      end
    end

    it "has no duplicate tokens for any target" do
      described_class.targets.each do |tid|
        list = described_class.actions_for(tid)
        expect(list.uniq).to(eq(list), "#{tid} has duplicate tokens: #{(list - list.uniq).inspect}")
      end
    end

    it "game_detail includes all expected tool tokens" do
      expect(described_class.actions_for("game_detail")).to include(
        "delete", "del", "rm", "reindex", "link", "unlink",
        "footage", "platform", "price", "shinies", "sync", "analyze"
      )
    end

    it "channel_list includes sort/order/next/shinies/analyze" do
      expect(described_class.actions_for("channel_list")).to include(
        "shinies", "analyze", "sort", "order", "next"
      )
    end

    it "analytics_glance includes with/without/analyze" do
      expect(described_class.actions_for("analytics_glance")).to include("with", "without", "analyze")
    end

    it "channel_visit includes consume" do
      expect(described_class.actions_for("channel_visit")).to include("consume")
    end

    it "confirmation includes confirm and cancel (only — no tool-level aliases)" do
      expect(described_class.actions_for("confirmation")).to include("confirm", "cancel")
      # Tool-level aliases (yes/y/ok/approve/true, no/n/false/discard) are
      # intentionally excluded from actions_for — they are chat-context synonyms
      # and would pollute the follow-up suggestion palette.
    end

    it "video_search mirrors video_list MINUS next/more/sort/order/analyze" do
      expect(described_class.actions_for("video_search")).to include(
        "show", "delete", "schedule", "publish", "unlist",
        "link", "unlink", "with", "without", "at-a-glance", "game", "shinies",
        "rm", "del", "pub"
      )
      expect(described_class.actions_for("video_search")).not_to include(
        "next", "more", "sort", "order", "analyze"
      )
    end
  end

  # ── mode_for ───────────────────────────────────────────────────────────────────

  describe ".mode_for" do
    it "returns nil for an unknown target" do
      expect(described_class.mode_for("nonexistent_target")).to be_nil
    end

    it "falls back to the target's base mode for an unknown action (HF3 — DSL parity)" do
      expect(described_class.mode_for("game_list", action: "bogus_action"))
        .to eq(described_class.mode_for("game_list", action: nil))
    end

    # ── Base mode (action: nil) ───────────────────────────────────────────────

    describe "base mode (action: nil)" do
      it "returns :append for game_list (mixed modes; append is the class default)" do
        expect(described_class.mode_for("game_list", action: nil)).to eq(:append)
      end

      it "returns :append for video_list" do
        expect(described_class.mode_for("video_list", action: nil)).to eq(:append)
      end

      it "returns :append for analytics_glance" do
        expect(described_class.mode_for("analytics_glance", action: nil)).to eq(:append)
      end

      it "returns :mutate for analyze_message (all tool entries are mutate)" do
        expect(described_class.mode_for("analyze_message", action: nil)).to eq(:mutate)
      end

      it "returns :mutate for channel_visit (only tool is consume → mutate)" do
        expect(described_class.mode_for("channel_visit", action: nil)).to eq(:mutate)
      end
    end

    # ── Universal actions are always :append ───────────────────────────────────
    # G92 (2026-07-05): `help` removed from universal_reply; share/revoke/unshare remain.

    describe "universal actions" do
      %w[share revoke unshare].each do |token|
        it "#{token.inspect} returns :append on any target" do
          expect(described_class.mode_for("game_list", action: token)).to eq(:append)
          expect(described_class.mode_for("analyze_message", action: token)).to eq(:append)
          expect(described_class.mode_for("channel_visit", action: token)).to eq(:append)
        end
      end
    end

    # ── Canonical tool actions ─────────────────────────────────────────────────

    it "returns :append for show on game_list" do
      expect(described_class.mode_for("game_list", action: "show")).to eq(:append)
    end

    it "returns :append for analyze on analytics_glance" do
      expect(described_class.mode_for("analytics_glance", action: "analyze")).to eq(:append)
    end

    it "returns :mutate for with on game_list" do
      expect(described_class.mode_for("game_list", action: "with")).to eq(:mutate)
    end

    it "returns :mutate for without on video_list" do
      expect(described_class.mode_for("video_list", action: "without")).to eq(:mutate)
    end

    it "returns :mutate for sort on channel_list" do
      expect(described_class.mode_for("channel_list", action: "sort")).to eq(:mutate)
    end

    it "returns :mutate for with/without on analyze_message" do
      expect(described_class.mode_for("analyze_message", action: "with")).to eq(:mutate)
      expect(described_class.mode_for("analyze_message", action: "without")).to eq(:mutate)
    end

    # ── Alias resolution ───────────────────────────────────────────────────────

    describe "tool-level alias resolution" do
      it "del → delete: returns :append on game_list" do
        expect(described_class.mode_for("game_list", action: "del")).to eq(:append)
      end

      it "rm → delete: returns :append on video_list" do
        expect(described_class.mode_for("video_list", action: "rm")).to eq(:append)
      end

      it "order → sort: returns :mutate on game_list" do
        expect(described_class.mode_for("game_list", action: "order")).to eq(:mutate)
      end

      it "order → sort: returns :mutate on video_list" do
        expect(described_class.mode_for("video_list", action: "order")).to eq(:mutate)
      end

      it "order → sort: returns :mutate on channel_list" do
        expect(described_class.mode_for("channel_list", action: "order")).to eq(:mutate)
      end

      it "order → sort: returns :mutate on game_linked_videos" do
        expect(described_class.mode_for("game_linked_videos", action: "order")).to eq(:mutate)
      end

      it "pub → publish: returns :append on video_list" do
        expect(described_class.mode_for("video_list", action: "pub")).to eq(:append)
      end

      it "pub → publish: returns :append on video_detail" do
        expect(described_class.mode_for("video_detail", action: "pub")).to eq(:append)
      end

      it "unshare → revoke (universal): returns :append on any target" do
        expect(described_class.mode_for("game_list", action: "unshare")).to eq(:append)
      end
    end

    describe "per-target alias resolution" do
      it "create → new on resume_missing returns :append" do
        expect(described_class.mode_for("resume_missing", action: "create")).to eq(:append)
      end

      it "new (canonical) on resume_missing returns :append" do
        expect(described_class.mode_for("resume_missing", action: "new")).to eq(:append)
      end
    end

    # ── Per-target mode isolation ──────────────────────────────────────────────

    it "sort is :mutate on list targets; a tool absent from a target falls back to base mode (HF3)" do
      expect(described_class.mode_for("game_channels", action: "sort"))
        .to eq(described_class.mode_for("game_channels", action: nil))
    end
  end

  # ── tool_for ──────────────────────────────────────────────────────────────────

  describe ".mode_for — unknown action falls back to base mode (HF3)" do
    it "returns the target's base mode for an unrecognized token (DSL parity: --help fall-through)" do
      expect(described_class.mode_for("game_list", action: "--help"))
        .to eq(described_class.mode_for("game_list", action: nil))
    end
  end

  describe ".tool_for" do
    it "returns the canonical tool for a canonical name" do
      expect(described_class.tool_for("delete")).to eq("delete")
      expect(described_class.tool_for("sort")).to eq("sort")
      expect(described_class.tool_for("publish")).to eq("publish")
    end

    it "resolves tool-level aliases → canonical" do
      expect(described_class.tool_for("del")).to eq("delete")
      expect(described_class.tool_for("rm")).to eq("delete")
      expect(described_class.tool_for("order")).to eq("sort")
      expect(described_class.tool_for("pub")).to eq("publish")
      expect(described_class.tool_for("ls")).to eq("list")
    end

    it "resolves universal_reply aliases" do
      expect(described_class.tool_for("unshare")).to eq("revoke")
    end

    it "returns nil for unknown tokens" do
      expect(described_class.tool_for("bogus")).to be_nil
    end

    it "returns nil for per-target-only aliases (not in global index)" do
      # 'create' is only an alias of 'new' on resume_missing — not a global alias.
      expect(described_class.tool_for("create")).to be_nil
    end

    it "is case-insensitive" do
      expect(described_class.tool_for("DEL")).to eq("delete")
      expect(described_class.tool_for("Order")).to eq("sort")
    end
  end

  # ── universal_tokens ─────────────────────────────────────────────────────────

  describe ".universal_tokens" do
    # G92 (2026-07-05): `help` removed from universal_reply; canonical tokens are share + revoke only.
    it "includes the canonical universal tool names" do
      expect(described_class.universal_tokens).to include("share", "revoke")
      expect(described_class.universal_tokens).not_to include("help")
    end

    it "includes aliases of universal tools (unshare → revoke)" do
      expect(described_class.universal_tokens).to include("unshare")
    end

    it "returns a frozen Array of Strings" do
      expect(described_class.universal_tokens).to be_frozen
      expect(described_class.universal_tokens).to be_an(Array)
      expect(described_class.universal_tokens).to all(be_a(String))
    end
  end

  # ── except: target exclusion ─────────────────────────────────────────────────
  #
  # Ship-the-capability coverage: except: is not used in the real tools.yml (kinds:
  # covers the owner's policy), but the Matrix wires it and tests pin the behaviour
  # via synthetic docs injected through DispatchConfigInjection.

  describe "except: universal tool exclusion (synthetic doc)" do
    context "when share has except: [game_list]" do
      before do
        inject_dispatch_config!(universal_reply: <<~YAML)
          share:
            mode: append
            except: [game_list]
        YAML
      end
      after { restore_dispatch_config! }

      it "does NOT include share in actions_for(game_list)" do
        expect(described_class.actions_for("game_list")).not_to include("share")
      end

      it "still includes share in actions_for(video_list) (not excepted)" do
        expect(described_class.actions_for("video_list")).to include("share")
      end

      # G92 (2026-07-05): `help` removed from universal_reply; revoke is the only un-excepted universal here.
      it "still includes revoke in actions_for(game_list) (not excepted)" do
        expect(described_class.actions_for("game_list")).to include("revoke")
        expect(described_class.actions_for("game_list")).not_to include("help")
      end

      it "mode_for(game_list, action: share) falls back to base mode (HF3 — not a universal for this target)" do
        base = described_class.mode_for("game_list", action: nil)
        expect(described_class.mode_for("game_list", action: "share")).to eq(base)
      end

      it "mode_for(video_list, action: share) is :append (universal, not excepted)" do
        expect(described_class.mode_for("video_list", action: "share")).to eq(:append)
      end
    end

    context "when an alias of an excepted universal tool is used" do
      before do
        inject_dispatch_config!(universal_reply: <<~YAML)
          revoke:
            mode: append
            aliases: [unshare]
            except: [confirmation]
        YAML
      end
      after { restore_dispatch_config! }

      it "does NOT include the alias (unshare) in actions_for for the excepted target" do
        expect(described_class.actions_for("confirmation")).not_to include("revoke")
        expect(described_class.actions_for("confirmation")).not_to include("unshare")
      end

      it "includes the alias in a non-excepted target" do
        expect(described_class.actions_for("game_list")).to include("revoke", "unshare")
      end
    end
  end

  # ── reload! ──────────────────────────────────────────────────────────────────

  describe ".reload!" do
    it "clears memoization so the next call rebuilds the index" do
      idx_before = described_class.idx
      described_class.reload!
      idx_after = described_class.idx
      expect(idx_after).not_to equal(idx_before)
    end

    it "returns nil" do
      expect(described_class.reload!).to be_nil
    end

    it "produces an equivalent index after reload (same data, new object)" do
      before = described_class.idx
      described_class.reload!
      after = described_class.idx
      expect(after).to eq(before)
    end
  end
end
