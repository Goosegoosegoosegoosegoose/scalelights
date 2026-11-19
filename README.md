# scalelights

A norns script for learning major and minor scales on a LinnStrument 200.
It paints the current scale over the LinnStrument's own 4ths layout and shows
a circle of fifths on the grid.

## Controls

| | |
|---|---|
| E1 | lights: **root + triad** / **rainbow** (scale only) / **normal** (the LinnStrument's own 4ths colors, no scale) |
| E2 | key, around the circle of fifths |
| E3 | major / natural minor / harmonic minor |
| K2 | relative major ↔ minor |
| K3 | screen page: circle of fifths / scale degrees / **playing** |

**Grid:** ring of 12 keys = circle of fifths (C at top, neighbouring keys medium),
center = relative major/minor, top right = scale type, row 4 = degree ladder,
bottom right = one-octave keyboard.

## Rainbow

Only the scale is lit. The root is white, then the colors walk around the color
wheel as the scale goes up: 1 white · 2 orange · 3 yellow · 4 lime · 5 green ·
6 cyan · 7 magenta (raised 7th in harmonic minor: pink). Everything else is dark.

The LinnStrument has no per-pad brightness over MIDI — each pad is one of 10 colors
or off.

## What you're playing

Hold notes on the LinnStrument and norns names them:

- **playing** page (K3): big chord name (e.g. `Dm7`, `C/E`), the roman numeral in
  the current key (`ii7`, `I (inversion)`, `V7`, `viio`…), and every held note low
  to high with its octave and scale degree (`-` = outside the key).
- Two notes show the interval (`M3`, `P5`, `tritone`…).
- Knows triads, sus2/4, 6ths, 7ths (maj7, 7, m7, m7b5, dim7, m(maj7), +maj7),
  add9 and 9ths, in any inversion. Anything else is listed note by note.
- The circle page's bottom line also shows the chord while you play.

## Colors (root + triad)

| Degree | Color |
|---|---|
| root | yellow |
| 3rd & 5th | green |
| 2nd, 4th, 6th, 7th | white |
| raised 7th (harmonic minor) | magenta |

Blue and red are left to the LinnStrument's own 4ths layout.

## Setup

1. Copy `scalelights.lua` to `dust/code/scalelights/` on norns.
2. Turn off the **midigrid** mod if it's on (it takes over the LinnStrument as a grid).
3. In PARAMETERS > EDIT, run **learn bottom-left note** and press the LinnStrument's
   bottom-left pad. Leave `row offset` at 5 for 4ths tuning.

## Routing

```
LinnStrument ──USB──▶ norns ──USB──▶ Electra One Mini ──▶ Nymphes
```

The LinnStrument plugs straight into norns. Everything it plays (notes plus MPE
pitch bend, pressure and CC74, on their original channels) is passed on to the
**out device**, the Electra One Mini, which forwards it to the Nymphes. The scale-light
CCs only go back to the LinnStrument, never to the synth.

- `midi device` / `out device (Electra Mini)` are picked automatically by name
  (`linnstrument`, `electra`); check them in PARAMETERS > EDIT if a port is missed.
- `LinnStrument thru` turns the pass-through off if you only want lights.
- On the Mini, the USB port norns sends on has to be routed to the port the Nymphes is on.
- Switching the out device, turning thru off, or leaving the script sends all-notes-off
  on all 16 channels so nothing hangs.

Lights are set with LinnStrument CC20 (column), CC21 (row) and CC22 (color).
