# Phase 20 — friendly URLs.
#
# Shared specs for the renameable family (Project / Bundle /
# MilestoneRule). Pass the model class plus a hash of factory + name
# attribute overrides. The renameable family slugs from `name` and uses
# the `:history` module.
RSpec.shared_examples "a renameable friendly resource" do |klass, factory:, fallback_prefix:|
  describe "#{klass.name} (renameable friendly_id)" do
    it "generates a slug on create from name" do
      record = create(factory, name: "My Test #{klass.name}")
      expect(record.slug).to eq("my-test-#{klass.name.downcase}")
    end

    it "resolves slug collisions to distinct slugs across same-name records" do
      # Use a per-run unique base so residual rows in the projects /
      # bundles / etc. tables (and the friendly_id_slugs history table)
      # don't perturb the candidate stack across spec runs.
      base = "collide-#{SecureRandom.hex(4)}-shared"
      a = create(factory, name: base)
      b = create(factory, name: base)
      c = create(factory, name: base)
      expect(a.slug).to eq(base)
      # No two records share a slug; the suffix shape (`-2`, `-<id>`,
      # `<uuid>`) is friendly_id's internal choice and acceptable in
      # any form. We only assert distinctness.
      expect([ a.slug, b.slug, c.slug ].uniq.length).to eq(3)
    end

    it "returns the slug from to_param (not the id)" do
      record = create(factory, name: "Param Test")
      expect(record.to_param).to eq(record.slug)
      expect(record.to_param).not_to eq(record.id.to_s)
    end

    it "resolves friendly.find by slug" do
      record = create(factory, name: "Find Me")
      expect(klass.friendly.find(record.slug)).to eq(record)
    end

    it "resolves friendly.find by integer id" do
      record = create(factory, name: "Integer Find")
      expect(klass.friendly.find(record.id)).to eq(record)
    end

    it "resolves friendly.find by stringified integer id" do
      record = create(factory, name: "String Id Find")
      expect(klass.friendly.find(record.id.to_s)).to eq(record)
    end

    it "regenerates the slug on rename" do
      record = create(factory, name: "Original Name")
      original_slug = record.slug
      record.update!(name: "Renamed To Other")
      expect(record.reload.slug).to eq("renamed-to-other")
      expect(record.slug).not_to eq(original_slug)
    end

    it "resolves the OLD slug after rename via the :history module" do
      record = create(factory, name: "History Test")
      old_slug = record.slug
      record.update!(name: "History Renamed")
      expect(klass.friendly.find(old_slug)).to eq(record)
    end

    it "falls back to a typed-prefix slug on a blank name" do
      record = build(factory)
      record.name = ""
      record.save(validate: false)
      record.reload
      expect(record.slug).to start_with(fallback_prefix.to_s)
    end

    it "transliterates unicode into ASCII" do
      record = create(factory, name: "Café Étoile")
      expect(record.slug).to eq("cafe-etoile")
    end

    it "truncates very long names at the slug_limit boundary" do
      long_name = "abcdefghij " * 22  # 242 chars — under the 255-char column cap
      record = create(factory, name: long_name)
      expect(record.slug.length).to be <= 80
      expect(record.slug).not_to end_with("-")
    end

    it "strips slashes and leading / trailing whitespace" do
      record = create(factory, name: "  /weird /  name/  ")
      expect(record.slug).to eq("weird-name")
    end
  end
end

# Identifier-style: Channel, Video, Game share the same friendly_id
# `:finders`-only contract on a natural URL-safe column.
RSpec.shared_examples "an identifier-style friendly resource" do |klass, factory:|
  describe "#{klass.name} (identifier-style friendly_id)" do
    it "returns the natural identifier from to_param" do
      record = create(factory)
      expect(record.to_param).not_to eq(record.id.to_s)
    end

    it "resolves friendly.find by slug" do
      record = create(factory)
      expect(klass.friendly.find(record.to_param)).to eq(record)
    end

    it "resolves friendly.find by integer id" do
      record = create(factory)
      expect(klass.friendly.find(record.id)).to eq(record)
    end

    it "resolves friendly.find by stringified integer id" do
      record = create(factory)
      expect(klass.friendly.find(record.id.to_s)).to eq(record)
    end

    it "raises RecordNotFound on a non-matching slug" do
      _record = create(factory)
      expect { klass.friendly.find("never-existed-anywhere-#{SecureRandom.hex(4)}") }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
