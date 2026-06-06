# frozen_string_literal: true

# Base class for all `Pito::*` ViewComponents.
#
# Every component in the `app/components/` tree inherits (directly or
# indirectly) from this class, which in turn inherits from
# `ViewComponent::Base`.  Inheriting here rather than from
# `ViewComponent::Base` directly gives us a single choke-point to add
# helpers, concerns, or default behaviour in future without touching every
# component.
#
# ## Event component constructor shape
#
# Components that render a single chat/stream event follow a two-keyword
# constructor convention:
#
#   def initialize(payload: {}, event: nil)
#
# * `payload` — a plain `Hash` (usually `HashWithIndifferentAccess`) carrying
#   the persisted JSON payload for the event.  Components call
#   `payload.with_indifferent_access` when they need symbol/string parity.
#
# * `event` — the `Event` ActiveRecord instance, used only for
#   `event.created_at` (the timestamp shown in the meta line).  May be `nil`
#   in preview / test rendering; every component must handle `nil` safely via
#   `event&.created_at`.
#
# ## Rendering and encapsulation
#
# Components are rendered via `render_inline(Component.new(...))` in specs and
# via the `<%= render ComponentClass.new(...) %>` pattern in templates.
# Each component owns its own template (`_component.html.erb` by default).
# Components do not use slots or content areas unless the component name
# explicitly documents them.
#
# ## Spec conventions
#
# Component specs live under `spec/components/` and are auto-tagged
# `type: :component` by the RSpec metadata hook in `rails_helper.rb`.
# Use plain Nokogiri assertions (`.css(...)`, `.text`, `.to_html`) rather
# than Capybara matchers; the project does not depend on Capybara.
class ApplicationComponent < ViewComponent::Base
end
