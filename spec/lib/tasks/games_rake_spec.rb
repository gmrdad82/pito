require "rails_helper"
require "rake"

# Phase 28 §01a — `pito:backfill_version_parents` rake task spec.
RSpec.describe "games rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/games",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["pito:backfill_version_parents"] }

  before do
    task.reenable
  end

  describe "pito:backfill_version_parents" do
    it "attaches a GOTY edition under its primary" do
      halo  = create(:game, title: "Halo 3")
      goty  = create(:game, title: "Halo 3 Game of the Year Edition")
      task.invoke
      expect(goty.reload.version_parent_id).to eq(halo.id)
      expect(goty.version_title).to eq("Game of the Year")
    end

    it "attaches a Deluxe edition under its primary" do
      prag = create(:game, title: "Pragmata")
      deluxe = create(:game, title: "Pragmata Deluxe Edition")
      task.invoke
      expect(deluxe.reload.version_parent_id).to eq(prag.id)
      expect(deluxe.version_title).to eq("Deluxe")
    end

    it "attaches a Standard edition under its primary" do
      prag = create(:game, title: "Pragmata")
      standard = create(:game, title: "Pragmata Standard Edition")
      task.invoke
      expect(standard.reload.version_parent_id).to eq(prag.id)
      expect(standard.version_title).to eq("Standard")
    end

    it "matches case-insensitively" do
      prag = create(:game, title: "Pragmata")
      loud = create(:game, title: "PRAGMATA DELUXE EDITION")
      task.invoke
      expect(loud.reload.version_parent_id).to eq(prag.id)
    end

    it "matches the Collector's variant" do
      base = create(:game, title: "Some Game")
      cele = create(:game, title: "Some Game Collector's Edition")
      task.invoke
      expect(cele.reload.version_parent_id).to eq(base.id)
      expect(cele.version_title).to eq("Collector's")
    end

    it "matches the Anniversary variant" do
      base = create(:game, title: "Skyrim")
      ann  = create(:game, title: "Skyrim Anniversary Edition")
      task.invoke
      expect(ann.reload.version_parent_id).to eq(base.id)
      expect(ann.version_title).to eq("Anniversary")
    end

    it "matches the Definitive variant" do
      base = create(:game, title: "Witcher 3")
      defe = create(:game, title: "Witcher 3 Definitive Edition")
      task.invoke
      expect(defe.reload.version_parent_id).to eq(base.id)
      expect(defe.version_title).to eq("Definitive")
    end

    it "matches the Ultimate variant" do
      base = create(:game, title: "Mortal Kombat 11")
      ult  = create(:game, title: "Mortal Kombat 11 Ultimate Edition")
      task.invoke
      expect(ult.reload.version_parent_id).to eq(base.id)
      expect(ult.version_title).to eq("Ultimate")
    end

    it "matches GOTY (acronym)" do
      base = create(:game, title: "Skyrim")
      goty = create(:game, title: "Skyrim GOTY")
      task.invoke
      expect(goty.reload.version_parent_id).to eq(base.id)
      expect(goty.version_title).to eq("Game of the Year")
    end

    it "leaves the row alone when no matching primary exists" do
      orphan = create(:game, title: "Lonely Deluxe Edition")
      task.invoke
      expect(orphan.reload.version_parent_id).to be_nil
    end

    it "is idempotent (re-running attaches zero new rows)" do
      base = create(:game, title: "Halo 3")
      goty = create(:game, title: "Halo 3 Game of the Year")
      task.invoke
      task.reenable
      expect { task.invoke }.not_to change { goty.reload.version_parent_id }
    end

    it "prints a summary line" do
      base = create(:game, title: "Halo 3")
      _goty = create(:game, title: "Halo 3 Game of the Year")
      _orphan = create(:game, title: "Lonely Deluxe Edition")
      expect { task.invoke }.to output(/attached: 1, skipped: 2, total: 3\./).to_stdout
    end

    it "does NOT attach when the candidate has no suffix to strip" do
      _solo = create(:game, title: "Halo 3")
      task.invoke
      # Halo 3 itself has no suffix; the regex does not match, no
      # attempt to attach. Just verify the parent stays a primary.
      expect(Game.find_by(title: "Halo 3").version_parent_id).to be_nil
    end

    it "longer suffixes win over shorter ones (Deluxe Edition vs Deluxe)" do
      base = create(:game, title: "Pragmata")
      # "Pragmata Deluxe Edition" must use "Deluxe Edition" suffix
      # (the longer matcher) so the base title resolves to "Pragmata"
      # and the version_title is "Deluxe" (not the literal " Edition").
      ed = create(:game, title: "Pragmata Deluxe Edition")
      task.invoke
      expect(ed.reload.version_parent_id).to eq(base.id)
      expect(ed.version_title).to eq("Deluxe")
    end

    it "does not touch already-attached editions on re-run" do
      base = create(:game, title: "Halo 3")
      goty = create(:game, title: "Halo 3 Game of the Year", version_parent: base, version_title: "Game of the Year")
      task.reenable
      expect { task.invoke }.not_to change { goty.reload.version_parent_id }
    end
  end
end
