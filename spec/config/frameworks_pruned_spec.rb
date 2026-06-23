# frozen_string_literal: true

require "rails_helper"

# 0.7.0 stripped three unused Rails frameworks (no usage, no schema): Action
# Mailer (notifications ride Slack/Discord webhooks), and Action Mailbox +
# Action Text (never used; Mailbox depends on Mailer). Their railtie/engine
# requires were removed from config/application.rb, so the constants must not
# load at all.
RSpec.describe "Pruned Rails frameworks" do
  it "does not load Action Mailer" do
    expect(defined?(ActionMailer)).to be_nil
  end

  it "does not load Action Mailbox" do
    expect(defined?(ActionMailbox)).to be_nil
  end

  it "does not load Action Text" do
    expect(defined?(ActionText)).to be_nil
  end
end
