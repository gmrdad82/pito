# frozen_string_literal: true

# Scripted screenshot / GIF capture — the committed successor to the
# throwaway heredocs that shot the mkt images. Scenarios are YAML
# instruction files under config/captures/; artifacts land ONLY under
# tmp/captures/<scenario>/ (shipped images are never overwritten — promoting a
# capture into docs/media or a site is a deliberate manual copy).
#
#   rake "pito:capture[ls-channels]"   # one scenario
#   rake pito:capture:list             # what's available
#
# Dev-only by design: scenarios log in with the fixed development TOTP and
# point at bin/dev (:3027) or an astro preview — NEVER at production.
# Shared run/list helpers for both namespaces.
def pito_capture_run!(scenarios, usage:, name:)
  abort("Refusing to run captures in production.") if Rails.env.production?
  abort("Usage: #{usage}") if name.blank?

  scenario = scenarios.find { |s| s.name == name }
  abort("Unknown scenario #{name.inspect} — see the matching :list task") if scenario.nil?

  puts "capturing #{scenario.name} against #{scenario.base_url}…"
  artifacts = Pito::Capture::Runner.call(scenario)
  puts "done — #{artifacts.size} artifact(s) under #{scenario.output_dir}"
end

def pito_capture_list!(scenarios)
  scenarios.each { |s| puts format("%-24s %s (%d steps)", s.name, s.base_url, s.steps.size) }
end

namespace :pito do
  desc "Run one pito capture scenario from config/captures (NAME or [name] arg)"
  task :capture, [ :name ] => :environment do |_t, args|
    pito_capture_run!(Pito::Capture::Scenario.all,
                      usage: 'rake "pito:capture[<name>]" — see pito:capture:list',
                      name:  args[:name].presence || ENV["NAME"].presence)
  end

  namespace :capture do
    desc "List the pito capture scenarios"
    task list: :environment do
      pito_capture_list!(Pito::Capture::Scenario.all)
    end
  end
end

# The pitomd-destined set — scenario YAMLs git-tracked in lib/support/pitomd,
# output scoped to tmp/captures/pitomd/ so the sets never collide. Promotion
# into ~/Dev/pitomd/public/media stays a manual copy.
namespace :pitomd do
  desc "Run one pitomd capture scenario from lib/support/pitomd (NAME or [name] arg)"
  task :capture, [ :name ] => :environment do |_t, args|
    pito_capture_run!(Pito::Capture::Scenario.pitomd,
                      usage: 'rake "pitomd:capture[<name>]" — see pitomd:capture:list',
                      name:  args[:name].presence || ENV["NAME"].presence)
  end

  namespace :capture do
    desc "List the pitomd capture scenarios"
    task list: :environment do
      pito_capture_list!(Pito::Capture::Scenario.pitomd)
    end
  end
end
