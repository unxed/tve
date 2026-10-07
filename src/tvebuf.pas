{ TveBuf: the text of the editor as a piece table, with a line index.

  MIT. The text is
  never moved; it is a list of pieces, each a run of bytes of one of two buffers that only grow.
    original   the text as it was read (never changed)
    added      everything that was typed or pasted since (only appended to)
  An edit cuts pieces and puts a piece of the added buffer between them; typing at the end of the last typed piece makes that piece longer instead of making a
  new one. Because the bytes of both buffers never change, any state of the list stays valid: an edit is recorded as "these pieces were replaced by these", which
  is all that undo and redo need (TTveEdit), and a deleted block of a hundred megabytes costs the same as a deleted letter.

  The text is bytes, with LF as the only line end (the line ends of a file are converted when it is read and written, see TveFile). The line index is the sorted
  offsets of the LF bytes of each buffer; a piece knows how many LF it has (found by two binary searches), the list keeps running totals, and so "where does
  line N start" and "which line is this offset in" are binary searches, with no scan of the text. Offsets and lengths are Int64.

  The totals of the pieces (Cum*) are rebuilt lazily from the first piece that an edit touched. }
unit TveBuf;

{$I tvdefs.inc}

interface

type
  TPiece = record
    Src: Byte;              { 0 original, 1 added }
    Start: Int64;           { in that buffer }
    Len: Int64;
    LFs: Int64;             { the LF bytes in the piece }
  end;
  TPieces = array of TPiece;

  { One edit as the replacement of a run of pieces: after the edit the pieces New are at Index in the place of the pieces Old. Undo puts Old back, redo New. }
  TTveEdit = record
    Index: Integer;
    Old, New: TPieces;
    Offset: Int64;          { where the text changed }
    Removed, Inserted: Int64;
  end;

  TTveBuffer = class;
  TTveChangeEvent = procedure(Sender: TTveBuffer; Offset, Removed, Inserted: Int64) of object;

  TTveBuffer = class
  private
    FOrig: AnsiString;
    FOrigLF: array of Int64;
    FOrigLFCount: Integer;
    FAdd: AnsiString;
    FAddLen: Int64;
    FAddLF: array of Int64;
    FAddLFCount: Integer;
    FPieces: TPieces;
    FCount: Integer;
    FCumLen: array of Int64;        { FCumLen[I] is the length of the pieces before I }
    FCumLF: array of Int64;
    FCumValid: Integer;             { FCumLen/FCumLF are right for the indexes 0..FCumValid }
    FTotal, FTotalLF: Int64;
    FVersion: LongWord;
    FOnChange: TTveChangeEvent;
    procedure ResetState;
    function LFArrayLower(Src: Byte; Pos: Int64): Integer;
    function CountLF(Src: Byte; Start, Len: Int64): Int64;
    function LFPos(Src: Byte; K: Integer): Int64;
    procedure MakePiece(var P: TPiece; Src: Byte; Start, Len: Int64);
    procedure EnsureCum(Index: Integer);
    function FindPiece(Offset: Int64; out Inner: Int64): Integer;
    function FindLF(K: Int64): Int64;
    procedure AppendAdded(const S: AnsiString);
    procedure Splice(Index, DelCount: Integer; const NewPieces: TPieces);
  public
    constructor Create;
    { Replaces the text by S (which has LF as the only line end). The change event is not raised, the version changes. }
    procedure SetText(const S: AnsiString);
    function Length: Int64;
    function LineCount: Int64;
    function ByteAt(Offset: Int64): Byte;
    function Copy(Offset, Count: Int64): AnsiString;
    function AsString: AnsiString;
    { A run of bytes of the text that is in one piece: P and the count of bytes from Offset to the end of the piece (False past the end). No copy is made. }
    function Chunk(Offset: Int64; out P: PByte; out Count: Int64): Boolean;

    { Lines are 0-based. LineStart is the offset of the first byte, LineEnd the offset of the LF that ends it (or the length of the text for the last line). }
    function LineStart(Line: Int64): Int64;
    function LineEnd(Line: Int64): Int64;
    function LineLength(Line: Int64): Int64;
    function LineText(Line: Int64): AnsiString;
    { The line that holds the byte at Offset (an offset at the length of the text is in the last line). }
    function LineOfOffset(Offset: Int64): Int64;

    { Replaces DelCount bytes at Offset by Ins; the result describes the edit for undo. Offset and DelCount are cut to the text. }
    function Replace(Offset, DelCount: Int64; const Ins: AnsiString): TTveEdit;
    function Insert(Offset: Int64; const S: AnsiString): TTveEdit;
    function Delete(Offset, Count: Int64): TTveEdit;
    { Undo (Back = True) or redo of an edit that was returned by Replace; the edits must be applied in the order opposite to that of the edits. }
    procedure Apply(const E: TTveEdit; Back: Boolean);

    { Grows by one at every change (also undo and redo). }
    property Version: LongWord read FVersion;
    property OnChange: TTveChangeEvent read FOnChange write FOnChange;
    { The number of pieces: for the tests and for the curious. }
    property PieceCount: Integer read FCount;
  end;

