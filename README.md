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

**Semantic colouring**: with `semantic` in the grammar (C/C++, Go, JavaScript, Pascal, Python, Shell), the names of the types and routines that the outline
finds are coloured where the text uses them (`View.SemanticNames`; the program turns it on). The names are found again before drawing when the text changed, for a
text up to `TveSemanticAutoLimit` (128 KB); a longer one keeps them until `View.UpdateNames`.

YAML block scalars (`key: |`, `key: >-`) colour their lines as text up to the next line that is not indented more than the key. Markdown fences take
`yaml`, `diff`, `toml`/`ini`, `make`, `xml` as well as the languages of the programs.

Built-in languages: C/C++, CSS, Go, HTML, JavaScript/TypeScript (as JavaScript), Jinja/Twig/Django, JSON, Markdown, Pascal, PHP, Python, Shell, Smarty, SQL, XML, YAML, INI/TOML, diff/patch, Makefile.

## Editing features

Keys below are those of the shipped maps (A: `TveKeymapA`, B: `TveKeymapB`); every command can be bound in a key map file by its name.

* **Folding** (`src/tvefold.pas`): a fold is a range of lines that collapses to its first line; folds nest and follow the edits (they are anchors of the
  document). Commands `FoldToggle` (Ctrl+K Z), `FoldFromBlock` (a fold from the selected lines; B: Ctrl+K A), `FoldCollapse` / `FoldExpand` (B: Ctrl+Num- / Ctrl+Num+).
  `View.Folds` is the list; the vertical movement and the scroll bar skip hidden lines. The grammar of a language tells what can be folded (`fold braces`,
  `fold indent`, `fold outline`, `fold /OPEN/ /CLOSE/` for words such as `begin` and `end`; `TveFoldRegions`): C/C++, Go, JavaScript, CSS, JSON and PHP by braces,
  Pascal by its block words, Shell by braces and `if`/`fi`, `case`/`esac`, the loops and `done`, Python and YAML by indentation, Markdown, INI/TOML, diff and
  Makefile by the outline, XML by its tags, HTML (and PHP, Smarty, Jinja) by its container elements and the blocks of the template language. `FoldToggle` and `FoldCollapse` on a line where no fold is take the innermost region of the grammar there (and put the cursor on
  its first line when it hides the cursor); `FoldAll` collapses every region, `UnfoldAll` expands every fold (neither is bound in the shipped maps).
* **Templates** (`src/tvetemplates.pas`): `View.Templates` holds templates loaded from a text (`[shortcut] description` starts one); command `Template` (Ctrl+J)
  replaces the word before the cursor by its template. Variables: `$DATE`, `$TIME` (with an optional format), `$PROMPT(question)` (asked through `View.OnPrompt`),
  `$CURSOR`, `$$`; the lines after the first get the indentation of the line.
* **Completion** (`src/tvecomplete.pas`): command `Completion` (Ctrl+Space) completes the word before the cursor from `View.Completion` (its keywords, the program
  gives it those of the language, then the words of the text); pressing it again cycles through the candidates and back to the typed fragment.
* **Macros**: see below.
* **State of a file** (`src/tvestate.pas`): `TveStateSave` / `TveStateLoad` keep the cursor, the first visible line, the selection, the bookmarks, the folds and the
  insert mode of a file in a section of an INI file; at most `TveStateMaxFiles` (200) files are kept, the one saved longest ago is dropped first. The program:
  `tve --state=FILE`.
* **Hex search** (`src/tvesearch.pas`): the option `Hex` searches bytes written in hexadecimal (`DE AD be ef`); `AllCodePages` searches a plain text in every
  single-byte code page as well. The find dialog (`TveFindDialog`) has both; the commands `HexSearch` and `FindInAllCodePages` are for the host (the program opens
  the find dialog with the option set).
* **Draw mode** (`src/tvedraw.pas`): command `DrawMode` (A: Ctrl+Q M) cycles off, single lines, double lines; in a draw mode the cursor keys draw lines of box
  characters and join them at corners and crossings. The status text shows `DRAW`.
* **Soft wrap** (`src/tvewrap.pas`): command `Wrap` (Alt+W) or `View.Wrap`: a long line is shown as several rows, broken after a blank when there is one; the text
  is not changed and the cursor keys move by rows.

## Keys, macros, outline, drag and drop

* **Key maps**: `TveKeymapA` / `TveKeymapB` are shipped as text; `TveNewKeymapFromFile(UseB, File, Err)` (or `TTveKeymap.LoadFile`) applies a user file over one of them
  (`Ctrl+K B = BlockBegin`, `F7 =` removes a binding; format in `src/tvecmds.pas`). The program: `tve --keymap=FILE`.
