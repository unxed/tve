# tve: a text editor component for tv3

`tve` is the editor view of the [tv3](https://github.com/unxed/tv3) family (Turbo Vision for Free Pascal). MIT licence.

## Design

* The text is a **piece table**: the file as it was read, a buffer of everything typed, and a list of pieces that tells
  which parts of them make the text now. An edit changes the list, never the bytes; undo and redo put an old piece list back.
* A **line index** (the offsets of the line ends of both buffers) answers "where does line N start" without scanning.
* Text is UTF-8 inside (`TvUStr` of tv3 gives columns and cells); the code page of a file is converted when it is read and written.
* The view is a `TView` of tv3: it draws cells, takes events, and uses the tv3 units for the clipboard, history, file names (also on DOS
  with UTF-8 names), masks, key names, INI files.

## Layout

| Path | What |
|---|---|
| `src/` | the units (`Tve*.pas`) |
| `tests/` | unit tests (`t_*.pas`), run by `tools/test.sh` |
| `tools/` | scripts |

tv3 is not a submodule here: `tools/need-tv.sh` finds a checkout (`TV=/path/to/tv3`, or `tv/`, or it clones one).
