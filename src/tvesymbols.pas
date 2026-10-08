{ TveSymbols: the symbols of a document (types, routines, headings) for a list to jump from.

  MIT.

  The rules are in the grammar of the language: the lines "symbol LEVEL /REGEX/" (see TveHl). Every line of the text is tried against the rules in order; the first
  one that matches makes an entry, with the group 1 of the expression (or the whole match) as its title. A match that starts inside a comment or a string
  (by the highlighter) is not an entry, so a commented-out routine is not listed. Entries come in the order of the text. With "outline indent",
  "outline braces" or "outline regions" in the grammar the level of an entry is the number of entries that hold it, plus one; "outline from" skips the deeper
  rules before a line; "outline body" holds the nested routines of Pascal in the routine up to the end of its body; "outline signature" joins the parameters of
  a routine over its lines. }
unit TveSymbols;

{$I tvdefs.inc}
{$H+}

interface

uses
  TveDoc, TveHl;

type
  TTveOutlineItem = record
    Line: Int64;          { 0-based }
    Level: Integer;       { 1 is the top level }
    Title: AnsiString;
    Kind: Integer;        { the LEVEL of the rule that found it (the level of nesting can differ) }
    Signature: AnsiString;  { with "outline signature": the title with the parameters and the return type, the lines joined; else the title }
  end;
  TTveOutline = array of TTveOutlineItem;
  TTveFoldRegion = record
    First, Last: Int64;   { 0-based lines; a fold of it hides the lines after First up to Last }
  end;
  TTveFoldRegions = array of TTveFoldRegion;

{ The outline of Doc by the rules of Lang (nil, or no rules: an empty outline). }
function TveOutline(Doc: TTveDoc; Lang: TTveLanguage): TTveOutline;
{ The entry that holds Line: the last one that starts at or before it (-1 if none). }
function TveOutlineAt(const Items: TTveOutline; Line: Int64): Integer;
{ The text of an entry for a list: its signature indented by its level. }
function TveOutlineLabel(const Item: TTveOutlineItem): AnsiString;
{ The regions of Doc that can be folded by the "fold" rules of Lang (see TveHl), sorted by the first line, the outer one first. A region of braces starts at the
  line above when the brace is alone on its line (under a heading); braces and words in comments and strings do not count. }
function TveFoldRegions(Doc: TTveDoc; Lang: TTveLanguage): TTveFoldRegions;
type
  TTveByteArray = array of Byte;
{ The names that the outline of Doc defines, for TTveHighlighter.SetNames: the entries of the rules of level 1 as types (hcType), the deeper ones as routines
  (hcFunction); the last part of a qualified title (TFoo.Bar, P::run); a title that is no identifier is left out. Empty unless the grammar says "semantic". }
procedure TveSemanticNames(Doc: TTveDoc; Lang: TTveLanguage; out Names: TWordArr; out Classes: TTveByteArray);

implementation

uses
  SysUtils, TveRegex;

{ The indentation of a line in cells (a tab to the next multiple of 8); -1 for a blank line. }
function IndentOf(const Text: AnsiString): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(Text) do
    case Text[I] of
      ' ': Inc(Result);
      #9: Result := (Result div 8 + 1) * 8;
      #13: ;
    else
      Exit;
    end;
  Result := -1;
end;

function Quoted(const Cls: TByteClasses; Idx: Integer): Boolean;
begin
  Result := (Idx - 1 <= High(Cls)) and (Cls[Idx - 1] in [hcComment, hcString]);
end;

type
  TPairEvent = record
    Pos, Pair: Integer;
    Open: Boolean;
    OpenLine: Int64;      { a close: the line of the word that it closes (-1: none) }
  end;

  { The words of the "fold /OPEN/ /CLOSE/" rules line by line, outside comments and strings, with a stack per pair. }
  TBlockScan = class
    Lang: TTveLanguage;
    Hl: TTveHighlighter;
    Line: Int64;
    Text: AnsiString;
    Cls: TByteClasses;
    HaveCls: Boolean;
    Events: array of TPairEvent;
    Count: Integer;
    Stacks: array of array of Int64;
    Outer: array of array of Boolean;     { the open word was one that "fold skip" names as the outer one }
    Depths: array of Integer;
    constructor Create(ALang: TTveLanguage; AHl: TTveHighlighter);
    procedure StartLine(L: Int64; const AText: AnsiString);
    procedure NeedCls;
    procedure Scan;                       { fills Events for the line, in the order of the text, and keeps the stacks }
    function Depth: Integer;              { the open words of all pairs }
  end;

