require "rails_helper"
require "rake"

# Phase F3 (Beta 4, 2026-05-20). Operator-only profile management.
# Replaces the web-side /settings/user pane that was cut per ADR 0016.
#
# Style mirrors `spec/lib/tasks/pito_rake_spec.rb` and
# `spec/lib/tasks/pito_tokens_rake_spec.rb` — load the task file via
# `Rake.application.rake_require`, stub stdin (and `noecho` for the
# password task), invoke the task, assert on stdout / stderr / DB
# side effects.
#
# `User#authenticate` is exercised directly (the `has_secure_password`
# helper). The `password_set` task reads via `IO::console#noecho`; we
# stub the singleton on `$stdin` per example so the password input
# round-trips without touching a real TTY.
RSpec.describe "pito:user rake tasks (F3 — profile cut)" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito_user",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:rename_task)       { Rake::Task["pito:user:rename"] }
  let(:password_set_task) { Rake::Task["pito:user:password_set"] }
  let(:password)          { "lucy-password-1" }

  before do
    rename_task.reenable
    password_set_task.reenable
    User.delete_all
  end

  # Stub `$stdin` to read the given lines (one per `gets` call). Also
  # stubs `$stdin.noecho` so the password task's `noecho(&:gets)` path
  # round-trips the same way as the plain `gets` path.
  def with_stdin(*lines)
    io = StringIO.new(lines.map { |l| l.to_s.end_with?("\n") ? l.to_s : "#{l}\n" }.join)
    allow($stdin).to receive(:gets) { io.gets }
    allow($stdin).to receive(:noecho).and_yield($stdin)
    yield
  end

  describe "pito:user:rename" do
    let!(:user) { create(:user, username: "lucy", password: password, password_confirmation: password) }

    it "updates the username when the new name is valid" do
      with_stdin("new_lucy") do
        expect { rename_task.invoke }.to output(/Username updated to: new_lucy/).to_stdout
      end
      expect(user.reload.username).to eq("new_lucy")
    end

    it "trims surrounding whitespace from the new username" do
      with_stdin("  trimmed_name  ") do
        rename_task.invoke
      end
      expect(user.reload.username).to eq("trimmed_name")
    end

    it "exits non-zero with a stderr warning on empty input" do
      with_stdin("") do
        expect {
          expect { rename_task.invoke }
            .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
        }.to output(/Empty username; aborting\./).to_stderr
      end
      expect(user.reload.username).to eq("lucy")
    end

    it "exits non-zero with a stderr warning when the new username fails validation" do
      with_stdin("not a username") do
        expect {
          expect { rename_task.invoke }
            .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
        }.to output(/Failed to update username:/).to_stderr
      end
      expect(user.reload.username).to eq("lucy")
    end

    it "exits non-zero with a stderr warning when no user exists" do
      User.delete_all

      with_stdin("anything") do
        expect {
          expect { rename_task.invoke }
            .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
        }.to output(/No user found\. Pito appears uninstalled\./).to_stderr
      end
    end
  end

  describe "pito:user:password_set" do
    let!(:user) { create(:user, username: "lucy", password: password, password_confirmation: password) }

    it "updates the password when current + new + confirm all line up" do
      new_password = "freshpassword456"
      with_stdin(password, new_password, new_password) do
        expect { password_set_task.invoke }.to output(/Password updated\./).to_stdout
      end

      user.reload
      expect(user.authenticate(new_password)).to be_truthy
      expect(user.authenticate(password)).to be(false)
    end

    it "exits non-zero with a stderr warning when the current password is wrong" do
      with_stdin("wrong-password", "irrelevant1", "irrelevant1") do
        expect {
          expect { password_set_task.invoke }
            .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
        }.to output(/Current password incorrect\./).to_stderr
      end
      expect(user.reload.authenticate(password)).to be_truthy
    end

    it "exits non-zero with a stderr warning when the confirmation does not match" do
      with_stdin(password, "freshpassword456", "different789") do
        expect {
          expect { password_set_task.invoke }
            .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
        }.to output(/Passwords do not match\./).to_stderr
      end
      expect(user.reload.authenticate(password)).to be_truthy
    end

    it "exits non-zero with a stderr warning when the new password fails validation (too short)" do
      with_stdin(password, "short", "short") do
        expect {
          expect { password_set_task.invoke }
            .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
        }.to output(/Failed to update password:/).to_stderr
      end
      expect(user.reload.authenticate(password)).to be_truthy
    end

    it "exits non-zero with a stderr warning when no user exists" do
      User.delete_all

      with_stdin("anything", "anything-else", "anything-else") do
        expect {
          expect { password_set_task.invoke }
            .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
        }.to output(/No user found\. Pito appears uninstalled\./).to_stderr
      end
    end
  end
end
