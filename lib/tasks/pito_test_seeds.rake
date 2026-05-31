# frozen_string_literal: true

# Snapshot the current database state into YAML seed files under
# `db/test_seeds/`, plus a manifest of Active Storage files.
#
# Usage:
#   bin/rails pito:test:seeds:prepare
#
# Output tree:
#   db/test_seeds/
#     active_storage_attachments.yml
#     active_storage_blobs.yml
#     active_storage_variant_records.yml
#     app_settings.yml
#     channels.yml
#     ...
#     manifest.yml            # table list + row counts + AS file manifest
#     files/
#       <blob_key>           # copied from storage root

namespace :pito do
  namespace :test do
    namespace :seeds do
      SEEDS_DIR = Rails.root.join("db/test_seeds")
      FILES_DIR = SEEDS_DIR.join("files")
      EXCLUDED_TABLES = %w[schema_migrations ar_internal_metadata].freeze

      def storage_root
        service = ActiveStorage::Blob.service
        return nil unless service.respond_to?(:root)

        Pathname.new(service.root)
      end

      def active_storage_file_path(blob)
        return nil unless blob.present?

        ActiveStorage::Blob.service.path_for(blob.key)
      end

      desc "Snapshot current DB rows → seed files (YAML + Active Storage files)"
      task prepare: :environment do
        FileUtils.rm_rf(SEEDS_DIR)
        FileUtils.mkdir_p(SEEDS_DIR)
        FileUtils.mkdir_p(FILES_DIR)

        conn = ActiveRecord::Base.connection
        tables = conn.tables.reject { |t| EXCLUDED_TABLES.include?(t) }.sort

        manifest = { tables: {}, active_storage_files: {} }

        tables.each do |table|
          rows = conn.select_all("SELECT * FROM #{conn.quote_table_name(table)}").to_a

          File.write(
            SEEDS_DIR.join("#{table}.yml"),
            YAML.dump(rows)
          )

          manifest[:tables][table] = rows.length
          puts "==> #{table}: #{rows.length} rows"
        end

        # Copy Active Storage files to the support folder
        as_files = 0
        if defined?(ActiveStorage::Blob)
          ActiveStorage::Blob.find_each do |blob|
            src = active_storage_file_path(blob)
            next unless src&.exist?

            dest = FILES_DIR.join(blob.key)
            FileUtils.mkdir_p(dest.dirname)
            FileUtils.cp(src, dest)
            manifest[:active_storage_files][blob.key] = blob.filename.to_s
            as_files += 1
          end
        end

        File.write(SEEDS_DIR.join("manifest.yml"), YAML.dump(manifest))

        puts ""
        puts "Done. #{tables.length} tables + #{as_files} Active Storage files → db/test_seeds/"
      end

      desc "Drop existing + load prepared seeds (DESTRUCTIVE — runs only with FORCE=yes)"
      task populate: :environment do
        unless ENV["FORCE"] == "yes"
          puts "This will DESTROY all data in the database and replace it with the prepared seeds."
          puts "Run with FORCE=yes to proceed."
          exit 1
        end

        manifest_path = SEEDS_DIR.join("manifest.yml")
        unless manifest_path.exist?
          puts "No manifest found at #{manifest_path}. Run pito:test:seeds:prepare first."
          exit 1
        end

        manifest = YAML.load_file(manifest_path, permitted_classes: [ Symbol, Date, Time, DateTime, BigDecimal ], aliases: true)
        tables = manifest[:tables].keys

        conn = ActiveRecord::Base.connection

        # Disable FK checks for the session so we can truncate/load in any order
        conn.execute("SET session_replication_role = 'replica';")

        # Truncate every table (do NOT restart identity — we will reset
        # sequences manually after the inserts so they match the loaded IDs)
        tables.each do |table|
          conn.execute("TRUNCATE TABLE #{conn.quote_table_name(table)} CASCADE;")
          puts "==> truncated #{table}"
        end

        # Cache generated columns per table so we skip them on insert
        generated_columns = {}
        tables.each do |table|
          cols = conn.select_values(<<~SQL)
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = '#{table}'
              AND is_generated = 'ALWAYS'
          SQL
          generated_columns[table] = cols if cols.any?
        end

        # Load each table's YAML in the order recorded in the manifest
        tables.each do |table|
          yaml_path = SEEDS_DIR.join("#{table}.yml")
          rows = YAML.load_file(yaml_path, permitted_classes: [ Symbol, Date, Time, DateTime, BigDecimal ], aliases: true)

          next if rows.empty?

          skip_cols = generated_columns[table] || []
          columns = rows.first.keys.reject { |c| skip_cols.include?(c) }
          col_names = columns.map { |c| conn.quote_column_name(c) }.join(", ")

          batch_size = 1_000
          rows.each_slice(batch_size) do |batch|
            values = batch.map do |row|
              columns.map { |c| conn.quote(row[c]) }.join(", ")
            end
            sql = "INSERT INTO #{conn.quote_table_name(table)} (#{col_names}) VALUES #{values.map { |v| "(#{v})" }.join(", ")}"
            conn.execute(sql)
          end

          puts "==> loaded #{table}: #{rows.length} rows"
        end

        # Restore Active Storage files
        as_root = storage_root
        if as_root && FILES_DIR.exist?
          manifest[:active_storage_files]&.each do |key, filename|
            src = FILES_DIR.join(key)
            next unless src.exist?

            dest = as_root.join(key)
            FileUtils.mkdir_p(dest.dirname)
            FileUtils.cp(src, dest)
          end
          puts "==> restored #{manifest[:active_storage_files]&.length || 0} Active Storage files"
        end

        # Reset all primary-key sequences to match the highest loaded ID + 1
        tables.each do |table|
          pk = conn.primary_key(table)
          next unless pk

          seq = conn.select_value(<<~SQL)
            SELECT pg_get_serial_sequence('#{table}', '#{pk}')
          SQL
          next unless seq

          max_id = conn.select_value("SELECT MAX(#{conn.quote_column_name(pk)}) FROM #{conn.quote_table_name(table)}")
          max_id = max_id.to_i + 1
          conn.execute("SELECT setval('#{seq}', #{max_id}, false);")
        end
        puts "==> reset sequences"

        # Re-enable FK checks
        conn.execute("SET session_replication_role = 'origin';")

        puts ""
        puts "Done. Database restored from db/test_seeds/"
      end
    end
  end
end
