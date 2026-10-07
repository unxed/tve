program t_fold;
{ TveFold: hiding, view numbers, nesting, following edits. }
{$mode objfpc}{$H+}
uses SysUtils, TveBuf, TveDoc, TveFold;
{$I testlib.inc}
var
  D: TTveDoc;
  F: TTveFolds;
  I: Integer;
  T: AnsiString;
begin
  D := TTveDoc.Create;
  T := '';
  for I := 0 to 19 do
    T := T + 'line' + IntToStr(I) + #10;
  D.LoadText(T);
  F := TTveFolds.Create(D);
  Check(F.Add(2, 6, True) = 0, 'add');
  Check(F.Add(4, 5, False) = 1, 'add nested');
  Check(F.Add(0, 100, False) = -1, 'bad range refused');
  Check(F.IsHidden(3) and F.IsHidden(6) and not F.IsHidden(2) and not F.IsHidden(7), 'hidden lines');
  Check(F.LineToView(7) = 3, 'view of line 7: ' + IntToStr(F.LineToView(7)));
  Check(F.LineToView(4) = 2, 'a hidden line has the view of its fold');
  Check(F.ViewToLine(3) = 7, 'back');
  Check(F.ViewToLine(2) = 2, 'the first line of the fold');
  Check(F.VisibleCount = 17, 'visible count ' + IntToStr(F.VisibleCount));
  Check(F.NextVisible(2, True) = 7, 'next visible skips the fold');
  Check(F.NextVisible(7, False) = 2, 'previous visible');
  Check(F.Level(1) = 1, 'level of the nested fold');
  Check(F.FoldAt(5) = 1, 'innermost fold at a line');
  Check(F.FoldAt(3, True) = -1, 'no fold starts at 3');
  F.Reveal(5);
  Check((not F.IsHidden(5)) and (F.VisibleCount = 21), 'reveal');
  Check(F.Toggle(2) and F.IsHidden(3), 'toggle collapses');
  D.Insert(D.Buffer.LineStart(1), 'new' + #10);
  Check((F.StartLine(0) = 3) and (F.EndLine(0) = 7), 'the fold follows an insert above');
  D.Insert(D.Buffer.LineStart(5), 'x' + #10);
  Check(F.EndLine(0) = 8, 'an insert inside widens it');
  T := F.SaveText;
  F.LoadText(T);
  Check(F.Count = 2, 'save and load ' + T);
  F.Free;
  D.Free;
  Finish;
end.
