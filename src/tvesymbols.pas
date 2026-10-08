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
  end;
  TTveOutline = array of TTveOutlineItem;

{ The outline of Doc by the rules of Lang (nil, or no rules: an empty outline). }
function TveOutline(Doc: TTveDoc; Lang: TTveLanguage): TTveOutline;
{ The entry that holds Line: the last one that starts at or before it (-1 if none). }
function TveOutlineAt(const Items: TTveOutline; Line: Int64): Integer;
{ The text of an entry for a list: indented by its level. }
function TveOutlineLabel(const Item: TTveOutlineItem): AnsiString;

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

end.
