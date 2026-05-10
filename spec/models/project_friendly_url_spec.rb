require "rails_helper"

# Phase 20 — friendly URLs. Project-specific friendly_id behaviour. The
# generic contract lives in
# `spec/support/friendly_url_shared_examples.rb`.
RSpec.describe Project, type: :model do
  it_behaves_like "a renameable friendly resource", Project,
                  factory: :project, fallback_prefix: "project-"
end
