# frozen_string_literal: true

require "rails_helper"

# ── Game::Traits::Apply — the write path (traits-design.md section 4) ──────
RSpec.describe Game::Traits::Apply, type: :service do
  let(:game) { create(:game) }

  describe "setting scales" do
    it "sets a scale value with the given source and enqueues a re-embed" do
      result = nil
      expect { result = described_class.call(game: game, source: "classified", scales: { "difficulty" => "brutal" }) }
        .to have_enqueued_job(GameEmbedIndexJob).with(game.id)

      expect(result).to eq(changed: true, skipped_owner: [])
      game.reload
      expect(game.trait_value("difficulty")).to eq("brutal")
      expect(game.trait_source("difficulty")).to eq("classified")
    end

    it "stamps classified_at (UTC ISO8601) only on a source: classified write" do
      described_class.call(game: game, source: "classified", scales: { "difficulty" => "brutal" })
      expect(game.reload.traits["classified_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end

    it "does not stamp classified_at on a source: owner write" do
      described_class.call(game: game, source: "owner", scales: { "difficulty" => "brutal" })
      expect(game.reload.traits["classified_at"]).to be_nil
    end

    it "keeps an existing classified_at across a later non-classified write" do
      described_class.call(game: game, source: "classified", scales: { "difficulty" => "brutal" })
      stamp = game.reload.traits["classified_at"]

      described_class.call(game: game, source: "owner", scales: { "pace" => "fast" })
      expect(game.reload.traits["classified_at"]).to eq(stamp)
    end

    it "removes a scale when the value is nil, deleting its sources entry for a classified write" do
      described_class.call(game: game, source: "classified", scales: { "difficulty" => "brutal" })
      described_class.call(game: game, source: "classified", scales: { "difficulty" => nil })

      game.reload
      expect(game.trait_value("difficulty")).to be_nil
      expect(game.trait_source("difficulty")).to be_nil
    end

    it "removes a scale but KEEPS a pinned-absent sources entry for an owner removal" do
      described_class.call(game: game, source: "classified", scales: { "difficulty" => "brutal" })
      described_class.call(game: game, source: "owner", scales: { "difficulty" => nil })

      game.reload
      expect(game.trait_value("difficulty")).to be_nil
      expect(game.trait_source("difficulty")).to eq("owner")
    end

    it "raises Pito::Error::TraitInvalid for an unknown scale name" do
      expect { described_class.call(game: game, source: "classified", scales: { "nope" => "x" }) }
        .to raise_error(Pito::Error::TraitInvalid, /unknown scale "nope"/)
    end

    it "raises Pito::Error::TraitInvalid for an out-of-vocabulary scale value" do
      expect { described_class.call(game: game, source: "classified", scales: { "difficulty" => "impossible" }) }
        .to raise_error(Pito::Error::TraitInvalid, /not a valid value for scale "difficulty"/)
    end
  end

  describe "tags" do
    it "adds a classified tag in declaration order regardless of call order" do
      described_class.call(game: game, source: "classified", add_tags: %w[worth_it space])
      expect(game.reload.trait_tags).to eq(%w[space worth_it])
    end

    it "removing a classified/derived tag deletes both the value and its sources entry" do
      described_class.call(game: game, source: "classified", add_tags: [ "space" ])
      described_class.call(game: game, source: "classified", remove_tags: [ "space" ])

      game.reload
      expect(game.trait_tags).not_to include("space")
      expect(game.trait_source("space")).to be_nil
    end

    it "removing a tag with source: owner keeps a pinned-absent sources entry" do
      described_class.call(game: game, source: "classified", add_tags: [ "space" ])
      described_class.call(game: game, source: "owner", remove_tags: [ "space" ])

      game.reload
      expect(game.trait_tags).not_to include("space")
      expect(game.trait_source("space")).to eq("owner")
    end

    it "raises Pito::Error::TraitInvalid for a tag in both add_tags and remove_tags" do
      expect { described_class.call(game: game, source: "classified", add_tags: [ "space" ], remove_tags: [ "space" ]) }
        .to raise_error(Pito::Error::TraitInvalid, /both add_tags and remove_tags/)
    end

    it "raises Pito::Error::TraitInvalid for an unknown tag name" do
      expect { described_class.call(game: game, source: "classified", add_tags: [ "not_a_tag" ]) }
        .to raise_error(Pito::Error::TraitInvalid, /unknown tag "not_a_tag"/)
    end
  end

  describe "source legality per name" do
    it "raises when source: classified touches a derived-declared tag" do
      expect { described_class.call(game: game, source: "classified", add_tags: [ "action" ]) }
        .to raise_error(Pito::Error::TraitInvalid, /source "classified" not legal for derived-declared tag "action"/)
    end

    it "raises when source: derived touches a classified-declared tag" do
      expect { described_class.call(game: game, source: "derived", add_tags: [ "space" ]) }
        .to raise_error(Pito::Error::TraitInvalid, /source "derived" not legal for classified-declared tag "space"/)
    end

    it "raises when source: derived touches any scale (no scale is derived-declared)" do
      expect { described_class.call(game: game, source: "derived", scales: { "difficulty" => "brutal" }) }
        .to raise_error(Pito::Error::TraitInvalid, /source "derived" cannot touch scale/)
    end

    it "allows source: owner to touch a derived-declared tag" do
      result = described_class.call(game: game, source: "owner", add_tags: [ "action" ])
      expect(result[:changed]).to be true
      expect(game.reload.trait_source("action")).to eq("owner")
    end
  end

  describe "owner-wins guard" do
    before { described_class.call(game: game, source: "owner", scales: { "story" => "catching" }) }

    it "skips a source: classified write to an owner-locked scale and reports it" do
      result = described_class.call(game: game, source: "classified", scales: { "story" => "bad" })
      expect(result).to eq(changed: false, skipped_owner: [ "story" ])
      expect(game.reload.trait_value("story")).to eq("catching")
    end

    it "skips a source: derived write to an owner-locked derived tag and reports it" do
      described_class.call(game: game, source: "owner", add_tags: [ "action" ])
      result = described_class.call(game: game, source: "derived", remove_tags: [ "action" ])
      expect(result).to eq(changed: false, skipped_owner: [ "action" ])
      expect(game.reload.trait_tags).to include("action")
    end

    it "applies alongside a non-owner-locked key in the same call, reporting only the locked one" do
      result = described_class.call(
        game: game, source: "classified", scales: { "story" => "bad", "pace" => "fast" }
      )
      expect(result).to eq(changed: true, skipped_owner: [ "story" ])
      game.reload
      expect(game.trait_value("story")).to eq("catching")
      expect(game.trait_value("pace")).to eq("fast")
    end

    it "an owner call is NEVER locked out (owner may always overwrite its own pin)" do
      result = described_class.call(game: game, source: "owner", scales: { "story" => "bad" })
      expect(result).to eq(changed: true, skipped_owner: [])
      expect(game.reload.trait_value("story")).to eq("bad")
    end
  end

  describe "no-op calls" do
    it "reports changed: false and does not enqueue a re-embed when nothing actually changes" do
      described_class.call(game: game, source: "classified", scales: { "difficulty" => "brutal" })

      expect { described_class.call(game: game, source: "classified", scales: { "difficulty" => "brutal" }) }
        .not_to have_enqueued_job(GameEmbedIndexJob)
    end

    it "a fully empty call is a no-op on an unclassified game" do
      result = described_class.call(game: game, source: "classified")
      expect(result).to eq(changed: false, skipped_owner: [])
      expect(game.reload.traits).to eq({})
    end
  end
end
