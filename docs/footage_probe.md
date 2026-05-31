# Footage Probe (ffprobe)

> How Pito extracts technical metadata from video files via `ffprobe`.

## Prerequisites

`ffprobe` must be installed. It ships with FFmpeg.

### Linux (Arch / EndeavourOS)

```bash
sudo pacman -S ffmpeg
```

### macOS

```bash
brew install ffmpeg
```

### Ubuntu / Debian

```bash
sudo apt-get install ffmpeg
```

Verify:

```bash
ffprobe -version
```

## Rake task

```bash
# Single file
bin/rails pito:tools:probe game=42 path=/mnt/media/round1.mkv

# Glob pattern (multiple files)
bin/rails pito:tools:probe game=42 path="/mnt/media/*.mkv"
```

### Required arguments

| Argument       | Description                                                            |
| -------------- | ---------------------------------------------------------------------- |
| `game=N`       | Database ID of the `Game` the footage belongs to.                      |
| `path=PATTERN` | Absolute or relative path. Supports shell globs (`*.mp4`, `**/*.mkv`). |

### What it does

1. Resolves the glob pattern.
2. Runs `ffprobe -print_format json -show_streams -show_format` against each file.
3. Parses the JSON and maps it to `Footage` attributes.
4. Upserts one `Footage` row per file, keyed by `[game_id, filename]`.
5. Prints a summary (`N probed, M skipped`).

## Extracted attributes

| Attribute           | Source (ffprobe)                                                    | Example                      |
| ------------------- | ------------------------------------------------------------------- | ---------------------------- |
| `resolution`        | `streams[video].width × height`                                     | `3840x2160`                  |
| `fps`               | `streams[video].r_frame_rate` (evaluated as a fraction)             | `60.0`                       |
| `duration_seconds`  | `format.duration` (rounded to integer)                              | `414`                        |
| `aspect_ratio`      | `streams[video].display_aspect_ratio` or computed from width/height | `16:9`                       |
| `orientation`       | Derived from width vs height                                        | `landscape`                  |
| `needs_grading`     | Derived from color metadata (see below)                             | `true` / `false`             |
| `audio_track_names` | `streams[audio].tags.title` or `tags.language`                      | `["Gameplay", "Commentary"]` |

### Color / grading detection (`needs_grading`)

`needs_grading` is `false` **only** when the file declares all three of:

- `color_space` = `bt709`
- `color_transfer` = `bt709` or `smpte170m`
- `color_primaries` = `bt709` or `smpte170m`

Any other combination (HDR10, HLG, DCI-P3, BT.2020, etc.) returns `true`.

> **Workflow note:** The "no grading needed" baseline is 8-bit Rec.709 with gamma ≈ 2.2 (covered by `bt709` transfer). When shooting, aim for this profile. Anything else (HLG, PQ, wide-gamut) will flag `needs_grading: true` so it can be graded before publishing.

## Examples

### SDR 1080p BT.709 (no grading needed)

```bash
bin/rails pito:tools:probe game=1 path="/media/tekken_2024.mkv"
```

Resulting `Footage` row:

```
resolution:        2560x1440
fps:               60.0
duration_seconds:  414
aspect_ratio:      16:9
orientation:       landscape
needs_grading:     false
audio_track_names: ["Gameplay", "Commentary"]
```

### HDR 4K 10-bit (grading needed)

```bash
bin/rails pito:tools:probe game=2 path="/media/hdr_lake.mp4"
```

Resulting `Footage` row:

```
resolution:        3840x2160
fps:               60.0
duration_seconds:  60
aspect_ratio:      16:9
orientation:       landscape
needs_grading:     true
audio_track_names: ["track 1"]
```

## Service API

You can also call the probe directly from Ruby:

```ruby
result = Pito::Footage::Probe.call(path: "/path/to/clip.mp4")

result.success        # => true / false
result.resolution     # => "3840x2160"
result.fps            # => 60.0
result.bit_depth      # => 10
result.duration_seconds # => 60
result.needs_grading  # => true
result.audio_track_names # => ["Gameplay", "Commentary"]
result.error_message  # => nil (or error string on failure)
```

## Testing

The rspec suite uses captured ffprobe JSON fixtures (small text files) instead of real video clips:

```
spec/fixtures/files/ffprobe/sdr_1440p.json   # BT.709 SDR sample
spec/fixtures/files/ffprobe/hdr_4k.json      # HDR10+ 10-bit sample
```

Real video files for manual testing should be placed in `tmp/clips/` (gitignored) and referenced from the rake task.
