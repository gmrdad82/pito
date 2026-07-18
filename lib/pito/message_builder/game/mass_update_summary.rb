# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the plain-text :system report for a mass
      # `update game <field> <id> <value>, <id> <value>, …` batch (WP4).
      #
      # Game-field mass updates apply PER ROW and never abort on a bad row
      # (Pito::Chat::Handlers::Update#mass_update_game already did the applying —
      # this module only renders what happened). The report is:
      #   - a header naming the applied/skipped counts
      #   - one line per row, IN TYPED ORDER (never resorted, so a row's
      #     position in expand_detail always matches what was typed), either
      #       "#<id> <title> → <value>"  (applied)
      #       "#<id> — <reason>"         (skipped)
      #
      # No follow-up handle — this is a report, not a prompt.
      module MassUpdateSummary
        module_function

        # @param field [String] "footage" | "price" | "platform"
        # @param rows  [Array<Hash>] one entry per typed row, IN TYPED ORDER:
        #   { applied: true,  ref: "#<id>", title:, value: }
        #   { applied: false, ref: "#<id>" | "'<raw segment>'", reason: }
        # @return [Hash] a plain-text :system payload (html: false).
        def call(field:, rows:)
          applied_count = rows.count { |row| row[:applied] }
          skipped_count = rows.size - applied_count

          {
            "body" => Pito::Copy.render("pito.copy.update.mass_summary_header", {
              noun: "game", field: field, applied: applied_count, skipped: skipped_count
            }),
            "html"          => false,
            "expand_detail" => rows.map { |row| row_line(row) }
          }
        end

        def row_line(row)
          if row[:applied]
            Pito::Copy.render("pito.copy.update.mass_row_applied",
                               { ref: row[:ref], title: row[:title], value: row[:value] })
          else
            Pito::Copy.render("pito.copy.update.mass_row_skipped",
                               { ref: row[:ref], reason: row[:reason] })
          end
        end
      end
    end
  end
end
