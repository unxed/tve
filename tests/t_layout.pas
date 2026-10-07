program t_layout;
{ TveLayout: cells of tabs, wide characters, combining marks, stray bytes. }
{$mode objfpc}{$H+}
uses SysUtils, TvUtf8, TveLayout;
{$I testlib.inc}

const
  Japan = #$E6#$97#$A5#$E6#$9C#$AC;                 { two wide characters: 4 cells }
  Privet = #$D0#$9F#$D1#$80;                         { 2 characters, 2 cells }

var
  C: TTveCharInfo;

begin
  Utf8Enabled := True;
  Check(LayoutCells('abc', 8) = 3, 'ASCII');
  Check(LayoutCells(Japan, 8) = 4, 'wide characters: 2 cells each');
  Check(LayoutCells(Privet, 8) = 2, 'Cyrillic: 1 cell each');
  Check(LayoutCells('a'#$CC#$81, 8) = 1, 'a combining mark takes no cell');
  Check(LayoutCells('a'#$80'b', 8) = 3, 'a stray byte is one cell');
  Check(LayoutCells(#9, 8) = 8, 'a tab at the start: to the stop 8');
  Check(LayoutCells('ab'#9, 8) = 8, 'a tab after 2 cells: to 8');
  Check(LayoutCells('abcdefgh'#9, 8) = 16, 'a tab at a stop: the whole tab size');
  Check(LayoutCells('a'#9'b'#9, 4) = 8, 'tab size 4');

  LayoutAtCell('a'#9'bc', 1, 8, C);
  Check((C.Index = 2) and (C.Bytes = 1) and (C.CellStart = 1) and (C.Cells = 7), 'the cell right after a: the tab, 7 cells');
  LayoutAtCell('a'#9'bc', 5, 8, C);
  Check((C.Index = 2) and (C.CellStart = 1), 'a cell inside a tab belongs to the tab');
  LayoutAtCell('a'#9'bc', 8, 8, C);
  Check((C.Index = 3) and (C.CellStart = 8) and (C.Cells = 1), 'the cell after the tab: b');
  LayoutAtCell('a' + Japan, 2, 8, C);
  Check((C.Index = 2) and (C.CellStart = 1) and (C.Cells = 2), 'the second cell of a wide character belongs to it');
  LayoutAtCell('ab', 5, 8, C);
  Check((C.Index = 3) and (C.Bytes = 0) and (C.CellStart = 5) and (C.Cells = 1), 'past the end: a virtual blank');

  Check(LayoutIndexToCell('a'#9'bc', 3, 8) = 8, 'index to cell after a tab');
  Check(LayoutIndexToCell('a' + Japan, 5, 8) = 3, 'index to cell after a wide character');
  Check(LayoutIndexToCell('ab', 6, 8) = 5, 'an index past the end counts one cell per byte');
  Check(LayoutCellToIndex('a'#9'bc', 8, 8) = 3, 'cell to index');
  Check(LayoutCellToIndex('a'#9'bc', 3, 8) = 3, 'a cell inside a tab: the next character starting at or after it');
  Check(LayoutCellToIndex('ab', 9, 8) = 3, 'a cell past the end');

  Check(LayoutSlice('abcdef', 2, 5, 8) = 'cde', 'slice');
  Check(LayoutSlice('a'#9'b', 0, 10, 8) = 'a       b ', 'slice: the tab is blanks, the tail is blanks');
  Check(LayoutSlice('a'#9'b', 3, 6, 8) = '   ', 'slice inside a tab');
  Check(LayoutSlice(Japan, 1, 4, 8) = ' ' + #$E6#$9C#$AC, 'slice cut in the middle of a wide character: a blank in its place');
  Check(LayoutSlice('ab', 0, 5, 8) = 'ab   ', 'slice past the end');

  Check(IsWordCp(Ord('a')) and IsWordCp(Ord('_')) and IsWordCp(Ord('7')) and not IsWordCp(Ord(' ')) and not IsWordCp(Ord('-')), 'word characters: ASCII');
  Check(IsWordCp($43F) and IsWordCp($E9) and not IsWordCp($A0) and not IsWordCp($2014) and not IsWordCp($D7), 'word characters: letters above 127, not signs');
  Utf8Enabled := False;
  Check(LayoutCells(Privet, 8) = 4, 'no UTF-8: a byte is a cell');
  Utf8Enabled := True;
  Finish;
end.
