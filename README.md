# NX Nebula — live wallpaper for KDE Plasma 6

The living background of the [NX design language](https://github.com/nerdrx/nx-kde):
a drifting violet/cyan nebula over deep space, with an optional clock overlay
and a folder gallery built for ultrawide displays. Companion to the
[NX theme suite](https://github.com/nerdrx/nx-kde), works fine standalone.

No shaders, no per-frame CPU work — pre-rendered sprite layers animated with
transform and opacity only, fully paused whenever the desktop isn't visible.

## Features

- **Living nebula** — blobs drift on 35–60 s orbits with a slow breathe;
  sparse parallax starfield with gentle twinkle, and a shooting star every
  minute or two. Speed dial from 0.25× (subliminal) to 3×. Identical
  composition to the static NX Nebula wallpaper, so lock screen and desktop
  match — and every instance jitters its own periods, so two screens never
  move in lockstep.
- **The sky knows the hour** — stars brighten and twinkle harder late at
  night, ease off by day, the nebula glows a touch deeper in the dark. A few
  percent either way, on fixed civil hours (no location needed).
- **The sky knows the calendar** — on the peak nights of the real annual
  meteor showers (Perseids, Geminids, Quadrantids, …) shooting stars arrive
  every half minute, all along one shared radiant, the way a shower actually
  looks. No two meteors are alike, and every few minutes a slow satellite
  crosses the whole sky in a dead-straight line, flaring once mid-pass.
- **Aurora** — on the deepest night hours, once or twice an hour, a violet
  and cyan curtain rises over the stars, shimmers for a couple of minutes,
  and dissolves. Pre-rendered like everything else; still no shaders.
- **The celestial bodies** — the moon rises after dusk showing its *real
  phase* (sixteen baked frames, accurate to the almanac); the Milky Way
  veils the deepest hours; the evening star hangs steady in the twilight
  (planets don't twinkle); and once every few dark hours a comet makes a
  slow two-minute crossing, violet head running out into a cyan tail.
- **Clock overlay** — wide-tracked day name, date, and time, centered or
  top-centered; 12/24-hour follows the system locale, or force either. On
  special nights a quiet almanac line appears under the time — "THE
  PERSEIDS TONIGHT", "FULL MOON", "THE LONGEST NIGHT" — and on ordinary
  nights it simply isn't there.
- **The seasons** — dawn and dusk drift ±1.2 h through the year, so June
  nights arrive late and December nights early. A southern-hemisphere
  switch flips the seasons and mirrors the moon, which really does wax on
  the left down there.
- **Folder gallery** — point it at a folder (JPEG/PNG/WebP/BMP/AVIF/JXL)
  and it walks the subfolders too; images rotate on an interval with
  crossfades and a gentle arrival settle, optional shuffle, EXIF orientation
  respected, and broken files are skipped instead of stalling a slot.
  Optional captions set the file name under each photo in the NX type, and
  a "one photo per day" mode turns the wall into a daily print every screen
  agrees on.
- **A packing curator** — on ultrawide rows a hidden scout decodes postage
  stamps of what's coming just for their aspect ratios, and each turn picks
  the photo that fills the row best — with a fairness cap so an awkward
  shape still gets its day.
- **Aspect-mismatch strategies** (the ultrawide problem): fit / fill /
  pan-scan modes; letterbox backdrop as nebula, blurred self-copy, or dim;
  frame styles from a plain lit tile through a glowing tile to a rounded
  glass card — the glow samples each photo's own dominant hue, so every
  picture arrives with its own light; and an ultrawide mode that packs 2–3
  portrait images side by side as a rotating card row instead of
  letterboxing one.
- **OLED care** — the clock and the photo row wander a slow, continuous
  few-pixel Lissajous over minutes, spreading the brightest static shapes
  across the panel. On by default, invisible in practice.

## Install

```bash
./install.sh
```

Then right-click the desktop → *Desktop and Wallpaper* → Wallpaper type
**NX Nebula (Live)**. All options live in that dialog.

Remove with `./uninstall.sh`.

## Requirements

KDE Plasma 6.2+ (built against 6.7), Qt 6.4+. Rendered layer sprites are
committed; regenerating them (`tools/gen_nebula_layers.py`) needs Python 3
with numpy + Pillow and is only necessary if you retune the composition.

## License

GPL-3.0-or-later.
