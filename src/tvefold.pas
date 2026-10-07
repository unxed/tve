{ TveFold: folds, regions of lines that can be collapsed to their first line.

  MIT.

  A fold is a pair of anchors of the document (the start of its first line and the start of its last line), so it follows the edits; it is gone when its anchors are,
  or when an edit made its end come before its start. A collapsed fold hides the lines after its first line up to and including its last line. Folds nest. The editor
  asks which lines are hidden, and converts between line numbers and the numbers of the visible lines (what the scroll bar counts). }
unit TveFold;

{$I tvdefs.inc}
{$H+}

interface

uses
  TveBuf, TveDoc;

type
  TTveFolds = class
  private
    FDoc: TTveDoc;
    FStart, FEnd: array of Integer;       // anchor ids
    FCollapsed: array of Boolean;
    FRanges: array of Int64;              // merged hidden ranges: first, last, first, last ...
    FRangesVersion: LongWord;
    FStamp: LongWord;
    FRangesStamp: LongWord;
    procedure Rebuild;
    function RangeCount: Integer;
  public
    constructor Create(ADoc: TTveDoc);
    destructor Destroy; override;
    function Count: Integer;
    // Changes with every change of the folds (collapsing, adding, removing).
    property Stamp: LongWord read FStamp;
    function Add(L1, L2: Int64; Collapsed: Boolean): Integer;
    procedure Remove(I: Integer);
    procedure Clear;
    function StartLine(I: Integer): Int64;
    function EndLine(I: Integer): Int64;
    function Collapsed(I: Integer): Boolean;
    procedure SetCollapsed(I: Integer; V: Boolean);
    // The innermost fold that starts or contains the line; -1 if none. StartsHere: only the folds that start at the line.
    function FoldAt(Line: Int64; StartsHere: Boolean = False): Integer;
    function Level(I: Integer): Integer;
    function IsHidden(Line: Int64): Boolean;
    // Visible line numbers (0-based) of a line (a hidden line has the one of the fold that hides it), and back.
    function LineToView(Line: Int64): Int64;
    function ViewToLine(View: Int64): Int64;
    function VisibleCount: Int64;
    function NextVisible(Line: Int64; Down: Boolean): Int64;
    // Expands the collapsed folds that hide the line.
    procedure Reveal(Line: Int64);
    // Collapses/expands the innermost fold at the line (the one that starts there, else the one that contains it); False if there is none.
    function Toggle(Line: Int64): Boolean;
    function CollapseAt(Line: Int64): Boolean;
    function ExpandAt(Line: Int64): Boolean;
    // For saving: "start,end,collapsed" per fold, and back.
    function SaveText: AnsiString;
    procedure LoadText(const S: AnsiString);
  end;

implementation

uses
  SysUtils;

constructor TTveFolds.Create(ADoc: TTveDoc);
begin
  inherited Create;
  FDoc := ADoc;
  FRangesStamp := High(LongWord);
end;

destructor TTveFolds.Destroy;
begin
  Clear;
  inherited Destroy;
end;

function TTveFolds.Count: Integer;
begin
  Result := Length(FStart);
end;

function TTveFolds.Add(L1, L2: Int64; Collapsed: Boolean): Integer;
var
  N: Integer;
begin
  if (L1 < 0) or (L2 <= L1) or (L2 >= FDoc.Buffer.LineCount) then
    Exit(-1);
  N := Length(FStart);
  SetLength(FStart, N + 1);
  SetLength(FEnd, N + 1);
  SetLength(FCollapsed, N + 1);
  FStart[N] := FDoc.AddAnchor(FDoc.Buffer.LineStart(L1));
  FEnd[N] := FDoc.AddAnchor(FDoc.Buffer.LineStart(L2));
  FCollapsed[N] := Collapsed;
  Inc(FStamp);
  Result := N;
end;

procedure TTveFolds.Remove(I: Integer);
var
  J: Integer;
begin
  if (I < 0) or (I >= Length(FStart)) then
    Exit;
  FDoc.RemoveAnchor(FStart[I]);
  FDoc.RemoveAnchor(FEnd[I]);
  for J := I to High(FStart) - 1 do
  begin
    FStart[J] := FStart[J + 1];
    FEnd[J] := FEnd[J + 1];
    FCollapsed[J] := FCollapsed[J + 1];
  end;
  SetLength(FStart, Length(FStart) - 1);
  SetLength(FEnd, Length(FEnd) - 1);
  SetLength(FCollapsed, Length(FCollapsed) - 1);
  Inc(FStamp);
