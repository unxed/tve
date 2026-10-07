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
  E.Free;
  D.Free;
  Clip.Free;
  Finish;
end.
