# scalelights

A norns script for learning major and minor scales on a LinnStrument 200.
It paints the current scale over the LinnStrument's own 4ths layout and shows
a circle of fifths on the grid.

## Controls

| | |
|---|---|
| E1 | light style: **root + triad** / **root + scale** |
| E2 | key, around the circle of fifths |
| E3 | major / natural minor / harmonic minor |
| K2 | relative major ↔ minor |
| K3 | screen page: circle of fifths / scale degrees |

**Grid:** ring of 12 keys = circle of fifths (C at top, neighbouring keys medium),
center = relative major/minor, top right = scale type, row 4 = degree ladder,
bottom right = one-octave keyboard.

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

Lights are set with LinnStrument CC20 (column), CC21 (row) and CC22 (color).
