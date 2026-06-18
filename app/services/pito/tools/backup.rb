# frozen_string_literal: true

require "shellwords"

module Pito
  module Tools
    # Captures a full local backup into a timestamped, gzipped folder:
    #
    #   backup/<yyyy-mm-dd hh-mm-ss>/
    #     database.sql.gz        # pg_dump | gzip — INCLUDES the Voyage pgvector
    #                            # embeddings (they are plain Postgres columns)
    #     active_storage.tar.gz  # tar -czf of the Disk service root
    #
    # Uses system tools (pg_dump / tar / gzip) shelled out, and prints progress.
    # Restore is intentionally MANUAL — there is no restore task. The backup/
    # folder is git-ignored.
    #
    # Thin wrapper: `bin/rails pito:tools:backup`. The logic lives here so it can
    # be specced (stub #run! to avoid invoking real system tools).
    class Backup
      Result = Struct.new(:dir, :artifacts, keyword_init: true)

      def self.call(...) = new(...).call

      # @param root  [Pathname, String] repo root the backup/ folder hangs off.
      # @param out   [IO]               progress sink (defaults to $stdout).
      # @param clock [Time]             timestamp used for the folder name.
      def initialize(root: Rails.root, out: $stdout, clock: Time.current)
        @root  = Pathname(root)
        @out   = out
        @clock = clock
      end

      # @return [Result] the destination dir + the artifact paths produced.
      def call
        dir = @root.join("backup", @clock.strftime("%Y-%m-%d %H-%M-%S"))
        FileUtils.mkdir_p(dir)
        @out.puts "Backing up to #{dir}"

        artifacts = [ dump_database(dir), archive_assets(dir) ].compact

        @out.puts "Done — #{artifacts.size} artifact(s):"
        artifacts.each { |path| @out.puts "  #{path.basename}  (#{human_size(path)})" }

        Result.new(dir: dir, artifacts: artifacts)
      end

      private

      # pg_dump the configured database, gzip it. Carries the Voyage embeddings
      # (pgvector columns) since they are part of the SQL schema.
      def dump_database(dir)
        cfg  = ActiveRecord::Base.connection_db_config.configuration_hash
        path = dir.join("database.sql.gz")
        env  = cfg[:password].present? ? { "PGPASSWORD" => cfg[:password].to_s } : {}

        cmd = [
          "pg_dump",
          ("--host=#{Shellwords.escape(cfg[:host])}"         if cfg[:host].present?),
          ("--port=#{cfg[:port]}"                            if cfg[:port].present?),
          ("--username=#{Shellwords.escape(cfg[:username])}" if cfg[:username].present?),
          "--no-owner", "--no-privileges",
          Shellwords.escape(cfg[:database].to_s),
          "| gzip -c > #{Shellwords.escape(path.to_s)}"
        ].compact.join(" ")

        @out.puts "  → database — pg_dump → gzip…"
        run!("database — pg_dump → gzip", cmd, path, env:)
      end

      # tar + gzip the ActiveStorage Disk service root. Skips gracefully when the
      # service is not disk-backed (e.g. S3) or the root does not yet exist.
      def archive_assets(dir)
        root = storage_root
        if root.nil? || !root.exist?
          @out.puts "  → active storage — no Disk root, skipped"
          return nil
        end

        path = dir.join("active_storage.tar.gz")
        cmd  = "tar -czf #{Shellwords.escape(path.to_s)} -C #{Shellwords.escape(root.to_s)} ."
        @out.puts "  → active storage — tar → gzip…"
        run!("active storage — tar → gzip", cmd, path)
      end

      def storage_root
        service = ActiveStorage::Blob.service
        service.respond_to?(:root) ? Pathname(service.root) : nil
      end

      # Run a shell command (with optional env), raising on a non-zero exit.
      # Returns the artifact path it produced. Stub this in specs.
      def run!(label, command, output_path, env: {})
        raise "backup step failed: #{label}" unless system(env, command)

        output_path
      end

      def human_size(path)
        ActiveSupport::NumberHelper.number_to_human_size(File.size?(path).to_i)
      end
    end
  end
end
