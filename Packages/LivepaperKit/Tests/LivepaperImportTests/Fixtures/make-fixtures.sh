#!/bin/bash
# Regenerates the import fixture corpus. The files are checked in, so this only
# records how they were made. It needs a full ffmpeg (Homebrew's), not the
# bundled helper: libx264 and libvpx are used here as clip generators only.
#
# testsrc2 burns in a frame counter and differs in every frame, so a repeated
# or missing frame shows.
set -euo pipefail
cd "$(dirname "$0")"

FF=(ffmpeg -hide_banner -loglevel error -y)
SRC=(-f lavfi -i "testsrc2=size=320x180:rate=30:duration=2")
TONE=(-f lavfi -i "sine=frequency=440:duration=2")

# Already what the library keeps: H.264, SDR, constant rate, first frame at zero. Remux.
"${FF[@]}" "${SRC[@]}" -c:v h264_videotoolbox -b:v 300k -bf 0 -g 30 -pix_fmt yuv420p -an plain-h264.mp4

# The loop-seam flash reported in Wallper: an audio track longer than the video track.
"${FF[@]}" "${SRC[@]}" -f lavfi -i "sine=frequency=440:duration=2.4" \
  -c:v h264_videotoolbox -b:v 300k -bf 0 -g 30 -pix_fmt yuv420p -c:a aac -b:a 64k long-audio.mp4

# Stereo noise at 100 kbit/s, which the audio encoder cannot spend less on: the copy's audio must come out no faster.
"${FF[@]}" "${SRC[@]}" -f lavfi -i "aevalsrc=exprs=-1+2*random(0)|-1+2*random(1):s=48000:d=2" \
  -c:v h264_videotoolbox -b:v 300k -bf 0 -g 30 -pix_fmt yuv420p -c:a aac -b:a 100k noisy-audio.mp4

# B-frames and the edit list ffmpeg writes for them: the first frame is not at zero in media time.
"${FF[@]}" "${SRC[@]}" -c:v libx264 -preset veryfast -b:v 300k -bf 2 -g 30 -pix_fmt yuv420p -an bframes-edit-list.mp4

# Both at once, so that the transcode has audio to trim too.
"${FF[@]}" "${SRC[@]}" -f lavfi -i "sine=frequency=440:duration=2.4" \
  -c:v libx264 -preset veryfast -b:v 300k -bf 2 -g 30 -pix_fmt yuv420p -c:a aac -b:a 64k bframes-long-audio.mp4

# B-frames at a low rate for the picture, as uploads often are: transcoded, and the copy must come out no larger.
"${FF[@]}" "${SRC[@]}" -c:v libx264 -preset medium -b:v 100k -bf 3 -g 30 -pix_fmt yuv420p -an bframes-low-rate.mp4

# Variable frame rate: every third frame after the first second is dropped and the gaps are kept.
"${FF[@]}" "${SRC[@]}" -vf "select='lt(n,30)+mod(n,3)'" -fps_mode vfr \
  -c:v h264_videotoolbox -b:v 300k -bf 0 -g 30 -pix_fmt yuv420p -an variable-rate.mp4

# HDR: 10-bit HEVC tagged HLG / BT.2020, in the stream and in the container. The
# encoder alone writes only the matrix, and AVFoundation would take the file for SDR.
"${FF[@]}" "${SRC[@]}" -c:v hevc_videotoolbox -profile:v main10 -pix_fmt p010le -b:v 400k -bf 0 -g 30 -tag:v hvc1 \
  -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc \
  -bsf:v hevc_metadata=colour_primaries=9:transfer_characteristics=18:matrix_coefficients=9 -movflags +write_colr -an hdr-hlg.mov

# A second of black before the picture: the poster must not be black.
"${FF[@]}" -f lavfi -i "color=c=black:size=320x180:rate=30:duration=1" "${SRC[@]}" \
  -filter_complex "[0:v][1:v]concat=n=2:v=1[v]" -map "[v]" \
  -c:v h264_videotoolbox -b:v 300k -bf 0 -g 30 -pix_fmt yuv420p -an black-lead-in.mp4

# Shot sideways: the picture is 180x320 once the track's rotation is applied.
"${FF[@]}" "${SRC[@]}" -c:v h264_videotoolbox -b:v 300k -bf 0 -g 30 -pix_fmt yuv420p -an -f mp4 /tmp/livepaper-unrotated.mp4
"${FF[@]}" -display_rotation 90 -i /tmp/livepaper-unrotated.mp4 -c copy rotated.mov
rm -f /tmp/livepaper-unrotated.mp4

# The containers AVFoundation cannot open.
"${FF[@]}" "${SRC[@]}" "${TONE[@]}" -c:v libvpx-vp9 -b:v 300k -deadline realtime -cpu-used 8 -c:a libopus -b:a 48k vp9-opus.webm
"${FF[@]}" "${SRC[@]}" -c:v libx264 -preset veryfast -b:v 300k -pix_fmt yuv420p -an h264.mkv
"${FF[@]}" "${SRC[@]}" "${TONE[@]}" -c:v mpeg4 -b:v 400k -c:a libmp3lame -b:a 64k mpeg4-mp3.avi
"${FF[@]}" "${SRC[@]}" "${TONE[@]}" -c:v wmv2 -b:v 400k -c:a wmav2 -b:a 64k wmv2.wmv
"${FF[@]}" -f lavfi -i "testsrc2=size=160x90:rate=10:duration=2" animation.gif

ls -la
