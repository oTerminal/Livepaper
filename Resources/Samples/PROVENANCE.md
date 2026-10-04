# Sample wallpapers: provenance

Onboarding's first step offers these three loops. Each one is
cut from a video that Free Nature Stock publishes under CC0 1.0. Each file's name is the name an import gives
the wallpaper.

| File | Shows | Size | Length | Picture |
|---|---|---|---|---|
| `Autumn Stream.mp4` | Water pouring over dark rocks scattered with fallen yellow leaves, close up, fixed camera | 8,345,911 bytes | 8.008 s, 240 frames | 2560×1440 |
| `Golden Maple.mp4` | The crown of a golden autumn maple against a deep blue sky, thin cirrus drifting behind it, fixed camera looking up | 6,355,201 bytes | 10.010 s, 300 frames | 2560×1440 |
| `Tall Grass.mp4` | Tall grass moving in the wind against a clear blue sky, low fixed camera | 8,669,259 bytes | 10.010 s, 300 frames | 1920×1080 |

All three files are HEVC Main 8-bit (`hvc1`), 4:2:0, 29.97 fps constant (1001/30000), with no B-frames. Their first
frame is a sync frame, and they have a sync frame every 60 frames. Primaries, transfer and matrix are all tagged
BT.709, with limited range, in both the stream and the `colr` box. The files have no audio, no rotation and
no edit list other than the one that plays the media from zero. `moov` comes first. Together they are
23.4 MB.

## Licence

