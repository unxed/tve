program t_buf;
{ TveBuf: the piece table against a plain string, with random edits, undo and redo. }
{$mode objfpc}{$H+}
uses SysUtils, TveBuf;
{$I testlib.inc}

var
  B: TTveBuffer;
  Model: AnsiString;
  Seed: LongWord = 12345;
  Changes: Int64;
  Last: array[0..2] of Int64;

function Rnd(N: Integer): Integer;
begin
  Seed := Seed * 1103515245 + 12345;
  if N <= 0 then Exit(0);
  Result := Integer((Seed shr 8) mod LongWord(N));
end;

function RandText(MaxLen: Integer): AnsiString;
var
  N, I: Integer;
begin
  N := Rnd(MaxLen + 1);
  SetLength(Result, N);
  for I := 1 to N do
    case Rnd(6) of
      0: Result[I] := #10;
      1: Result[I] := ' ';
      else Result[I] := Chr(Ord('a') + Rnd(26));
    end;
end;

{ the lines of the model }
function ModelLineCount: Int64;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to Length(Model) do
    if Model[I] = #10 then Inc(Result);
end;

function ModelLineStart(Line: Int64): Int64;
var
  I: Integer;
  N: Int64;
begin
  if Line <= 0 then Exit(0);
  N := 0;
  for I := 1 to Length(Model) do
    if Model[I] = #10 then
    begin
      Inc(N);
      if N = Line then Exit(I);
    end;
  Result := Length(Model);
end;