end;

procedure TTveFolds.Clear;
begin
  while Count > 0 do
    Remove(Count - 1);
end;

function TTveFolds.StartLine(I: Integer): Int64;
begin
  Result := FDoc.Buffer.LineOfOffset(FDoc.AnchorPos(FStart[I]));
end;

function TTveFolds.EndLine(I: Integer): Int64;
begin
  Result := FDoc.Buffer.LineOfOffset(FDoc.AnchorPos(FEnd[I]));
end;

function TTveFolds.Collapsed(I: Integer): Boolean;
begin
  Result := FCollapsed[I];
end;

procedure TTveFolds.SetCollapsed(I: Integer; V: Boolean);
begin
  if FCollapsed[I] <> V then
  begin
    FCollapsed[I] := V;
    Inc(FStamp);
  end;
end;

procedure TTveFolds.Rebuild;
var
  I, J, N: Integer;
  A, B, T: Int64;
begin
  // drop the folds that lost their anchors or turned upside down
  I := 0;
  while I < Length(FStart) do
  begin
    if not FDoc.AnchorAlive(FStart[I]) or not FDoc.AnchorAlive(FEnd[I]) or (EndLine(I) <= StartLine(I)) then
      Remove(I)
    else
      Inc(I);
  end;
  FRanges := nil;
  for I := 0 to High(FStart) do
    if FCollapsed[I] then
    begin
      A := StartLine(I) + 1;
      B := EndLine(I);
      N := Length(FRanges);
      SetLength(FRanges, N + 2);
      FRanges[N] := A;
      FRanges[N + 1] := B;
    end;
  // sort by the first line, then merge
  N := Length(FRanges) div 2;
  for I := 1 to N - 1 do
    for J := I downto 1 do
      if FRanges[2 * J] < FRanges[2 * (J - 1)] then
      begin
        T := FRanges[2 * J]; FRanges[2 * J] := FRanges[2 * (J - 1)]; FRanges[2 * (J - 1)] := T;
        T := FRanges[2 * J + 1]; FRanges[2 * J + 1] := FRanges[2 * (J - 1) + 1]; FRanges[2 * (J - 1) + 1] := T;
      end;
  J := 0;
  for I := 1 to N - 1 do
    if FRanges[2 * I] <= FRanges[2 * J + 1] + 1 then
    begin
      if FRanges[2 * I + 1] > FRanges[2 * J + 1] then
        FRanges[2 * J + 1] := FRanges[2 * I + 1];
    end
    else
    begin
      Inc(J);
      FRanges[2 * J] := FRanges[2 * I];
      FRanges[2 * J + 1] := FRanges[2 * I + 1];
    end;
  if N > 0 then
    SetLength(FRanges, 2 * (J + 1));
  FRangesVersion := FDoc.Buffer.Version;
  FRangesStamp := FStamp;
end;

function TTveFolds.RangeCount: Integer;
begin
  if (FRangesVersion <> FDoc.Buffer.Version) or (FRangesStamp <> FStamp) then
    Rebuild;
  Result := Length(FRanges) div 2;
end;

function TTveFolds.FoldAt(Line: Int64; StartsHere: Boolean): Integer;
var
  I: Integer;
  S, E: Int64;
  BestSpan: Int64;
begin
  Result := -1;
  BestSpan := High(Int64);
  RangeCount;
  for I := 0 to High(FStart) do
  begin
    S := StartLine(I);
    E := EndLine(I);
    if (S = Line) or (not StartsHere and (S < Line) and (Line <= E)) then
      if (E - S < BestSpan) then
      begin
        BestSpan := E - S;
        Result := I;
      end;
  end;
end;

function TTveFolds.Level(I: Integer): Integer;
var
  J: Integer;
  S, E: Int64;
begin
  Result := 0;
  S := StartLine(I);
  E := EndLine(I);
  for J := 0 to High(FStart) do
    if (J <> I) and (StartLine(J) <= S) and (EndLine(J) >= E) and not ((StartLine(J) = S) and (EndLine(J) = E) and (J > I)) then
      Inc(Result);
end;

function TTveFolds.IsHidden(Line: Int64): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to RangeCount - 1 do
    if (Line >= FRanges[2 * I]) and (Line <= FRanges[2 * I + 1]) then
      Exit(True);
