{ TveDraw: the line-drawing mode. The cursor keys draw lines of box characters (single or double) instead of just moving: moving from a cell to the next
  joins the two cells, and the characters at both are chosen by which of their four sides are joined (so crossings and corners come out right).

  MIT. }
unit TveDraw;

{$I tvdefs.inc}
{$H+}

interface

uses
  TveEditor;

type
  TTveDrawStyle = (dsSingle, dsDouble);
  TTveDir = (dirUp, dirDown, dirLeft, dirRight);

{ Draws a step in the direction and moves the cursor there; False if the cursor cannot go there (the top of the text). One undo step. }
function TveDrawStep(E: TTveEditor; Dir: TTveDir; Style: TTveDrawStyle): Boolean;
{ The sides joined by a box character: bit 1 up, 2 down, 4 left, 8 right; 0 if the character is no box character. }
function TveBoxSides(CP: LongWord; out Style: TTveDrawStyle): Integer;
function TveBoxChar(Sides: Integer; Style: TTveDrawStyle): LongWord;

implementation

uses
  SysUtils, TvUtf8, TvUStr, TveLayout;

const
  Single_: array[1..15] of LongWord = (
    $2502, $2502, $2502,                      // up, down, up+down: a vertical line
    $2500, $2518, $2510, $2524,               // left, left+up, left+down, left+up+down
    $2500, $2514, $250C, $251C,               // right, right+up, right+down, right+up+down
    $2500, $2534, $252C, $253C);              // left+right, ... all
  Double_: array[1..15] of LongWord = (
    $2551, $2551, $2551,
    $2550, $255D, $2557, $2563,
    $2550, $255A, $2554, $2560,
    $2550, $2569, $2566, $256C);

function TveBoxChar(Sides: Integer; Style: TTveDrawStyle): LongWord;
begin
  if (Sides < 1) or (Sides > 15) then
    Exit($20);
  if Style = dsSingle then
    Result := Single_[Sides]
  else
    Result := Double_[Sides];
end;

function TveBoxSides(CP: LongWord; out Style: TTveDrawStyle): Integer;
var
  I: Integer;
begin
  Style := dsSingle;
  for I := 1 to 15 do
    if Single_[I] = CP then
    begin
      // the vertical and the horizontal lines are shared by the sides with a bit more than the character shows
      case CP of
        $2502: Exit(3);
        $2500: Exit(12);
      end;
      Exit(I);
    end;
  Style := dsDouble;
  for I := 1 to 15 do
    if Double_[I] = CP then
    begin
      case CP of
        $2551: Exit(3);
        $2550: Exit(12);
      end;
      Exit(I);
    end;
  Result := 0;
end;

// The code point of the character at a cell (blank past the end of the line or inside a wide character).
function CharAt(E: TTveEditor; L: Int64; Cell: Integer): LongWord;
var
  S: AnsiString;
  Info: TTveCharInfo;
  Len: Integer;
  CP: LongWord;
begin
  S := E.Doc.Buffer.LineText(L);
  LayoutAtCell(S, Cell, E.Opt.TabSize, Info);
  if (Info.Bytes = 0) or (Info.CellStart <> Cell) then
    Exit($20);
  if Utf8Decode(@S[Info.Index], Info.Bytes, CP, Len) then
    Result := CP
  else
    Result := $20;
end;

procedure PutAt(E: TTveEditor; L: Int64; Cell: Integer; CP: LongWord);
var
  S, Pad: AnsiString;
  Info: TTveCharInfo;
  Cells: Integer;
  LS: Int64;
begin
  S := E.Doc.Buffer.LineText(L);
  LS := E.Doc.Buffer.LineStart(L);
  Cells := LayoutCells(S, E.Opt.TabSize);
  if Cell >= Cells then
  begin
    Pad := StringOfChar(' ', Cell - Cells);
    E.Doc.Insert(LS + Length(S), Pad + U8Encode(CP));
    Exit;
  end;
  LayoutAtCell(S, Cell, E.Opt.TabSize, Info);
  if (Info.Cells = 1) and (Info.Bytes > 0) and (S[Info.Index] <> #9) then
    E.Doc.Replace(LS + Info.Index - 1, Info.Bytes, U8Encode(CP))
  else if Info.Bytes > 0 then
    E.Doc.Replace(LS + Info.Index - 1, Info.Bytes, U8Encode(CP));
end;

// The sides joined at a cell. A plain vertical or horizontal line does not say which of its two ends are joined: those with a neighbour that is joined back.
function SidesAt(E: TTveEditor; L: Int64; Cell: Integer): Integer;
var
  CP: LongWord;
  St, St2: TTveDrawStyle;
  Raw: Integer;

  function Faces(L2: Int64; C2: Integer; Bit: Integer): Boolean;
  begin
    if (L2 < 0) or (C2 < 0) or (L2 >= E.Doc.Buffer.LineCount) then
      Exit(False);
    Result := (TveBoxSides(CharAt(E, L2, C2), St2) and Bit) <> 0;
  end;

begin
  CP := CharAt(E, L, Cell);
  Raw := TveBoxSides(CP, St);
  Result := Raw;
  if (CP = $2502) or (CP = $2551) then
  begin
    if not Faces(L - 1, Cell, 2) then Result := Result and not 1;
    if not Faces(L + 1, Cell, 1) then Result := Result and not 2;
  end
  else if (CP = $2500) or (CP = $2550) then
  begin
    if not Faces(L, Cell - 1, 8) then Result := Result and not 4;
    if not Faces(L, Cell + 1, 4) then Result := Result and not 8;
  end;
end;

function TveDrawStep(E: TTveEditor; Dir: TTveDir; Style: TTveDrawStyle): Boolean;
var
  L, L2: Int64;
  C, C2: Integer;
  Out_, In_: Integer;
  S1, S2: Integer;
begin
  L := E.Line;
  C := E.Cell;
  L2 := L;
  C2 := C;
  case Dir of
    dirUp: begin Dec(L2); Out_ := 1; In_ := 2; end;
    dirDown: begin Inc(L2); Out_ := 2; In_ := 1; end;
    dirLeft: begin Dec(C2); Out_ := 4; In_ := 8; end;
  else
    begin Inc(C2); Out_ := 8; In_ := 4; end;
  end;
  if (L2 < 0) or (C2 < 0) then
    Exit(False);
  E.Doc.BeginGroup;
  try
    // a new line at the end of the text
    if L2 >= E.Doc.Buffer.LineCount then
      E.Doc.Insert(E.Doc.Buffer.Length, #10);
    S1 := SidesAt(E, L, C) or Out_;
    S2 := SidesAt(E, L2, C2) or In_;
    PutAt(E, L, C, TveBoxChar(S1, Style));
    PutAt(E, L2, C2, TveBoxChar(S2, Style));
    E.GotoLineCell(L2, C2);
  finally
    E.Doc.EndGroup;
  end;
  Result := True;
end;

end.
