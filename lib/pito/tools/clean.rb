# frozen_string_literal: true

require "fileutils"

module Pito
  module Tools
    # Clears the scratch in `tmp/`. Backs `pito:clean` / `pito clean`.
    #
    # Policy (owner decision, 0.7.0): tmp/ is disposable EXCEPT a small protected
    # set — everything else under tmp/ is removed. Safe because dev Active Storage
    # blobs live under `public/pito-storage`, not tmp/ (see config/storage.yml).
    #
    # Protected (never removed):
    #   - tmp/storage : test Active Storage disk root
    #   - tmp/pids    : running server pidfiles
    #   - any `.keep` : directory markers
    #
    # Also truncates `log/*.log` (native dev only; in Docker logs are STDOUT).
    # Returns the list of cleared targets.
    class Clean
      PROTECTED = %w[storage pids].freeze

      def self.call(root: Rails.root) = new(root).call

      def initialize(root)
        @root = Pathname(root)
      end

      def call
        cleared = []

        tmp = @root.join("tmp")
        if tmp.directory?
          removed = false
          tmp.children.each do |child|
            name = child.basename.to_s
            next if name == ".keep" || PROTECTED.include?(name)

            FileUtils.rm_rf(child)
            removed = true
          end
          cleared << "tmp/* (kept: #{PROTECTED.join(', ')}, .keep)" if removed
        end

        logs = Dir.glob(@root.join("log", "*.log").to_s)
        logs.each { |f| File.truncate(f, 0) }
        cleared << "log/*.log" unless logs.empty?

        cleared
      end
    end
  end
end
