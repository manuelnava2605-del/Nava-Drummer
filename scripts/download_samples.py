"""
NavaDrummer — Drum Sample Downloader
Downloads GSCW Kit 1 samples from GitHub and organizes them into
assets/sounds/drums/<pad>/ with velocity-layer naming.

Mapping:
  [layer][rr] → source filename
  soft   = velocity < 50   (lightest takes)
  medium = velocity 50-89
  hard   = velocity >= 90  (heaviest takes)
"""

import os, urllib.request, shutil, sys

BASE_URL = (
    "https://raw.githubusercontent.com/gregharvey/drum-samples/master/"
    "GSCW%20Drums%20Kit%201%20Samples/"
)
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds", "drums")

# ─────────────────────────────────────────────────────────────────────────────
# SAMPLE MAP
# Format: { dest_pad_folder: [ [soft_srcs...], [medium_srcs...], [hard_srcs...] ] }
# Each src is the original filename (without the URL base).
# ─────────────────────────────────────────────────────────────────────────────
SAMPLE_MAP = {

    "kick": [
        # soft (V01–V04)
        ["Kick-V01-Yamaha-16x16.wav", "Kick-V02-Yamaha-16x16.wav",
         "Kick-V03-Yamaha-16x16.wav", "Kick-V04-Yamaha-16x16.wav"],
        # medium (V05–V08)
        ["Kick-V05-Yamaha-16x16.wav", "Kick-V06-Yamaha-16x16.wav",
         "Kick-V07-Yamaha-16x16.wav", "Kick-V08-Yamaha-16x16.wav"],
        # hard (V09–V12)
        ["Kick-V09-Yamaha-16x16.wav", "Kick-V10-Yamaha-16x16.wav",
         "Kick-V11-Yamaha-16x16.wav", "Kick-V12-Yamaha-16x16.wav"],
    ],

    "snare": [
        # soft (V01–V06)
        ["SNARE-V01-CustomWorks-6x13.wav", "SNARE-V02-CustomWorks-6x13.wav",
         "SNARE-V03-CustomWorks-6x13.wav", "SNARE-V04-CustomWorks-6x13.wav",
         "SNARE-V05-CustomWorks-6x13.wav", "SNARE-V06-CustomWorks-6x13.wav"],
        # medium (V07–V13)
        ["SNARE-V07-CustomWorks-6x13.wav", "SNARE-V08-CustomWorks-6x13.wav",
         "SNARE-V09-CustomWorks-6x13.wav", "SNARE-V10-CustomWorks-6x13.wav",
         "SNARE-V11-CustomWorks-6x13.wav", "SNARE-V12-CustomWorks-6x13.wav",
         "SNARE-V13-CustomWorks-6x13.wav"],
        # hard (V14–V20)
        ["SNARE-V14-CustomWorks-6x13.wav", "SNARE-V15-CustomWorks-6x13.wav",
         "SNARE-V16-CustomWorks-6x13.wav", "SNARE-V17-CustomWorks-6x13.wav",
         "SNARE-V18-CustomWorks-6x13.wav", "SNARE-V19-CustomWorks-6x13.wav",
         "SNARE-V20-CustomWorks-6x13.wav"],
    ],

    "hihat_closed": [
        # soft (V01–V03)
        ["HHats-CL-V01-SABIAN-AAX.wav", "HHats-CL-V02-SABIAN-AAX.wav",
         "HHats-CL-V03-SABIAN-AAX.wav"],
        # medium (V04–V07)
        ["HHats-CL-V04-SABIAN-AAX.wav", "HHats-CL-V05-SABIAN-AAX.wav",
         "HHats-CL-V06-SABIAN-AAX.wav", "HHats-CL-V07-SABIAN-AAX.wav"],
        # hard (V08–V10)
        ["HHats-CL-V08-SABIAN-AAX.wav", "HHats-CL-V09-SABIAN-AAX.wav",
         "HHats-CL-V10-SABIAN-AAX.wav"],
    ],

    "hihat_open": [
        # soft (V01–V02)
        ["HHats-OP-V01-SABIAN-AAX.wav", "HHats-OP-V02-SABIAN-AAX.wav"],
        # medium (V03–V05)
        ["HHats-OP-V03-SABIAN-AAX.wav", "HHats-OP-V04-SABIAN-AAX.wav",
         "HHats-OP-V05-SABIAN-AAX.wav"],
        # hard (V06–V08)
        ["HHats-OP-V06-SABIAN-AAX.wav", "HHats-OP-V07-SABIAN-AAX.wav",
         "HHats-OP-V08-SABIAN-AAX.wav"],
    ],

    "hihat_pedal": [
        # soft (V01)          # V03 is missing in the repo
        ["HHats-PDL-V01-SABIAN-AAX.wav"],
        # medium (V02)
        ["HHats-PDL-V02-SABIAN-AAX.wav"],
        # hard (V04, V05)
        ["HHats-PDL-V04-SABIAN-AAX.wav", "HHats-PDL-V05-SABIAN-AAX.wav"],
    ],

    "crash": [
        # soft (18" V01–V02)
        ["18-Crash-V01-SABIAN-18.wav", "18-Crash-V02-SABIAN-18.wav"],
        # medium (V03)
        ["18-Crash-V03-SABIAN-18.wav"],
        # hard (V04–V05)
        ["18-Crash-V04-SABIAN-18.wav", "18-Crash-V05-SABIAN-18.wav"],
    ],

    "crash2": [
        # soft (14" V01–V02)
        ["14-Crash-V01-SABIAN-14.wav", "14-Crash-V02-SABIAN-14.wav"],
        # medium (V03–V04)
        ["14-Crash-V03-SABIAN-14.wav", "14-Crash-V04-SABIAN-14.wav"],
        # hard (V05–V06)
        ["14-Crash-V05-SABIAN-14.wav", "14-Crash-V06-SABIAN-14.wav"],
    ],

    "ride": [
        # soft (V01–V02)
        ["Ride-V01-ROBMOR-SABIAN-22.wav", "Ride-V02-ROBMOR-SABIAN-22.wav"],
        # medium (V03–V05)
        ["Ride-V03-ROBMOR-SABIAN-22.wav", "Ride-V04-ROBMOR-SABIAN-22.wav",
         "Ride-V05-ROBMOR-SABIAN-22.wav"],
        # hard (V06–V08)
        ["Ride-V06-ROBMOR-SABIAN-22.wav", "Ride-V07-ROBMOR-SABIAN-22.wav",
         "Ride-V08-ROBMOR-SABIAN-22.wav"],
    ],

    "ride_bell": [
        # soft (V01–V02)
        ["BELL-V01-ROBMOR-SABIAN-22.wav", "BELL-V02-ROBMOR-SABIAN-22.wav"],
        # medium (V03–V05)
        ["BELL-V03-ROBMOR-SABIAN-22.wav", "BELL-V04-ROBMOR-SABIAN-22.wav",
         "BELL-V05-ROBMOR-SABIAN-22.wav"],
        # hard (V06–V08)
        ["BELL-V06-ROBMOR-SABIAN-22.wav", "BELL-V07-ROBMOR-SABIAN-22.wav",
         "BELL-V08-ROBMOR-SABIAN-22.wav"],
    ],

    "tom1": [
        # soft (TOM10 V01–V02)   — 10" high tom
        ["TOM10-V01-StarClassic-10x10.wav", "TOM10-V02-StarClassic-10x10.wav"],
        # medium (V03, V05) — V04 missing in repo
        ["TOM10-V03-StarClassic-10x10.wav", "TOM10-V05-StarClassic-10x10.wav"],
        # hard (V06–V08)
        ["TOM10-V06-StarClassic-10x10.wav", "TOM10-V07-StarClassic-10x10.wav",
         "TOM10-V08-StarClassic-10x10.wav"],
    ],

    "tom2": [
        # soft (TOM13 V01–V02)  — 13" mid tom
        ["TOM13-V01-StarClassic-13x13.wav", "TOM13-V02-StarClassic-13x13.wav"],
        # medium (V03–V05)
        ["TOM13-V03-StarClassic-13x13.wav", "TOM13-V04-StarClassic-13x13.wav",
         "TOM13-V05-StarClassic-13x13.wav"],
        # hard (V06–V08)
        ["TOM13-V06-StarClassic-13x13.wav", "TOM13-V07-StarClassic-13x13.wav",
         "TOM13-V08-StarClassic-13x13.wav"],
    ],

    # Floor tom — reuse TOM13 with different RR start (aliased in DrumEngine)
    "floor_tom": [
        ["TOM13-V03-StarClassic-13x13.wav", "TOM13-V04-StarClassic-13x13.wav"],
        ["TOM13-V05-StarClassic-13x13.wav", "TOM13-V06-StarClassic-13x13.wav"],
        ["TOM13-V07-StarClassic-13x13.wav", "TOM13-V08-StarClassic-13x13.wav"],
    ],

    "rimshot": [
        # soft (V01–V02)
        ["RIMSHOTS-V01-CW-6x13.wav", "RIMSHOTS-V02-CW-6x13.wav"],
        # medium (V03–V05)
        ["RIMSHOTS-V03-CW-6x13.wav", "RIMSHOTS-V04-CW-6x13.wav",
         "RIMSHOTS-V05-CW-6x13.wav"],
        # hard (V06–V08)
        ["RIMSHOTS-V06-CW-6x13.wav", "RIMSHOTS-V07-CW-6x13.wav",
         "RIMSHOTS-V08-CW-6x13.wav"],
    ],

    "crossstick": [
        # soft (SSTICK V01–V02)
        ["SSTICK-V01-CW-6x13.wav", "SSTICK-V02-CW-6x13.wav"],
        # medium (V03–V05)
        ["SSTICK-V03-CW-6x13.wav", "SSTICK-V04-CW-6x13.wav",
         "SSTICK-V05-CW-6x13.wav"],
        # hard (V06–V08)
        ["SSTICK-V06-CW-6x13.wav", "SSTICK-V07-CW-6x13.wav",
         "SSTICK-V08-CW-6x13.wav"],
    ],
}

