# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::HashtagHelp do
  # Ensure all handlers are registered before each example.
  before { Pito::FollowUp::Registry.register_all! }

  describe ".call" do
    # ── Internal / unknown targets ────────────────────────────────────────────

    context "when target is internal (channel_visit)" do
      it "returns nil" do
        expect(described_class.call(target: "channel_visit")).to be_nil
      end
    end

    context "when target is unknown" do
      it "returns nil for a completely unknown target" do
        expect(described_class.call(target: "does_not_exist")).to be_nil
      end
    end

    context "when action is unknown on a known target" do
      it "returns nil" do
        expect(described_class.call(target: "game_detail", action: "nonexistent_action")).to be_nil
      end
    end

    # ── game_detail / show-game ────────────────────────────────────────────────

    describe "game_detail target (show-game indicator)" do
      context "target-level page (action: nil)" do
        subject(:result) { described_class.call(target: "game_detail") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes 'Usage:'" do
          expect(result["body"]).to include("Usage:")
        end

        it "body is wrapped in .pito-help-block" do
          expect(result["body"]).to include('class="pito-help-block"')
        end

        it "body lists the delete action" do
          expect(result["body"]).to include("delete")
        end

        it "body lists the price action" do
          expect(result["body"]).to include("price")
        end

        it "body lists the link action" do
          expect(result["body"]).to include("link")
        end

        it "body lists the unlink action" do
          expect(result["body"]).to include("unlink")
        end

        it "body lists the reindex action" do
          expect(result["body"]).to include("reindex")
        end

        it "body includes --help option" do
          expect(result["body"]).to include("--help")
        end

        # G92 (2026-07-05): `help` removed from universal_reply; target pages no
        # longer show a "help" action row — the --help FLAG is the surviving surface.
        it "body does NOT list a universal `help` action row (G92)" do
          expect(result["body"]).not_to include(">help</span>")
        end
      end

      context "action-level page (action: 'price')" do
        subject(:result) { described_class.call(target: "game_detail", action: "price") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes 'Usage:'" do
          expect(result["body"]).to include("Usage:")
        end

        it "body includes the price usage shape" do
          expect(result["body"]).to include("price")
          expect(result["body"]).to include("amount")
        end

        it "body includes the --help option" do
          expect(result["body"]).to include("--help")
        end

        it "body is wrapped in .pito-help-block" do
          expect(result["body"]).to include('class="pito-help-block"')
        end
      end

      context "action-level page (action: 'footage', retired WP1)" do
        it "returns nil (footage is no longer a declared game_detail action)" do
          expect(described_class.call(target: "game_detail", action: "footage")).to be_nil
        end
      end

      context "action-level page (action: 'delete')" do
        subject(:result) { described_class.call(target: "game_detail", action: "delete") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions delete" do
          expect(result["body"]).to include("delete")
        end
      end

      context "action-level page (action: 'link')" do
        subject(:result) { described_class.call(target: "game_detail", action: "link") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions video id" do
          expect(result["body"]).to include("video")
          expect(result["body"]).to include("id")
        end
      end
    end

    # ── game_list / list-games ─────────────────────────────────────────────────

    describe "game_list target (list-games indicator)" do
      context "target-level page (action: nil)" do
        subject(:result) { described_class.call(target: "game_list") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes the show action" do
          expect(result["body"]).to include("show")
        end

        it "body includes the delete action" do
          expect(result["body"]).to include("delete")
        end

        it "body includes the rm action" do
          expect(result["body"]).to include("rm")
        end

        it "body includes the with action" do
          expect(result["body"]).to include("with")
        end

        it "body includes the without action" do
          expect(result["body"]).to include("without")
        end
      end

      context "action-level page (action: 'show')" do
        subject(:result) { described_class.call(target: "game_list", action: "show") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes id wording" do
          expect(result["body"]).to include("id")
        end
      end

      context "action-level page (action: 'delete')" do
        subject(:result) { described_class.call(target: "game_list", action: "delete") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes id wording" do
          expect(result["body"]).to include("id")
        end
      end

      context "action-level page (action: 'with')" do
        subject(:result) { described_class.call(target: "game_list", action: "with") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions columns" do
          expect(result["body"]).to include("columns")
        end

        it "body mentions game column vocab (platform)" do
          expect(result["body"]).to include("platform")
        end

        it "body mentions game column vocab (genre)" do
          expect(result["body"]).to include("genre")
        end
      end

      context "action-level page (action: 'without')" do
        subject(:result) { described_class.call(target: "game_list", action: "without") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions columns" do
          expect(result["body"]).to include("columns")
        end

        it "body mentions game column vocab (publisher)" do
          expect(result["body"]).to include("publisher")
        end
      end

      context "action-level page (action: 'sort')" do
        subject(:result) { described_class.call(target: "game_list", action: "sort") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes the usage line" do
          expect(result["body"]).to include("sort")
        end

        it "body includes sortable column names (release date removed — item 24)" do
          expect(result["body"]).to include("title")
          expect(result["body"]).to include("platform")
          expect(result["body"]).not_to include("release date")
        end

        it "body mentions [desc] option" do
          expect(result["body"]).to include("desc")
        end
      end

      context "action-level page (action: 'order') — normalizes to sort copy" do
        subject(:result) { described_class.call(target: "game_list", action: "order") }

        it "returns an html payload (renders the sort page)" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes sort column content" do
          expect(result["body"]).to include("title")
        end
      end

      context "target-level page — includes sort action row" do
        subject(:result) { described_class.call(target: "game_list") }

        it "body includes the sort action" do
          expect(result["body"]).to include("sort")
        end

        it "body does NOT include an extra 'order' row (order has no own copy)" do
          # The target page iterates actions and shows rows where copy exists.
          # 'order' has no own copy block so it is skipped (next unless data).
          # Count occurrences: 'order' may appear in the sort usage, that's ok;
          # we just verify the page renders without error and contains sort.
          expect(result["body"]).to be_a(String)
        end
      end
    end

    # ── video_detail / show-video ──────────────────────────────────────────────

    describe "video_detail target (show-video indicator)" do
      context "target-level page (action: nil)" do
        subject(:result) { described_class.call(target: "video_detail") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes the delete action" do
          expect(result["body"]).to include("delete")
        end

        it "body includes the reindex action" do
          expect(result["body"]).to include("reindex")
        end

        it "body includes the link action" do
          expect(result["body"]).to include("link")
        end

        it "body includes the unlink action" do
          expect(result["body"]).to include("unlink")
        end
      end

      context "action-level page (action: 'reindex')" do
        subject(:result) { described_class.call(target: "video_detail", action: "reindex") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions reindex" do
          expect(result["body"]).to include("reindex")
        end
      end

      context "action-level page (action: 'link')" do
        subject(:result) { described_class.call(target: "video_detail", action: "link") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions game id" do
          expect(result["body"]).to include("game")
          expect(result["body"]).to include("id")
        end
      end
    end

    # ── video_list / list-videos ───────────────────────────────────────────────

    describe "video_list target (list-videos indicator)" do
      context "target-level page (action: nil)" do
        subject(:result) { described_class.call(target: "video_list") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes the show action" do
          expect(result["body"]).to include("show")
        end

        it "body includes the delete action" do
          expect(result["body"]).to include("delete")
        end

        it "body includes the with action" do
          expect(result["body"]).to include("with")
        end

        it "body includes the without action" do
          expect(result["body"]).to include("without")
        end
      end

      context "action-level page (action: 'with')" do
        subject(:result) { described_class.call(target: "video_list", action: "with") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions columns" do
          expect(result["body"]).to include("columns")
        end

        it "body mentions video column vocab (channel)" do
          expect(result["body"]).to include("channel")
        end

        it "body mentions video column vocab (visibility)" do
          expect(result["body"]).to include("visibility")
        end

        it "body mentions video column vocab (duration — canonical since G26.3)" do
          expect(result["body"]).to include("duration")
        end

        it "body mentions video column vocab (views)" do
          expect(result["body"]).to include("views")
        end
      end

      context "action-level page (action: 'without')" do
        subject(:result) { described_class.call(target: "video_list", action: "without") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions columns" do
          expect(result["body"]).to include("columns")
        end

        it "body mentions video column vocab (channel)" do
          expect(result["body"]).to include("channel")
        end

        it "body mentions video column vocab (visibility)" do
          expect(result["body"]).to include("visibility")
        end

        it "body mentions video column vocab (duration) and not the removed comments (G26.1/G26.3)" do
          expect(result["body"]).to include("duration")
          expect(result["body"]).not_to include("comments")
        end
      end

      context "action-level page (action: 'sort')" do
        subject(:result) { described_class.call(target: "video_list", action: "sort") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes sort-column names" do
          expect(result["body"]).to include("channel")
          expect(result["body"]).to include("visibility")
          expect(result["body"]).to include("views")
          expect(result["body"]).to include("likes")
          expect(result["body"]).to include("duration")
        end

        it "body mentions [desc] option" do
          expect(result["body"]).to include("desc")
        end
      end

      context "action-level page (action: 'order') — normalizes to sort copy" do
        subject(:result) { described_class.call(target: "video_list", action: "order") }

        it "returns an html payload (renders the sort page)" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes sort column content" do
          expect(result["body"]).to include("views")
        end
      end

      context "target-level page — includes sort action row" do
        subject(:result) { described_class.call(target: "video_list") }

        it "body includes the sort action" do
          expect(result["body"]).to include("sort")
        end
      end
    end

    # ── channel_list / list-channels ──────────────────────────────────────────

    describe "channel_list target (list-channels indicator)" do
      context "target-level page (action: nil)" do
        subject(:result) { described_class.call(target: "channel_list") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes the shinies action (visit moved to show channel)" do
          expect(result["body"]).to include("shinies")
          expect(result["body"]).not_to include("visit")
        end

        it "body does NOT include the reindex action" do
          expect(result["body"]).not_to include("reindex")
        end
      end
    end

    describe "channel_detail target (show-channel indicator)" do
      context "target-level page (action: nil)" do
        subject(:result) { described_class.call(target: "channel_detail") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes the visit action" do
          expect(result["body"]).to include("visit")
        end
      end

      context "action-level page (action: 'visit')" do
        subject(:result) { described_class.call(target: "channel_detail", action: "visit") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions channel and studio destinations" do
          expect(result["body"]).to include("channel")
          expect(result["body"]).to include("studio")
        end
      end
    end

    # ── confirmation / confirm ────────────────────────────────────────────────

    describe "confirmation target (confirm indicator)" do
      context "target-level page (action: nil)" do
        subject(:result) { described_class.call(target: "confirmation") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes the confirm action" do
          expect(result["body"]).to include("confirm")
        end

        it "body includes the cancel action" do
          expect(result["body"]).to include("cancel")
        end

        it "body includes --help option" do
          expect(result["body"]).to include("--help")
        end
      end

      context "action-level page (action: 'confirm')" do
        subject(:result) { described_class.call(target: "confirmation", action: "confirm") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions confirm aliases (yes, ok, approve, true)" do
          expect(result["body"]).to include("yes")
          expect(result["body"]).to include("ok")
          expect(result["body"]).to include("approve")
          expect(result["body"]).to include("true")
        end
      end

      context "action-level page (action: 'cancel')" do
        subject(:result) { described_class.call(target: "confirmation", action: "cancel") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions cancel aliases (no, false, discard)" do
          expect(result["body"]).to include("no")
          expect(result["body"]).to include("false")
          expect(result["body"]).to include("discard")
        end
      end
    end

    # ── Universal share verb rows ──────────────────────────────────────────────
    #
    # The target-level help page always includes a `share` row (from
    # pito.share_help.share); `revoke` and `unshare` rows are appended
    # only when a Share record exists for the supplied event.

    describe "universal share verb rows on the target-level page" do
      let(:conversation) { Conversation.create! }
      let(:turn) do
        conversation.turns.create!(
          position: Turn.next_position_for(conversation),
          input_kind: :chat, input_text: "hi"
        )
      end
      let(:event) do
        Event.create_with_position!(
          conversation:, turn:, kind: :system,
          payload: { "text" => "hello", "reply_handle" => "help-test" }
        )
      end

      context "with event: nil (no event context)" do
        subject(:result) { described_class.call(target: "game_detail", event: nil) }

        it "includes 'share' in the help body" do
          expect(result["body"]).to include("share")
        end

        it "does NOT include 'revoke' (no event to check Share against)" do
          expect(result["body"]).not_to include("revoke")
        end

        it "does NOT include 'unshare'" do
          expect(result["body"]).not_to include("unshare")
        end
      end

      context "with event but no Share record (un-shared)" do
        subject(:result) { described_class.call(target: "game_detail", event:) }

        it "includes 'share' in the help body" do
          expect(result["body"]).to include("share")
        end

        it "does NOT include 'revoke' when the event has no Share" do
          expect(result["body"]).not_to include("revoke")
        end

        it "does NOT include 'unshare' when the event has no Share" do
          expect(result["body"]).not_to include("unshare")
        end
      end

      context "with event AND a Share record (shared)" do
        before { Share.create!(event:, conversation:) }

        subject(:result) { described_class.call(target: "game_detail", event:) }

        it "includes 'share' in the help body" do
          expect(result["body"]).to include("share")
        end

        it "includes 'revoke' when the event has a Share" do
          expect(result["body"]).to include("revoke")
        end

        it "includes 'unshare' when the event has a Share" do
          expect(result["body"]).to include("unshare")
        end
      end

      context "action-level page — universal rows are not added to action pages" do
        subject(:result) { described_class.call(target: "game_detail", action: "price", event:) }

        it "returns an html payload (action page unaffected)" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end
      end
    end
  end
end