implementation

{ --- the LF arrays --- }

constructor TTveBuffer.Create;
begin
  inherited Create;
  ResetState;
end;

procedure TTveBuffer.ResetState;
begin
  FOrig := '';
  FOrigLF := nil;
  FOrigLFCount := 0;
  FAdd := '';
  FAddLen := 0;
  FAddLF := nil;
  FAddLFCount := 0;
  FPieces := nil;
  FCount := 0;
  FCumLen := nil;
  FCumLF := nil;
  SetLength(FCumLen, 1);
  SetLength(FCumLF, 1);
  FCumLen[0] := 0;
  FCumLF[0] := 0;
  FCumValid := 0;
  FTotal := 0;
  FTotalLF := 0;
end;

{ The index of the first LF of the buffer that is at Pos or after. }
function TTveBuffer.LFArrayLower(Src: Byte; Pos: Int64): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  if Src = 0 then Hi := FOrigLFCount else Hi := FAddLFCount;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    if LFPos(Src, Mid) < Pos then
      Lo := Mid + 1
    else
      Hi := Mid;
  end;
  Result := Lo;
end;

function TTveBuffer.LFPos(Src: Byte; K: Integer): Int64;
begin
  if Src = 0 then
    Result := FOrigLF[K]
  else
    Result := FAddLF[K];
end;

function TTveBuffer.CountLF(Src: Byte; Start, Len: Int64): Int64;
begin
  if Len <= 0 then
    Exit(0);
  Result := LFArrayLower(Src, Start + Len) - LFArrayLower(Src, Start);
end;

procedure TTveBuffer.MakePiece(var P: TPiece; Src: Byte; Start, Len: Int64);
begin
  P.Src := Src;
  P.Start := Start;
  P.Len := Len;
  P.LFs := CountLF(Src, Start, Len);
end;

{ --- the totals --- }

procedure TTveBuffer.EnsureCum(Index: Integer);
var
  I: Integer;
begin
  if Index > FCount then
    Index := FCount;
  if System.Length(FCumLen) < FCount + 1 then
  begin
    SetLength(FCumLen, FCount + 1 + (FCount shr 1) + 16);
    SetLength(FCumLF, System.Length(FCumLen));
  end;
  for I := FCumValid + 1 to Index do
  begin
    FCumLen[I] := FCumLen[I - 1] + FPieces[I - 1].Len;
    FCumLF[I] := FCumLF[I - 1] + FPieces[I - 1].LFs;
  end;
  if Index > FCumValid then
    FCumValid := Index;
end;

{ The piece that holds the byte at Offset, and the distance of the byte from the start of the piece. At the end of the text: the index FCount, Inner = 0. }
function TTveBuffer.FindPiece(Offset: Int64; out Inner: Int64): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Inner := 0;
  if Offset >= FTotal then
    Exit(FCount);
  EnsureCum(FCount);
  Lo := 0;
  Hi := FCount;                          { the last I with FCumLen[I] <= Offset }
  while Hi - Lo > 1 do
  begin
    Mid := (Lo + Hi) shr 1;
    if FCumLen[Mid] <= Offset then
      Lo := Mid
    else
      Hi := Mid;
  end;
  Result := Lo;
  Inner := Offset - FCumLen[Lo];
