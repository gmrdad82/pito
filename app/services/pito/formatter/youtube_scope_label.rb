# Pure function. Short, readable label for a Google OAuth scope.
#
# Google scopes arrive as full URLs
# (https://www.googleapis.com/auth/userinfo.email) or as plain strings
# (openid, email, profile). Strips everything up to and including the
# last `/` so URL-shaped scopes collapse to the trailing segment; plain
# strings pass through.
#
# Examples:
#   call("https://www.googleapis.com/auth/userinfo.email") => "userinfo.email"
#   call("openid")                                         => "openid"
#   call("")                                               => ""
module Pito
  module Formatter
    module YoutubeScopeLabel
      module_function

      def call(scope)
        str = scope.to_s
        return "" if str.empty?

        str.include?("/") ? str.split("/").last.to_s : str
      end
    end
  end
end