Free Nature Stock's licence page, https://freenaturestock.com/license/, says: "All free photos and videos
published on Free Nature Stock are licensed under Creative Commons Zero. In short, that means I've waived
copyright and dedicate these assets to the public domain for anyone to use freely." It links to the CC0 1.0 deed,
https://creativecommons.org/publicdomain/zero/1.0/. The Wayback Machine's copy of that page from 2020-08-08 says the same
(http://web.archive.org/web/20200808030729/https://freenaturestock.com/license/). None of the three is from
Pexels, Pixabay, Mixkit, Coverr or Unsplash. The site says of its own content: "All photos and videos on Free Nature
Stock are authentic, never AI-generated."

Author: Free Nature Stock (freenaturestock.com). No photographer is named on the site. Its Terms of Use
(https://freenaturestock.com/terms/) say that Build Interactive, LLC operates it, and the licence page speaks
in the first person.

## Autumn Stream.mp4

- **Source title:** Autumn Leaves in River Water
- **Author:** Free Nature Stock (see above)
- **Source page:** https://freenaturestock.com/video/autumn-leaves-in-river-water/
- **Source file:** https://cdn.freenaturestock.com/videos/freenaturestock-autumn-leaves-in-river-water.mp4
  (78,378,091 bytes, SHA-256 `2a87720c48a63f9cee268afc6ee2a63ba16e0707f02f8aca792fec736464d231`; H.264 High,
  3840×2160, 29.97 fps, 31.03 s, BT.709, no audio)
- **Licence:** CC0 1.0 (https://freenaturestock.com/license/)
- **Fetched:** 2026-09-24
- **SHA-256 of `Autumn Stream.mp4`:** `47b28e6266fb579094ec56aa63ec32483717918fd8943050430c307b4ee29814`
- **What was done:** source frames 216–455 (240 frames) make the loop. The 45 frames after the loop (456–500)
  crossfade into its first 45 frames, so the loop's last frame (455) wraps to a blend that begins at frame 456.
  The picture is scaled from 3840×2160 to 2560×1440 (Lanczos) and encoded in two passes at 8.5 Mbit/s.
  ```sh
  ffmpeg -hide_banner -y -i freenaturestock-autumn-leaves-in-river-water.mp4 -filter_complex '[0:v]trim=start_frame=216:end_frame=501,setpts=PTS-STARTPTS,scale=2560:1440:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv420p,split[a][b];[a]trim=start_frame=240:end_frame=285,setpts=PTS-STARTPTS[tail];[b]trim=start_frame=0:end_frame=240,setpts=PTS-STARTPTS[head];[tail][head]xfade=transition=fade:duration=1.501500:offset=0,format=yuv420p[v]' -map '[v]' -an -sn -dn -map_metadata -1 -map_chapters -1 -fps_mode passthrough -frames:v 240 -c:v libx265 -preset slow -b:v 8500k -profile:v main -pix_fmt yuv420p -x265-params bframes=0:open-gop=0:keyint=60:min-keyint=60:scenecut=0:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited:info=0:pass=1:stats=autumn-stream.x265.log -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv -tag:v hvc1 -movflags +faststart -video_track_timescale 30000 -f mp4 /dev/null
  ffmpeg -hide_banner -y -i freenaturestock-autumn-leaves-in-river-water.mp4 -filter_complex '[0:v]trim=start_frame=216:end_frame=501,setpts=PTS-STARTPTS,scale=2560:1440:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv420p,split[a][b];[a]trim=start_frame=240:end_frame=285,setpts=PTS-STARTPTS[tail];[b]trim=start_frame=0:end_frame=240,setpts=PTS-STARTPTS[head];[tail][head]xfade=transition=fade:duration=1.501500:offset=0,format=yuv420p[v]' -map '[v]' -an -sn -dn -map_metadata -1 -map_chapters -1 -fps_mode passthrough -frames:v 240 -c:v libx265 -preset slow -b:v 8500k -profile:v main -pix_fmt yuv420p -x265-params bframes=0:open-gop=0:keyint=60:min-keyint=60:scenecut=0:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited:info=0:pass=2:stats=autumn-stream.x265.log -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv -tag:v hvc1 -movflags +faststart -video_track_timescale 30000 'Autumn Stream.mp4'
  ```

## Golden Maple.mp4

- **Source title:** Clouds Above a Maple Tree
- **Author:** Free Nature Stock (see above)
- **Source page:** https://freenaturestock.com/video/clouds-above-a-maple-tree/
- **Source file:** https://cdn.freenaturestock.com/videos/freenaturestock-clouds-above-a-maple-tree.mp4
  (78,982,046 bytes, SHA-256 `8fcd0cc863aa75edbdde01c65b816bb3a0541e81436203c7dd32d58020f56d5f`; H.264 High,
  3840×2160, 29.97 fps, 32.03 s, BT.709, no audio)
- **Licence:** CC0 1.0 (https://freenaturestock.com/license/)
- **Fetched:** 2026-09-24
- **SHA-256 of `Golden Maple.mp4`:** `cc15aef377a1a743b11b3b5c66e1db40092414c33fe5f7aeb9dd469e3efe49e6`
- **What was done:** source frames 19–318 (300 frames) make the loop. The 60 frames after the loop (319–378, two
  seconds) crossfade into its first 60 frames. The clouds drift slowly, so the crossfade is longer here than in the
  other two. The picture is scaled from 3840×2160 to 2560×1440 (Lanczos) and encoded in two passes at 5 Mbit/s.
  ```sh
  ffmpeg -hide_banner -y -i freenaturestock-clouds-above-a-maple-tree.mp4 -filter_complex '[0:v]trim=start_frame=19:end_frame=379,setpts=PTS-STARTPTS,scale=2560:1440:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv420p,split[a][b];[a]trim=start_frame=300:end_frame=360,setpts=PTS-STARTPTS[tail];[b]trim=start_frame=0:end_frame=300,setpts=PTS-STARTPTS[head];[tail][head]xfade=transition=fade:duration=2.002000:offset=0,format=yuv420p[v]' -map '[v]' -an -sn -dn -map_metadata -1 -map_chapters -1 -fps_mode passthrough -frames:v 300 -c:v libx265 -preset slow -b:v 5000k -profile:v main -pix_fmt yuv420p -x265-params bframes=0:open-gop=0:keyint=60:min-keyint=60:scenecut=0:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited:info=0:pass=1:stats=golden-maple.x265.log -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv -tag:v hvc1 -movflags +faststart -video_track_timescale 30000 -f mp4 /dev/null
  ffmpeg -hide_banner -y -i freenaturestock-clouds-above-a-maple-tree.mp4 -filter_complex '[0:v]trim=start_frame=19:end_frame=379,setpts=PTS-STARTPTS,scale=2560:1440:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv420p,split[a][b];[a]trim=start_frame=300:end_frame=360,setpts=PTS-STARTPTS[tail];[b]trim=start_frame=0:end_frame=300,setpts=PTS-STARTPTS[head];[tail][head]xfade=transition=fade:duration=2.002000:offset=0,format=yuv420p[v]' -map '[v]' -an -sn -dn -map_metadata -1 -map_chapters -1 -fps_mode passthrough -frames:v 300 -c:v libx265 -preset slow -b:v 5000k -profile:v main -pix_fmt yuv420p -x265-params bframes=0:open-gop=0:keyint=60:min-keyint=60:scenecut=0:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited:info=0:pass=2:stats=golden-maple.x265.log -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv -tag:v hvc1 -movflags +faststart -video_track_timescale 30000 'Golden Maple.mp4'
  ```

## Tall Grass.mp4

- **Source title:** Tall Grass Blowing in the Wind
- **Author:** Free Nature Stock (see above)
- **Source page:** https://freenaturestock.com/video/tall-grass-blowing-in-the-wind/
- **Source file:** https://cdn.freenaturestock.com/videos/freenaturestock-tall-grass-blowing-in-the-wind.mp4
  (39,346,720 bytes, SHA-256 `e8ea8b4bceba058af77cd5cb6df370d29f2d08b332c13c8d191385f25a9f9d2c`; H.264 High,
  1920×1080, 29.97 fps, 20.52 s, BT.709, no audio)
- **Licence:** CC0 1.0 (https://freenaturestock.com/license/)
- **Fetched:** 2026-09-24
- **SHA-256 of `Tall Grass.mp4`:** `3cf555c6eaccfa59e362a9162f35f072b7299578efbc4e6bad82714fce1f8624`
- **What was done:** source frames 7–306 (300 frames) make the loop. The 45 frames after the loop (307–351)
  crossfade into its first 45 frames. The picture stays at the source's 1920×1080 (the scale is a no-op) and is
  encoded in two passes at 7 Mbit/s.
  ```sh
  ffmpeg -hide_banner -y -i freenaturestock-tall-grass-blowing-in-the-wind.mp4 -filter_complex '[0:v]trim=start_frame=7:end_frame=352,setpts=PTS-STARTPTS,scale=1920:1080:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv420p,split[a][b];[a]trim=start_frame=300:end_frame=345,setpts=PTS-STARTPTS[tail];[b]trim=start_frame=0:end_frame=300,setpts=PTS-STARTPTS[head];[tail][head]xfade=transition=fade:duration=1.501500:offset=0,format=yuv420p[v]' -map '[v]' -an -sn -dn -map_metadata -1 -map_chapters -1 -fps_mode passthrough -frames:v 300 -c:v libx265 -preset slow -b:v 7000k -profile:v main -pix_fmt yuv420p -x265-params bframes=0:open-gop=0:keyint=60:min-keyint=60:scenecut=0:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited:info=0:pass=1:stats=tall-grass.x265.log -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv -tag:v hvc1 -movflags +faststart -video_track_timescale 30000 -f mp4 /dev/null
  ffmpeg -hide_banner -y -i freenaturestock-tall-grass-blowing-in-the-wind.mp4 -filter_complex '[0:v]trim=start_frame=7:end_frame=352,setpts=PTS-STARTPTS,scale=1920:1080:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv420p,split[a][b];[a]trim=start_frame=300:end_frame=345,setpts=PTS-STARTPTS[tail];[b]trim=start_frame=0:end_frame=300,setpts=PTS-STARTPTS[head];[tail][head]xfade=transition=fade:duration=1.501500:offset=0,format=yuv420p[v]' -map '[v]' -an -sn -dn -map_metadata -1 -map_chapters -1 -fps_mode passthrough -frames:v 300 -c:v libx265 -preset slow -b:v 7000k -profile:v main -pix_fmt yuv420p -x265-params bframes=0:open-gop=0:keyint=60:min-keyint=60:scenecut=0:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited:info=0:pass=2:stats=tall-grass.x265.log -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv -tag:v hvc1 -movflags +faststart -video_track_timescale 30000 'Tall Grass.mp4'
  ```

## How the loops are made seamless

None of the three sources ends where it starts, so each loop is made seamless with a crossfade of its tail into
its head. For a loop of L frames from source frame S with an X-frame crossfade, output frame k (k ≥ X) is
source frame S+k. For k < X it is a linear blend of source frames S+L+k and S+k, which is pure S+L at k = 0
and moves to S+k. The last output frame is source frame S+L−1, and it wraps to the first, which is source frame S+L.
The wrap is therefore an ordinary step of the source, and the change from tail to head takes place across the
crossfade, away from the wrap. In the commands the `[tail]` input is the X frames after the loop, the `[head]` is
the loop itself, and `xfade` at offset 0 blends them over the head's first X frames.

Before the choice, a search over start frames and loop lengths picked the pair whose crossfade window blends the
most alike frames: 160×90 grey frames, mean absolute difference. Only then were the files encoded.

## Checks

- **Colour:** ffprobe reports `hevc`/`hvc1` Main, `yuv420p`, `color_range=tv`,
  `color_primaries=bt709`, `color_transfer=bt709`, `color_space=bt709` and `has_b_frames=0` for each file.
  The `colr` box is `nclx` 1/1/1. The sources were already BT.709 SDR, and there is no HDR anywhere.
- **Loop:** each file was read back and compared at 320×180 grey against its source stretch. The first frame
  matches source S+L, and every frame from X on matches source S+k, to within the encoding error (at most 1.6 of
  255). The step across the wrap is the size of an ordinary step: Autumn Stream 10.3 against a median of 9.8,
  Tall Grass 5.4 against 6.7. Golden Maple is 1.35, the same as the step into each of its sync frames inside the clip
  (1.0–1.3). The crossfade's middle frames were viewed at full size and show no visible double image.
- **Pictures:** frames at the start, the crossfade's middle, the crossfade's end, the middle and the end, and
  the frames either side of the wrap, were viewed full size. There is no text, logo, watermark, person or
  face. The camera is on a tripod: phase correlation finds no camera movement in the river and the maple, and
  the grass, whose texture defeats that measure, was checked by eye across the frames. Any frame-to-frame change is the
  water, the leaves, the grass or the clouds. A block-by-block search for a sudden local change (a bird or an
  insect crossing) found none in the three stretches used, and none of the stretches includes a fade. VMAF
  against a lossless render of the same filter graph: 87.7 (Autumn Stream), 88.6 (Golden Maple), 82.5 (Tall Grass).
- **Import:** the real `Importer` (LivepaperImport), run on each file into a library under a temporary home,
  finds the file ISO media, `hvc1` decodable, constant timing of 1001/30000, no edit list, no frame reordering,
  first frame a sync frame, SDR and upright. The plan is `.remux`, the copy is written by the remux, the loop
  seam validator passes both the sample file and the library's copy (first PTS 0, seam step 1001, no frames
  before the first sync), and a hover preview is made. The unedited sources are planned `.transcode` (B-frames and an edit
  list), and that is why they were re-encoded.

## Tools

- ffmpeg 9.0.2 (Homebrew) with libx265: x265 4.3+1-e9b8812, 8/10/12-bit build.
- Encoded on macOS 27.0 on Apple Silicon (arm64).
- Another build, x265 version or machine can produce files that differ in their bytes. The SHA-256 values above
  are for the files as committed.
