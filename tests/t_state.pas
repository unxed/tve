program t_state;
{ TveState: the cursor, bookmarks and folds survive a session. Needs a view, so the test builds one without a screen. }
{$mode objfpc}{$H+}
uses SysUtils, TvGeom, TvIni, TveBuf, TveDoc, TveEditor, TveView, TveState;
{$I testlib.inc}
var
  D, D2: TTveDoc;
  V, V2: TTveView;
  Ini: TIniFile;
  R: TRect;
  T: AnsiString;
  I: Integer;
begin
  T := '';
  for I := 0 to 49 do
    T := T + 'line ' + IntToStr(I) + #10;
  D := TTveDoc.Create;
  D.LoadText(T);
  R.Assign(0, 0, 40, 10);
  V := TTveView.Create(R, nil, nil, D);
  V.Editor.GotoLineCell(7, 3);
  V.Editor.SetBookmark(2);
  V.Editor.GotoLineCell(20, 0);
  V.Folds.Add(10, 15, True);
  V.Editor.GotoLineCell(30, 2);
  V.Editor.SetSelection(skStream, D.Buffer.LineStart(30));
  V.Editor.GotoOffset(D.Buffer.LineStart(30) + 4);
  Ini := TIniFile.Create('');
  TveStateSave(Ini, '/tmp/x.txt', V);
  V.Free;
  D.Free;
  D2 := TTveDoc.Create;
  D2.LoadText(T);
  V2 := TTveView.Create(R, nil, nil, D2);
  Check(not TveStateLoad(Ini, '/tmp/other.txt', V2), 'nothing for another file');
  Check(TveStateLoad(Ini, '/tmp/x.txt', V2), 'state loaded');
  Check((V2.Editor.Line = 30) and (V2.Editor.Cell = 4), 'cursor ' + IntToStr(V2.Editor.Line) + ':' + IntToStr(V2.Editor.Cell));
  Check(V2.Editor.BookmarkLine(2) = 7, 'bookmark');
  Check(V2.Folds.Count = 1, 'fold');
  Check(V2.Editor.HasSelection, 'selection');
  V2.Free;
  D2.Free;
  Ini.Free;
  Finish;
end.