function ModelLineOf(Offset: Int64): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Offset do
    if (I <= Length(Model)) and (Model[I] = #10) then Inc(Result);
end;

function Same: Boolean;
var
  L, K: Int64;
  Li: Integer;
begin
  Result := (B.Length = Length(Model)) and (B.AsString = Model) and (B.LineCount = ModelLineCount);
  if not Result then Exit;
  for Li := 1 to 4 do
  begin
    L := Rnd(Integer(B.LineCount) + 2) - 1;
    if B.LineStart(L) <> ModelLineStart(L) then Exit(False);
    K := Rnd(Length(Model) + 2) - 1;
    if B.LineOfOffset(K) <> ModelLineOf(K) then Exit(False);
  end;
end;

type
  THook = class
    procedure Hit(Sender: TTveBuffer; Offset, Removed, Inserted: Int64);
  end;

procedure THook.Hit(Sender: TTveBuffer; Offset, Removed, Inserted: Int64);
begin
  Inc(Changes);
  Last[0] := Offset; Last[1] := Removed; Last[2] := Inserted;
end;

var
  Hook: THook;
  I, J, N, Edits: Integer;
  Ok: Boolean;
  E: TTveEdit;
  Log: array of TTveEdit;
  Models: array of AnsiString;
  Off, Cnt: Int64;
  P: PByte;
  Got: Int64;
  T: AnsiString;

begin
  B := TTveBuffer.Create;
  Check((B.Length = 0) and (B.LineCount = 1) and (B.AsString = ''), 'an empty buffer: one empty line');
  B.SetText('one'#10'two'#10'three');
  Model := 'one'#10'two'#10'three';
  Check(Same, 'SetText');
  Check((B.LineStart(0) = 0) and (B.LineStart(1) = 4) and (B.LineStart(2) = 8), 'line starts');
  Check((B.LineEnd(0) = 3) and (B.LineEnd(1) = 7) and (B.LineEnd(2) = 13), 'line ends (the last is the length of the text)');
  Check((B.LineText(1) = 'two') and (B.LineLength(2) = 5), 'line text and length');
  Check((B.LineOfOffset(0) = 0) and (B.LineOfOffset(4) = 1) and (B.LineOfOffset(3) = 0) and (B.LineOfOffset(13) = 2), 'the line of an offset');
  Check(B.ByteAt(4) = Ord('t'), 'ByteAt');
  Check(B.Copy(2, 4) = 'e'#10'tw', 'Copy across a line end');
  Check(B.Copy(-3, 5) = 'on', 'Copy from before the start');
  Check(B.Copy(10, 99) = 'ree', 'Copy past the end');

  Hook := THook.Create;
  B.OnChange := @Hook.Hit;
  Changes := 0;
  B.Insert(3, 'XY');
  Check((B.AsString = 'oneXY'#10'two'#10'three') and (Changes = 1) and (Last[0] = 3) and (Last[1] = 0) and (Last[2] = 2), 'Insert inside a piece, the event');
  B.Delete(0, 4);
  Check(B.AsString = 'Y'#10'two'#10'three', 'Delete across a piece end');
  B.Insert(B.Length, #10'end');
  Check((B.LineCount = 4) and (B.LineText(3) = 'end'), 'Insert at the end');
  B.SetText('abc');
  Model := 'abc';
  B.OnChange := nil;
  { typing coalesces: many single letters, few pieces }
  for I := 1 to 200 do
    B.Insert(B.Length, Chr(Ord('a') + I mod 26));
  Check(B.PieceCount <= 3, 'typing at the end makes the last piece longer, not new ones (' + IntToStr(B.PieceCount) + ' pieces)');
  Check(Length(B.AsString) = 203, 'and the text is all there');

  { zero-copy access }
  B.SetText('hello'#10'world');
  B.Insert(5, '!!!');
  Check(B.Chunk(0, P, Got) and (Got = 5) and (P^ = Ord('h')), 'Chunk: the first piece');
  Check(B.Chunk(5, P, Got) and (Got = 3) and (P^ = Ord('!')), 'Chunk: the piece of the added buffer');
  Check(not B.Chunk(99, P, Got), 'Chunk past the end');

  { random edits against the model, then undo and redo of all of them }
  for N := 1 to 30 do
  begin
    T := RandText(60);
    B.SetText(T);
    Model := T;
    Edits := 150;
    SetLength(Log, Edits);
    SetLength(Models, Edits + 1);
    Models[0] := Model;
    Ok := Same;
    for I := 0 to Edits - 1 do
    begin
      Off := Rnd(Length(Model) + 1);
      Cnt := 0;
      if Rnd(3) > 0 then
        Cnt := Rnd(Length(Model) - Integer(Off) + 1);
      T := '';
      if Rnd(3) > 0 then
        T := RandText(8);
      Log[I] := B.Replace(Off, Cnt, T);
      Delete(Model, Integer(Off) + 1, Integer(Cnt));
      Insert(T, Model, Integer(Off) + 1);
      Models[I + 1] := Model;
      if not Same then
      begin
        Ok := False;
        WriteLn('  after edit ', I, ': off=', Off, ' cnt=', Cnt, ' ins=', Length(T));
        Break;
      end;
    end;
    if Ok then
    begin
      for I := Edits - 1 downto 0 do
      begin
        B.Apply(Log[I], True);
        Model := Models[I];
        if not Same then begin Ok := False; WriteLn('  after undo ', I); Break; end;
      end;
    end;
    if Ok then
      for I := 0 to Edits - 1 do
      begin
        B.Apply(Log[I], False);
        Model := Models[I + 1];
        if not Same then begin Ok := False; WriteLn('  after redo ', I); Break; end;
      end;
    if not Ok then
      Break;
  end;
  Check(Ok, 'random edits (30 x 150): the text, the lines, undo and redo of all of them equal the model');

  { a big text: lines by binary search }
  T := '';
  for I := 1 to 20000 do
    T := T + 'line ' + IntToStr(I) + #10;
  B.SetText(T);
  Check(B.LineCount = 20001, 'a big text: the lines');
  Check(B.LineText(12344) = 'line 12345', 'a big text: a line in the middle');
  B.Insert(B.LineStart(100), 'new'#10'lines'#10);
  Check((B.LineText(100) = 'new') and (B.LineText(102) = 'line 101') and (B.LineCount = 20003), 'a big text: lines after an insert');
  B.Delete(B.LineStart(50), B.LineStart(60) - B.LineStart(50));
  Check((B.LineText(50) = 'line 61') and (B.LineCount = 19993), 'a big text: lines after a delete of ten lines');
  B.Free;
  Finish;
end.