LAYER_NAMES = ["soft", "medium", "hard"]


def download_file(url: str, dest: str) -> bool:
    try:
        urllib.request.urlretrieve(url, dest)
        return True
    except Exception as e:
        print(f"  ✗ FAILED {os.path.basename(dest)}: {e}", file=sys.stderr)
        return False


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    total_ok = 0
    total_fail = 0

    for pad, layers in SAMPLE_MAP.items():
        pad_dir = os.path.join(OUT_DIR, pad)
        os.makedirs(pad_dir, exist_ok=True)
        print(f"\n[{pad}]")

        for layer_idx, srcs in enumerate(layers):
            layer_name = LAYER_NAMES[layer_idx]
            for rr_idx, src_file in enumerate(srcs):
                dest_name = f"{pad}_{layer_name}_{rr_idx + 1}.wav"
                dest_path = os.path.join(pad_dir, dest_name)

                # Skip if already downloaded
                if os.path.exists(dest_path) and os.path.getsize(dest_path) > 1000:
                    print(f"  OK (cached) {dest_name}")
                    total_ok += 1
                    continue

                url = BASE_URL + src_file.replace(" ", "%20")
                ok  = download_file(url, dest_path)
                if ok:
                    size = os.path.getsize(dest_path)
                    print(f"  OK {dest_name}  ({size//1024} KB)")
                    total_ok += 1
                else:
                    total_fail += 1

    print(f"\n{'='*50}")
    print(f"Done: {total_ok} downloaded, {total_fail} failed")
    if total_fail:
        print("Re-run the script to retry failed downloads.")


if __name__ == "__main__":
    main()
