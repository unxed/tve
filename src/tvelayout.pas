{ TveLayout: where the characters of a line are on the screen.

  MIT.

  A line is UTF-8 bytes. A cell is a place on the screen: a tab takes the cells up to the next tab stop, a wide character two, a combining mark none, a stray byte (not a
  part of a valid UTF-8 sequence) one. The cursor of the editor is a cell (the free cursor can be past the end of the line, where every cell is a blank).
  All the numbers are 0-based; "index" is the 1-based byte index of Pascal strings.

  A cell that is inside a character (the second cell of a wide character, a cell of a tab) belongs to that character: CellToIndex gives the start and the end of the
  character, so that a caller can snap the cursor. }
unit TveLayout;

{$I tvdefs.inc}

interface

type
  TTveCharInfo = record
    Index: Integer;         { the byte index of the character }
    Bytes: Integer;         { its length in bytes }
    CellStart: Integer;     { the first cell }
    Cells: Integer;         { how many cells (0 for a combining mark) }
  end;

{ The number of cells of the whole line. }
function LayoutCells(const S: AnsiString; TabSize: Integer): Integer;
{ Describes the character that starts at the byte index Index (1-based) when the characters before it end at the cell CellStart. }
procedure LayoutChar(const S: AnsiString; Index, CellStart, TabSize: Integer; out Info: TTveCharInfo);
{ The character at a cell. Past the end of the line: Index = Length + 1, Bytes = 0, CellStart = Cell, Cells = 1 (a virtual blank). }
procedure LayoutAtCell(const S: AnsiString; Cell, TabSize: Integer; out Info: TTveCharInfo);
{ The first cell of the character at the byte index Index (an index past the end gives the cells of the whole line). }
function LayoutIndexToCell(const S: AnsiString; Index, TabSize: Integer): Integer;
{ The byte index of the first character that starts at or after Cell (past the end: Length + 1). }
function LayoutCellToIndex(const S: AnsiString; Cell, TabSize: Integer): Integer;

{ The text of the line from the cell From to the cell To (exclusive), with the tabs and the cut characters shown as blanks: what the screen shows. }
function LayoutSlice(const S: AnsiString; From, To_, TabSize: Integer): AnsiString;

{ Word characters: letters, digits, underscore and everything above U+007F that is not a space or a punctuation of the common blocks. }
function IsWordCp(CP: LongWord): Boolean;

implementation

uses
  TvUtf8;

function IsWordCp(CP: LongWord): Boolean;
begin
  if CP < $80 then
    Exit(((CP >= Ord('0')) and (CP <= Ord('9'))) or ((CP >= Ord('A')) and (CP <= Ord('Z'))) or ((CP >= Ord('a')) and (CP <= Ord('z'))) or (CP = Ord('_')));
  if (CP < $C0) then
    Exit(False);                                       { Latin-1 signs and punctuation; the letters start at U+00C0 (and U+00AA, U+00B5, U+00BA, ignored) }
  if (CP >= $2000) and (CP <= $2BFF) then
    Exit(False);                                       { general punctuation, symbols, arrows, math, frames }
  if (CP >= $3000) and (CP <= $303F) then
    Exit(False);                                       { CJK punctuation }
  if (CP >= $FF00) and (CP <= $FF0F) then
    Exit(False);
  Result := CP <> $D7;
  if CP = $F7 then
    Result := False;
end;

procedure LayoutChar(const S: AnsiString; Index, CellStart, TabSize: Integer; out Info: TTveCharInfo);
var
  CP: LongWord;
  Used, W: Integer;
