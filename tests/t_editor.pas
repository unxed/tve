program t_editor;
{ TveEditor: cursor, movements, typing, deleting, selection, clipboard, undo. }
{$mode objfpc}{$H+}
uses SysUtils, TvUtf8, TveBuf, TveDoc, TveEditor;
{$I testlib.inc}

type
  TClip = class
    Text: AnsiString;
    Column: Boolean;
    procedure SetIt(const T: AnsiString; Col: Boolean);
    function GetIt(out T: AnsiString; out Col: Boolean): Boolean;
  end;

procedure TClip.SetIt(const T: AnsiString; Col: Boolean);
begin
  Text := T; Column := Col;
end;

function TClip.GetIt(out T: AnsiString; out Col: Boolean): Boolean;
begin
  T := Text; Col := Column; Result := Text <> '';
end;

var
  D: TTveDoc;
  E: TTveEditor;
  Clip: TClip;
  I: Integer;

procedure Setup(const Text: AnsiString);
begin
  if E <> nil then E.Free;
  D.LoadText(Text);
  E := TTveEditor.Create(D);
  E.OnClipSet := @Clip.SetIt;
  E.OnClipGet := @Clip.GetIt;
end;

function Txt: AnsiString;
begin
  Result := D.Buffer.AsString;
end;

function At(L: Int64; C: Integer): Boolean;
begin
  Result := (E.Line = L) and (E.Cell = C);
end;

const
  Japan = #$E6#$97#$A5#$E6#$9C#$AC;
  Privet = #$D0#$9F#$D1#$80#$D0#$B8;

