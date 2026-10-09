{ TveSearch: find and replace in the text of a buffer.

  MIT.

  A pattern is a plain text or a regular expression (TveRegex). A pattern that cannot match across a line end is searched line by line (fast, and the same
  for a 2-million line file); a pattern that can (a "\n" in the text, \s, [^...], \D, \W in a regular expression) is searched in the whole text of the buffer, which is
  taken once for a version of the buffer. Positions are byte offsets in the buffer.

  Forward: the first match that starts at or after From. Backward: the last match that ends at or before From. The scope can be restricted to a range (the selected
  text): a match must lie inside it. ReplaceAll collects the matches first and edits from the last to the first, in one undo group, so it is as fast as the search. }
unit TveSearch;

{$I tvdefs.inc}

interface

uses
  TveBuf, TveDoc, TveRegex;

type
  TTveSearchOptions = record
    Pattern: AnsiString;
    CaseSensitive: Boolean;
    WholeWord: Boolean;
    UseRegex: Boolean;
    Hex: Boolean;                   // the pattern is bytes in hexadecimal ("DE AD be ef"), searched as they are
    AllCodePages: Boolean;          // a plain pattern is searched in every single-byte code page as well as in UTF-8
    Backward: Boolean;
    ScopeFrom, ScopeTo: Int64;      { the range that a match must lie in; ScopeTo < 0: the whole text }
  end;

  TTveMatch = record
    Start, Stop: Int64;             { the match is Start .. Stop - 1 }
    Caps: TCaps;                    { for a regular expression: the groups, as indexes in Subject }
    Subject: AnsiString;            { the text that the indexes of Caps are in }
  end;

  TTveFindStatus = (fsFound, fsNotFound, fsBadPattern, fsAborted);

  TTveSearcher = class
  private
    FBuf: TTveBuffer;
    FOpt: TTveSearchOptions;
    FRegex: TTveRegex;
    FError: AnsiString;
    FCross: Boolean;
    FText: AnsiString;
    FTextVersion: LongWord;
    FTextValid: Boolean;
    function Prepare(const Opt: TTveSearchOptions): Boolean;
    function WordOk(const S: AnsiString; A, B: Integer): Boolean;
    function MatchInSubject(const S: AnsiString; From: Integer; out MS, ME: Integer; out Caps: TCaps; out Aborted: Boolean): Boolean;
    function InScope(A, B: Int64): Boolean;
    function FindForward(From: Int64; out M: TTveMatch; out Aborted: Boolean): Boolean;
    function FindBackward(From: Int64; out M: TTveMatch; out Aborted: Boolean): Boolean;
    function WholeText: AnsiString;
    function FindOne(const Opt: TTveSearchOptions; From: Int64; out M: TTveMatch): TTveFindStatus;
  public
    constructor Create(ABuf: TTveBuffer);
    destructor Destroy; override;
    property Error: AnsiString read FError;
    function Find(const Opt: TTveSearchOptions; From: Int64; out M: TTveMatch): TTveFindStatus;
    { The replacement text for a match (the groups of a regular expression are expanded) }
    function ReplacementFor(const M: TTveMatch; const Repl: AnsiString): AnsiString;
    { Replaces all the matches in the scope in one undo group; the count, or -1 on a bad pattern }
    function ReplaceAll(Doc: TTveDoc; const Opt: TTveSearchOptions; const Repl: AnsiString): Integer;
    function Count(const Opt: TTveSearchOptions): Integer;
  end;

function TveDefaultSearch: TTveSearchOptions;

implementation

uses
  SysUtils, TvCharset, TvUtf8, TveLayout;

function HexToBytes(const S: AnsiString; out Bytes: AnsiString): Boolean;
var
  I, Hi: Integer;
  V: Integer;
begin
  Bytes := '';
  Hi := -1;
  Result := False;
  for I := 1 to Length(S) do
  begin
    case S[I] of
      '0'..'9': V := Ord(S[I]) - 48;
      'a'..'f': V := Ord(S[I]) - 87;
      'A'..'F': V := Ord(S[I]) - 55;
      ' ', #9, ',': Continue;
    else
      Exit;
    end;
    if Hi < 0 then
      Hi := V
    else
    begin
      Bytes := Bytes + Chr(Hi * 16 + V);
      Hi := -1;
    end;
  end;
  Result := Hi < 0;
end;

function TveDefaultSearch: TTveSearchOptions;
begin
  Result.Pattern := '';
  Result.CaseSensitive := False;
  Result.WholeWord := False;
  Result.UseRegex := False;
  Result.Hex := False;
  Result.AllCodePages := False;
  Result.Backward := False;
  Result.ScopeFrom := 0;
  Result.ScopeTo := -1;
