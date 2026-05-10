# Phase 20 — friendly URLs. Collection slug column + backfill.
class AddSlugToCollections < ActiveRecord::Migration[8.1]
  def up
    add_column :collections, :slug, :string

    collection_klass = Class.new(ActiveRecord::Base) { self.table_name = "collections" }
    collection_klass.reset_column_information
    collection_klass.find_each do |row|
      candidate = Pito::SlugBuilder.build(row.name.presence || "collection-#{row.id}", limit: 80)
      candidate = "collection-#{row.id}" if candidate.blank?
      slug = unique_slug(candidate, collection_klass, row.id)
      row.update_columns(slug: slug)
    end

    change_column_null :collections, :slug, false
    add_index :collections, :slug, unique: true
  end

  def down
    remove_index :collections, :slug
    remove_column :collections, :slug
  end

  private

  def unique_slug(candidate, klass, current_id)
    base = candidate
    suffix = 1
    loop do
      try = suffix == 1 ? base : "#{base}-#{suffix}"
      taken = klass.where(slug: try).where.not(id: current_id).exists?
      return try unless taken
      suffix += 1
    end
  end
end
