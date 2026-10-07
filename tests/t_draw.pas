program t_draw;
{ TveDraw: lines, corners and crossings of box characters. }
{$mode objfpc}{$H+}
uses SysUtils, TveBuf, TveDoc, TveEditor, TveDraw;
{$I testlib.inc}
var
  D: TTveDoc;
  E: TTveEditor;
  St: TTveDrawStyle;
begin
  D := TTveDoc.Create;
  D.LoadText('');
  E := TTveEditor.Create(D);
  { a rectangle: right, right, down, down, left, left, up, up }
  TveDrawStep(E, dirRight, dsSingle);
  TveDrawStep(E, dirRight, dsSingle);
  TveDrawStep(E, dirDown, dsSingle);
  TveDrawStep(E, dirDown, dsSingle);
  TveDrawStep(E, dirLeft, dsSingle);
  TveDrawStep(E, dirLeft, dsSingle);
  TveDrawStep(E, dirUp, dsSingle);
  TveDrawStep(E, dirUp, dsSingle);
  Check(D.Buffer.AsString = #$E2#$94#$8C#$E2#$94#$80#$E2#$94#$90#10 + #$E2#$94#$82' '#$E2#$94#$82#10 + #$E2#$94#$94#$E2#$94#$80#$E2#$94#$98,
    'a rectangle: ' + D.Buffer.AsString);
  Check(D.UndoCount = 8, 'a step is an undo step: ' + IntToStr(D.UndoCount));
  Check(TveBoxSides($253C, St) = 15, 'sides of a cross');
  Check(TveBoxChar(10, dsDouble) = $2554, 'double corner');
  E.Free;
  D.Free;
  Finish;
end.
