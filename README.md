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
- **Clock overlay** — wide-tracked day name, date, and time, centered or
  top-centered; 12/24-hour follows the system locale, or force either.
- **Folder gallery** — point it at a folder (JPEG/PNG/WebP/BMP/AVIF/JXL);
  images rotate on an interval with crossfades, optional shuffle, EXIF
  orientation respected, and broken files are skipped instead of stalling a
  slot.
- **Aspect-mismatch strategies** (the ultrawide problem): fit / fill /
  pan-scan modes; letterbox backdrop as nebula, blurred self-copy, or dim;
  optional glass frame; and an ultrawide mode that packs 2–3 portrait images
  side by side as a rotating card row instead of letterboxing one.

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
