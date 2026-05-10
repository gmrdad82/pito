require "rails_helper"

RSpec.describe MilestoneRule, type: :model do
  it_behaves_like "a renameable friendly resource", MilestoneRule,
                  factory: :milestone_rule, fallback_prefix: "milestone-rule-"
end
