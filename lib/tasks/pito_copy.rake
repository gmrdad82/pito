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

      below_standard_keys = []

      if result.registered.empty?
        puts "  (none — no leaf keys under pito.copy.* yet)"
      else
        result.registered.each do |entry|
          kind         = entry[:single] ? "single" : "multi"
          placeholders = entry[:placeholders].empty? ? "—" : entry[:placeholders].map { |p| "%{#{p}}" }.join(", ")
          flag         = entry[:below_standard] ? "  ⚠ BELOW STANDARD (<50)" : ""
          below_standard_keys << entry[:key] if entry[:below_standard]
          puts format("  %-60s  variants=%-3d  placeholders=%-25s  %s%s",
                      entry[:key], entry[:variants], placeholders, kind, flag)
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

      # ── Below-standard summary ─────────────────────────────────────────────
      if below_standard_keys.any?
        puts "Below-standard pools (< #{Pito::Copy::Audit::STANDARD_MIN_SIZE} variants):"
        puts ""
        below_standard_keys.each { |k| puts "  #{k}" }
        puts ""
      end

      # ── Summary ────────────────────────────────────────────────────────────
      puts "── Summary ──────────────────────────────────────────────────────"
      puts "  Registered keys:      #{result.registered.size}"
      puts "  Legacy candidates:    #{result.legacy_candidates.size}"
      puts "  Below standard (<#{Pito::Copy::Audit::STANDARD_MIN_SIZE}): #{below_standard_keys.size}"
      puts "=================================================================="
      puts ""
    end
  end
end
