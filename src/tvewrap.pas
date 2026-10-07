{ TveWrap: soft wrap of long lines.

  MIT; the behaviour (a long line shown as several rows, broken at the blanks when it can be) is that of the usual editors. The text is not
  changed. A line is cut in segments, each at most Width cells wide: a segment ends after a blank (or a hyphen) when there is one in it, else where the next
  character would not fit. A character (a tab, a wide letter) is never split between two segments.

  TTveWrapMap knows how many rows each line takes (a line hidden by a fold takes none) and where each line starts, so that a row of the view can be found by a
  search and a position of the text by one call. It is built for one width and one tab size and has to be built again when the text, the width, the tab size or
  the folds change (Valid tells). }
unit TveWrap;

{$I tvdefs.inc}

interface

uses
  TveBuf, TveFold;

type
  TTveIntArray = array of Integer;

{ The cells where the segments of the text start (the first is 0), for a width of Width cells. }
function WrapSegments(const Text: AnsiString; Width, TabSize: Integer): TTveIntArray;

type
  TTveWrapMap = class
  private
    FBuf: TTveBuffer;
    FFirst: array of Int64;         { the first row of each line, and the number of rows at the end }
    FWidth, FTab: Integer;
    FVersion: LongWord;
    FFoldStamp: LongWord;
    FHaveFolds: Boolean;
    FBuilt: Boolean;
  public
    constructor Create(ABuf: TTveBuffer);
    procedure Build(Width, TabSize: Integer; Folds: TTveFolds);
    function Valid(Width, TabSize: Integer; Folds: TTveFolds): Boolean;
    function TotalRows: Int64;
    function FirstRow(Line: Int64): Int64;
    function RowsOf(Line: Int64): Integer;
    { The line that the row belongs to (the last line for a row past the end), and the number of the segment in it. }
    function RowToLine(Row: Int64; out Seg: Integer): Int64;
    { The cells where the segment starts and ends (exclusive); the last segment of a line ends at its length (at least one cell more). }
    procedure SegBounds(Line: Int64; Seg: Integer; out A, B: Integer);
    function SegOfCell(Line: Int64; Cell: Integer): Integer;
    function RowOf(Line: Int64; Cell: Integer): Int64;
  end;

implementation

uses
  TveLayout;

function WrapSegments(const Text: AnsiString; Width, TabSize: Integer): TTveIntArray;
var
  Idx, Cell, SegStart, LastBreak, N: Integer;
  Info: TTveCharInfo;
  Done: Boolean;

  procedure AddSeg(C: Integer);
  begin
    SetLength(Result, N + 1);
    Result[N] := C;
    Inc(N);
  end;

begin
  Result := nil;
  N := 0;
  AddSeg(0);
  if Width < 1 then
    Exit;
  Idx := 1;
  Cell := 0;
  SegStart := 0;
  LastBreak := -1;
  while Idx <= Length(Text) do
  begin
    LayoutChar(Text, Idx, Cell, TabSize, Info);
    if Info.Bytes < 1 then
      Break;
    Done := False;
    while not Done do
    begin
      if (Info.Cells > 0) and (Cell - SegStart + Info.Cells > Width) and (Cell > SegStart) then
      begin
        { the character does not fit: break at the last blank of the row, or here }
        if (LastBreak > SegStart) and (LastBreak <= Cell) then
          SegStart := LastBreak
        else
          SegStart := Cell;
        AddSeg(SegStart);
        LastBreak := -1;
        LayoutChar(Text, Idx, Cell, TabSize, Info);
      end
      else
        Done := True;
    end;
    Inc(Cell, Info.Cells);
    if Text[Idx] in [' ', #9, '-'] then
      LastBreak := Cell;
    Inc(Idx, Info.Bytes);
  end;
end;

constructor TTveWrapMap.Create(ABuf: TTveBuffer);
begin
  inherited Create;
  FBuf := ABuf;
end;

procedure TTveWrapMap.Build(Width, TabSize: Integer; Folds: TTveFolds);
var
  L, N: Int64;
  Rows: Int64;
begin
  N := FBuf.LineCount;
  SetLength(FFirst, N + 1);
  Rows := 0;
  for L := 0 to N - 1 do
  begin
    FFirst[L] := Rows;
    if (Folds <> nil) and Folds.IsHidden(L) then
      Continue;
    Inc(Rows, Length(WrapSegments(FBuf.LineText(L), Width, TabSize)));
  end;
  FFirst[N] := Rows;
  FWidth := Width;
  FTab := TabSize;
  FVersion := FBuf.Version;
  FHaveFolds := Folds <> nil;
  if Folds <> nil then
    FFoldStamp := Folds.Stamp
  else
    FFoldStamp := 0;
  FBuilt := True;
end;

function TTveWrapMap.Valid(Width, TabSize: Integer; Folds: TTveFolds): Boolean;
begin
  Result := FBuilt and (Width = FWidth) and (TabSize = FTab) and (FVersion = FBuf.Version) and
    (FHaveFolds = (Folds <> nil)) and ((Folds = nil) or (FFoldStamp = Folds.Stamp));
end;

function TTveWrapMap.TotalRows: Int64;
begin
  Result := FFirst[High(FFirst)];
end;

function TTveWrapMap.FirstRow(Line: Int64): Int64;
begin
  if Line < 0 then
    Line := 0;
  if Line > High(FFirst) then
    Line := High(FFirst);
  Result := FFirst[Line];
end;

function TTveWrapMap.RowsOf(Line: Int64): Integer;
begin
  if (Line < 0) or (Line >= High(FFirst)) then
    Result := 0
  else
    Result := FFirst[Line + 1] - FFirst[Line];
end;

function TTveWrapMap.RowToLine(Row: Int64; out Seg: Integer): Int64;
var
  Lo, Hi, Mid: Int64;
begin
  Seg := 0;
  if Row < 0 then
    Row := 0;
  if Row >= TotalRows then
  begin
    Result := High(FFirst) - 1;
    while (Result > 0) and (RowsOf(Result) = 0) do
      Dec(Result);
    Seg := RowsOf(Result) - 1;
    if Seg < 0 then
      Seg := 0;
    Exit;
  end;
  { the last line whose first row is <= Row and that has rows }
  Lo := 0;
  Hi := High(FFirst) - 1;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if FFirst[Mid] <= Row then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  while (Lo < High(FFirst) - 1) and (RowsOf(Lo) = 0) do
    Inc(Lo);
  Result := Lo;
  Seg := Row - FFirst[Lo];
end;

procedure TTveWrapMap.SegBounds(Line: Int64; Seg: Integer; out A, B: Integer);
var
  S: TTveIntArray;
  T: AnsiString;
begin
  T := FBuf.LineText(Line);
  S := WrapSegments(T, FWidth, FTab);
  if Seg < 0 then
    Seg := 0;
  if Seg > High(S) then
    Seg := High(S);
  A := S[Seg];
  if Seg < High(S) then
    B := S[Seg + 1]
  else
  begin
    B := LayoutCells(T, FTab) + 1;
    if B < A + 1 then
      B := A + 1;
  end;
end;

function TTveWrapMap.SegOfCell(Line: Int64; Cell: Integer): Integer;
var
  S: TTveIntArray;
  I: Integer;
begin
  S := WrapSegments(FBuf.LineText(Line), FWidth, FTab);
  Result := 0;
  for I := 0 to High(S) do
    if S[I] <= Cell then
      Result := I;
end;

function TTveWrapMap.RowOf(Line: Int64; Cell: Integer): Int64;
begin
  Result := FirstRow(Line) + SegOfCell(Line, Cell);
end;

end.
