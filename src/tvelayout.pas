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

{ The word that holds the character at the byte index Idx, or ends right before it: S[A .. B - 1]. False when there is none. }
function TveWordAt(const S: AnsiString; Idx: Integer; out A, B: Integer): Boolean;
{ The byte index of the next whole-word occurrence of Word in S at or after From (0 when there is none). }
function TveFindWord(const S, Word: AnsiString; From: Integer): Integer;

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

function CpAtIdx(const S: AnsiString; I: Integer; out Len: Integer): LongWord;
begin
  Result := Byte(S[I]);
  Len := 1;
  if (Result >= $80) and Utf8Decode(@S[I], Length(S) - I + 1, Result, Len) then
    Exit;
  if Result >= $80 then
  begin
    Result := Byte(S[I]);
    Len := 1;
  end;
end;

function StartBefore(const S: AnsiString; I: Integer): Integer;
begin
  { the start of the character that ends right before I }
  Result := I - 1;
  while (Result > 1) and ((Byte(S[Result]) and $C0) = $80) and (I - Result < 4) do
    Dec(Result);
end;

function TveWordAt(const S: AnsiString; Idx: Integer; out A, B: Integer): Boolean;
var
  L, P: Integer;
begin
  Result := False;
  A := 0;
  B := 0;
  if (Idx < 1) or (Idx > Length(S) + 1) then
    Exit;
  if (Idx <= Length(S)) and IsWordCp(CpAtIdx(S, Idx, L)) then
    P := Idx
  else if Idx > 1 then
  begin
    P := StartBefore(S, Idx);
    if not IsWordCp(CpAtIdx(S, P, L)) then
      Exit;
  end
  else
    Exit;
  A := P;
  while A > 1 do
  begin
    L := StartBefore(S, A);
    if not IsWordCp(CpAtIdx(S, L, P)) then
      Break;
    A := L;
  end;
  B := A;
  while B <= Length(S) do
  begin
    if not IsWordCp(CpAtIdx(S, B, L)) then
      Break;
    Inc(B, L);
  end;
  Result := B > A;
end;

function TveFindWord(const S, Word: AnsiString; From: Integer): Integer;
var
  I, L: Integer;
  Ok: Boolean;
begin
  Result := 0;
  if Word = '' then
    Exit;
  I := From;
  if I < 1 then
    I := 1;
  while I <= Length(S) - Length(Word) + 1 do
  begin
    if (S[I] = Word[1]) and (Copy(S, I, Length(Word)) = Word) then
    begin
      Ok := True;
      if I > 1 then
        Ok := not IsWordCp(CpAtIdx(S, StartBefore(S, I), L));
      if Ok and (I + Length(Word) <= Length(S)) then
        Ok := not IsWordCp(CpAtIdx(S, I + Length(Word), L));
      if Ok then
        Exit(I);
    end;
    Inc(I);
  end;
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
