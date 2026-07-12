# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Capture::Runner do
  # Browser-interface stub — CI never launches Chrome. Records every call.
  class CaptureStubBrowser
    attr_reader :calls

    def initialize = @calls = []
    def start                       = calls << [ :start ]
    def stop                        = calls << [ :stop ]
    def visit(url)                  = calls << [ :visit, url ]
    def login!                      = calls << [ :login ]
    def submit_command(text)        = calls << [ :command, text ]
    def wait_for_selector(css, timeout:) = calls << [ :wait_selector, css, timeout ]
    def wait_for_text(text, timeout:)    = calls << [ :wait_text, text, timeout ]
    def sleep_for(seconds)          = calls << [ :sleep, seconds.to_f ]
    def type_text(text)             = calls << [ :type, text ]
    def press_enter                 = calls << [ :enter ]

    def screenshot(path, selector: nil, full: true)
      calls << [ :shot, path.to_s, selector, full ]
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "png")
    end
  end

  let(:root)    { Pathname.new(Dir.mktmpdir) }
  let(:browser) { CaptureStubBrowser.new }

  after { FileUtils.remove_entry(root) }

  def scenario(steps)
    Pito::Capture::Scenario.new(
      { "name" => "demo", "base_url" => "http://localhost:3027", "steps" => steps }
    )
  end

  def run(steps)
    described_class.call(scenario(steps), browser:, root:, io: StringIO.new)
  end

  it "drives the full step vocabulary in order and always stops the browser" do
    run([ { "login" => true },
          { "command" => "ls channels" },
          { "wait_for" => { "text" => "channels", "timeout" => 5 } },
          { "sleep" => 0.2 },
          { "shot" => "one.png" } ])

    expect(browser.calls.map(&:first)).to eq(
      %i[start visit login command wait_text sleep shot stop]
    )
  end

  it "writes shots under tmp/captures/<name>/ inside the given root" do
    artifacts = run([ { "shot" => "one.png" } ])

    expect(artifacts.map(&:to_s))
      .to all(start_with(root.join("tmp/captures/demo").to_s))
    expect(artifacts.first).to be_exist
  end

  it "captures fps×duration frames for a gif and assembles via the Pillow helper" do
    assembler_calls = []
    allow_any_instance_of(described_class).to receive(:assemble_gif) { |_, *args, **kw| assembler_calls << [ args, kw ] }

    run([ { "gif" => { "name" => "demo.gif", "duration" => 2, "fps" => 4 } } ])

    frame_shots = browser.calls.select { |c| c.first == :shot }
    expect(frame_shots.size).to eq(8) # 4 fps × 2s
    expect(assembler_calls.size).to eq(1)
  end

  it "builds the assembler command from the committed Pillow helper (array args, no shell)" do
    statuses = []
    allow(Open3).to receive(:capture3) { |*cmd| statuses << cmd; [ "", "", instance_double(Process::Status, success?: true) ] }

    run([ { "keyframe" => "01.png" },
          { "storyboard" => { "name" => "s.gif", "seconds_per_frame" => 0.5, "width" => 800 } } ])

    cmd = statuses.first
    expect(cmd.first).to eq("python3")
    expect(cmd[1]).to end_with("lib/support/capture/assemble_gif.py")
    expect(cmd.last(2)).to eq(%w[500 800]) # duration_ms, width
  end

  it "captures storyboard keyframes and assembles them at seconds_per_frame" do
    ffmpeg_calls = []
    allow(Open3).to receive(:capture3) { |*cmd| ffmpeg_calls << [ cmd ]; [ "", "", instance_double(Process::Status, success?: true) ] }

    artifacts = run([ { "type" => "ls" },
                      { "keyframe" => "01-ls.png" },
                      { "type" => " channels" },
                      { "keyframe" => "02-ls-channels.png" },
                      { "submit" => true },
                      { "keyframe" => "03-thinking.png" },
                      { "keyframe" => "04-message.png" },
                      { "storyboard" => { "name" => "story.gif", "seconds_per_frame" => 2 } } ])

    expect(browser.calls.map(&:first))
      .to eq(%i[start visit type shot type shot enter shot shot stop])
    # 4 keyframe PNGs stay as a playable suite + the assembled GIF.
    expect(artifacts.map { |a| File.basename(a) })
      .to eq(%w[01-ls.png 02-ls-channels.png 03-thinking.png 04-message.png story.gif])
    # 2s per frame → 2000ms per frame in the assembler.
    expect(ffmpeg_calls.first[0].last(2).first).to eq("2000")
  end

  it "refuses a storyboard with no registered keyframes" do
    expect { run([ { "storyboard" => { "name" => "story.gif" } } ]) }
      .to raise_error(/no keyframes/)
  end

  it "stops the browser even when a step raises" do
    expect {
      described_class.call(
        scenario([ { "wait_for" => { "selector" => "#nope" } } ]).tap { |s|
          allow(browser).to receive(:wait_for_selector).and_raise(RuntimeError, "timeout")
        }, browser:, root:, io: StringIO.new
      )
    }.to raise_error(RuntimeError, "timeout")

    expect(browser.calls.last).to eq([ :stop ])
  end
end
