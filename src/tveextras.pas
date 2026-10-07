{ TveExtras: small commands that do not belong to the blocks: the keyboard layout fix, date and time, a character by its code, "calculate the block".

  MIT. }
unit TveExtras;

{$I tvdefs.inc}

interface

uses
  TveEditor;

{ Text typed in the wrong layout of the keyboard: Latin letters of a Russian text, or the other way (the layout is guessed from the text). }
function FixLayoutText(const S: AnsiString): AnsiString;
{ the selection, else the word at the cursor, else the line }
function FixLayout(E: TTveEditor; WholeLine: Boolean = False): Boolean;

{ a date / time at the cursor; the format is the one of FormatDateTime ('yyyy-mm-dd hh:nn:ss') }
function InsertDateTime(E: TTveEditor; const Format: AnsiString): Boolean;
{ a character by its code point (the number of Unicode) }
function InsertCodePoint(E: TTveEditor; CP: LongWord): Boolean;
{ the text of the selection (or of the current line) calculated; the result is put in the clipboard of the editor (OnClipSet) and returned. Column blocks are added up. }
function CalcBlock(E: TTveEditor; out Result_: AnsiString): Boolean;

implementation

uses
  SysUtils, TvUtf8, TvUStr, TveCalc;

const
  { QWERTY keys and the Russian letters on them, both cases }
  LatLower = 'qwertyuiop[]asdfghjkl;''zxcvbnm,./`';
  LatUpper = 'QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>?~';

function RusLower(I: Integer): LongWord;
const
  T: array[0..33] of Word = ($439, $446, $443, $43A, $435, $43D, $433, $448, $449, $437, $445, $44A,
    $444, $44B, $432, $430, $43F, $440, $43E, $43B, $434, $436, $44D, $44F, $447, $441, $43C, $438, $442, $44C, $431, $44E, $2E, $451);
begin
  Result := T[I];
end;

function FixLayoutText(const S: AnsiString): AnsiString;
var
  I, K, Used, Cyr, Lat: Integer;
  CP, U: LongWord;
  R: AnsiString;
  ToLatin: Boolean;
  Found: Boolean;
begin
  Cyr := 0;
  Lat := 0;
  I := 1;
  while I <= Length(S) do
  begin
    CP := Byte(S[I]);
    Used := 1;
    if (CP >= $80) and not (Utf8Decode(@S[I], Length(S) + 1 - I, CP, Used) and (Used >= 2)) then
    begin
      CP := Byte(S[I]);
      Used := 1;
    end;
    if (CP >= $400) and (CP <= $4FF) then Inc(Cyr)
    else if ((CP >= 65) and (CP <= 90)) or ((CP >= 97) and (CP <= 122)) then Inc(Lat);
    Inc(I, Used);
  end;
  if Cyr + Lat = 0 then
    Exit(S);                                 { no letters: nothing to tell the layout by }
  ToLatin := Cyr > Lat;
  R := '';
  I := 1;
  while I <= Length(S) do
  begin
    CP := Byte(S[I]);
    Used := 1;
    if (CP >= $80) and not (Utf8Decode(@S[I], Length(S) + 1 - I, CP, Used) and (Used >= 2)) then
    begin
      CP := Byte(S[I]);
      Used := 1;
    end;
    Found := False;
    if ToLatin then
    begin
      for K := 0 to 33 do
        if (RusLower(K) = CP) or (CpUpper(RusLower(K)) = CP) then
        begin
          if CpUpper(RusLower(K)) = CP then
            R := R + LatUpper[K + 1]
          else
            R := R + LatLower[K + 1];
          Found := True;
          Break;
        end;
    end
    else if CP < $80 then
      for K := 1 to Length(LatLower) do
        if (LatLower[K] = Chr(CP)) or (LatUpper[K] = Chr(CP)) then
        begin
          U := RusLower(K - 1);
          if LatUpper[K] = Chr(CP) then
            U := CpUpper(U);
          R := R + U8Encode(U);
          Found := True;
          Break;
        end;
    if not Found then
      R := R + Copy(S, I, Used);
    Inc(I, Used);
  end;
  Result := R;
end;

function FixLayout(E: TTveEditor; WholeLine: Boolean): Boolean;
var
  A, B: Int64;
  Old, New_: AnsiString;
  Pin: Integer;
begin
  Result := False;
  if E.Doc.ReadOnly then
    Exit;
  if WholeLine then
  begin
    E.ClearSelection;
    A := E.Doc.Buffer.LineStart(E.Line);
    B := E.Doc.Buffer.LineEnd(E.Line);
  end
  else if E.HasSelection then
  begin
    if not E.SelectionRange(A, B) then
      Exit;
  end
  else
  begin
    E.SelectWord;
    if not E.HasSelection or not E.SelectionRange(A, B) then
    begin
      E.ClearSelection;
      Exit;
    end;
    E.ClearSelection;
  end;
  Old := E.Doc.Buffer.Copy(A, B - A);
  New_ := FixLayoutText(Old);
  if New_ = Old then
    Exit;
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.Replace(A, B - A, New_);
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := True;
end;

function InsertDateTime(E: TTveEditor; const Format: AnsiString): Boolean;
begin
  Result := E.TypeText(FormatDateTime(Format, Now));
end;

function InsertCodePoint(E: TTveEditor; CP: LongWord): Boolean;
begin
  Result := (CP > 0) and (CP <= $10FFFF) and E.TypeText(U8Encode(CP));
end;

function CalcBlock(E: TTveEditor; out Result_: AnsiString): Boolean;
var
  T, Err: AnsiString;
  Col: Boolean;
  V: Double;
begin
  Result := False;
  Result_ := '';
  if E.HasSelection then
    T := E.SelectionText(Col)
  else
  begin
    T := E.Doc.Buffer.LineText(E.Line);
    Col := False;
  end;
  if Col then
    Result := CalcSum(T, V, Err)
  else
    Result := CalcExpression(StringReplace(T, #10, ' ', [rfReplaceAll]), V, Err);
  if Result then
  begin
    Result_ := CalcFormat(V);
    if Assigned(E.OnClipSet) then
      E.OnClipSet(Result_, False);
  end
  else
    Result_ := Err;
end;

end.