* **Macros**: a view records commands and typed text (`MacroRecord`, `MacroPlay`, `MacroPlayAll` are commands that a key map can bind; the shipped maps bind
  none). A search or a replacement that the host runs (`View.FindNext`, `ReplaceNext`, `ReplaceAll` after its dialog) is recorded with its pattern and options.
  `View.RecordedMacro` is a `TTveMacro` (`src/tvemacro.pas`) with a text form, one step per line: a command name, a quoted text (`"hello\n"`),
  `prompt "Name?"` (asks through `View.OnPrompt` and types the answer), `find "x" case word regex back hex`, `replace "x" "y" ...`, `replaceall "x" "y" ...`,
  `goto 12:5` (also `goto 12`, `goto +OFFSET`). A host that moves the cursor or types text after a dialog of its own uses `View.GotoPlace`, `GotoOffsetPlace` and
  `TypeText`, which are recorded (the program does so for go to line, the outline and insert a character).
  `View.PlayMacro(N)` plays it N times; `PlayMacro(0)` (command `MacroPlayAll`) plays it again and again until a step fails (a search finds nothing, a prompt
  is cancelled, a step of the cursor cannot move at an end of the text) or a round changes nothing; a failed step ends the playing in every case.
  `View.SaveMacroFile` / `LoadMacroFile`. The program: `--macro=FILE`, File menu "Save macro" / "Load macro" (file `tve.macro`).
* **Navigation guidelines of vtui**: the dialogs and the menu bar of the program are tv3's, which follow them (`docs/UX-CONFORMANCE.md` of tv3 has the table, tve's
  place in it and the two places where the editor keeps its own rules: the word definition and `Ctrl+C`). The program opens the menu bar with `F9` and `F10`;
  its commands are declared once with `TvActions` and the menu and the status line read them. `tests/pty/test_app.py` checks the menu keys and the word keys in a pty (`tools/pty_screen.py`).
  The wheel scrolls the editor under the pointer, not the focused one (tv3's `UxWheelUnderCursor`). The word movement of the vtui guidelines (`WORDNAV.md`) is optional, not the
  default: the commands `NavWordLeft`, `NavWordRight`, `SelNavWordLeft`, `SelNavWordRight` (`TTveEditor.MoveNavWordLeft/Right`) and the key map text `TveNavWordsKeymapText`
  (pass it as the override text of `TveNewKeymap`); the program: `tve --words=nav`. Word wrap is not taken into account (a jump stops at the end of the logical line).
* **Outline**: `TveOutline(Doc, Lang)` (`src/tvesymbols.pas`) lists `(line, level, title)` of types, routines, headings and so on, by the `symbol LEVEL /REGEX/` lines of
  a grammar (Pascal, C/C++, Go, Python, JavaScript, PHP, Shell, Markdown, HTML/Smarty/Jinja, SQL, YAML, INI/TOML, Makefile, diff). Matches inside comments and strings
  are skipped. `outline indent` (Python) and `outline braces` (C/C++, JavaScript) in a grammar nest the entries: the level is 1 + the number of entries that hold
  it (by indentation, or by braces outside comments and strings). `outline from LEVEL /REGEX/` takes the deeper entries only after the first matching line: in
  a Pascal unit the routines come from the implementation part, so a routine is listed once. Command `Outline` (Alt+O and Ctrl+Shift+O in both maps); the program
  shows it in a list dialog (`TveListDialog`).
* **Drag and drop**: a press on selected text and a drag moves it to where the button is released, Ctrl copies; one undo step (`DragBlock`, `View.DragDrop`).
  While dragging, the cell where the text would go is marked (`View.DropAttr`, the highlight colour by default). Released over another editor view, the text
  goes into its document at that place (moved, or copied with Ctrl), is selected there, and that window gets the focus. A pointer above or below the view (while
  dragging or selecting) scrolls it by as many rows as the pointer is away from it, at most a page per mouse event. Column selections are not dragged.

## What is not done

* Outline rules are line based regular expressions: multi-line signatures give the first line only; Pascal, Go, PHP and the markup languages use the fixed levels of
  their rules (no nesting).
* The macro is one per view and has no conditions other than a failed step; what a host does to the text by itself (not through the view) is not recorded.
* Drag and drop works between the editor views of one program, not with other programs; the horizontal scrolling follows the cursor only.
* Folding by the grammar has no rules for SQL; HTML folds only the elements that always have an end tag (not `p`, `li`, `td` ...); a tag that spans lines does
  not count; the block words of Pascal count a `case` of a variant record as a block.
* Colouring: the semantic names are only those of the outline of the same file (no names of other units or headers, no variables, no scopes); the Markdown fences know all the grammars
  but Smarty, PHP and Jinja; a YAML block scalar is known by its key up to an indentation of 16 (a comment after `|` is coloured as its text).

## Audit

`tools/audit/fetch-corpora.sh` fetches the reference corpora and `tools/audit/borrow-audit.py --ref build/corpora/list.txt src app tests tools`
compares the sources with them; CI runs both (job `borrow-audit`) and fails on any chain of 24 tokens or more.