end;

function TTveFolds.LineToView(Line: Int64): Int64;
var
  I: Integer;
  A, B: Int64;
begin
  Result := Line;
  for I := 0 to RangeCount - 1 do
  begin
    A := FRanges[2 * I];
    B := FRanges[2 * I + 1];
    if Line > B then
      Dec(Result, B - A + 1)
    else if Line >= A then
    begin
      Dec(Result, Line - A + 1);
      Break;
    end
    else
      Break;
  end;
end;

function TTveFolds.ViewToLine(View: Int64): Int64;
var
  I: Integer;
  A, B: Int64;
begin
  Result := View;
  for I := 0 to RangeCount - 1 do
  begin
    A := FRanges[2 * I];
    B := FRanges[2 * I + 1];
    if Result >= A then
      Inc(Result, B - A + 1)
    else
      Break;
  end;
end;

function TTveFolds.VisibleCount: Int64;
var
  I: Integer;
begin
  Result := FDoc.Buffer.LineCount;
  for I := 0 to RangeCount - 1 do
    Dec(Result, FRanges[2 * I + 1] - FRanges[2 * I] + 1);
end;

function TTveFolds.NextVisible(Line: Int64; Down: Boolean): Int64;
var
  I: Integer;
begin
  if Down then
    Result := Line + 1
  else
    Result := Line - 1;
  for I := 0 to RangeCount - 1 do
    if (Result >= FRanges[2 * I]) and (Result <= FRanges[2 * I + 1]) then
    begin
      if Down then
        Result := FRanges[2 * I + 1] + 1
      else
        Result := FRanges[2 * I] - 1;
    end;
  if Result < 0 then
    Result := 0;
  if Result >= FDoc.Buffer.LineCount then
    Result := FDoc.Buffer.LineCount - 1;
end;

procedure TTveFolds.Reveal(Line: Int64);
var
  I: Integer;
begin
  RangeCount;
  for I := 0 to High(FStart) do
    if FCollapsed[I] and (StartLine(I) < Line) and (Line <= EndLine(I)) then
      SetCollapsed(I, False);
end;

function TTveFolds.Toggle(Line: Int64): Boolean;
var
  I: Integer;
begin
  I := FoldAt(Line, True);
  if I < 0 then
    I := FoldAt(Line);
  Result := I >= 0;
  if Result then
    SetCollapsed(I, not FCollapsed[I]);
end;

function TTveFolds.CollapseAt(Line: Int64): Boolean;
var
  I: Integer;
begin
  I := FoldAt(Line, True);
  if I < 0 then
    I := FoldAt(Line);
  Result := I >= 0;
  if Result then
    SetCollapsed(I, True);
end;

function TTveFolds.ExpandAt(Line: Int64): Boolean;
var
  I: Integer;
begin
  I := FoldAt(Line, True);
  if I < 0 then
    I := FoldAt(Line);
  Result := I >= 0;
  if Result then
    SetCollapsed(I, False);
end;

function TTveFolds.SaveText: AnsiString;
var
  I: Integer;
begin
  RangeCount;
  Result := '';
  for I := 0 to High(FStart) do
  begin
    if Result <> '' then
      Result := Result + ';';
    Result := Result + IntToStr(StartLine(I)) + ',' + IntToStr(EndLine(I)) + ',' + IntToStr(Ord(FCollapsed[I]));
  end;
end;

procedure TTveFolds.LoadText(const S: AnsiString);
var
  P, E, C1, C2: Integer;
  Item: AnsiString;
  A, B: Int64;
begin
  Clear;
  P := 1;
  while P <= Length(S) do
  begin
    E := P;
    while (E <= Length(S)) and (S[E] <> ';') do
      Inc(E);
    Item := Copy(S, P, E - P);
    P := E + 1;
    C1 := Pos(',', Item);
    if C1 = 0 then
      Continue;
    C2 := Pos(',', Copy(Item, C1 + 1, MaxInt));
    if C2 = 0 then
      Continue;
    C2 := C1 + C2;
    if TryStrToInt64(Copy(Item, 1, C1 - 1), A) and TryStrToInt64(Copy(Item, C1 + 1, C2 - C1 - 1), B) then
      Add(A, B, Copy(Item, C2 + 1, MaxInt) = '1');
  end;
end;

end.
