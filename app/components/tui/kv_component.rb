module Tui
  class KvComponent < ViewComponent::Base
    def initialize(rows:)
      @rows = rows.to_a
    end

    attr_reader :rows

    def normalized_rows
      rows.map do |row|
        if row.is_a?(Hash)
          [ row[:label].to_s, row[:value].to_s ]
        else
          [ row[0].to_s, row[1].to_s ]
        end
      end
    end
  end
end
