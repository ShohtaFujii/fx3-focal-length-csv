#!/bin/bash
# ============================================================================
#  FX3 Focal Length CSV Tool
#  Sony FX3 (and other Sony camera) MP4クリップのRTMDメタデータから
#  実際の焦点距離 (Actual Focal Length) を読み取り、CSVにまとめます。
#
#  使い方:
#   フォルダ（複数可）や MP4 ファイルをこのアイコンにドラッグ＆ドロップしてください。
#   （ダブルクリックだけで起動した場合は、対象フォルダを選ぶダイアログが出ます）
#
#  必要なもの: ffmpeg（ffprobe）, python3
#   無ければ自動で案内します。Homebrewが入っていれば自動インストールも可能です。
# ============================================================================

set -u
cd "$(dirname "$0")"

echo "=========================================="
echo " FX3 Focal Length CSV Tool"
echo "=========================================="
echo ""

# ---- 1. gather targets (dropped folders/files, or ask via dialog) ----
TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "対象が渡されていません。フォルダを選んでください..."
  CHOSEN=$(osascript -e 'POSIX path of (choose folder with prompt "FX3クリップの入ったフォルダを選んでください")' 2>/dev/null)
  if [ -z "$CHOSEN" ]; then
    echo "フォルダが選択されませんでした。終了します。"
    read -n 1 -s -r -p "Press any key to close..."
    exit 1
  fi
  TARGETS=("$CHOSEN")
fi

# ---- 2. check ffmpeg/ffprobe ----
if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffprobe（ffmpeg）が見つかりません。"
  if command -v brew >/dev/null 2>&1; then
    echo "Homebrewが見つかったので、ffmpegをインストールします（数分かかることがあります）..."
    brew install ffmpeg
  else
    echo ""
    echo "Homebrewもffmpegも見つかりませんでした。次を実行してから、もう一度このスクリプトを実行してください："
    echo ""
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo "  brew install ffmpeg"
    echo ""
    read -n 1 -s -r -p "Press any key to close..."
    exit 1
  fi
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3が見つかりません。App Storeまたは 'xcode-select --install' でコマンドラインツールを入れてください。"
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

echo "ffprobe: $(command -v ffprobe)"
echo "python3: $(command -v python3)"
echo ""

# ---- 3. write the embedded python analyzer ----
PYSCRIPT="$(mktemp -t fx3_rtmd_XXXXXX).py"
cat > "$PYSCRIPT" << 'PYEOF'
#!/usr/bin/env python3
"""
Sony RTMD (LensUnitMetadata) focal length extractor.
Ported from AdrianEddy/telemetry-parser (MIT/Apache-2.0) sony/rtmd_tags.rs,
re-implemented in pure Python + ffprobe (no Rust/cargo build required).
"""
import csv
import json
import struct
import subprocess
import sys
import time
from pathlib import Path

TAG_FOCAL_LENGTH = 0x8005        # LensZoom (Actual Focal Length)
TAG_FOCAL_LENGTH_35MM = 0x8004   # LensZoom (35mm Still Camera Equivalent)
TAG_CONTAINER = 0x8300


def read_f16(b2: bytes) -> float:
    num = struct.unpack('>h', b2)[0]
    exp = (num >> 12) & 0xF
    if exp >= 8:
        exp -= 16
    mantissa = num & 0x0FFF
    return mantissa * (10.0 ** exp)


def parse_tags(data: bytes, out: dict):
    pos, n = 0, len(data)
    while pos < n:
        if pos + 2 > n:
            break
        tag = struct.unpack_from('>H', data, pos)[0]
        pos += 2
        if tag == 0x060E:
            pos += 14
            continue
        if tag == 0 or tag == 0xFFFF:
            break
        if pos + 2 > n:
            break
        length = struct.unpack_from('>H', data, pos)[0]
        pos += 2
        if pos + length > n:
            break
        tag_data = data[pos:pos + length]
        pos += length
        if tag == TAG_CONTAINER:
            parse_tags(tag_data, out)
            continue
        if tag == TAG_FOCAL_LENGTH and length >= 2:
            out['focal_length_mm'] = read_f16(tag_data[:2]) * 1000.0
        elif tag == TAG_FOCAL_LENGTH_35MM and length >= 2:
            out['focal_length_35mm_mm'] = read_f16(tag_data[:2]) * 1000.0


def find_rtmd_stream_index(path: str):
    r = subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'stream=index,codec_tag_string',
         '-of', 'json', path], capture_output=True, text=True, timeout=30)
    info = json.loads(r.stdout or '{}')
    for s in info.get('streams', []):
        if s.get('codec_tag_string') == 'rtmd':
            return s['index']
    return None