begin
  Utf8Enabled := True;
  D := TTveDoc.Create;
  Clip := TClip.Create;
  E := nil;

  { movements }
  Setup('hello'#10'wor'#10'x');
  E.MoveRight; E.MoveRight;
  Check(At(0, 2), 'right');
  E.MoveDown;
  Check(At(1, 2), 'down');
  E.MoveEnd;
  Check(At(1, 3), 'end');
  E.MoveUp;
  Check(At(0, 3), 'up keeps the wanted cell (3, set by End on the shorter line)');
  E.MoveHome;
  Check(At(0, 0), 'home');
  E.MoveLeft;
  Check(At(0, 0), 'left at the start of the text stays');
  E.MoveDown; E.MoveHome; E.MoveLeft;
  Check(At(0, 5), 'left at the start of a line goes to the end of the line before');
  E.MoveRight;
  Check(At(0, 6), 'right with the free cursor goes on past the end');

  Setup('abc'#10'defghij'#10'k');
  E.Opt.FreeCursor := False;
  E.MoveEnd; E.MoveRight;
  Check(At(1, 0), 'without the free cursor: right at the end goes to the next line');
  E.MoveEnd;
  E.MoveDown;
  Check(At(2, 1), 'down clamps to the end of the line');
  E.MoveUp;
  Check(At(1, 7), 'and up comes back to the wanted cell');

  { tabs and wide characters are one step }
  Setup('a'#9'b' + Japan + 'c');
  E.MoveRight;
  Check(At(0, 1), 'right: a');
  E.MoveRight;
  Check(At(0, 8), 'right over a tab');
  E.MoveRight; E.MoveRight;
  Check(At(0, 11), 'right over a wide character is 2 cells (b at 8, wide at 9..10, next at 11)');
  E.MoveLeft;
  Check(At(0, 9), 'left over a wide character');

  { words }
  Setup('foo bar_baz  +-  qux');
  E.MoveWordRight;
  Check(At(0, 4), 'word right: to the start of the next word');
  E.MoveWordRight;
  Check(At(0, 13), 'word right: over a word and the blanks, to the signs');
  E.MoveWordRight;
  Check(At(0, 17), 'word right: over the signs and the blanks');
  E.MoveWordLeft;
  Check(At(0, 13), 'word left: back to the signs');
  E.MoveWordLeft;
  Check(At(0, 4), 'word left');
  E.MoveTextEnd;
  Check(At(0, 20), 'text end');
  E.MoveTextStart;
  Check(At(0, 0), 'text start');

  { the word movement of the guidelines (optional, E.7 of the guidelines): the rules of WORDNAV.md }
  Setup('foo.bar baz');
  E.MoveNavWordRight;
  Check(At(0, 3), 'nav: |foo.bar -> foo|.bar (the end of a word before a divider)');
  E.MoveNavWordRight;
  Check(At(0, 8), 'nav: foo|.bar -> foo.bar |baz (a divider is crossed with the word after it only up to the blank)');
  E.MoveNavWordRight;
  Check(At(0, 11), 'nav: to the end of the line');
  E.MoveNavWordLeft;
  Check(At(0, 8), 'nav: Ctrl+Left to the start of the word');
  E.MoveNavWordLeft;
  Check(At(0, 4), 'nav: Ctrl+Left: a divider followed by a word is the start of that word (foo.|bar)');
  E.MoveNavWordLeft;
  Check(At(0, 0), 'nav: Ctrl+Left to the start of the line');
  Setup('...///x');
  E.MoveNavWordRight;
  Check(At(0, 7), 'nav: a run of dividers is not split: no stop inside ...///x (a divider followed by a word is no stop going right)');
  Setup('ab ...///');
  E.MoveNavWordRight;
  Check(At(0, 3), 'nav: the start of the run of dividers');
  E.MoveNavWordRight;
  Check(At(0, 9), 'nav: ... the whole run (mixed dividers) is crossed in one jump');
  Setup('  foo');
  E.MoveNavWordRight;
  Check(At(0, 2), 'nav: from blanks to the first token');
  { line boundaries: the end of a line is a stop, the next jump goes to the next line }
  Setup('ab cd'#10'  ef'#10'gh');
  E.GotoLineCell(0, 3);
  E.MoveNavWordRight;
  Check(At(0, 5), 'nav: Ctrl+Right stops at the end of the line');
  E.MoveNavWordRight;
  Check(At(1, 0), 'nav: ... the next one goes to the beginning of the next line');
  E.MoveNavWordRight;
  Check(At(1, 2), 'nav: ... and on to the first token');
  E.GotoLineCell(1, 0);
  E.MoveNavWordLeft;
  Check(At(0, 5), 'nav: Ctrl+Left at the beginning of a line goes to the end of the previous one');
  E.MoveNavWordLeft;
  Check(At(0, 3), 'nav: ... and on to the start of the word');
  Setup('ab'#13#10'cd');
  E.MoveNavWordRight;
  E.MoveNavWordRight;
  Check(At(1, 0), 'nav: CR LF is one line end');
  E.MoveNavWordLeft;
  Check(At(0, 2), 'nav: ... also going back');
  { the selecting variants of the editor treat dividers as blanks }
  Setup('foo bar.baz');
  E.MoveNavWordRight(True);
  Check(At(0, 3), 'nav: Ctrl+Shift+Right: |foo -> foo| (the end of a word)');
  E.MoveNavWordRight(True);
  Check(At(0, 7), 'nav: ... over the blank to the end of the next word (never stopping on the blank)');
  E.MoveNavWordRight(True);
  Check(At(0, 11), 'nav: ... a divider ends a word as a blank does');
  E.MoveNavWordLeft(True);
  Check(At(0, 8), 'nav: Ctrl+Shift+Left: to the start of baz');
  E.MoveNavWordLeft(True);
  Check(At(0, 4), 'nav: ... to the start of bar');
  Check(E.HasSelection, 'nav: the selection is made');
  { UTF-8: a character is not split; letters of any script are word characters }
  Setup(Japan + ' ' + Japan + '.x');
  E.MoveNavWordRight;
  Check(At(0, 5), 'nav: wide characters are word characters (a jump over two of them, 4 cells)');
  E.MoveNavWordRight;
  Check(At(0, 9), 'nav: ... the blank is crossed with the next word, up to the divider');
  E.MoveNavWordLeft;
  Check(At(0, 5), 'nav: ... and back');

  { typing, the free cursor pads }
  Setup('ab');
  E.MoveEnd;
  E.TypeText('c');
  Check(Txt = 'abc', 'typing at the end');
  E.GotoLineCell(0, 6);
  E.TypeText('x');
  Check(Txt = 'abc   x', 'typing past the end pads with blanks');
  Setup('abc');
  E.Opt.InsertMode := False;
  E.GotoLineCell(0, 1);
  E.TypeText('X');
  Check((Txt = 'aXc') and At(0, 2), 'overwrite mode');
  E.Opt.InsertMode := True;
  Setup('é');
  E.TypeText('ü');
  Check(Txt = 'üé', 'a character of two bytes');

  { new line and the indent }
  Setup('  abc');
  E.MoveEnd;
  E.NewLine;
  Check((Txt = '  abc'#10'  ') and At(1, 2), 'auto indent copies the indent');
  E.Opt.AutoIndent := False;
  E.NewLine;
  Check((Txt = '  abc'#10'  '#10) and At(2, 0), 'no auto indent');
  Setup('abcdef');
  E.GotoLineCell(0, 3);
  E.NewLine;
  Check((Txt = 'abc'#10'def') and At(1, 0), 'a line is split');

  { Backspace and Delete }
  Setup('abc'#10'def');
  E.GotoLineCell(1, 0);
  E.Backspace;
  Check((Txt = 'abcdef') and At(0, 3), 'Backspace at the start of a line joins it');
  E.Backspace;
  Check(Txt = 'abdef', 'Backspace');
  E.DeleteChar;
  Check(Txt = 'abef', 'Delete');
  E.MoveEnd;
  E.GotoLineCell(0, 9);
  E.Backspace;
  Check((Txt = 'abef') and At(0, 8), 'Backspace in the free space only moves the cursor');
  Setup('ab'#10'cd');
  E.MoveEnd;
  E.DeleteChar;
  Check(Txt = 'abcd', 'Delete at the end of a line joins the next one');
  Setup('x' + Japan + 'y');
  E.GotoLineCell(0, 3);
  E.Backspace;
  Check(Txt = 'x' + #$E6#$9C#$AC + 'y', 'Backspace removes the whole wide character before the cursor');

  { Backspace unindents }
  Setup('    one'#10'  two'#10'          ');
  E.GotoLineCell(2, 10);
  E.Backspace;
  Check(At(2, 2), 'Backspace in an indent goes to the indent of a line above that is less (the line above has 2)');
  E.Backspace;
  Check(At(2, 0), 'and again: no smaller indent above, to 0');
  Setup('    x');
  E.Opt.BackspaceUnindent := False;
  E.GotoLineCell(0, 4);
  E.Backspace;
  Check(At(0, 3), 'without the option: one blank');

  { tab }
  Setup('ab');
  E.Tab;
  Check((Txt = '        ab') and At(0, 8), 'Tab inserts blanks up to the next stop');
  Setup('ab');
  E.Opt.UseTabChars := True;
  E.GotoLineCell(0, 2);
  E.Tab;
  Check((Txt = 'ab'#9) and At(0, 8), 'Tab with real tabs');
  E.Opt.UseTabChars := False;
  Setup('hello world'#10'');
  E.Opt.SmartTab := True;
  E.MoveDown;
  E.Tab;
  Check(At(1, 6), 'smart tab: to the word start of the line above');

  { delete line, to eol, words }
  Setup('one'#10'two'#10'three');
  E.MoveDown;
  E.DeleteLine;
  Check(Txt = 'one'#10'three', 'delete line');
  E.DeleteLine;
  Check(Txt = 'one', 'delete the last line takes the line end before');
  Setup('hello world');
  E.GotoLineCell(0, 5);
  E.DeleteToEol;
  Check(Txt = 'hello', 'delete to end of line');
  Setup('hello world');
  E.GotoLineCell(0, 5);
  E.DeleteToBol;
  Check(Txt = ' world', 'delete to start of line');
  Setup('foo bar baz');
  E.DeleteWordRight;
  Check(Txt = 'bar baz', 'delete word right');
  E.GotoLineCell(0, 7);
  E.DeleteWordLeft;
  Check(Txt = 'bar ', 'delete word left');

  { selection by movement }
  Setup('abcdef');
  E.GotoLineCell(0, 1);
  E.MoveRight(True); E.MoveRight(True);
  Check(E.HasSelection, 'Shift+right selects');
  Check(E.CopyBlock and (Clip.Text = 'bc') and not Clip.Column, 'copy the selection');
  E.TypeText('X');
  Check((Txt = 'aXdef') and not E.HasSelection, 'typing replaces the selection');
  E.Opt.OverwriteBlocks := False;
  E.GotoLineCell(0, 0);
  E.MoveRight(True);
  E.TypeText('Y');
  Check(Txt = 'aYXdef', 'with OverwriteBlocks off typing keeps the selected text and inserts at the cursor');
  E.Opt.OverwriteBlocks := True;
  Setup('abcdef');
  E.MoveRight(True); E.MoveRight(True);
  E.MoveRight;
  Check(not E.HasSelection, 'a movement without Shift drops the selection');
  E.Opt.PersistentBlocks := True;
  E.MoveRight(True);
  E.MoveRight(True);
  E.MoveLeft;
  Check(E.HasSelection, 'with persistent blocks it stays');
  Setup('abcdefgh');
  E.Opt.PersistentBlocks := True;
  E.MoveRight(True); E.MoveRight(True); E.MoveRight(True);
  E.MoveRight; E.MoveRight; E.MoveDown;
  E.CopyBlock;
  Check(E.HasSelection and (Clip.Text = 'abc'), 'with persistent blocks the moves without Shift do not extend it: ' + Clip.Text);
  E.TypeText('Z');
  E.CopyBlock;
  Check(Clip.Text = 'abc', 'nor does typing: ' + Clip.Text);
  E.Opt.PersistentBlocks := False;

  Setup('abc def ghi');
  E.GotoLineCell(0, 5);
  E.SelectWord;
  Check(E.CopyBlock and (Clip.Text = 'def'), 'select word');
  E.SelectAll;
  Check(E.CopyBlock and (Clip.Text = 'abc def ghi'), 'select all');
  Setup('one'#10'two'#10'three');
  E.MoveDown;
  E.SelectLine;
  Check(E.CopyBlock and (Clip.Text = 'two'#10), 'select line (the line end goes with it)');
  Check(E.CutBlock and (Txt = 'one'#10'three'), 'cut a line');
  E.MoveTextEnd;
  E.Paste;
  Check(Txt = 'one'#10'threetwo'#10, 'paste (the cursor was at the end of the text)');

  { column blocks }
  Setup('abcdef'#10'ghijkl'#10'mnopqr');
  E.GotoLineCell(0, 1);
  E.StartSelection(skColumn);
  E.GotoLineCell(2, 3);
  Check(E.HasSelection, 'a column block');
  Check(E.CopyBlock and (Clip.Text = 'bc'#10'hi'#10'no') and Clip.Column, 'copy a column block');
  E.DeleteSelection;
  Check(Txt = 'adef'#10'gjkl'#10'mpqr', 'delete a column block');
  E.GotoLineCell(0, 4);
  E.PasteText('XY'#10'ZW', True);
  Check(Txt = 'adefXY'#10'gjklZW'#10'mpqr', 'paste a column block');
  Setup('ab');
  E.GotoLineCell(0, 1);
  E.PasteText('1'#10'2'#10'3', True);
  Check(Txt = 'a1b'#10' 2'#10' 3', 'a column block is pasted into new lines, short lines are padded');

  { undo through the editor }
  Setup('start');
  E.MoveEnd;
  E.TypeText('a'); E.TypeText('b'); E.TypeText('c');
  Check(Txt = 'startabc', 'typed');
  E.Undo;
  Check((Txt = 'start') and At(0, 5), 'one undo takes the typed run back, the cursor is where it was');
  E.Redo;
  Check((Txt = 'startabc') and At(0, 8), 'redo puts the cursor after it');
  Setup('aXb');
  E.GotoLineCell(0, 1);
  E.MoveRight(True);
  E.TypeText('YZ');
  Check(Txt = 'aYZb', 'replace the selection');
  E.Undo;
  Check(Txt = 'aXb', 'replace and typing are one undo step (the group)');

  { read-only }
  Setup('ro');
  D.ReadOnly := True;
  E.TypeText('x');
  Check(Txt = 'ro', 'read-only: no typing');
  D.ReadOnly := False;

  { auto brackets }
  Setup('');
  E.Opt.AutoBrackets := True;
  E.TypeText('(');
  Check((Txt = '()') and At(0, 1), 'auto bracket');
  E.TypeText(')');
  Check((Txt = '()') and At(0, 2), 'the closing bracket is skipped');
  { hard wrap while typing }
  D.LoadText('');
  E.Opt := TveDefaultEditorOptions;
  E.Opt.WrapColumn := 10;
  E.GotoOffset(0);
  for I := 1 to Length('aaa bbb ccc ddd') do
    E.TypeText(Copy('aaa bbb ccc ddd', I, 1));
  Check(D.Buffer.AsString = 'aaa bbb' + #10 + 'ccc ddd', 'wrap: ' + D.Buffer.AsString);
  E.Opt.WrapColumn := 0;
  E.Free;
  D.Free;
  Clip.Free;
  Finish;
end.
