# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::CommandHelp do
  describe ".call" do
    # ── :list delegation ──────────────────────────────────────────────────────

    context "when verb is :list" do
      context "noun: nil (bare `list --help` → noun-index page)" do
        subject(:result) { described_class.call(:list) }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes 'Usage:'" do
          expect(result["body"]).to include("Usage:")
        end

        it "body includes a Forms group" do
          expect(result["body"]).to include("Forms")
        end

        it "body lists 'list games'" do
          expect(result["body"]).to include("list games")
        end

        it "body lists 'list videos'" do
          expect(result["body"]).to include("list videos")
        end

        it "body lists 'list channels'" do
          expect(result["body"]).to include("list channels")
        end

        it "body includes '--help' option" do
          expect(result["body"]).to include("--help")
        end

        it "does NOT equal the Game::ListHelp man page (which has a Columns group)" do
          games_payload = Pito::MessageBuilder::Game::ListHelp.call
          expect(result["body"]).not_to eq(games_payload["body"])
        end

        it "body does NOT include 'Columns:'" do
          # Columns: is a distinguishing feature of the noun-level list pages
          expect(result["body"]).not_to include("Columns:")
        end
      end

      context "noun: :games" do
        it "delegates to Game::ListHelp" do
          list_payload = Pito::MessageBuilder::Game::ListHelp.call
          result = described_class.call(:list, noun: :games)
          expect(result["body"]).to eq(list_payload["body"])
        end
      end

      context "noun: :videos" do
        subject(:result) { described_class.call(:list, noun: :videos) }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes 'Usage:'" do
          expect(result["body"]).to include("Usage:")
        end

        it "body mentions 'list videos'" do
          expect(result["body"]).to include("list videos")
        end

        it "body mentions the 'game' column" do
          expect(result["body"]).to include("game")
        end

        it "body mentions the 'duration' column" do
          expect(result["body"]).to include("duration")
        end

        it "body mentions the 'views' column" do
          expect(result["body"]).to include("views")
        end

        it "body mentions the 'likes' column" do
          expect(result["body"]).to include("likes")
        end

        it "body mentions the 'comments' column" do
          expect(result["body"]).to include("comments")
        end

        it "body is wrapped in .pito-help-block" do
          expect(result["body"]).to include('class="pito-help-block"')
        end
      end

      context "noun: :channels" do
        subject(:result) { described_class.call(:list, noun: :channels) }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes 'Usage:'" do
          expect(result["body"]).to include("Usage:")
        end

        it "body mentions 'list channels'" do
          expect(result["body"]).to include("list channels")
        end

        it "body includes a witty one-liner" do
          # The channels help always appends one line from channels_help array.
          # With the deterministic sampler (first entry) that's the first variant.
          expect(result["body"]).to include("Nothing here")
        end
      end
    end

    # ── Unknown verb ──────────────────────────────────────────────────────────

    context "when verb is unknown" do
      it "returns nil for an entirely unknown verb" do
        expect(described_class.call(:nope)).to be_nil
      end

      it "returns nil for an unknown noun on a known verb" do
        expect(described_class.call(:show, noun: :widget)).to be_nil
      end
    end

    # ── Verb-level pages (bare `<verb> --help`) ───────────────────────────────

    describe "verb-level page (noun: nil)" do
      context "delete (multi-noun: game + video)" do
        subject(:result) { described_class.call(:delete) }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body includes 'Usage:'" do
          expect(result["body"]).to include("Usage:")
        end

        it "body includes the delete verb" do
          expect(result["body"]).to include("delete")
        end

        it "body lists the game form" do
          expect(result["body"]).to include("game")
        end

        it "body lists the video form" do
          expect(result["body"]).to include("video")
        end

        it "body includes --help option" do
          expect(result["body"]).to include("--help")
        end

        it "body is wrapped in .pito-help-block" do
          expect(result["body"]).to include('class="pito-help-block"')
        end
      end

      context "footage (single-noun: game)" do
        subject(:result) { described_class.call(:footage) }

        it "returns a valid html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "verb-level page == noun-level page for single-entity verb" do
          noun_result = described_class.call(:footage, noun: :game)
          expect(result["body"]).to eq(noun_result["body"])
        end

        it "body includes the footage path argument" do
          expect(result["body"]).to include("path")
        end
      end

      context "show (multi-noun: game + video)" do
        subject(:result) { described_class.call(:show) }

        it "body lists both game and video forms" do
          expect(result["body"]).to include("game")
          expect(result["body"]).to include("video")
        end

        it "body uses id-only wording (no title)" do
          expect(result["body"]).not_to match(/title/i)
          expect(result["body"]).to include("id")
        end
      end

      # Remaining verbs — smoke-test that each renders a valid page
      %i[reindex link unlink publish unlist schedule import sync].each do |verb|
        context "verb :#{verb}" do
          subject(:result) { described_class.call(verb) }

          it "returns an html payload" do
            expect(result).to be_a(Hash)
            expect(result["html"]).to be(true)
          end

          it "body includes 'Usage:'" do
            expect(result["body"]).to include("Usage:")
          end

          it "body includes the verb name" do
            expect(result["body"]).to include(verb.to_s)
          end

          it "body includes '--help'" do
            expect(result["body"]).to include("--help")
          end
        end
      end
    end

    # ── Noun-level pages (`<verb> <noun> --help`) ─────────────────────────────

    describe "noun-level page (noun: given)" do
      context "delete game --help" do
        subject(:result) { described_class.call(:delete, noun: :game) }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "usage line mentions 'delete game <id>'" do
          expect(result["body"]).to include("delete game")
          expect(result["body"]).to include("&lt;id&gt;")
        end

        it "body describes id-only (never title)" do
          expect(result["body"]).to include("id")
          expect(result["body"]).not_to include("title")
        end

        it "body includes --help option" do
          expect(result["body"]).to include("--help")
        end
      end

      context "show game --help" do
        subject(:result) { described_class.call(:show, noun: :game) }

        it "usage line is id-only (no title)" do
          expect(result["body"]).to include("id")
          expect(result["body"]).not_to include("title")
        end

        it "body is wrapped in .pito-help-block" do
          expect(result["body"]).to include('class="pito-help-block"')
        end
      end

      context "footage game --help (single-entity verb)" do
        subject(:result) { described_class.call(:footage, noun: :game) }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "usage line includes footage game path shape" do
          expect(result["body"]).to include("footage game")
          expect(result["body"]).to include("path")
        end
      end

      context "import videos --help" do
        subject(:result) { described_class.call(:import, noun: :videos) }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions @handle override" do
          expect(result["body"]).to include("handle")
        end
      end

      context "sync channels --help" do
        subject(:result) { described_class.call(:sync, noun: :channels) }

        it "returns an html payload" do
          expect(result).to be_a(Hash)
          expect(result["html"]).to be(true)
        end

        it "body mentions 'with' option" do
          expect(result["body"]).to include("with")
        end
      end

      context "schedule video --help" do
        subject(:result) { described_class.call(:schedule, noun: :video) }

        it "body lists the schedule when-forms (incl. the DD-MM-YYYY date format)" do
          expect(result["body"]).to include("DD-MM-YYYY")
        end
      end
    end
  end
end