def get_packets(path: str, stream_index: int):
    r = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', str(stream_index),
         '-show_entries', 'packet=pts_time,pos,size', '-of', 'json', path],
        capture_output=True, text=True, timeout=120)
    info = json.loads(r.stdout or '{}')
    return info.get('packets', [])


def analyze_clip(path: str):
    idx = find_rtmd_stream_index(path)
    if idx is None:
        return {'ok': False, 'error': 'no RTMD stream (not Sony lens metadata?)'}
    packets = get_packets(path, idx)
    if not packets:
        return {'ok': False, 'error': 'no RTMD packets found'}
    frames = []
    with open(path, 'rb') as f:
        for pkt in packets:
            try:
                pos, size = int(pkt['pos']), int(pkt['size'])
            except (KeyError, ValueError):
                continue
            f.seek(pos)
            data = f.read(size)
            if len(data) < 0x1E or data[0:2] != b'\x00\x1c':
                continue
            out = {}
            parse_tags(data[0x1C:], out)
            if 'focal_length_mm' in out:
                frames.append({'t': float(pkt.get('pts_time', 0.0) or 0.0),
                                'mm': round(out['focal_length_mm'], 2)})
    if not frames:
        return {'ok': False, 'error': 'RTMD present but no focal length tag (manual/non-E-mount lens?)'}
    mms = [fr['mm'] for fr in frames]
    return {'ok': True, 'frames': frames, 'start_mm': mms[0], 'min_mm': min(mms), 'max_mm': max(mms)}


def find_clips(targets):
    exts = {'.mp4', '.mov', '.mxf'}
    out = []
    for t in targets:
        p = Path(t)
        if p.is_dir():
            out.extend(sorted(x for x in p.rglob('*') if x.suffix.lower() in exts))
        elif p.is_file() and p.suffix.lower() in exts:
            out.append(p)
    return sorted(set(out))


def main():
    targets = sys.argv[1:]
    if not targets:
        print("usage: fx3_rtmd.py <folder-or-file> [...]")
        sys.exit(1)

    clips = find_clips(targets)
    if not clips:
        print("MP4/MOV/MXFファイルが見つかりませんでした。")
        sys.exit(1)

    common_root = Path(targets[0]) if Path(targets[0]).is_dir() else Path(targets[0]).parent
    rows = []
    for i, clip in enumerate(clips, 1):
        try:
            rel = clip.relative_to(common_root)
        except ValueError:
            rel = clip.name
        print(f"[{i}/{len(clips)}] {rel} ...", end=' ', flush=True)
        try:
            res = analyze_clip(str(clip))
        except Exception as e:
            res = {'ok': False, 'error': str(e)}
        if res.get('ok'):
            zoomed = res['min_mm'] != res['max_mm']
            print(f"OK start={res['start_mm']}mm min={res['min_mm']}mm max={res['max_mm']}mm" + (" (zoom)" if zoomed else ""))
            rows.append({'Clip': str(rel), 'Start_mm': res['start_mm'], 'Min_mm': res['min_mm'],
                         'Max_mm': res['max_mm'], 'Zoomed': 'YES' if zoomed else '',
                         'Frames': len(res['frames']), 'Status': 'OK'})
        else:
            print(f"SKIP ({res.get('error')})")
            rows.append({'Clip': str(rel), 'Start_mm': '', 'Min_mm': '', 'Max_mm': '',
                         'Zoomed': '', 'Frames': '', 'Status': res.get('error', 'error')})

    out_csv = common_root / f"focal_length_report_{time.strftime('%Y%m%d_%H%M%S')}.csv"
    with open(out_csv, 'w', newline='', encoding='utf-8-sig') as f:
        w = csv.DictWriter(f, fieldnames=['Clip', 'Start_mm', 'Min_mm', 'Max_mm', 'Zoomed', 'Frames', 'Status'])
        w.writeheader()
        w.writerows(rows)

    ok_count = sum(1 for r in rows if r['Status'] == 'OK')
    print("")
    print(f"完了: {ok_count}/{len(rows)} クリップを解析しました。")
    print(f"CSV: {out_csv}")
    print(f"__CSV_PATH__{out_csv}")


if __name__ == '__main__':
    main()
PYEOF

# ---- 4. run it ----
OUTPUT=$(python3 "$PYSCRIPT" "${TARGETS[@]}" | tee /dev/tty)
CSV_PATH=$(echo "$OUTPUT" | grep '__CSV_PATH__' | sed 's/__CSV_PATH__//')

rm -f "$PYSCRIPT"

if [ -n "$CSV_PATH" ] && [ -f "$CSV_PATH" ]; then
  open -R "$CSV_PATH" 2>/dev/null
fi

echo ""
read -n 1 -s -r -p "Press any key to close..."
echo ""
