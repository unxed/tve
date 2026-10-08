{ TveSymbols: the symbols of a document (types, routines, headings) for a list to jump from.

  MIT.

  The rules are in the grammar of the language: the lines "symbol LEVEL /REGEX/" (see TveHl). Every line of the text is tried against the rules in order; the first
  one that matches makes an entry, with the group 1 of the expression (or the whole match) as its title. A match whose title starts inside a comment or a string
  (by the highlighter) is not an entry, so a commented-out routine is not listed. Entries come in the order of the text. }
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

function TveOutline(Doc: TTveDoc; Lang: TTveLanguage): TTveOutline;
var
  Hl: TTveHighlighter;
  L, N: Int64;
  LI, I, S, E, Cnt: Integer;
  Text, Title: AnsiString;
  Caps: TCaps;
  Cls: TByteClasses;
  Re: TTveRegex;
begin
  Result := nil;
  if (Doc = nil) or (Lang = nil) or (Lang.SymbolCount = 0) then
    Exit;
  Hl := TTveHighlighter.Create(Doc, Lang);
  try
    N := Doc.Buffer.LineCount;
    Cnt := 0;
    for LI := 0 to Integer(N) - 1 do        { a LongInt counter: a 32-bit target has no Int64 loops }
    begin
      L := LI;
      Text := Doc.Buffer.LineText(L);
      if Text = '' then
        Continue;
      for I := 0 to Lang.SymbolCount - 1 do
      begin
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
        Hl.ClassifyLine(L, Cls);
        if (S - 1 <= High(Cls)) and (Cls[S - 1] in [hcComment, hcString]) then
          Break;                       { the line is in a comment or a string: no entry from it }
        if Cnt = Length(Result) then
          SetLength(Result, Cnt * 2 + 16);
        Result[Cnt].Line := L;
        Result[Cnt].Level := Lang.SymbolLevel(I);
        Result[Cnt].Title := Title;
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