begin
  Info.Index := Index;
  Info.CellStart := CellStart;
  if (Index < 1) or (Index > Length(S)) then
  begin
    Info.Bytes := 0;
    Info.Cells := 1;
    Exit;
  end;
  if S[Index] = #9 then
  begin
    Info.Bytes := 1;
    if TabSize < 1 then TabSize := 8;
    Info.Cells := TabSize - (CellStart mod TabSize);
    Exit;
  end;
  if Byte(S[Index]) < $80 then
  begin
    Info.Bytes := 1;
    Info.Cells := 1;
    Exit;
  end;
  if Utf8Enabled and Utf8Decode(@S[Index], Length(S) + 1 - Index, CP, Used) and (Used >= 2) then
  begin
    Info.Bytes := Used;
    W := CharWidth(CP);
    if W < 0 then W := 1;
    Info.Cells := W;
  end
  else
  begin
    Info.Bytes := 1;
    Info.Cells := 1;
  end;
end;

function LayoutCells(const S: AnsiString; TabSize: Integer): Integer;
var
  I, Cells: Integer;
  C: TTveCharInfo;
begin
  I := 1;
  Cells := 0;
  while I <= Length(S) do
  begin
    LayoutChar(S, I, Cells, TabSize, C);
    Inc(Cells, C.Cells);
    Inc(I, C.Bytes);
  end;
  Result := Cells;
end;

procedure LayoutAtCell(const S: AnsiString; Cell, TabSize: Integer; out Info: TTveCharInfo);
var
  I, Cells: Integer;
  C: TTveCharInfo;
begin
  I := 1;
  Cells := 0;
  while I <= Length(S) do
  begin
    LayoutChar(S, I, Cells, TabSize, C);
    if (Cell < Cells + C.Cells) or ((C.Cells = 0) and (Cell = Cells) and False) then
    begin
      Info := C;
      Exit;
    end;
    Inc(Cells, C.Cells);
    Inc(I, C.Bytes);
  end;
  Info.Index := Length(S) + 1;
  Info.Bytes := 0;
  Info.CellStart := Cell;
  Info.Cells := 1;
end;

function LayoutIndexToCell(const S: AnsiString; Index, TabSize: Integer): Integer;
var
  I, Cells: Integer;
  C: TTveCharInfo;
begin
  I := 1;
  Cells := 0;
  while (I <= Length(S)) and (I < Index) do
  begin
    LayoutChar(S, I, Cells, TabSize, C);
    Inc(Cells, C.Cells);
    Inc(I, C.Bytes);
  end;
  Result := Cells;
  if Index > Length(S) + 1 then
    Inc(Result, Index - Length(S) - 1);
end;

function LayoutCellToIndex(const S: AnsiString; Cell, TabSize: Integer): Integer;
var
  I, Cells: Integer;
  C: TTveCharInfo;
begin
  I := 1;
  Cells := 0;
  while I <= Length(S) do
  begin
    if Cells >= Cell then
      Exit(I);
    LayoutChar(S, I, Cells, TabSize, C);
    Inc(Cells, C.Cells);
    Inc(I, C.Bytes);
  end;
  Result := Length(S) + 1;
end;

function LayoutSlice(const S: AnsiString; From, To_, TabSize: Integer): AnsiString;
var
  I, Cells, K: Integer;
  C: TTveCharInfo;
begin
  Result := '';
  I := 1;
  Cells := 0;
  while (I <= Length(S)) and (Cells < To_) do
  begin
    LayoutChar(S, I, Cells, TabSize, C);
    if (Cells + C.Cells > From) and (C.Cells > 0) then
    begin
      if (S[I] = #9) or (Cells < From) or (Cells + C.Cells > To_) then
      begin
        { a tab, or a character that is cut by the edge: blanks for the cells that are inside }
        for K := Cells to Cells + C.Cells - 1 do
          if (K >= From) and (K < To_) then
            Result := Result + ' ';
      end
      else
        Result := Result + Copy(S, I, C.Bytes);
    end
    else if (C.Cells = 0) and (Cells >= From) and (Cells <= To_) and (Result <> '') then
      Result := Result + Copy(S, I, C.Bytes);           { a combining mark goes with the character before it }
    Inc(Cells, C.Cells);
    Inc(I, C.Bytes);
  end;
  if Cells < To_ then
    Result := Result + StringOfChar(' ', To_ - Cells - (0));
end;

end.