end;

constructor TTveSearcher.Create(ABuf: TTveBuffer);
begin
  inherited Create;
  FBuf := ABuf;
end;

destructor TTveSearcher.Destroy;
begin
  FRegex.Free;
  inherited Destroy;
end;

function PatternCrossesLines(const P: AnsiString; UseRegex: Boolean): Boolean;
begin
  if not UseRegex then
    Exit(Pos(#10, P) > 0);
  Result := (Pos('\n', P) > 0) or (Pos('\s', P) > 0) or (Pos('\S', P) > 0) or (Pos('\D', P) > 0) or (Pos('\W', P) > 0) or (Pos('[^', P) > 0) or
            (Pos(#10, P) > 0) or (Pos('[:space:]', P) > 0) or (Pos('\r', P) > 0) or (Pos('\x0a', P) > 0) or (Pos('\x{a}', P) > 0) or (Pos('\x{A}', P) > 0) or (Pos('\x0A', P) > 0);
end;

function TTveSearcher.Prepare(const Opt: TTveSearchOptions): Boolean;
var
  Pat: AnsiString;
begin
  FOpt := Opt;
  FError := '';
  if Opt.Hex then
  begin
    if not HexToBytes(Opt.Pattern, Pat) or (Pat = '') then
    begin
      FError := 'bad hexadecimal pattern';
      Exit(False);
    end;
    FOpt.Pattern := Pat;
    FOpt.UseRegex := False;
    FOpt.CaseSensitive := True;
    FOpt.WholeWord := False;
  end;
  FCross := PatternCrossesLines(FOpt.Pattern, FOpt.UseRegex);
  FreeAndNil(FRegex);
  if FOpt.Pattern = '' then
  begin
    FError := 'empty pattern';
    Exit(False);
  end;
  if FOpt.UseRegex then
    Pat := FOpt.Pattern
  else
    Pat := RegexEscape(FOpt.Pattern);
  FRegex := TTveRegex.Create(Pat, not FOpt.CaseSensitive);
  if FRegex.Error <> '' then
  begin
    FError := FRegex.Error;
    Exit(False);
  end;
  Result := True;
end;

function TTveSearcher.WholeText: AnsiString;
begin
  if (not FTextValid) or (FTextVersion <> FBuf.Version) then
  begin
    FText := FBuf.AsString;
    FTextVersion := FBuf.Version;
    FTextValid := True;
  end;
  Result := FText;
end;

{ The characters before A and after B (indexes in S: the match is S[A .. B - 1]) are not word characters }
function TTveSearcher.WordOk(const S: AnsiString; A, B: Integer): Boolean;
var
  CP: LongWord;
  K: Integer;
begin
  Result := True;
  if not FOpt.WholeWord then
    Exit;
  if A > 1 then
  begin
    K := 1;
    while (K < 4) and (A - K > 1) and ((Byte(S[A - K]) and $C0) = $80) do
      Inc(K);
    CP := Byte(S[A - 1]);
    if (Byte(S[A - 1]) >= $80) and Utf8Decode(@S[A - K], K, CP, K) then
      ;
    if IsWordCp(CP) then
      Exit(False);
  end;
  if B <= Length(S) then
  begin
    CP := Byte(S[B]);
    if (CP >= $80) and Utf8Decode(@S[B], Length(S) - B + 1, CP, K) then
      ;
    if IsWordCp(CP) then
      Exit(False);
  end;
end;

{ The first match in S at or after index From that passes the whole-word test }
function TTveSearcher.MatchInSubject(const S: AnsiString; From: Integer; out MS, ME: Integer; out Caps: TCaps; out Aborted: Boolean): Boolean;
var
  I: Integer;
begin
  Result := False;
  Aborted := False;
  I := From;
  while I <= Length(S) + 1 do
  begin
    if not FRegex.Exec(S, I, Caps) then
    begin
      Aborted := FRegex.Aborted;
      Exit;
    end;
    MS := Caps[0];
    ME := Caps[1];
    if WordOk(S, MS, ME) then
      Exit(True);
    I := MS + 1;
    if I <= Length(S) then
      while (I <= Length(S)) and ((Byte(S[I]) and $C0) = $80) do
        Inc(I);
  end;
end;

function TTveSearcher.InScope(A, B: Int64): Boolean;
begin
  if FOpt.ScopeTo < 0 then
    Exit(True);
  Result := (A >= FOpt.ScopeFrom) and (B <= FOpt.ScopeTo);
end;

function TTveSearcher.FindForward(From: Int64; out M: TTveMatch; out Aborted: Boolean): Boolean;
var
  L, LastLine: Int64;
  LS, LE: Int64;
  S: AnsiString;
  MS, ME, Idx: Integer;
  Caps: TCaps;
begin
  Result := False;
  Aborted := False;
  if FOpt.ScopeTo >= 0 then
  begin
    if From < FOpt.ScopeFrom then From := FOpt.ScopeFrom;
    if From > FOpt.ScopeTo then Exit;
  end;
  if FCross then
  begin
    S := WholeText;
    Idx := Integer(From) + 1;
    while MatchInSubject(S, Idx, MS, ME, Caps, Aborted) do
    begin
      if (FOpt.ScopeTo >= 0) and (ME - 1 > FOpt.ScopeTo) then
        Exit;
      if InScope(MS - 1, ME - 1) then
      begin
        M.Start := MS - 1;
        M.Stop := ME - 1;
        M.Caps := Caps;
        M.Subject := S;
        Exit(True);
      end;
      Idx := MS + 1;
    end;
    Exit;
  end;
  L := FBuf.LineOfOffset(From);
  LastLine := FBuf.LineCount - 1;
  if FOpt.ScopeTo >= 0 then
    LastLine := FBuf.LineOfOffset(FOpt.ScopeTo);
  while L <= LastLine do
  begin
    LS := FBuf.LineStart(L);
    LE := FBuf.LineEnd(L);
    S := FBuf.Copy(LS, LE - LS);
    Idx := 1;
    if From > LS then
      Idx := Integer(From - LS) + 1;
    if Idx <= Length(S) + 1 then
      while MatchInSubject(S, Idx, MS, ME, Caps, Aborted) do
      begin
        if InScope(LS + MS - 1, LS + ME - 1) then
        begin
          M.Start := LS + MS - 1;
          M.Stop := LS + ME - 1;
          M.Caps := Caps;
          M.Subject := S;
          Exit(True);
        end;
        if (FOpt.ScopeTo >= 0) and (LS + ME - 1 > FOpt.ScopeTo) then
          Exit;
        Idx := MS + 1;
      end;
    if Aborted then
      Exit;
    Inc(L);
  end;
end;

function TTveSearcher.FindBackward(From: Int64; out M: TTveMatch; out Aborted: Boolean): Boolean;
var
  L: Int64;
  LS, LE: Int64;
  S: AnsiString;
  MS, ME, Idx: Integer;
  Caps: TCaps;
  Have: Boolean;
  Best: TTveMatch;
  Base: Int64;
  Limit: Int64;
  FirstLine: Int64;
begin
  Result := False;
  Aborted := False;
  if FOpt.ScopeTo >= 0 then
  begin
    if From > FOpt.ScopeTo then From := FOpt.ScopeTo;
    if From < FOpt.ScopeFrom then Exit;
  end;
  if FCross then
  begin
    S := WholeText;
    Have := False;
    Idx := 1;
    if FOpt.ScopeTo >= 0 then
      Idx := Integer(FOpt.ScopeFrom) + 1;
    while MatchInSubject(S, Idx, MS, ME, Caps, Aborted) do
    begin
      if ME - 1 > From then
        Break;
      if InScope(MS - 1, ME - 1) then
      begin
        Best.Start := MS - 1; Best.Stop := ME - 1; Best.Caps := Caps; Best.Subject := S;
        Have := True;
      end;
      Idx := ME;
      if ME = MS then
        Inc(Idx);
    end;
    if Have then
    begin
      M := Best;
      Exit(True);
    end;
    Exit;
  end;
  L := FBuf.LineOfOffset(From);
  FirstLine := 0;
  if FOpt.ScopeTo >= 0 then
    FirstLine := FBuf.LineOfOffset(FOpt.ScopeFrom);
  while L >= FirstLine do
  begin
    LS := FBuf.LineStart(L);
    LE := FBuf.LineEnd(L);
    S := FBuf.Copy(LS, LE - LS);
    Base := LS;
    Limit := From - LS;                     { a match must end at or before this offset in the line }
    Have := False;
    Idx := 1;
    while Idx <= Length(S) + 1 do
    begin
      if not MatchInSubject(S, Idx, MS, ME, Caps, Aborted) then
        Break;
      if ME - 1 > Limit then
        Break;
      if InScope(Base + MS - 1, Base + ME - 1) then
      begin
        Best.Start := Base + MS - 1; Best.Stop := Base + ME - 1; Best.Caps := Caps; Best.Subject := S;
        Have := True;
      end;
      Idx := ME;
      if ME = MS then
        Inc(Idx);
    end;
    if Have then
    begin
      M := Best;
      Exit(True);
    end;
    if Aborted then
      Exit;
    Dec(L);
  end;
end;

function TTveSearcher.FindOne(const Opt: TTveSearchOptions; From: Int64; out M: TTveMatch): TTveFindStatus;
var
  Aborted, Ok: Boolean;
begin
  M.Start := 0; M.Stop := 0; M.Subject := '';
  if not Prepare(Opt) then
    Exit(fsBadPattern);
  if Opt.Backward then
    Ok := FindBackward(From, M, Aborted)
  else
    Ok := FindForward(From, M, Aborted);
  if Ok then
    Result := fsFound
  else if Aborted then
    Result := fsAborted
  else
    Result := fsNotFound;
end;

function TTveSearcher.Find(const Opt: TTveSearchOptions; From: Int64; out M: TTveMatch): TTveFindStatus;
var
  Variants: array of AnsiString;
  I, J: Integer;
  O: TTveSearchOptions;
  M2: TTveMatch;
  R: TTveFindStatus;
  Lost: Integer;
  Conv: AnsiString;
  Dup: Boolean;
begin
  Result := FindOne(Opt, From, M);
  if not Opt.AllCodePages or Opt.UseRegex or Opt.Hex or (Result = fsBadPattern) or IsPlainAscii(Opt.Pattern) then
    Exit;
  // the same text in the other code pages
  SetLength(Variants, 0);
  for I := 0 to CharsetListCount - 1 do
  begin
    Conv := CharsetFromUtf8(CharsetListId(I), Opt.Pattern, Lost);
    if (Lost > 0) or (Conv = '') or (Conv = Opt.Pattern) then
      Continue;
    Dup := False;
    for J := 0 to High(Variants) do
      if Variants[J] = Conv then
        Dup := True;
    if not Dup then
    begin
      SetLength(Variants, Length(Variants) + 1);
      Variants[High(Variants)] := Conv;
    end;
  end;
  for I := 0 to High(Variants) do
  begin
    O := Opt;
    O.Pattern := Variants[I];
    O.CaseSensitive := True;
    R := FindOne(O, From, M2);
    if R <> fsFound then
      Continue;
    if (Result <> fsFound) or (Opt.Backward and (M2.Start > M.Start)) or (not Opt.Backward and (M2.Start < M.Start)) then
    begin
      M := M2;
      Result := fsFound;
    end;
  end;
end;

function TTveSearcher.ReplacementFor(const M: TTveMatch; const Repl: AnsiString): AnsiString;
begin
  if (FRegex <> nil) and FOpt.UseRegex then
    Result := FRegex.Expand(Repl, M.Subject, M.Caps)
  else
    Result := Repl;
end;

function TTveSearcher.Count(const Opt: TTveSearchOptions): Integer;
var
  M: TTveMatch;
  O: TTveSearchOptions;
  P: Int64;
begin
  Result := 0;
  O := Opt;
  O.Backward := False;
  P := 0;
  if O.ScopeTo >= 0 then
    P := O.ScopeFrom;
  while Find(O, P, M) = fsFound do
  begin
    Inc(Result);
    P := M.Stop;
    if M.Stop = M.Start then
      Inc(P);
  end;
end;

function TTveSearcher.ReplaceAll(Doc: TTveDoc; const Opt: TTveSearchOptions; const Repl: AnsiString): Integer;
var
  O: TTveSearchOptions;
  M: TTveMatch;
  P: Int64;
  Starts, Stops: array of Int64;
  Texts: array of AnsiString;
  N, I: Integer;
begin
  O := Opt;
  O.Backward := False;
  Result := 0;
  Starts := nil;
  Stops := nil;
  Texts := nil;
  if Doc.ReadOnly then
    Exit;
  P := 0;
  if O.ScopeTo >= 0 then
    P := O.ScopeFrom;
  N := 0;
  while True do
  begin
    case Find(O, P, M) of
      fsBadPattern: Exit(-1);
      fsFound: ;
    else
      Break;
    end;
    if N = Length(Starts) then
    begin
      SetLength(Starts, N * 2 + 16);
      SetLength(Stops, N * 2 + 16);
      SetLength(Texts, N * 2 + 16);
    end;
    Starts[N] := M.Start;
    Stops[N] := M.Stop;
    Texts[N] := ReplacementFor(M, Repl);
    Inc(N);
    P := M.Stop;
    if M.Stop = M.Start then
      Inc(P);
  end;
  if N = 0 then
    Exit;
  Doc.BeginGroup;
  for I := N - 1 downto 0 do
    Doc.Replace(Starts[I], Stops[I] - Starts[I], Texts[I]);
  Doc.EndGroup;
  Result := N;
end;

end.
