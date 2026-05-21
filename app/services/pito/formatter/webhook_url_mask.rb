# Pure function. Renders a placeholder mask string for a webhook URL
# input field.
#
# The actual URL value is NEVER rendered in HTML view source — only the
# mask is visible. The brand-specific prefix is the publicly-known
# portion; the secret portion shows as three asterisks.
#
# @param brand [Symbol] :discord or :slack
# @return [String] e.g. "https://discord.com/***"
# @raise [ArgumentError] for unknown brands
#
# Examples:
#   call(:discord) => "https://discord.com/***"
#   call(:slack)   => "https://hooks.slack.com/***"
module Pito
  module Formatter
    module WebhookUrlMask
      module_function

      def call(brand)
        case brand.to_sym
        when :discord then "https://discord.com/***"
        when :slack   then "https://hooks.slack.com/***"
        else raise ArgumentError, "unknown brand: #{brand.inspect}"
        end
      end
    end
  end
end