end;

{ The offset of the K-th LF (0-based) of the text. }
function TTveBuffer.FindLF(K: Int64): Int64;
var
  Lo, Hi, Mid: Integer;
  First: Integer;
begin
  EnsureCum(FCount);
  Lo := 0;
  Hi := FCount;                          { the piece that has the LF: the last I with FCumLF[I] <= K }
  while Hi - Lo > 1 do
  begin
    Mid := (Lo + Hi) shr 1;
    if FCumLF[Mid] <= K then
      Lo := Mid
    else
      Hi := Mid;
  end;
  First := LFArrayLower(FPieces[Lo].Src, FPieces[Lo].Start);
  Result := FCumLen[Lo] + (LFPos(FPieces[Lo].Src, First + Integer(K - FCumLF[Lo])) - FPieces[Lo].Start);
end;

{ --- reading --- }

procedure TTveBuffer.SetText(const S: AnsiString);
var
  I: Integer;
  P: TPiece;
begin
  ResetState;
  FOrig := S;
  SetLength(FOrigLF, 16);
  for I := 1 to System.Length(S) do
    if S[I] = #10 then
    begin
      if FOrigLFCount = System.Length(FOrigLF) then
        SetLength(FOrigLF, FOrigLFCount * 2);
      FOrigLF[FOrigLFCount] := I - 1;
      Inc(FOrigLFCount);
    end;
  if System.Length(S) > 0 then
  begin
    SetLength(FPieces, 4);
    MakePiece(P, 0, 0, System.Length(S));
    FPieces[0] := P;
    FCount := 1;
    FTotal := P.Len;
    FTotalLF := P.LFs;
  end;
  Inc(FVersion);
end;

function TTveBuffer.Length: Int64;
begin
  Result := FTotal;
end;

function TTveBuffer.LineCount: Int64;
begin
  Result := FTotalLF + 1;
end;

function TTveBuffer.Chunk(Offset: Int64; out P: PByte; out Count: Int64): Boolean;
var
  I: Integer;
  Inner: Int64;
begin
  P := nil;
  Count := 0;
  if (Offset < 0) or (Offset >= FTotal) then
    Exit(False);
  I := FindPiece(Offset, Inner);
  Count := FPieces[I].Len - Inner;
  if FPieces[I].Src = 0 then
    P := @PByte(@FOrig[1])[FPieces[I].Start + Inner]
  else
    P := @PByte(@FAdd[1])[FPieces[I].Start + Inner];
  Result := True;
end;

function TTveBuffer.ByteAt(Offset: Int64): Byte;
var
  P: PByte;
  N: Int64;
begin
  if Chunk(Offset, P, N) then
    Result := P^
  else
    Result := 0;
end;

function TTveBuffer.Copy(Offset, Count: Int64): AnsiString;
var
  P: PByte;
  N, Got: Int64;
begin
  Result := '';
  if Offset < 0 then
  begin
    Inc(Count, Offset);
    Offset := 0;
  end;
  if Offset + Count > FTotal then
    Count := FTotal - Offset;
  if Count <= 0 then
    Exit;
  SetLength(Result, Count);
  Got := 0;
  while Got < Count do
  begin
    if not Chunk(Offset + Got, P, N) then
      Break;
    if N > Count - Got then
      N := Count - Got;
    Move(P^, Result[Got + 1], N);
    Inc(Got, N);
  end;
end;

function TTveBuffer.AsString: AnsiString;
begin
  Result := Copy(0, FTotal);
end;

{ --- lines --- }

function TTveBuffer.LineStart(Line: Int64): Int64;
begin
  if Line <= 0 then
    Exit(0);
  if Line > FTotalLF then
    Exit(FTotal);
  Result := FindLF(Line - 1) + 1;
end;

function TTveBuffer.LineEnd(Line: Int64): Int64;
begin
  if Line < 0 then
    Exit(0);
  if Line >= FTotalLF then
    Exit(FTotal);
  Result := FindLF(Line);
end;

function TTveBuffer.LineLength(Line: Int64): Int64;
begin
  Result := LineEnd(Line) - LineStart(Line);
