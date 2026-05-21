# Pure function. Strips the brand-account Google domain from OAuth emails.
#
# Brand-account emails come back from Google in the shape
# `<long-id>@pages.plusgoogle.com`. The domain is noise — every brand
# account uses it — so we strip the suffix and surface just the local
# part. Real Gmail (*@gmail.com) and custom-domain addresses pass
# through untouched.
#
# Examples:
#   call("12345@pages.plusgoogle.com") => "12345"
#   call("user@gmail.com")             => "user@gmail.com"
#   call("")                           => ""
#   call(nil)                          => ""
module Pito
  module Formatter
    module YoutubeConnectionEmail
      module_function

      def call(email)
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
    end
  end
end
