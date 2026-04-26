module ApplicationHelper
  def nav_link(label, path)
    if current_page?(path)
      tag.span("[ #{label} ]", style: "font-weight: bold; color: #1a1a1a;")
    else
      "[ ".html_safe + link_to(label, path) + " ]".html_safe
    end
  end
end
