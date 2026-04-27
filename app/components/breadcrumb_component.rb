class BreadcrumbComponent < ViewComponent::Base
  def initialize(crumbs:, truncate_length: 32, last_truncate: 80)
    @crumbs = crumbs
    @truncate_length = truncate_length
    @last_truncate = last_truncate
  end

  def segments
    @crumbs.map.with_index do |crumb, i|
      last = i == @crumbs.size - 1
      label, path = crumb.is_a?(Array) ? crumb : [ crumb, nil ]
      truncated = helpers.truncate(label.to_s, length: last ? @last_truncate : @truncate_length, omission: "…")
      { label: truncated, href: last ? nil : (path || "#"), active: last }
    end
  end
end
