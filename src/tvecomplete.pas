{ TveComplete: completion of words: the candidates for the word before the cursor, from a list of keywords and from the words of the text.

  MIT. }
unit TveComplete;

{$I tvdefs.inc}
{$H+}

interface

uses
  TveEditor;

type
  TTveWords = array of AnsiString;

  TTveCompletion = class
  public
    Keywords: TTveWords;
    MinPrefix: Integer;            // the shortest word fragment that is completed
    CaseSensitive: Boolean;
    MaxText: Int64;                // the words are taken from this many bytes around the cursor
    constructor Create;
    procedure SetKeywords(const S: AnsiString);      // blank separated
    // The fragment before the cursor (its start is the byte offset FragStart in the buffer) and the candidates, keywords first, then the words of the text.
    function Candidates(E: TTveEditor; out Fragment: AnsiString; out FragStart: Int64; out Items: TTveWords): Boolean;
  end;

implementation

uses
  SysUtils, TveLayout;

constructor TTveCompletion.Create;
begin
  inherited Create;
  MinPrefix := 1;
  MaxText := 4 * 1024 * 1024;
end;

procedure TTveCompletion.SetKeywords(const S: AnsiString);
var
  I, Start: Integer;
begin
  Keywords := nil;
  I := 1;
  while I <= Length(S) do
  begin
    while (I <= Length(S)) and (S[I] in [' ', #9, #10, #13]) do
      Inc(I);
    Start := I;
    while (I <= Length(S)) and not (S[I] in [' ', #9, #10, #13]) do
      Inc(I);
    if I > Start then
    begin
      SetLength(Keywords, Length(Keywords) + 1);
      Keywords[High(Keywords)] := Copy(S, Start, I - Start);
    end;
  end;
end;

function IsWordByte(C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Byte(C) >= $80);
end;

function TTveCompletion.Candidates(E: TTveEditor; out Fragment: AnsiString; out FragStart: Int64; out Items: TTveWords): Boolean;
var
  Line: AnsiString;
  I, Cut: Integer;
  Text: AnsiString;
  From, To_, P, Q: Int64;
  W: AnsiString;
  Count: Integer;

  function Matches(const Cand: AnsiString): Boolean;
  begin
    if Length(Cand) <= Length(Fragment) then
      Exit(False);
    if CaseSensitive then
      Result := Copy(Cand, 1, Length(Fragment)) = Fragment
    else
      Result := SameText(Copy(Cand, 1, Length(Fragment)), Fragment);
  end;

  function Have(const Cand: AnsiString): Boolean;
  var
    K: Integer;
  begin
    for K := 0 to Count - 1 do
      if Items[K] = Cand then
        Exit(True);
    Result := False;
  end;

  procedure AddItem(const Cand: AnsiString);
  begin
    if Have(Cand) then
      Exit;
    if Count >= Length(Items) then
      SetLength(Items, Count * 2 + 16);
    Items[Count] := Cand;
    Inc(Count);
  end;

begin
  Result := False;
  Items := nil;
  Count := 0;
  Line := E.Doc.Buffer.LineText(E.Line);
  Cut := LayoutCellToIndex(Line, E.Cell, E.Opt.TabSize);
  I := Cut;
  while (I > 1) and IsWordByte(Line[I - 1]) do
    Dec(I);
  Fragment := Copy(Line, I, Cut - I);
  FragStart := E.Doc.Buffer.LineStart(E.Line) + I - 1;
  if Length(Fragment) < MinPrefix then
    Exit;
  for I := 0 to High(Keywords) do
    if Matches(Keywords[I]) then
      AddItem(Keywords[I]);
  // the words of the text around the cursor
  From := E.Offset - MaxText div 2;
  if From < 0 then From := 0;
  To_ := E.Offset + MaxText div 2;
  if To_ > E.Doc.Buffer.Length then To_ := E.Doc.Buffer.Length;
  Text := E.Doc.Buffer.Copy(From, To_ - From);
  P := 1;
  while P <= Length(Text) do
  begin
    if IsWordByte(Text[P]) then
    begin
      Q := P;
      while (Q <= Length(Text)) and IsWordByte(Text[Q]) do
        Inc(Q);
      // the fragment itself is not a candidate
      if not ((From + P - 1 <= FragStart) and (From + Q - 1 >= FragStart + Length(Fragment)) and (From + P - 1 = FragStart)) then
      begin
        W := Copy(Text, P, Q - P);
        if Matches(W) then
          AddItem(W);
      end;
      P := Q;
    end
    else
      Inc(P);
  end;
  SetLength(Items, Count);
  Result := Count > 0;
end;

end.
