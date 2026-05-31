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
# `[game_id, filename]`. Probed attributes are written; existing rows are
# overwritten in full.
namespace :pito do
  namespace :tools do
    desc "Probe video files with ffprobe and upsert Footage rows. game=N path=PATTERN"
    task probe: :environment do
      game_id = ENV["game"]
      path_pattern = ENV["path"]

      abort "Usage: bin/rails pito:tools:probe game=N path=PATTERN" if game_id.blank? || path_pattern.blank?

      game = Game.find_by(id: game_id)
      abort "Game #{game_id} not found." unless game

      files = Dir.glob(File.expand_path(path_pattern)).select { |f| File.file?(f) }.sort
      abort "No files matched: #{path_pattern}" if files.empty?

      puts "==> Probing #{files.length} file(s) for game '#{game.title}' (id=#{game.id})"
      puts ""

      probed = 0
      skipped = 0
      errors = []

      files.each_with_index do |file, i|
        puts "  [#{i + 1}/#{files.length}] #{File.basename(file)}"

        result = Pito::Footage::Probe.call(path: file)

        unless result.success
          errors << "#{File.basename(file)}: #{result.error_message}"
          skipped += 1
          next
        end

        Footage.upsert(
          {
            game_id: game.id,
            filename: File.basename(file),
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
      puts "Done. #{probed} probed, #{skipped} skipped."

      if errors.any?
        puts ""
        puts "Errors:"
        errors.each { |e| puts "  #{e}" }
      end
    end
  end
end
