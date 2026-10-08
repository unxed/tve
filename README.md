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
| `langs/` | the grammars of the built-in languages (`lang-*.hl`, parts `part-*.hl`); `tools/gen-langs.py` makes `src/tvelangdata.inc` from them |
| `app/` | `tve`, the editor as a program (and the test bench of the view) |
| `tests/` | unit tests (`t_*.pas`), run by `tools/test.sh` |
| `tools/` | scripts; `hldump.pas` shows how a file is coloured |

tv3 is not a submodule here: `tools/need-tv.sh` finds a checkout (`TV=/path/to/tv3`, or `tv/`, or it clones one).

## Syntax highlighting

Grammars (`langs/`) have contexts and a stack, so a language can live inside another one: HTML with CSS and JavaScript, and a template language
(Smarty, PHP, Jinja/Twig/Django) that is injected into every context of them, Markdown with fenced code. The format is in the header of `src/tvehl.pas`;
`tests/data/appeals.tpl` is the test file (HTML, CSS, JavaScript and Smarty mixed in every place). `build/hldump FILE` prints the classes of the bytes.

Built-in languages: C/C++, CSS, Go, HTML, JavaScript/TypeScript (as JavaScript), Jinja/Twig/Django, JSON, Markdown, Pascal, PHP, Python, Shell, Smarty, SQL, XML, YAML, INI/TOML, diff/patch, Makefile.

## Keys, macros, outline, drag and drop

* **Key maps**: `TveKeymapA` / `TveKeymapB` are shipped as text; `TveNewKeymapFromFile(UseB, File, Err)` (or `TTveKeymap.LoadFile`) applies a user file over one of them
  (`Ctrl+K B = BlockBegin`, `F7 =` removes a binding; format in `src/tvecmds.pas`). The program: `tve --keymap=FILE`.
* **Macros**: a view records commands and typed text (`MacroRecord`, `MacroPlay` are commands that a key map can bind; the shipped maps bind neither).
  `View.RecordedMacro` is a `TTveMacro` (`src/tvemacro.pas`) with a text form: one command name or one quoted text (`"hello\n"`) per line;
  `View.SaveMacroFile` / `LoadMacroFile`. The program: `--macro=FILE`, File menu "Save macro" / "Load macro" (file `tve.macro`).
* **Navigation guidelines of vtui**: the dialogs and the menu bar of the program are tv3's, which follow them (`docs/UX-CONFORMANCE.md` of tv3 has the table, tve's
  place in it and the two places where the editor keeps its own rules: the word definition and `Ctrl+C`). The program opens the menu bar with `F9` and `F10`;
  its commands are declared once with `TvActions` and the menu and the status line read them. `tests/pty/test_app.py` checks the menu keys and the word keys in a pty (`tools/pty_screen.py`).
  The wheel scrolls the editor under the pointer, not the focused one (tv3's `UxWheelUnderCursor`). The word movement of the vtui guidelines (`WORDNAV.md`) is optional, not the
  default: the commands `NavWordLeft`, `NavWordRight`, `SelNavWordLeft`, `SelNavWordRight` (`TTveEditor.MoveNavWordLeft/Right`) and the key map text `TveNavWordsKeymapText`
  (pass it as the override text of `TveNewKeymap`); the program: `tve --words=nav`. Word wrap is not taken into account (a jump stops at the end of the logical line).
* **Outline**: `TveOutline(Doc, Lang)` (`src/tvesymbols.pas`) lists `(line, level, title)` of types, routines, headings and so on, by the `symbol LEVEL /REGEX/` lines of
  a grammar (Pascal, C/C++, Go, Python, JavaScript, PHP, Shell, Markdown, HTML/Smarty/Jinja, SQL, YAML, INI/TOML, Makefile, diff). Matches inside comments and strings
  are skipped. Command `Outline` (Alt+O and Ctrl+Shift+O in both maps); the program shows it in a list dialog (`TveListDialog`).
* **Drag and drop**: a press on selected text and a drag moves it to where the button is released, Ctrl copies; one undo step (`DragBlock`, `View.DragDrop`).
  Column selections are not dragged.

## What is not done

* Outline rules are line based regular expressions: no nesting by indentation or braces (Python and Pascal use fixed levels), multi-line signatures give the first line only,
  and a declaration and its implementation both appear (Pascal).
* The macro is one per view and has no repeat counts, no prompts, no conditions; a command that the host handles itself (a dialog) is not recorded.
* Drag and drop works inside one view; no dragging to another window and no auto-scroll speed control (one line per mouse event outside the view).
* Colouring: no semantic colouring (a function name that is only known from its definition), no folding by grammar, the Markdown fences know fewer languages than there are grammars
  (no YAML, diff, INI, Makefile inside a fence), block scalars of YAML are coloured as plain text.
* The hardware cursor shows the drop place during a drag; there is no separate drop marker.
