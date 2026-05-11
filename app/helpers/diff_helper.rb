# Phase 23 §23b — diff page rendering helpers.
#
# Both the channel diff (Phase 11 §11i, when it ships) and the video
# diff (Phase 23) consume these helpers. Centralising the formatting
# rules here keeps the two surfaces visually consistent and matches
# the boundary serialization rule (booleans render as `yes` / `no`).
module DiffHelper
  # Format a value for display in the diff page table cells. Returns
  # an `html_safe` string. Long descriptions are truncated to 240
  # chars with an ellipsis; tags render as a comma-separated pill
  # list; booleans render as `yes` / `no`; nil renders as the muted
  # `(empty)` placeholder.
  def human_diff_value(field, value)
    case field.to_s
    when "description"
      format_long_text(value)
    when "tags"
      format_tags(value)
    when "self_declared_made_for_kids", "contains_synthetic_media",
         "embeddable", "public_stats_viewable", "made_for_kids_effective"
      format_boolean(value)
    when "view_count", "like_count", "comment_count", "duration_seconds"
      format_integer(value)
    when "publish_at", "published_at"
      format_time(value)
    when "thumbnail_url"
      format_url(value)
    else
      format_short_text(value)
    end
  end

  # Returns true when the field is one of the "Pito-cannot-push"
  # display-only fields. The decision radio for these fields is
  # disabled — only `accept youtube` makes sense.
  def diff_field_display_only?(field)
    Youtube::DiffComputer::DISPLAY_ONLY_FIELDS.include?(field.to_s)
  end

  def format_short_text(value)
    return content_tag(:span, "(empty)", class: "text-muted") if value.nil? || value.to_s.empty?
    content_tag(:span, value.to_s)
  end

  def format_long_text(value)
    return content_tag(:span, "(empty)", class: "text-muted") if value.nil? || value.to_s.empty?

    text = value.to_s
    if text.length > 240
      truncated = text[0, 240] + "…"
      content_tag(:span, truncated, title: text)
    else
      content_tag(:span, text)
    end
  end

  def format_tags(value)
    list = Array(value).compact.map(&:to_s)
    return content_tag(:span, "(empty)", class: "text-muted") if list.empty?

    items = list.map { |t| content_tag(:span, t, class: "diff-tag") }
    safe_join(items, " ")
  end

  def format_boolean(value)
    return content_tag(:span, "(empty)", class: "text-muted") if value.nil?

    bool = case value
    when true, "true", "yes", 1, "1" then true
    when false, "false", "no", 0, "0" then false
    else value
    end

    if bool == true
      content_tag(:span, "yes")
    elsif bool == false
      content_tag(:span, "no")
    else
      content_tag(:span, value.to_s)
    end
  end

  def format_integer(value)
    return content_tag(:span, "(empty)", class: "text-muted") if value.nil? || value.to_s.empty?
    n = begin
      Integer(value.to_s)
    rescue ArgumentError, TypeError
      return content_tag(:span, value.to_s)
    end
    content_tag(:span, number_with_delimiter(n))
  end

  def format_time(value)
    return content_tag(:span, "(empty)", class: "text-muted") if value.nil? || value.to_s.empty?

    t = case value
    when Time, DateTime, ActiveSupport::TimeWithZone then value
    else
          begin
            Time.iso8601(value.to_s)
          rescue ArgumentError, TypeError
            return content_tag(:span, value.to_s)
          end
    end

    content_tag(:span, t.utc.iso8601)
  end

  def format_url(value)
    return content_tag(:span, "(empty)", class: "text-muted") if value.nil? || value.to_s.empty?
    content_tag(:span, value.to_s, style: "word-break: break-all;")
  end
end
