require "rails_helper"
require "rake"

RSpec.describe "pito:tools:auth rake tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("pito:tools:auth:enroll")
  end

  before do
    Rake::Task["pito:tools:auth:enroll"].reenable
    Rake::Task["pito:tools:auth:reset"].reenable
  end

  describe "pito:tools:auth:enroll" do
    context "when not yet enrolled" do
      before { AppSetting.disable_totp! }

      it "enrolls a new TOTP seed" do
        suppress_output { Rake::Task["pito:tools:auth:enroll"].invoke }
        expect(AppSetting.totp_enabled?).to be true
      end

      it "prints the provisioning URI" do
        expect { Rake::Task["pito:tools:auth:enroll"].invoke }
          .to output(/otpauth:\/\/totp/).to_stdout
      end
    end

    context "when already enrolled" do
      before { AppSetting.enroll_totp!(seed: ROTP::Base32.random_base32) }

      it "exits without enrolling when FORCE is not set" do
        expect { Rake::Task["pito:tools:auth:enroll"].invoke }
          .to raise_error(SystemExit)
        expect(AppSetting.totp_enabled?).to be true
      end

      it "rotates the seed when FORCE=yes" do
        old_seed = AppSetting.totp_seed
        begin
          ENV["FORCE"] = "yes"
          suppress_output { Rake::Task["pito:tools:auth:enroll"].invoke }
        ensure
          ENV.delete("FORCE")
        end
        expect(AppSetting.totp_seed).not_to eq(old_seed)
        expect(AppSetting.totp_enabled?).to be true
      end
    end
  end

  describe "pito:tools:auth:reset" do
    before { AppSetting.enroll_totp!(seed: ROTP::Base32.random_base32) }

    it "disables TOTP" do
      suppress_output { Rake::Task["pito:tools:auth:reset"].invoke }
      expect(AppSetting.totp_enabled?).to be false
    end

    it "prints a re-enroll hint" do
      expect { Rake::Task["pito:tools:auth:reset"].invoke }
        .to output(/pito:tools:auth:enroll/).to_stdout
    end
  end

  def suppress_output
    $stdout = File.open(File::NULL, "w")
    yield
  ensure
    $stdout = STDOUT
  end
end
