# Phase F3 (Beta 4, 2026-05-20) — operator-only profile management.
#
# Replaces the web-side /settings/user profile pane that was cut per
# ADR 0016. pito is single-install, single-owner; the username +
# password update path lives in the shell alongside the other
# `pito:*` operator tasks.
#
# Mirrors the prompt-style of an interactive console: each task asks
# for the relevant inputs on stdin, validates them, and exits non-zero
# with a clear stderr message on any failure. Passwords are read via
# `IO::console#noecho` so the operator's terminal never echoes the
# typed characters. `User.first` is the canonical pito owner — there
# is exactly one user row in this install (Phase 29 — Unit A2 +
# CLAUDE.md hard rules).
#
# Companion namespace: `lib/tasks/pito.rake` already ships
# `pito:user:reset_totp` and `pito:user:regenerate_backup_codes`. Rake
# concatenates the `pito:user:*` namespaces across both files so the
# four tasks coexist under one umbrella.

require "io/console"

namespace :pito do
  namespace :user do
    desc "Rename the pito owner — prompts for new username"
    task rename: :environment do
      user = User.first
      unless user
        warn "No user found. Pito appears uninstalled."
        exit 1
      end

      print "Current username: #{user.username}\nNew username: "
      new_username = $stdin.gets.to_s.strip
      if new_username.empty?
        warn "Empty username; aborting."
        exit 1
      end

      if user.update(username: new_username)
        puts "Username updated to: #{user.username}"
      else
        warn "Failed to update username:"
        warn user.errors.full_messages.join("\n")
        exit 1
      end
    end

    desc "Set the pito owner password — prompts for current + new password"
    task password_set: :environment do
      user = User.first
      unless user
        warn "No user found. Pito appears uninstalled."
        exit 1
      end

      print "Current password: "
      current = $stdin.noecho(&:gets).to_s.strip
      puts ""

      unless user.authenticate(current)
        warn "Current password incorrect."
        exit 1
      end

      print "New password: "
      new_pass = $stdin.noecho(&:gets).to_s.strip
      puts ""
      print "Confirm new password: "
      confirm = $stdin.noecho(&:gets).to_s.strip
      puts ""

      if new_pass != confirm
        warn "Passwords do not match."
        exit 1
      end

      if user.update(password: new_pass, password_confirmation: new_pass)
        puts "Password updated."
      else
        warn "Failed to update password:"
        warn user.errors.full_messages.join("\n")
        exit 1
      end
    end
  end
end
