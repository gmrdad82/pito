# Phase 20 — friendly URLs. Bundle slug column + backfill.
class AddSlugToBundles < ActiveRecord::Migration[8.1]
  def up
    add_column :bundles, :slug, :string

    bundle_klass = Class.new(ActiveRecord::Base) { self.table_name = "bundles" }
    bundle_klass.reset_column_information
    bundle_klass.find_each do |row|
      candidate = Pito::SlugBuilder.build(row.name.presence || "bundle-#{row.id}", limit: 80)
      candidate = "bundle-#{row.id}" if candidate.blank?
      slug = unique_slug(candidate, bundle_klass, row.id)
      row.update_columns(slug: slug)
    end

    change_column_null :bundles, :slug, false
    add_index :bundles, :slug, unique: true
  end

  def down
    remove_index :bundles, :slug
    remove_column :bundles, :slug
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
