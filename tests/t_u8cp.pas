program t_u8cp;
{ The document is UTF-8 in a program with a code page too (TvUtf8.Utf8Enabled = False): the view draws its characters, the cursor moves by them. }
{$mode objfpc}{$H+}
uses SysUtils, TvGeom, TvCodePg, TvUtf8, TvViews, TvMem, TvApp, TvWindow, TveDoc, TveView, TveLayout;
{$I testlib.inc}

const
  Zhe = #$D0#$B6;                 { U+0436 }
  Line = #$E2#$94#$80;            { U+2500 }
  Cjk = #$E4#$B8#$AD;             { U+4E2D, two cells }
  Acute = #$CC#$81;               { U+0301, a combining mark }

var
  App: TApplication;
  W: TWindow;
  V: TTveView;
  D: TTveDoc;
  Rc: TRect;
  Row0, Row1: ShortString;
begin
  CpSelect(866);
  Utf8Enabled := False;
  MemInit(60, 12);
  App := TApplication.Create;
  Rc := TRect.Create(0, 0, 40, 8);
  W := TWindow.Create(Rc, 'u8', 1);
  Rc := W.GetExtent;
  Rc.Grow(-1, -1);
  D := TTveDoc.Create;
  D.LoadText(Zhe + Line + 'x'#10 + Cjk + 'e' + Acute + 'y'#10);
  V := TTveView.Create(Rc, nil, nil, D, True);
  W.Insert(V);
  App.InsertWindow(W);
  V.DrawView;
  Row0 := MemText(2, 1, 38);
  Row1 := MemText(3, 1, 38);
  Check(Pos(Zhe + Line + 'x', Row0) > 0, 'a Cyrillic letter and a frame line are one cell each: ' + Row0);
  Check(Pos(Cjk + 'e' + Acute + 'y', Row1) > 0, 'a wide character and a combining mark: ' + Row1);
  Check(Pos(#$E2#$95#$A8, Row0) = 0, 'the lead byte of the letter is not shown as the frame character of CP866');
  V.Editor.GotoLineCell(0, 1);
  Check(V.Editor.Offset = 2, 'cell 1 is after the two bytes of the letter: ' + IntToStr(V.Editor.Offset));
  V.Editor.GotoLineCell(1, 2);
  Check(V.Editor.Offset = D.Buffer.LineStart(1) + 3, 'a wide character takes two cells: ' + IntToStr(V.Editor.Offset));
  D.Insert(0, Zhe + Zhe + ' ab'#10);
  V.Editor.GotoLineCell(0, 0);
  V.Editor.MoveWordRight(False);
  Check(V.Editor.Offset = 5, 'a word of two letters is four bytes, the blank after it is skipped: ' + IntToStr(V.Editor.Offset));
  Check(LayoutCells(Zhe + Line + 'x', 8) = 3, 'layout: three cells');
  Check(TveUpper(Zhe + 'a') = #$D0#$96'A', 'upper case of UTF-8');
  Check(TveLower(#$D0#$96'A' + #$FF) = Zhe + 'a' + #$FF, 'lower case of UTF-8, a stray byte stays');
  V.MessageText := Zhe + ' message';
  V.DrawView;
  Check((Pos(Zhe + ' message', MemText(2, 1, 38)) > 0) or (Pos(Zhe + ' message', MemText(7, 1, 38)) > 0),
    'the message line is drawn as UTF-8');
  App.Free;
  Finish;
end.
