# Channel::Diff::CellComponent
#
# Renders a single cell in the diff reconciliation table (video diff
# surface today; channel diff was retired in Unit A0). The
# `field_kind:` kwarg selects the rendering shape, matching the 7
# patterns that previously lived in `DiffHelper#format_*`.
#
# Behavior preserved from the legacy helper:
#   - nil / empty values render the muted `(empty)` placeholder
#   - :long_text truncates to 240 chars with the full text in `title`
#   - :tags renders array entries as `.diff-tag` pills, space-joined
#   - :boolean coerces yes/no/true/false/1/0 to `yes` / `no`
#   - :integer renders with `number_with_delimiter`
#   - :time renders ISO8601 in UTC
#   - :url applies `word-break: break-all` for long thumbnail URLs
#
# Use `.kind_for(field)` to map a diff field name to the matching
# `field_kind:` value (mirrors the legacy `human_diff_value` switch).
#
# ## Kwargs
#
# @param value [Object] the value to render
#   (String / Integer / Time / Array / Boolean / nil)
# @param field_kind [Symbol] one of:
#   :short_text / :long_text / :tags / :boolean / :integer / :time / :url
#
# ## Usage
#
#   <%= render Channel::Diff::CellComponent.new(
#         value: diff.pito_value(field),
#         field_kind: Channel::Diff::CellComponent.kind_for(field)
#       ) %>
class Channel::Diff::CellComponent < ViewComponent::Base
  VALID_KINDS = %i[short_text long_text tags boolean integer time url].freeze

  LONG_TEXT_FIELDS = %w[description].freeze
  TAGS_FIELDS      = %w[tags].freeze
  BOOLEAN_FIELDS   = %w[
    self_declared_made_for_kids
    contains_synthetic_media
    embeddable
    public_stats_viewable
    made_for_kids_effective
  ].freeze
  INTEGER_FIELDS   = %w[view_count like_count comment_count duration_seconds].freeze
  TIME_FIELDS      = %w[publish_at published_at].freeze
  URL_FIELDS       = %w[thumbnail_url].freeze

  def self.kind_for(field)
    name = field.to_s
    return :long_text if LONG_TEXT_FIELDS.include?(name)
    return :tags      if TAGS_FIELDS.include?(name)
    return :boolean   if BOOLEAN_FIELDS.include?(name)
    return :integer   if INTEGER_FIELDS.include?(name)
    return :time      if TIME_FIELDS.include?(name)
    return :url       if URL_FIELDS.include?(name)
    :short_text
  end

  def initialize(value:, field_kind:)
    unless VALID_KINDS.include?(field_kind)
      raise ArgumentError, "field_kind must be one of #{VALID_KINDS.inspect}"
    end
    @value      = value
    @field_kind = field_kind
  end

  attr_reader :value, :field_kind

  def empty?
    value.nil? || value.to_s.empty?
  end

  def tags_empty?
    Array(value).compact.map(&:to_s).empty?
  end

  def boolean_value
    case value
    when true, "true", "yes", 1, "1" then true
    when false, "false", "no", 0, "0" then false
    else value
    end
  end

  def truncated_long_text
    text = value.to_s
    if text.length > 240
      [ text[0, 240] + "…", text ]
    else
      [ text, nil ]
    end
  end

  def integer_display
    Integer(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def time_value
    case value
    when Time, DateTime, ActiveSupport::TimeWithZone
      value
    else
      begin
        Time.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end

  def tag_list
    Array(value).compact.map(&:to_s)
  end
end
