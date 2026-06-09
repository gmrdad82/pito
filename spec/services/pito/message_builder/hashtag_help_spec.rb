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

        it "body lists the footage action" do
          expect(result["body"]).to include("footage")
        end

        it "body lists the link action" do
          expect(result["body"]).to include("link")
        end

        it "body lists the unlink action" do
          expect(result["body"]).to include("unlink")
        end

        it "body lists the resync action" do
          expect(result["body"]).to include("resync")
        end

        it "body includes --help option" do
          expect(result["body"]).to include("--help")
        end
      end

      context "action-level page (action: 'footage')" do
        subject(:result) { described_class.call(target: "game_detail", action: "footage") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes 'Usage:'" do
          expect(result["body"]).to include("Usage:")
        end

        it "body includes the footage usage shape" do
          expect(result["body"]).to include("footage")
          expect(result["body"]).to include("path")
        end

        it "body includes the --help option" do
          expect(result["body"]).to include("--help")
        end

        it "body is wrapped in .pito-help-block" do
          expect(result["body"]).to include('class="pito-help-block"')
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

        it "body includes the visit action" do
          expect(result["body"]).to include("visit")
        end

        it "body includes the reindex action" do
          expect(result["body"]).to include("reindex")
        end
      end

      context "action-level page (action: 'visit')" do
        subject(:result) { described_class.call(target: "channel_list", action: "visit") }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions @handle" do
          expect(result["body"]).to include("handle")
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
  end
end
