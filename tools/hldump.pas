program hldump;
{ Shows how the highlighter classifies a file: every line, and under it a line of letters (one per byte).
  usage: hldump FILE [language]. The letters: . normal, c comment, s string, 0 number, k keyword, t type, b builtin, p preproc, o operator, e escape, T tag, a attr,
  E entity, v variable, d delimiter, f function, P property, S selector, V value, A asm, x special. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, TveBuf, TveDoc, TveHl, TveLang;
const
  Letters = '.cs0ktbpoeTaEvdfPSVAx';
var
  D: TTveDoc;
  L: TTveLanguage;
  H: TTveHighlighter;
  F: TStringList;
  I, J: Integer;
  C: TByteClasses;
  S, Map: AnsiString;
begin
  F := TStringList.Create;
  F.LoadFromFile(ParamStr(1));
  D := TTveDoc.Create;
  D.LoadText(F.Text);
  if ParamCount >= 2 then
    L := TveLangByName(ParamStr(2))
  else
    L := TveLangForFile(ParamStr(1));
  if L = nil then
  begin
    WriteLn('no language');
    Halt(1);
  end;
  H := TTveHighlighter.Create(D, L);
  for I := 0 to F.Count - 1 do
  begin
    H.ClassifyLine(I, C);
    S := D.Buffer.LineText(I);
    Map := '';
    for J := 0 to High(C) do
      if (Byte(S[J + 1]) and $C0) = $80 then
        Map := Map + ''
      else
        Map := Map + Letters[C[J] + 1];
    WriteLn(S);
    if Trim(Map) <> '' then
      WriteLn(Map);
  end;
end.
