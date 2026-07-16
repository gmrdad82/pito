# frozen_string_literal: true

require "rails_helper"
require "rake"
require_relative "../../support/rake_spec_helper"

RSpec.describe "pito:nl:sync", type: :rake do
  before(:all) { load_tasks } # rubocop:disable RSpec/BeforeAfterAll

  before { reenable("pito:nl:sync") }

  def invoke_task
    Rake::Task["pito:nl:sync"].invoke
  end

  it "calls Pito::Nl::Router.sync!" do
    allow(Pito::Nl::Router).to receive(:sync!).and_return(upserted: 0, pruned: 0, embedded: 0)

    suppress_output { invoke_task }

    expect(Pito::Nl::Router).to have_received(:sync!)
  end

  it "prints the upserted/pruned/embedded counts sync! returns" do
    allow(Pito::Nl::Router).to receive(:sync!).and_return(upserted: 185, pruned: 3, embedded: 12)

    output = nil
    original_stdout = $stdout
    $stdout = StringIO.new
    begin
      invoke_task
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    expect(output).to include("Upserted: 185")
    expect(output).to include("Pruned:   3")
    expect(output).to include("Embedded: 12")
  end

  it "runs Pito::Nl::Router.sync! for real end to end (no stub)" do
    expect { suppress_output { invoke_task } }.not_to raise_error
    expect(Pito::Nl::Router::Example.count).to be > 0
  end
end
