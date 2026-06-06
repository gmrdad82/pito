# frozen_string_literal: true

namespace :pito do
  namespace :copy do
    desc "Audit pito.copy.* dictionary keys and list legacy migration candidates"
    task audit: :environment do
      result = Pito::Copy::Audit.call

      puts ""
      puts "== pito:copy:audit ================================================"
      puts ""

      # ── Registered keys ────────────────────────────────────────────────────
      puts "Registered keys (pito.copy.*):"
      puts ""

      if result.registered.empty?
        puts "  (none — no leaf keys under pito.copy.* yet)"
      else
        result.registered.each do |entry|
          kind         = entry[:single] ? "single" : "multi"
          placeholders = entry[:placeholders].empty? ? "—" : entry[:placeholders].map { |p| "%{#{p}}" }.join(", ")
          puts format("  %-60s  variants=%-3d  placeholders=%-25s  %s",
                      entry[:key], entry[:variants], placeholders, kind)
        end
      end

      puts ""

      # ── Legacy candidates ──────────────────────────────────────────────────
      puts "Legacy candidates (array-valued leaves outside pito.copy.*):"
      puts ""

      if result.legacy_candidates.empty?
        puts "  (none)"
      else
        result.legacy_candidates.each do |entry|
          placeholders = entry[:placeholders].empty? ? "—" : entry[:placeholders].map { |p| "%{#{p}}" }.join(", ")
          puts format("  %-60s  variants=%-3d  placeholders=%s",
                      entry[:key], entry[:variants], placeholders)
        end
      end

      puts ""

      # ── Summary ────────────────────────────────────────────────────────────
      puts "── Summary ──────────────────────────────────────────────────────"
      puts "  Registered keys:      #{result.registered.size}"
      puts "  Legacy candidates:    #{result.legacy_candidates.size}"
      puts "=================================================================="
      puts ""
    end
  end
end