constructor TBlockScan.Create(ALang: TTveLanguage; AHl: TTveHighlighter);
begin
  inherited Create;
  Lang := ALang;
  Hl := AHl;
  SetLength(Stacks, Lang.FoldPairCount);
  SetLength(Outer, Lang.FoldPairCount);
  SetLength(Depths, Lang.FoldPairCount);
end;

procedure TBlockScan.StartLine(L: Int64; const AText: AnsiString);
begin
  Line := L;
  Text := AText;
  HaveCls := False;
  Count := 0;
end;

procedure TBlockScan.NeedCls;
begin
  if not HaveCls then
    Hl.ClassifyLine(Line, Cls);
  HaveCls := True;
end;

function TBlockScan.Depth: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Depths) do
    Inc(Result, Depths[I]);
end;

procedure TBlockScan.Scan;
var
  I, J, K, NO, NC: Integer;
  OpenAt, OpenEnd, CloseAt, CloseEnd: array[0..63] of Integer;
  Caps: TCaps;

  procedure Matches(Re: TTveRegex; var At, AtEnd: array of Integer; out N: Integer);
  var
    Q: Integer;
  begin
    N := 0;
    Q := 1;
    while (Q <= Length(Text)) and Re.Exec(Text, Q, Caps) do
    begin
      NeedCls;
      if not Quoted(Cls, Caps[0]) and (N <= High(At)) then
      begin
        At[N] := Caps[0];
        AtEnd[N] := Caps[1];
        Inc(N);
      end;
      if Caps[1] > Caps[0] then
        Q := Caps[1]
      else
        Q := Caps[0] + 1;
    end;
  end;

  procedure Emit(P, Pair: Integer; IsOpen: Boolean; OL: Int64);
  var
    X: Integer;
  begin
    if Count = Length(Events) then
      SetLength(Events, Count * 2 + 8);
    X := Count;
    { by the position in the line }
    while (X > 0) and (Events[X - 1].Pos > P) do
    begin
      Events[X] := Events[X - 1];
      Dec(X);
    end;
    Events[X].Pos := P;
    Events[X].Pair := Pair;
    Events[X].Open := IsOpen;
    Events[X].OpenLine := OL;
    Inc(Count);
  end;

  function IsSkipped(Pair, P: Integer): Boolean;
  begin
    Result := (Lang.FoldSkip <> nil) and (Depths[Pair] > 0) and Outer[Pair][Depths[Pair] - 1] and Lang.FoldSkip.ExecAt(Text, P, Caps);
  end;

begin
  Count := 0;
  for I := 0 to Lang.FoldPairCount - 1 do
  begin
    Matches(Lang.FoldOpen(I), OpenAt, OpenEnd, NO);
    Matches(Lang.FoldClose(I), CloseAt, CloseEnd, NC);
    J := 0;
    K := 0;
    while (J < NO) or (K < NC) do
      if (J < NO) and ((K >= NC) or (OpenAt[J] < CloseAt[K])) then
      begin
        if not IsSkipped(I, OpenAt[J]) then
        begin
          if Depths[I] = Length(Stacks[I]) then
          begin
            SetLength(Stacks[I], Depths[I] * 2 + 16);
            SetLength(Outer[I], Depths[I] * 2 + 16);
          end;
          Stacks[I][Depths[I]] := Line;
          Outer[I][Depths[I]] := (Lang.FoldSkipIn <> nil) and Lang.FoldSkipIn.ExecAt(Text, OpenAt[J], Caps);
          Inc(Depths[I]);
          Emit(OpenAt[J], I, True, -1);
        end;
        Inc(J);
      end
      else
      begin
        if Depths[I] > 0 then
        begin
          Dec(Depths[I]);
          Emit(CloseAt[K], I, False, Stacks[I][Depths[I]]);
        end;
        Inc(K);
      end;
  end;
end;

function FoldRegionsOf(Doc: TTveDoc; Lang: TTveLanguage; WithOutline: Boolean): TTveFoldRegions; forward;

