module ApplicationHelper
  def nav_link(label, path)
    if current_page?(path)
      tag.span("[ #{label} ]", class: "text-black font-bold no-underline")
    else
      "[ ".html_safe + link_to(label, path) + " ]".html_safe
    end
  end
end
