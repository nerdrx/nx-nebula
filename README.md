# NX Nebula — live wallpaper for KDE Plasma 6

The living background of the [NX design language](https://github.com/nerdrx/nx-kde):
a drifting violet/cyan nebula over deep space, with an optional clock overlay
and a folder gallery built for ultrawide displays. Companion to the
[NX theme suite](https://github.com/nerdrx/nx-kde), works fine standalone.

No shaders, no per-frame CPU work — pre-rendered sprite layers animated with
transform and opacity only, fully paused whenever the desktop isn't visible.

## Features

- **Living nebula** — blobs drift on 35–60 s orbits with a slow breathe;
  sparse parallax starfield with gentle twinkle. Speed dial from 0.25×
  (subliminal) to 3×. Identical composition to the static NX Nebula
  wallpaper, so lock screen and desktop match.
- **Clock overlay** — wide-tracked day name, date, and time, centered or
  top-centered.
- **Folder gallery** — point it at a folder; images rotate on an interval
  with crossfades, optional shuffle.
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
