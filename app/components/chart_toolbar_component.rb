class ChartToolbarComponent < ViewComponent::Base
  RANGES = %w[ 7d 30d 90d 1y all ].freeze

  def initialize(current_range:, base_path:)
    @current_range = current_range
    @base_path = base_path
  end

  def ranges
    RANGES
  end

  def active?(range)
    range == @current_range
  end

  def path_for(range)
    "#{@base_path}?range=#{range}"
  end
end
