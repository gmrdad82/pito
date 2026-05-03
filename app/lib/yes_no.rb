# YesNo — boundary helper for the "yes"/"no" string convention.
#
# Internally pito stores booleans as Postgres booleans and Ruby true/false
# values. At every external boundary (URL filter params, JSON request bodies,
# JSON response bodies, MCP tool inputs, MCP tool outputs) the value is
# expressed as the string "yes" or "no" — never `true`/`false`/`1`/`0`.
#
# Use this module to convert in both directions and to validate inbound
# values. Strict semantics: only the literal strings "yes" and "no" (any
# case) are accepted. Booleans, integers, "true"/"false", "on"/"off",
# "1"/"0" are NOT yes/no values — `yes_no?` returns false for them so
# callers can reject the request with a clear 422.
module YesNo
  module_function

  # Convert a Ruby boolean to the canonical string form.
  def to_yes_no(boolean)
    boolean ? "yes" : "no"
  end

  # Convert a "yes"/"no" string to a Ruby boolean. Case-insensitive.
  # Anything other than "yes" returns false; callers that need strict
  # validation should call `yes_no?` first.
  def from_yes_no(value)
    value.to_s.downcase == "yes"
  end

  # True if the value is exactly the string "yes" or "no" (any case).
  def yes_no?(value)
    %w[yes no].include?(value.to_s.downcase)
  end
end
