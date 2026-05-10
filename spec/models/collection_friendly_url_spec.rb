require "rails_helper"

RSpec.describe Collection, type: :model do
  it_behaves_like "a renameable friendly resource", Collection,
                  factory: :collection, fallback_prefix: "collection-"
end