end;

function TTveBuffer.LineText(Line: Int64): AnsiString;
var
  A: Int64;
begin
  A := LineStart(Line);
  Result := Copy(A, LineEnd(Line) - A);
end;

function TTveBuffer.LineOfOffset(Offset: Int64): Int64;
var
  I: Integer;
  Inner: Int64;
  First: Integer;
begin
  if Offset <= 0 then
    Exit(0);
  if Offset >= FTotal then
    Exit(FTotalLF);
  I := FindPiece(Offset, Inner);
  First := LFArrayLower(FPieces[I].Src, FPieces[I].Start);
  Result := FCumLF[I] + (LFArrayLower(FPieces[I].Src, FPieces[I].Start + Inner) - First);
end;

{ --- editing --- }

procedure TTveBuffer.AppendAdded(const S: AnsiString);
var
  I, N: Integer;
begin
  N := System.Length(S);
  if N = 0 then
    Exit;
  if FAddLen + N > System.Length(FAdd) then
    SetLength(FAdd, (FAddLen + N) * 2 + 64);
  Move(S[1], FAdd[FAddLen + 1], N);
  for I := 1 to N do
    if S[I] = #10 then
    begin
      if FAddLFCount = System.Length(FAddLF) then
        SetLength(FAddLF, FAddLFCount * 2 + 16);
      FAddLF[FAddLFCount] := FAddLen + I - 1;
      Inc(FAddLFCount);
    end;
  Inc(FAddLen, N);
end;

{ The pieces Index .. Index + DelCount - 1 are replaced by NewPieces; the totals are corrected. }
procedure TTveBuffer.Splice(Index, DelCount: Integer; const NewPieces: TPieces);
var
  I, Delta: Integer;
begin
  for I := Index to Index + DelCount - 1 do
  begin
    Dec(FTotal, FPieces[I].Len);
    Dec(FTotalLF, FPieces[I].LFs);
  end;
  for I := 0 to High(NewPieces) do
  begin
    Inc(FTotal, NewPieces[I].Len);
    Inc(FTotalLF, NewPieces[I].LFs);
  end;
  Delta := System.Length(NewPieces) - DelCount;
  if FCount + Delta > System.Length(FPieces) then
    SetLength(FPieces, (FCount + Delta) * 2 + 8);
  if Delta <> 0 then
    Move(FPieces[Index + DelCount], FPieces[Index + System.Length(NewPieces)], (FCount - Index - DelCount) * SizeOf(TPiece));
  for I := 0 to High(NewPieces) do
    FPieces[Index + I] := NewPieces[I];
  Inc(FCount, Delta);
  if FCumValid > Index then
    FCumValid := Index;
  Inc(FVersion);
end;

function TTveBuffer.Replace(Offset, DelCount: Int64; const Ins: AnsiString): TTveEdit;
var
  First, Last, I, K: Integer;
  InnerA, InnerB: Int64;
  NewList: TPieces;
  EndOffset: Int64;
  Coalesce: Boolean;
