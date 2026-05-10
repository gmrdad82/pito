require "rails_helper"

RSpec.describe Bundle, type: :model do
  it_behaves_like "a renameable friendly resource", Bundle,
                  factory: :bundle, fallback_prefix: "bundle-"
end
