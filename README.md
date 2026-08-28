# FX3 Focal Length CSV Tool

A macOS tool that reads the actual focal length (`LensZoom (Actual Focal
Length)`) frame-by-frame from the RTMD (Real-Time MetaData) timed metadata
embedded in Sony FX3 (and other Sony camera) MP4 clips, and summarizes the
start/min/max focal length per clip into a CSV.

When shooting with a native Sony E-mount lens (this tool has been verified
with the FE 24-70mm F2.8 GM II), the electronic communication between the
camera and the lens is recorded inside the video's timed metadata (the
`rtmd` stream). This tool parses that raw data directly, capturing focal
length changes during zooms as well.

## Usage

1. Put `fx3_focal_length.command` anywhere in Finder.
2. Drag and drop the folder containing the clips you want to analyze onto
   this file's icon (if drag-and-drop doesn't work in your environment,
   double-clicking instead shows a folder picker dialog).
3. Terminal opens and analyzes the clips one by one.
4. When finished, `focal_length_report_YYYYMMDD_HHMMSS.csv` is created
   directly inside the folder you dropped.

Folders are scanned recursively, including subfolders, so dropping a single
parent folder that contains multiple clip folders will produce one combined
CSV covering everything underneath it.

### CSV columns

| Column | Description |
|---|---|
| `Clip` | Relative path of the clip |
| `Start_mm` | Focal length (mm) at the clip's first frame |
| `Min_mm` / `Max_mm` | Minimum / maximum focal length (mm) within the clip |
| `Zoomed` | `YES` if the focal length changed during the clip |
| `Frames` | Number of frames for which a focal length was successfully read |
| `Status` | `OK`, or the reason the clip was skipped (e.g. no lens communication metadata) |

## Requirements

- macOS
- [ffmpeg](https://ffmpeg.org/) (uses the `ffprobe` command)
  - If it's not installed, the script guides you through it automatically.
    If Homebrew is present, it will run `brew install ffmpeg` for you.
- Python 3 (works with macOS's built-in `/usr/bin/python3`)

## How it works

Sony's `rtmd` stream is a timed metadata track with one metadata sample per
video frame. Each sample is a nested TLV (tag/length/value) structure based
on the SMPTE RP210 tag registry. The "actual focal length" is stored under
tag `0x8005`, encoded in Sony's own compact floating-point format (a 12-bit
mantissa times 10 to the power of a signed 4-bit exponent, in meters).

This tool uses `ffprobe` to get the byte position and size of each `rtmd`
packet for a clip, reads that byte range directly, and parses it in Python
as described above. No Rust/Cargo build environment is required at all.

### When some clips don't produce a value

A clip whose `Status` column shows `RTMD present but no focal length tag`
is not a bug in this tool. It means **the camera itself failed to
electronically communicate with the lens while recording that clip**. The
bundled XML sidecar (`...M01.XML`) shows `LensControlInformation` with
`status="none"`, and the `<Lens modelName=.../>` entry is missing entirely.
Typical causes include the lens not being fully locked into the mount, or
the camera's "shoot without lens" setting being accidentally enabled.

## Credits

The RTMD tag structure and parsing approach are based on
[AdrianEddy/telemetry-parser](https://github.com/AdrianEddy/telemetry-parser)
(`src/sony/rtmd_tags.rs`, `src/sony/mod.rs`, MIT OR Apache-2.0). This tool
is a Python port of that Rust logic. Many thanks for the excellent reverse
engineering and implementation.

> Copyright © 2021 Adrian \<adrian.eddy at gmail\>
> Licensed under MIT OR Apache-2.0

## License

This repository is released under the [MIT License](LICENSE).