begin
  if Offset < 0 then Offset := 0;
  if Offset > FTotal then Offset := FTotal;
  if DelCount < 0 then DelCount := 0;
  if Offset + DelCount > FTotal then DelCount := FTotal - Offset;
  Result.Offset := Offset;
  Result.Removed := DelCount;
  Result.Inserted := System.Length(Ins);
  Result.Old := nil;
  Result.New := nil;
  if (DelCount = 0) and (Ins = '') then
  begin
    Result.Index := 0;
    Exit;
  end;
  EndOffset := Offset + DelCount;
  First := FindPiece(Offset, InnerA);
  { typing at the end of the last piece of the added buffer that ends where the added buffer ends: that piece grows }
  Coalesce := False;
  if (Ins <> '') and (DelCount = 0) and (InnerA = 0) and (First > 0) then
    with FPieces[First - 1] do
      Coalesce := (Src = 1) and (Start + Len = FAddLen);
  if Coalesce then
  begin
    Result.Index := First - 1;
    SetLength(Result.Old, 1);
    Result.Old[0] := FPieces[First - 1];
    AppendAdded(Ins);
    SetLength(NewList, 1);
    MakePiece(NewList[0], 1, Result.Old[0].Start, Result.Old[0].Len + System.Length(Ins));
    Splice(First - 1, 1, NewList);
    SetLength(Result.New, 1);
    Result.New[0] := NewList[0];
    if Assigned(FOnChange) then
      FOnChange(Self, Offset, 0, System.Length(Ins));
    Exit;
  end;
  if EndOffset >= FTotal then
  begin
    Last := FCount - 1;
    InnerB := 0;
    if FCount > 0 then
      InnerB := FPieces[Last].Len;        { the end of the last piece }
  end
  else
  begin
    Last := FindPiece(EndOffset, InnerB); { the piece that holds the first byte that stays }
  end;
  if (DelCount > 0) and (EndOffset < FTotal) and (InnerB = 0) then
  begin
    Dec(Last);                             { the range ends exactly at a boundary: the piece before is the last one that changes }
    InnerB := FPieces[Last].Len;
  end;
  { the pieces that change: First .. Last (First = FCount: an insert at the end, nothing to replace) }
  if (First >= FCount) or ((DelCount = 0) and (InnerA = 0)) then
  begin
    { a pure insertion between two pieces (or at the end): nothing is replaced }
    Result.Index := First;
    SetLength(NewList, 0);
    if Ins <> '' then
    begin
      SetLength(NewList, 1);
      K := Integer(FAddLen);
      AppendAdded(Ins);
      MakePiece(NewList[0], 1, K, System.Length(Ins));
    end;
    Splice(First, 0, NewList);
    Result.New := NewList;
    if Assigned(FOnChange) then
      FOnChange(Self, Offset, 0, System.Length(Ins));
    Exit;
  end;
  if (DelCount = 0) then
    Last := First;                         { an insert inside a piece (or at the start of one): only that piece is cut }
  Result.Index := First;
  SetLength(Result.Old, Last - First + 1);
  for I := First to Last do
    Result.Old[I - First] := FPieces[I];
  SetLength(NewList, 0);
  K := 0;
  SetLength(NewList, 3);
  if InnerA > 0 then
  begin
    MakePiece(NewList[K], FPieces[First].Src, FPieces[First].Start, InnerA);
    Inc(K);
  end;
  if Ins <> '' then
  begin
    I := Integer(FAddLen);
    AppendAdded(Ins);
    MakePiece(NewList[K], 1, I, System.Length(Ins));
    Inc(K);
  end;
  if DelCount = 0 then
  begin
    { the rest of the cut piece }
    if FPieces[First].Len - InnerA > 0 then
    begin
      MakePiece(NewList[K], FPieces[First].Src, FPieces[First].Start + InnerA, FPieces[First].Len - InnerA);
      Inc(K);
    end;
  end
  else if FPieces[Last].Len - InnerB > 0 then
  begin
    MakePiece(NewList[K], FPieces[Last].Src, FPieces[Last].Start + InnerB, FPieces[Last].Len - InnerB);
    Inc(K);
  end;
  SetLength(NewList, K);
  Splice(First, Last - First + 1, NewList);
  Result.New := NewList;
  if Assigned(FOnChange) then
    FOnChange(Self, Offset, DelCount, System.Length(Ins));
end;

function TTveBuffer.Insert(Offset: Int64; const S: AnsiString): TTveEdit;
begin
  Result := Replace(Offset, 0, S);
end;

function TTveBuffer.Delete(Offset, Count: Int64): TTveEdit;
begin
  Result := Replace(Offset, Count, '');
end;

procedure TTveBuffer.Apply(const E: TTveEdit; Back: Boolean);
var
  Removed, Inserted: Int64;
begin
  if (System.Length(E.Old) = 0) and (System.Length(E.New) = 0) then
    Exit;
  if Back then
  begin
    Splice(E.Index, System.Length(E.New), E.Old);
    Removed := E.Inserted;
    Inserted := E.Removed;
  end
  else
  begin
    Splice(E.Index, System.Length(E.Old), E.New);
    Removed := E.Removed;
    Inserted := E.Inserted;
  end;
  if Assigned(FOnChange) then
    FOnChange(Self, E.Offset, Removed, Inserted);
end;

end.
