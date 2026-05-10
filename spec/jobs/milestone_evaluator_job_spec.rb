require "rails_helper"

RSpec.describe MilestoneEvaluatorJob, type: :job do
  it "invokes Calendar::MilestoneEvaluator#evaluate_all!" do
    evaluator = instance_double(Calendar::MilestoneEvaluator)
    expect(Calendar::MilestoneEvaluator).to receive(:new).and_return(evaluator)
    expect(evaluator).to receive(:evaluate_all!)
    described_class.new.perform
  end

  it "is registered as a Sidekiq cron at 02:00 UTC daily" do
    schedule = YAML.load_file(Rails.root.join("config/sidekiq_cron.yml"))
    entry = schedule["milestone_evaluator"]
    expect(entry).to be_present
    expect(entry["cron"]).to eq("0 2 * * *")
    expect(entry["class"]).to eq("MilestoneEvaluatorJob")
  end
end
