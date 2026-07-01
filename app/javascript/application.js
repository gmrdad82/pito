// Pito — application entry point
//
// importmap-rails entry point. Loads Turbo, registers Stimulus controllers,
// and imports vendored JS modules (actioncable, etc).

import "@hotwired/turbo-rails"
import "pito/turbo_actions"
import "pito/ready"
import "controllers"
