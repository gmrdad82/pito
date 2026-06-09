# frozen_string_literal: true

# Pito footage probe — run ffprobe against one or more video files and
# upsert `Footage` rows.
#
# Usage:
#   bin/rails pito:tools:probe game=42 path=/mnt/media/tekken/*.mkv
#   bin/rails pito:tools:probe game=42 path=/mnt/media/tekken/round1.mkv
#
# The task expands the path (supports globs), runs `Pito::Footage::Probe`
# against each file, and upserts a `Footage` row per file keyed by
# `[game_id, filename]`.
#
# INCREMENTAL by default: a file whose `[game_id, filename]` already has a
# Footage row is SKIPPED (ffprobe is NOT re-run) — so re-running on the same
# folder only picks up NEW files. Pass `force=1` to re-probe + overwrite every
# matched file.
namespace :pito do
  namespace :tools do
    desc "Probe video files with ffprobe and upsert Footage rows. game=N path=PATTERN [force=1]"
    task probe: :environment do
      game_id = ENV["game"]
      path_pattern = ENV["path"]
      force = ENV["force"].to_s == "1"

      abort "Usage: bin/rails pito:tools:probe game=N path=PATTERN" if game_id.blank? || path_pattern.blank?

      game = Game.find_by(id: game_id)
      abort "Game #{game_id} not found." unless game

      # Only video footage — mp4 / mkv / mov. Everything else in the folder is ignored.
      video_exts = %w[.mp4 .mkv .mov].freeze
      files = Dir.glob(File.expand_path(path_pattern))
                 .select { |f| File.file?(f) && video_exts.include?(File.extname(f).downcase) }
                 .sort
      abort "No mp4/mkv/mov files matched: #{path_pattern}" if files.empty?

      puts "==> Probing #{files.length} file(s) for game '#{game.title}' (id=#{game.id})#{force ? ' [force]' : ''}"
      puts ""

      probed = 0
      already = 0
      failed = 0
      errors = []

      files.each_with_index do |file, i|
        filename = File.basename(file)

        # Incremental: skip files already imported for this game (unless force).
        if !force && Footage.exists?(game_id: game.id, filename: filename)
          already += 1
          puts "  [#{i + 1}/#{files.length}] #{filename} — already imported, skipping"
          next
        end

        puts "  [#{i + 1}/#{files.length}] #{filename}"

        result = Pito::Footage::Probe.call(path: file)

        unless result.success
          errors << "#{filename}: #{result.error_message}"
          failed += 1
          next
        end

        Footage.upsert(
          {
            game_id: game.id,
            filename: filename,
            resolution: result.resolution,
            fps: result.fps,
            duration_seconds: result.duration_seconds,
            aspect_ratio: result.aspect_ratio,
            orientation: result.orientation,
            needs_grading: result.needs_grading,
            audio_track_names: result.audio_track_names,
            updated_at: Time.current
          },
          unique_by: :index_footages_on_game_id_and_filename
        )

        probed += 1
      end

      puts ""
      puts "Done. #{probed} probed, #{already} already imported (skipped), #{failed} failed."

      if errors.any?
        puts ""
        puts "Errors:"
        errors.each { |e| puts "  #{e}" }
      end
    end
  end
end
