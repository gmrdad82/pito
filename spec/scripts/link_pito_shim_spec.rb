# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"

# Helpers for driving the real shell function out of the install/update
# scripts. They can't share a shell file (each runs standalone via
# `curl | sh`), so the function is extracted verbatim from each and executed
# inside a sandboxed PATH.
module LinkPitoShimHelpers
  module_function

  def repo_root
    File.expand_path("../..", __dir__)
  end

  # Pull the function out verbatim; a renamed/removed function fails loudly
  # instead of silently testing nothing.
  def extract(rel)
    src = File.read(File.join(repo_root, rel))
    fn = src[/^link_pito_shim\(\) \{\n.*?^\}\n/m]
    raise "link_pito_shim() not found in #{rel}" if fn.nil?

    fn
  end

  # Sandbox: an install dir (the `pito` shim + `pito-cli` live there), a bin
  # dir standing in for /usr/local/bin, and a PATH holding nothing but a fake
  # `sudo` (it just execs its argv) plus the two coreutils the function needs
  # — so `command -v pito` sees only what a case puts there.
  def sandbox(with_shim: true)
    Dir.mktmpdir("link-pito-shim") do |tmp|
      dirs = %w[install bin other fake].to_h { |d| [ d.to_sym, File.join(tmp, d) ] }
      dirs.each_value { |d| FileUtils.mkdir_p(d) }

      File.write(File.join(dirs[:install], "pito-cli"), "#!/bin/sh\n")
      File.write(File.join(dirs[:install], "pito"), "#!/bin/sh\n# deprecation shim\n") if with_shim

      sudo = File.join(dirs[:fake], "sudo")
      File.write(sudo, "#!/bin/sh\nexec \"$@\"\n")
      FileUtils.chmod(0o755, sudo)
      %w[ln readlink].each do |tool|
        real = [ "/usr/bin", "/bin" ].map { |d| File.join(d, tool) }.find { |p| File.executable?(p) }
        raise "#{tool} not found" if real.nil?

        FileUtils.ln_s(real, File.join(dirs[:fake], tool))
      end

      yield dirs
    end
  end

  def run_shim(fn, dirs, path_after_bin: [])
    harness = File.join(File.dirname(dirs[:install]), "harness.sh")
    File.write(harness, "set -eu\n#{fn}\nlink_pito_shim\n")
    env = {
      "PATH" => ([ dirs[:fake], dirs[:bin] ] + path_after_bin).join(":"),
      "PITO_BIN_DIR" => dirs[:bin]
    }
    _out, err, status = Open3.capture3(env, "/bin/sh", harness, chdir: dirs[:install], unsetenv_others: true)
    [ err, status ]
  end

  def shim_path(dirs) = File.join(dirs[:bin], "pito")
end

# The `pito` name is shared with the terminal client (pito-tui ships its
# binary, its .deb and its Homebrew formula as `pito`; on Intel macOS that
# formula writes /usr/local/bin/pito — the very path this deprecation shim
# wants). The scripts used to `ln -sf` that path unconditionally, silently
# replacing a file they don't own, and would also plant a /usr/local/bin/pito
# that shadows the client's /usr/bin/pito from the .deb (/usr/local/bin comes
# first in the default PATH). The shim is a courtesy — it never takes the name
# from someone else.
RSpec.describe "link_pito_shim (script/install.sh, script/update.sh)" do
  include LinkPitoShimHelpers
  extend LinkPitoShimHelpers

  %w[script/install.sh script/update.sh].each do |rel|
    describe rel do
      fn = extract(rel)

      it "links the shim when the name is free" do
        sandbox do |dirs|
          err, status = run_shim(fn, dirs)
          expect(status).to be_success, err
          expect(File.readlink(shim_path(dirs))).to eq(File.join(dirs[:install], "pito"))
        end
      end

      it "leaves a foreign regular file alone (Homebrew on Intel macOS writes this path)" do
        sandbox do |dirs|
          client = shim_path(dirs)
          File.write(client, "#!/bin/sh\n# the pito terminal client\n")
          FileUtils.chmod(0o755, client)

          err, status = run_shim(fn, dirs)
          expect(status).to be_success
          expect(File.symlink?(client)).to be(false)
          expect(File.read(client)).to include("terminal client")
          expect(err).to include("pito-cli")
        end
      end

      it "leaves a foreign symlink alone (a Cellar link has no pito-cli beside it)" do
        sandbox do |dirs|
          cellar = File.join(File.dirname(dirs[:bin]), "Cellar", "pito", "5.0.0", "bin")
          FileUtils.mkdir_p(cellar)
          File.write(File.join(cellar, "pito"), "#!/bin/sh\n")
          FileUtils.ln_s(File.join(cellar, "pito"), shim_path(dirs))

          err, status = run_shim(fn, dirs)
          expect(status).to be_success
          expect(File.readlink(shim_path(dirs))).to eq(File.join(cellar, "pito"))
          expect(err).to include("pito-cli")
        end
      end

      it "does not shadow a `pito` that already resolves further down PATH (the client's .deb)" do
        sandbox do |dirs|
          deb = File.join(dirs[:other], "pito")
          File.write(deb, "#!/bin/sh\n")
          FileUtils.chmod(0o755, deb)

          err, status = run_shim(fn, dirs, path_after_bin: [ dirs[:other] ])
          expect(status).to be_success
          expect(File.exist?(shim_path(dirs))).to be(false)
          expect(err).to include(deb)
        end
      end

      it "re-links its own stale shim from a previous install dir" do
        sandbox do |dirs|
          old = File.join(File.dirname(dirs[:bin]), "old-install")
          FileUtils.mkdir_p(old)
          File.write(File.join(old, "pito"), "#!/bin/sh\n")
          File.write(File.join(old, "pito-cli"), "#!/bin/sh\n")
          FileUtils.ln_s(File.join(old, "pito"), shim_path(dirs))

          _err, status = run_shim(fn, dirs)
          expect(status).to be_success
          expect(File.readlink(shim_path(dirs))).to eq(File.join(dirs[:install], "pito"))
        end
      end

      it "is a no-op when the install dir carries no shim" do
        sandbox(with_shim: false) do |dirs|
          _err, status = run_shim(fn, dirs)
          expect(status).to be_success
          expect(File.exist?(shim_path(dirs))).to be(false)
        end
      end

      it "carries no unconditional link at the client's name" do
        expect(File.read(File.join(repo_root, rel))).not_to match(%r{ln -sf .*/usr/local/bin/pito(\s|$)})
      end
    end
  end

  it "keeps the two copies of the function byte-identical" do
    expect(extract("script/install.sh")).to eq(extract("script/update.sh"))
  end
end
