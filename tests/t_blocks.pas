program t_blocks;
{ TveBlocks: indent, case, sort, line commands, copy/move, tabs, format. }
{$mode objfpc}{$H+}
uses SysUtils, TvUtf8, TveBuf, TveDoc, TveEditor, TveBlocks;
{$I testlib.inc}

var
  D: TTveDoc;
  E: TTveEditor;

procedure Setup(const Text: AnsiString);
begin
  if E <> nil then E.Free;
  D.LoadText(Text);
  E := TTveEditor.Create(D);
  E.Opt.IndentSize := 2;
end;

function Txt: AnsiString;
begin
  Result := D.Buffer.AsString;
end;

procedure SelectLines(L1, L2: Integer);
begin
  E.GotoLineCell(L1, 0);
  E.StartSelection(skStream);
  E.GotoLineCell(L2, 0);
  E.MoveEnd(True);
end;

function At(L: Int64; C: Integer): Boolean;
begin
  Result := (E.Line = L) and (E.Cell = C);
end;

var
  C: Int64;

begin
  Utf8Enabled := True;
  D := TTveDoc.Create;
  E := nil;

  { indent }
  Setup('a'#10'b'#10#10'c');
  SelectLines(0, 3);
  Check(BlockIndent(E) and (Txt = '  a'#10'  b'#10#10'  c'), 'indent: the lines of the selection, empty lines stay empty');
  D.Undo(C);
  Check(Txt = 'a'#10'b'#10#10'c', 'indent is one undo step');
  Setup('x');
  E.GotoLineCell(0, 1);
  BlockIndent(E);
  Check((Txt = '  x') and At(0, 3), 'indent of the current line; the cursor stays on the text');
  Setup('  a'#10'    b'#10'c');
  SelectLines(0, 2);
  Check(not BlockUnindent(E) and (Txt = '  a'#10'    b'#10'c'), 'unindent: refused when a line cannot');
  E.Opt.UnlimitedUnindent := True;
  Check(BlockUnindent(E) and (Txt = 'a'#10'  b'#10'c'), 'unindent: unlimited');
  Setup(#9'a');
  E.Opt.TabSize := 8;
  E.Opt.IndentSize := 2;
  E.Opt.UnlimitedUnindent := True;
  BlockUnindent(E);
  Check(Txt = '      a', 'unindent of a tab: its rest stays as blanks');
  Setup('a');
  E.Opt.UseTabChars := True;
  E.Opt.IndentSize := 8;
  BlockIndent(E);
  Check(Txt = #9'a', 'indent by the tab size with real tabs');

  { case }
  Setup('hello world');
  E.GotoLineCell(0, 2);
  ChangeCase(E, caseUpper);
  Check(Txt = 'HELLO world', 'upper case of the word at the cursor');
  Setup('Hello World');
  SelectLines(0, 0);
  E.GotoLineCell(0, 11);
  E.StartSelection(skStream);
  E.GotoLineCell(0, 0);
  ChangeCase(E, caseLower);
  Check(Txt = 'hello world', 'lower case of the selection');
  ChangeCase(E, caseTitle);
  Check(Txt = 'Hello World', 'title case');
  ChangeCase(E, caseToggle);
  Check(Txt = 'hELLO wORLD', 'toggle case');
  Setup('abc'#10'def'#10'ghi');
  E.MoveDown;
  ChangeCaseLines(E, caseUpper);
  Check(Txt = 'abc'#10'DEF'#10'ghi', 'case of the line');
  Setup(#$D0#$BF#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82);
  E.GotoLineCell(0, 1);
  ChangeCase(E, caseUpper);
  Check(Txt = #$D0#$9F#$D0#$A0#$D0#$98#$D0#$92#$D0#$95#$D0#$A2, 'upper case of a Cyrillic word');
  Setup('ab cd');
  E.StartSelection(skColumn);
  E.GotoLineCell(0, 2);
  ChangeCase(E, caseUpper);
  Check(Txt = 'AB cd', 'case of a column block');

  { sort }
  Setup('pear'#10'apple'#10'fig'#10'banana');
  SelectLines(0, 3);
  Check(SortLines(E, False) and (Txt = 'apple'#10'banana'#10'fig'#10'pear'), 'sort');
  D.Undo(C);
  Check(Txt = 'pear'#10'apple'#10'fig'#10'banana', 'sort is one undo step');
  Setup('b'#10'A'#10'c');
  SelectLines(0, 2);
  Check(SortLines(E, True) and (Txt = 'c'#10'b'#10'A'), 'sort descending, case-insensitive');
  Setup('b'#10'A'#10'c');
  SelectLines(0, 2);
  SortLines(E, False, True);
  Check(Txt = 'A'#10'b'#10'c', 'sort, case sensitive: capitals first');
  Setup('x3 b'#10'x1 c'#10'x2 a');
  E.GotoLineCell(0, 3);
  E.StartSelection(skColumn);
  E.GotoLineCell(2, 4);
  Check(SortLines(E, False) and (Txt = 'x2 a'#10'x3 b'#10'x1 c'), 'sort by the columns of a column block (whole lines move)');
  Setup('already'#10'sorted');
  SelectLines(0, 1);
  Check(not SortLines(E, False), 'sorted already: nothing to do');
  Setup('2'#10'1'#10'3'#10'1');
  SelectLines(0, 3);
  SortLines(E, False);
  Check(Txt = '1'#10'1'#10'2'#10'3', 'duplicates stay');

  { line commands }
  Setup('one'#10'two');
  E.GotoLineCell(0, 2);
  DuplicateLine(E);
  Check((Txt = 'one'#10'one'#10'two') and At(1, 2), 'duplicate line');
  Setup('one'#10'  two'#10'x');
  JoinLine(E);
  Check((Txt = 'one two'#10'x') and At(0, 3), 'join: the blanks of the next line become one');
  Setup('one '#10'two');
  JoinLine(E);
  Check(Txt = 'one two', 'join: no extra blank when the line ends with one');
  Setup('abcdef');
  E.GotoLineCell(0, 3);
  BreakLineStay(E);
  Check((Txt = 'abc'#10'def') and At(0, 3), 'break line and stay');
  Setup('a'#10'b');
  InsertLineBelow(E);
  Check((Txt = 'a'#10#10'b') and At(0, 0), 'insert line below, the cursor stays');
  InsertLineAbove(E);
  Check((Txt = #10'a'#10#10'b') and At(1, 0), 'insert line above, the cursor stays on its line');

  { copy / move: the marks of a block stay while the cursor moves }
  Setup('hello world');
  E.Opt.PersistentBlocks := True;
  E.StartSelection(skStream);
  E.GotoLineCell(0, 5);
  E.FreezeSelection;
  E.GotoLineCell(0, 11);
  Check(E.HasSelection and E.IsFrozen, 'a block with marks stays when the cursor moves');
  Check(CopyBlockHere(E) and (Txt = 'hello worldhello'), 'copy block here');
  Check(E.HasSelection and (E.Offset = 16), 'and the copy is the new block');
  Setup('hello world');
  E.Opt.PersistentBlocks := True;
  E.StartSelection(skStream);
  E.GotoLineCell(0, 6);
  E.FreezeSelection;
  E.GotoLineCell(0, 11);
  Check(MoveBlockHere(E) and (Txt = 'worldhello '), 'move block here (the cursor after the block moves with the text)');
  Setup('abcdef');
  E.Opt.PersistentBlocks := True;
  E.GotoLineCell(0, 1);
  E.StartSelection(skStream);
  E.GotoLineCell(0, 4);
  E.FreezeSelection;
  E.GotoLineCell(0, 2);
  Check(not MoveBlockHere(E) and (Txt = 'abcdef'), 'move into the block itself is refused');
  E.Opt.PersistentBlocks := False;

  { drag and drop of the selection }
  Setup('one two three');
  E.GotoLineCell(0, 4);
  E.StartSelection(skStream);
  E.GotoLineCell(0, 8);                     { "two " }
  E.FreezeSelection;
  Check(DragBlock(E, 13, False) and (Txt = 'one threetwo '), 'drag: move forward: ' + Txt);
  Check(E.HasSelection and (E.Offset = 13), 'the moved text is selected');
  Check(D.Undo(C) and (Txt = 'one two three'), 'a move is one undo step');
  Setup('one two three');
  E.GotoLineCell(0, 4);
  E.StartSelection(skStream);
  E.GotoLineCell(0, 7);                     { "two" }
  E.FreezeSelection;
  Check(DragBlock(E, 0, False) and (Txt = 'twoone  three'), 'drag: move back: ' + Txt);
  Setup('one two three');
  E.GotoLineCell(0, 4);
  E.StartSelection(skStream);
  E.GotoLineCell(0, 7);
  E.FreezeSelection;
  Check(DragBlock(E, 13, True) and (Txt = 'one two threetwo'), 'drag with Ctrl copies: ' + Txt);
  Check(D.Undo(C) and (Txt = 'one two three'), 'a copy is one undo step');
  Setup('one two three');
  E.GotoLineCell(0, 4);
  E.StartSelection(skStream);
  E.GotoLineCell(0, 7);
  E.FreezeSelection;
  Check(E.HasSelection, 'selected again');
  Check(not DragBlock(E, 5, False) and (Txt = 'one two three'), 'drop inside the selection: refused (move)');
  Check(not DragBlock(E, 4, False) and not DragBlock(E, 7, False), 'drop at the ends: nothing to move');
  Check(not DragBlock(E, 5, True), 'drop inside the selection: refused (copy)');
  Check(DragBlock(E, 7, True) and (Txt = 'one twotwo three'), 'copy next to the selection: ' + Txt);
  Setup('a'#10'b'#10'c');
  E.GotoLineCell(0, 0);
  E.StartSelection(skLine);
  E.FreezeSelection;
  Check(DragBlock(E, 4, False) and (Txt = 'b'#10'a'#10'c'), 'a line selection moves: ' + Txt);
  Setup('abc');
  D.ReadOnly := True;
  E.GotoLineCell(0, 0);
  E.StartSelection(skStream);
  E.GotoLineCell(0, 1);
  Check(not DragBlock(E, 3, False), 'read only: no drag');
  D.ReadOnly := False;
  Setup('abc');
  Check(not DragBlock(E, 1, False), 'nothing selected');

  { tabs }
  Setup('a'#9'b'#10#9'x');
  ExpandTabs(E);
  Check(Txt = 'a       b'#10'        x', 'expand tabs');
  Setup('        a'#10'     b'#10'c');
  TabifyIndent(E);
  Check(Txt = #9'a'#10'     b'#10'c', 'tabify the indent (only whole tab stops)');
  Setup('a  '#10'b'#9#10'c');
  TrimTrailing(E);
  Check(Txt = 'a'#10'b'#10'c', 'trim trailing blanks');

  { format }
  Setup('The quick brown fox jumps over the lazy dog and runs away');
  FormatParagraph(E, alLeft, 0, 20, 0);
  Check(Txt = 'The quick brown fox'#10'jumps over the lazy'#10'dog and runs away', 'format left');
  Setup('The quick brown fox jumps over the lazy dog');
  FormatParagraph(E, alFull, 0, 20, 0);
  Check(Txt = 'The  quick brown fox'#10'jumps  over the lazy'#10'dog', 'format full: the extra blanks go to the first gaps, the last line is not justified');
  Setup('one two three four');
  FormatParagraph(E, alLeft, 2, 12, 2);
  Check(Txt = '    one two'#10'  three four', 'format with a left margin and a paragraph indent');
  Setup('first para'#10'continues here'#10#10'second para');
  FormatParagraph(E, alLeft, 0, 40, 0);
  Check(Txt = 'first para continues here'#10#10'second para', 'a paragraph ends at an empty line');
  Setup('abc'#10'de');
  SelectLines(0, 1);
  AlignLines(E, alRight, 0, 6);
  Check(Txt = '   abc'#10'    de', 'align lines to the right');
  Setup('ab');
  AlignLines(E, alCenter, 0, 8);
  Check(Txt = '   ab', 'align a line to the centre');

  E.Free;
  D.Free;
  Finish;
end.
