module YoutubeHelper
  # Brand-account emails come back from Google in the shape
  # `<long-id>@pages.plusgoogle.com`. The domain is noise — every brand
  # account uses it — so we strip the suffix and surface just the local
  # part. Real Gmail (`*@gmail.com`) and custom-domain addresses pass
  # through untouched. View layer only; the model still stores the full
  # email so the value round-trips faithfully if it ever needs to leave
  # the boundary.
  def format_connection_email(email)
    str = email.to_s
    return str if str.empty?

    local, domain = str.split("@", 2)
    return str if domain.nil?

    if domain.casecmp("pages.plusgoogle.com").zero?
      local
    else
      str
    end
  end

  # Short, readable label for an OAuth scope. Google scopes arrive as
  # full URLs (`https://www.googleapis.com/auth/userinfo.email`) or as
  # plain strings (`openid`, `email`, `profile`). Strip everything up
  # to and including the last `/` so URL-shaped scopes collapse to the
  # trailing segment; plain strings pass through.
  def format_scope_short_label(scope)
    str = scope.to_s
    return "" if str.empty?

    str.include?("/") ? str.split("/").last.to_s : str
  end
end