{ The text of a signature: blanks made one, none inside the brackets next to them. }
function TidySignature(const S: AnsiString): AnsiString;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if C in [#9, #10, #13] then
      C := ' ';
    if (C = ' ') and ((Result = '') or (Result[Length(Result)] in [' ', '(', '['])) then
      Continue;
    if (C in [')', ']', ',']) and (Result <> '') and (Result[Length(Result)] = ' ') then
      SetLength(Result, Length(Result) - 1);
    Result := Result + C;
  end;
  Result := TrimRight(Result);
end;

function TveOutline(Doc: TTveDoc; Lang: TTveLanguage): TTveOutline;
var
  Hl: TTveHighlighter;
  L, N, FromLine: Int64;
  LI, I, J, S, E, Cnt, Nest, Depth, Ind: Integer;
  Text, Title: AnsiString;
  Caps: TCaps;
  Cls: TByteClasses;
  HaveCls: Boolean;
  Re: TTveRegex;
  Open: array of Integer;           { nesting: the indentation or the brace depth of the entries that hold the next line }
  OpenCount: Integer;
  TitleEnd: array of Integer;       { the byte after the name of an entry in its line }
  Ext: array of Int64;              { outline regions: the last line that an entry holds, -1: by the level of its rule }
  Drop: array of Boolean;
  Items: TTveOutline;               { the entries, for the nested functions }

  procedure NeedCls;
  begin
    if not HaveCls then
      Hl.ClassifyLine(L, Cls);
    HaveCls := True;
  end;

  { the first non-blank byte of the line is in a comment or a string }
  function StartsQuoted: Boolean;
  var
    K: Integer;
  begin
    K := 1;
    while (K <= Length(Text)) and (Text[K] in [' ', #9]) do
      Inc(K);
    NeedCls;
    Result := (K - 1 <= High(Cls)) and (Cls[K - 1] in [hcComment, hcString]);
  end;

  procedure CloseFrom(Level: Integer);
  begin
    while (OpenCount > 0) and (Open[OpenCount - 1] >= Level) do
      Dec(OpenCount);
  end;

  { the title, the brackets that follow it (over lines, without comments) and the tail of the grammar; LastLine: the line where the brackets end }
  function SignatureOf(K: Integer; out LastLine: Int64): AnsiString;
  var
    LL: Int64;
    P, P0, D, Lines: Integer;
    T: AnsiString;
    C: TByteClasses;
    Paren: Boolean;
  begin
    Paren := False;
    Result := Items[K].Title;
    LL := Items[K].Line;
    LastLine := LL;
    T := Doc.Buffer.LineText(LL);
    Hl.ClassifyLine(LL, C);
    P := TitleEnd[K];
    Lines := 0;
    while True do
    begin
      P0 := P;
      while (P <= Length(T)) and (T[P] in [' ', #9]) do
        Inc(P);
      { type parameters [T any] only before the parameters }
      if (P > Length(T)) or not ((T[P] = '(') or ((T[P] = '[') and not Paren)) then
        Break;
      if P > P0 then
        Result := Result + ' ';
      Paren := Paren or (T[P] = '(');
      D := 0;
      repeat
        if P > Length(T) then
        begin
          Inc(LL);
          Inc(Lines);
          if (LL >= N) or (Lines > 40) then
            Exit(TidySignature(Result));
          LastLine := LL;
          T := Doc.Buffer.LineText(LL);
          Hl.ClassifyLine(LL, C);
          P := 1;
          Result := Result + ' ';
          Continue;
        end;
        if (P - 1 <= High(C)) and (C[P - 1] = hcComment) then
        begin
          Inc(P);
          Continue;
        end;
        if (P - 1 > High(C)) or (C[P - 1] <> hcString) then
          if T[P] in ['(', '['] then
            Inc(D)
          else if T[P] in [')', ']'] then
            Dec(D);
        Result := Result + T[P];
        Inc(P);
      until D <= 0;
    end;
    if (Lang.SignatureTail <> nil) and (P0 <= Length(T)) and Lang.SignatureTail.ExecAt(T, P0, Caps) and (Caps[1] > Caps[0]) then
      Result := Result + Copy(T, Caps[0], Caps[1] - Caps[0]);
    Result := TidySignature(Result);
  end;

  { "outline body": the end of the body of each entry of a routine; one inside a region that is no body (a class) is dropped }
  procedure Bodies;
  var
    Bs: TBlockScan;
    Wait: array of Integer;           { the entries whose body has not ended, the innermost last }
    Started: array of Boolean;
    BodyDepth: array of Integer;      { the depth of the open word of the body }
    WC, Next, K, Ev, X: Integer;
    LL: Int64;
    D: Integer;
  begin
    Bs := TBlockScan.Create(Lang, Hl);
    try
      SetLength(Wait, Cnt);
      SetLength(Started, Cnt);
      SetLength(BodyDepth, Cnt);
      WC := 0;
      Next := 0;
      for K := 0 to Cnt - 1 do
        Ext[K] := -1;
      for X := 0 to Integer(N) - 1 do
      begin
        LL := X;
        while (Next < Cnt) and (Result[Next].Line < LL) do
          Inc(Next);
        Bs.StartLine(LL, Doc.Buffer.LineText(LL));
        if (Next < Cnt) and (Result[Next].Line = LL) and (Result[Next].Kind >= Lang.OutlineBodyLevel) then
        begin
          if Bs.Depth > 0 then
            Drop[Next] := True
          else if Lang.OutlineNoBody.Exec(Bs.Text, 1, Caps) then
            Ext[Next] := LL
          else
          begin
            Wait[WC] := Next;
            Started[Next] := False;
            Inc(WC);
          end;
        end;
        D := Bs.Depth;
        Bs.Scan;
        for Ev := 0 to Bs.Count - 1 do
          if Bs.Events[Ev].Open then
          begin
            if (WC > 0) and not Started[Wait[WC - 1]] and (D = 0) and Lang.OutlineBody.ExecAt(Bs.Text, Bs.Events[Ev].Pos, Caps) then
            begin
              Started[Wait[WC - 1]] := True;
              BodyDepth[Wait[WC - 1]] := D;
            end;
            Inc(D);
          end
          else
          begin
            Dec(D);
            if (WC > 0) and Started[Wait[WC - 1]] and (D = BodyDepth[Wait[WC - 1]]) then
            begin
              Ext[Wait[WC - 1]] := LL;
              Dec(WC);
            end;
          end;
      end;
      { a body that does not end goes to the end of the text; an entry still waiting for one holds nothing }
      for K := 0 to WC - 1 do
        if Started[Wait[K]] then
          Ext[Wait[K]] := N - 1
        else
          Ext[Wait[K]] := Result[Wait[K]].Line;
    finally
      Bs.Free;
    end;
  end;

  { "outline regions": the level of an entry is 1 + the number of the entries that hold it }
  procedure RegionLevels;
  var
    Regs: TTveFoldRegions;
    K, R, SC, Kept: Integer;
    Stack: array of Integer;
    Head: Int64;

    function Holds(J, K2: Integer): Boolean;
    begin
      if Ext[J] >= 0 then
        Holds := Items[K2].Line <= Ext[J]
      else
        Holds := Items[J].Kind < Items[K2].Kind;
    end;

  begin
    for K := 0 to Cnt - 1 do
    begin
      Ext[K] := -1;
      Drop[K] := False;
    end;
    if Lang.OutlineBody <> nil then
      Bodies;
    Regs := FoldRegionsOf(Doc, Lang, False);
    R := 0;
    Items := Result;
    for K := 0 to Cnt - 1 do
    begin
      while (R <= High(Regs)) and (Regs[R].First < Result[K].Line) do
        Inc(R);
      { the outer region that starts on the line of the entry, or on a line of its parameters (the brace after them) }
      SignatureOf(K, Head);
      if (Ext[K] < 0) and (R <= High(Regs)) and (Regs[R].First <= Head) then
        Ext[K] := Regs[R].Last;
    end;
    SetLength(Stack, Cnt);
    SC := 0;
    Kept := 0;
    Items := Result;
    for K := 0 to Cnt - 1 do
    begin
      if Drop[K] then
        Continue;
      R := 0;
      while (R < SC) and Holds(Stack[R], K) do
        Inc(R);
      SC := R;
      Result[K].Level := SC + 1;
      Stack[SC] := Kept;
      Inc(SC);
      Result[Kept] := Result[K];
      Ext[Kept] := Ext[K];
      TitleEnd[Kept] := TitleEnd[K];
      Inc(Kept);
    end;
    Cnt := Kept;
    SetLength(Result, Cnt);
  end;

begin
  Result := nil;
  if (Doc = nil) or (Lang = nil) or (Lang.SymbolCount = 0) then
    Exit;
  Hl := TTveHighlighter.Create(Doc, Lang);
  try
    N := Doc.Buffer.LineCount;
    Nest := Lang.OutlineNest;
    FromLine := -1;
    if Lang.OutlineFrom <> nil then
      for LI := 0 to Integer(N) - 1 do
        if Lang.OutlineFrom.Exec(Doc.Buffer.LineText(LI), 1, Caps) then
        begin
          FromLine := LI;
          Break;
        end;
    Open := nil;
    OpenCount := 0;
    Depth := 0;
    Ind := 0;
    Cnt := 0;
    for LI := 0 to Integer(N) - 1 do        { a LongInt counter: a 32-bit target has no Int64 loops }
    begin
      L := LI;
      Text := Doc.Buffer.LineText(L);
      HaveCls := False;
      if Nest = 1 then
      begin
        Ind := IndentOf(Text);
        if (Ind >= 0) and (OpenCount > 0) and (Open[OpenCount - 1] >= Ind) and not StartsQuoted then
          CloseFrom(Ind);
      end
      else if Nest = 2 then
      begin
        Ind := Depth;
        J := 1;
        while (J <= Length(Text)) and (Text[J] in [' ', #9]) do
          Inc(J);
        { a brace that opens the body of the entry above on a line of its own keeps it open }
        if (J <= Length(Text)) and (Text[J] <> '{') then
          CloseFrom(Ind);
        if (Pos('{', Text) > 0) or (Pos('}', Text) > 0) then
        begin
          NeedCls;
          for J := 1 to Length(Text) do
            if (J - 1 > High(Cls)) or not (Cls[J - 1] in [hcComment, hcString]) then
              if Text[J] = '{' then
                Inc(Depth)
              else if (Text[J] = '}') and (Depth > 0) then
                Dec(Depth);
        end;
      end;
      if Text = '' then
        Continue;
      for I := 0 to Lang.SymbolCount - 1 do
      begin
        if (L <= FromLine) and (Lang.SymbolLevel(I) >= Lang.OutlineFromLevel) then
          Continue;
        Re := Lang.SymbolRegex(I);
        if not Re.Exec(Text, 1, Caps) then
          Continue;
        if (Re.Groups >= 1) and (Caps[2] > 0) then
        begin
          S := Caps[2];
          E := Caps[3];
        end
        else
        begin
          S := Caps[0];
          E := Caps[1];
        end;
        Title := Trim(Copy(Text, S, E - S));
        if Title = '' then
          Continue;
        NeedCls;
        { the match starts in a comment or a string: no entry from the line (a title in quotes, as name="x", is fine) }
        J := Caps[0];
        while (J < S) and (Text[J] in [' ', #9]) do
          Inc(J);
        if (J - 1 <= High(Cls)) and (Cls[J - 1] in [hcComment, hcString]) then
          Break;
        if Cnt = Length(Result) then
          SetLength(Result, Cnt * 2 + 16);
        Result[Cnt].Line := L;
        Result[Cnt].Title := Title;
        Result[Cnt].Signature := '';
        if Cnt >= Length(TitleEnd) then
          SetLength(TitleEnd, Length(Result));
        TitleEnd[Cnt] := E;
        Result[Cnt].Kind := Lang.SymbolLevel(I);
        if Nest in [0, 3] then
          Result[Cnt].Level := Lang.SymbolLevel(I)
        else
        begin
          CloseFrom(Ind);
          Result[Cnt].Level := OpenCount + 1;
          if OpenCount = Length(Open) then
            SetLength(Open, OpenCount * 2 + 8);
          Open[OpenCount] := Ind;
          Inc(OpenCount);
        end;
        Inc(Cnt);
        Break;
      end;
    end;
    SetLength(Result, Cnt);
    if Nest = 3 then
    begin
      SetLength(Ext, Cnt);
      SetLength(Drop, Cnt);
      RegionLevels;
    end;
    Items := Result;
    if Lang.Signature then
      for I := 0 to Cnt - 1 do
        if Result[I].Kind >= 2 then
          Result[I].Signature := SignatureOf(I, L);
  finally
    Hl.Free;
  end;
end;

function TveOutlineAt(const Items: TTveOutline; Line: Int64): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(Items) do
    if Items[I].Line <= Line then
      Result := I
    else
      Break;
end;

function TveOutlineLabel(const Item: TTveOutlineItem): AnsiString;
begin
  if Item.Signature <> '' then
    Result := StringOfChar(' ', 2 * (Item.Level - 1)) + Item.Signature
  else
    Result := StringOfChar(' ', 2 * (Item.Level - 1)) + Item.Title;
end;


procedure TveSemanticNames(Doc: TTveDoc; Lang: TTveLanguage; out Names: TWordArr; out Classes: TTveByteArray);
var
  Items: TTveOutline;
  I, J, K, N: Integer;
  T: AnsiString;
  Ok: Boolean;
begin
  Names := nil;
  Classes := nil;
  if (Lang = nil) or not Lang.Semantic then
    Exit;
  Items := TveOutline(Doc, Lang);
  N := 0;
  SetLength(Names, Length(Items));
  SetLength(Classes, Length(Items));
  for I := 0 to High(Items) do
  begin
    T := Items[I].Title;
    for J := Length(T) downto 1 do
      if T[J] in ['.', ':'] then
      begin
        T := Copy(T, J + 1, MaxInt);
        Break;
      end;
    Ok := (T <> '') and Lang.IsIdent(T[1], True);
    for J := 2 to Length(T) do
      if Ok and not Lang.IsIdent(T[J], False) then
        Ok := False;
    for K := 0 to N - 1 do
      if Ok and (Names[K] = T) then
        Ok := False;
    if not Ok then
      Continue;
    Names[N] := T;
    if Items[I].Kind <= 1 then
      Classes[N] := hcType
    else
      Classes[N] := hcFunction;
    Inc(N);
  end;
  SetLength(Names, N);
  SetLength(Classes, N);
end;

function RegionBefore(const A, B: TTveFoldRegion): Boolean;
begin
  Result := (A.First < B.First) or ((A.First = B.First) and (A.Last > B.Last));
end;

{ a merge sort (the regions of a long text are many) }
procedure SortRegions(var R: TTveFoldRegions);
var
  T: TTveFoldRegions;
  W, I, A, AEnd, B, BEnd, O, N: Integer;
begin
  N := Length(R);
  SetLength(T, N);
  W := 1;
  while W < N do
  begin
    I := 0;
    while I < N do
    begin
      A := I;
      AEnd := I + W;
      if AEnd > N then AEnd := N;
      B := AEnd;
      BEnd := I + 2 * W;
      if BEnd > N then BEnd := N;
      O := I;
      while (A < AEnd) or (B < BEnd) do
      begin
        if (B >= BEnd) or ((A < AEnd) and not RegionBefore(R[B], R[A])) then
        begin
          T[O] := R[A];
          Inc(A);
        end
        else
        begin
          T[O] := R[B];
          Inc(B);
        end;
        Inc(O);
      end;
      Inc(I, 2 * W);
    end;
    for I := 0 to N - 1 do
      R[I] := T[I];
    W := W * 2;
  end;
end;

function TveFoldRegions(Doc: TTveDoc; Lang: TTveLanguage): TTveFoldRegions;
begin
  Result := FoldRegionsOf(Doc, Lang, True);
end;

function FoldRegionsOf(Doc: TTveDoc; Lang: TTveLanguage; WithOutline: Boolean): TTveFoldRegions;
var
  Hl: TTveHighlighter;
  Cnt: Integer;
  N, L: Int64;
  LI, I, J, K, P, Ind, Last: Integer;
  Text: AnsiString;
  Cls: TByteClasses;
  HaveCls: Boolean;
  Caps: TCaps;
  Braces: array of Int64;
  BraceCount: Integer;
  Bs: TBlockScan;
  IndLine: array of Int64;
  IndDepth: array of Integer;
  IndBody: array of Boolean;              { a line indented more than the entry came after it }
  IndCount: Integer;
  LastText: Int64;
  Items: TTveOutline;

  procedure Add(A, B: Int64);
  begin
    if B <= A then
      Exit;
    if Cnt = Length(Result) then
      SetLength(Result, Cnt * 2 + 16);
    Result[Cnt].First := A;
    Result[Cnt].Last := B;
    Inc(Cnt);
  end;

  procedure NeedCls;
  begin
    Bs.NeedCls;
    Cls := Bs.Cls;
  end;

  { the line where a region of braces that opens on the line L starts: the line above when the brace is alone on its line (under a heading) }
  function BraceHead: Int64;
  begin
    Result := L;
    if (L > 0) and (Trim(Text) = '{') and (Trim(Doc.Buffer.LineText(L - 1)) <> '') then
      Result := L - 1;
  end;

begin
  Result := nil;
  Cnt := 0;
  if (Doc = nil) or (Lang = nil) then
    Exit;
  N := Doc.Buffer.LineCount;
  if Lang.FoldBraces or Lang.FoldIndent or (Lang.FoldPairCount > 0) then
  begin
    Hl := TTveHighlighter.Create(Doc, Lang);
    Bs := TBlockScan.Create(Lang, Hl);
    try
      Braces := nil;
      BraceCount := 0;
      IndCount := 0;
      LastText := -1;
      for LI := 0 to Integer(N) - 1 do        { a LongInt counter: a 32-bit target has no Int64 loops }
      begin
        L := LI;
        Text := Doc.Buffer.LineText(L);
        Bs.StartLine(L, Text);
        if Lang.FoldBraces and ((Pos('{', Text) > 0) or (Pos('}', Text) > 0)) then
        begin
          NeedCls;
          for J := 1 to Length(Text) do
            if not Quoted(Cls, J) then
              if Text[J] = '{' then
              begin
                if BraceCount = Length(Braces) then
                  SetLength(Braces, BraceCount * 2 + 16);
                Braces[BraceCount] := BraceHead;
                Inc(BraceCount);
              end
              else if (Text[J] = '}') and (BraceCount > 0) then
              begin
                Dec(BraceCount);
                Add(Braces[BraceCount], L);
              end;
        end;
        if Lang.FoldPairCount > 0 then
        begin
          Bs.Scan;
          for I := 0 to Bs.Count - 1 do
            if not Bs.Events[I].Open then
              Add(Bs.Events[I].OpenLine, L);
        end;
        if Lang.FoldIndent then
        begin
          Ind := IndentOf(Text);
          if Ind >= 0 then
          begin
            P := 1;
            while (P <= Length(Text)) and (Text[P] in [' ', #9]) do
              Inc(P);
            NeedCls;
            if not Quoted(Cls, P) then            { a line that goes on a string or a comment is part of what is above it }
            begin
              while (IndCount > 0) and (IndDepth[IndCount - 1] >= Ind) do
              begin
                Dec(IndCount);
                if IndBody[IndCount] then
                  Add(IndLine[IndCount], LastText);
              end;
              if IndCount > 0 then
                IndBody[IndCount - 1] := True;
              if IndCount = Length(IndLine) then
              begin
                SetLength(IndLine, IndCount * 2 + 16);
                SetLength(IndDepth, IndCount * 2 + 16);
                SetLength(IndBody, IndCount * 2 + 16);
              end;
              IndLine[IndCount] := L;
              IndDepth[IndCount] := Ind;
              IndBody[IndCount] := False;
              Inc(IndCount);
            end;
            LastText := L;
          end;
        end;
      end;
      while IndCount > 0 do
      begin
        Dec(IndCount);
        if IndBody[IndCount] then
          Add(IndLine[IndCount], LastText);
      end;
    finally
      Bs.Free;
      Hl.Free;
    end;
  end;
  if Lang.FoldOutline and WithOutline then
  begin
    Items := TveOutline(Doc, Lang);
    for I := 0 to High(Items) do
    begin
      L := N - 1;
      for J := I + 1 to High(Items) do
        if Items[J].Level <= Items[I].Level then
        begin
          L := Items[J].Line - 1;
          Break;
        end;
      while (L > Items[I].Line) and (Trim(Doc.Buffer.LineText(L)) = '') do
        Dec(L);
      Add(Items[I].Line, L);
    end;
  end;
  SetLength(Result, Cnt);
  { by the first line, the outer one first; no region twice }
  SortRegions(Result);
  Last := 0;
  for I := 0 to Cnt - 1 do
    if (I = 0) or (Result[I].First <> Result[Last - 1].First) or (Result[I].Last <> Result[Last - 1].Last) then
    begin
      Result[Last] := Result[I];
      Inc(Last);
    end;
  SetLength(Result, Last);
end;

end.
