module ApplicationHelper
  def nav_link(label, path)
    if current_page?(path)
      tag.span(label, style: "font-weight: bold; color: #1a1a1a;")
    else
      link_to(label, path)
    end
  end

  def breadcrumb(*crumbs)
    content_for(:breadcrumbs) do
      separator = tag.span(" / ", class: "text-muted")
      inner = safe_join(crumbs.map.with_index { |crumb, i| breadcrumb_segment(crumb, last: i == crumbs.size - 1) }, separator)
      "[ ".html_safe + inner + " ]".html_safe
    end
  end

  private

  def breadcrumb_segment(crumb, last: false)
    label, path = crumb.is_a?(Array) ? crumb : [ crumb, nil ]
    truncated = truncate(label.to_s, length: 32)
    if last
      tag.span(truncated, style: "font-weight: bold; color: #1a1a1a;")
    else
      link_to(truncated, path || "#")
    end
  end
end
