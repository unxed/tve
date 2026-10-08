{ TveSymbols: the symbols of a document (types, routines, headings) for a list to jump from.

  MIT.

  The rules are in the grammar of the language: the lines "symbol LEVEL /REGEX/" (see TveHl). Every line of the text is tried against the rules in order; the first
  one that matches makes an entry, with the group 1 of the expression (or the whole match) as its title. A match whose title starts inside a comment or a string
  (by the highlighter) is not an entry, so a commented-out routine is not listed. Entries come in the order of the text. With "outline indent" or
  "outline braces" in the grammar the level of an entry is the number of entries that hold it, plus one; "outline from" skips the deeper rules before a line. }
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
{ The text of an entry for a list: indented by its level. }
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
        if (S - 1 <= High(Cls)) and (Cls[S - 1] in [hcComment, hcString]) then
          Break;                       { the line is in a comment or a string: no entry from it }
        if Cnt = Length(Result) then
          SetLength(Result, Cnt * 2 + 16);
        Result[Cnt].Line := L;
        Result[Cnt].Title := Title;
        Result[Cnt].Kind := Lang.SymbolLevel(I);
        if Nest = 0 then
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

function Quoted(const Cls: TByteClasses; Idx: Integer): Boolean;
begin
  Result := (Idx - 1 <= High(Cls)) and (Cls[Idx - 1] in [hcComment, hcString]);
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
  Pairs: array of array of Int64;          { an open line stack per pair of words }
  PairCount: array of Integer;
  Opens, Closes: array of Integer;          { the byte indexes of the words of a pair on a line }
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
    if not HaveCls then
      Hl.ClassifyLine(L, Cls);
    HaveCls := True;
  end;

  { the byte indexes where Re matches on the line, outside comments and strings }
  procedure Matches(Re: TTveRegex; var At: array of Integer; out Count: Integer);
  var
    Q: Integer;
  begin
    Count := 0;
    Q := 1;
    while (Q <= Length(Text)) and Re.Exec(Text, Q, Caps) do
    begin
      NeedCls;
      if not Quoted(Cls, Caps[0]) and (Count <= High(At)) then
      begin
        At[Count] := Caps[0];
        Inc(Count);
      end;
      if Caps[1] > Caps[0] then
        Q := Caps[1]
      else
        Q := Caps[0] + 1;
    end;
  end;

  { the line where a region of braces that opens on the line L starts: the line above when the brace is alone on its line (under a heading) }
  function BraceHead: Int64;
  begin
    Result := L;
    if (L > 0) and (Trim(Text) = '{') and (Trim(Doc.Buffer.LineText(L - 1)) <> '') then
      Result := L - 1;
  end;

var
  OpenAt, CloseAt: array[0..63] of Integer;
  NO, NC: Integer;
begin
  Result := nil;
  Cnt := 0;
  if (Doc = nil) or (Lang = nil) then
    Exit;
  N := Doc.Buffer.LineCount;
  if Lang.FoldBraces or Lang.FoldIndent or (Lang.FoldPairCount > 0) then
  begin
    Hl := TTveHighlighter.Create(Doc, Lang);
    try
      Braces := nil;
      BraceCount := 0;
      SetLength(Pairs, Lang.FoldPairCount);
      SetLength(PairCount, Lang.FoldPairCount);
      IndCount := 0;
      LastText := -1;
      for LI := 0 to Integer(N) - 1 do        { a LongInt counter: a 32-bit target has no Int64 loops }
      begin
        L := LI;
        Text := Doc.Buffer.LineText(L);
        HaveCls := False;
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
        for I := 0 to Lang.FoldPairCount - 1 do
        begin
          Matches(Lang.FoldOpen(I), OpenAt, NO);
          Matches(Lang.FoldClose(I), CloseAt, NC);
          J := 0;
          K := 0;
          while (J < NO) or (K < NC) do
            if (J < NO) and ((K >= NC) or (OpenAt[J] < CloseAt[K])) then
            begin
              if PairCount[I] = Length(Pairs[I]) then
                SetLength(Pairs[I], PairCount[I] * 2 + 16);
              Pairs[I][PairCount[I]] := L;
              Inc(PairCount[I]);
              Inc(J);
            end
            else
            begin
              if PairCount[I] > 0 then
              begin
                Dec(PairCount[I]);
                Add(Pairs[I][PairCount[I]], L);
              end;
              Inc(K);
            end;
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
      Hl.Free;
    end;
  end;
  if Lang.FoldOutline then
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
