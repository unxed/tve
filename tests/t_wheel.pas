program t_wheel;
{ X.4 of the UX guidelines: the wheel scrolls the editor under the pointer, whatever has the focus; E.7 on the keys of the view: the optional word keys of the guidelines. }
{$mode objfpc}{$H+}
uses SysUtils, TvGeom, TvCodePg, TvEvents, TvKeys, TvViews, TvMem, TvApp, TvWindow, TveDoc, TveView, TveCmds;
{$I testlib.inc}

function R(A, B, C, D: Integer): TRect;
begin
  Result := TRect.Create(A, B, C, D);
end;

function Lines(N: Integer): AnsiString;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to N do
    Result := Result + 'line ' + IntToStr(I) + #10;
end;

function MakeWin(const Bounds: TRect; const Title: AnsiString; Num: Integer; out V: TTveView): TWindow;
var
  H, B: TScrollBar;
  D: TTveDoc;
  Rc: TRect;
begin
  Result := TWindow.Create(Bounds, Title, Num);
  H := Result.StandardScrollBar(sbHorizontal or sbHandleKeyboard);
  B := Result.StandardScrollBar(sbVertical or sbHandleKeyboard);
  Rc := Result.GetExtent;
  Rc.Grow(-1, -1);
  D := TTveDoc.Create;
  D.LoadText('foo.bar'#10 + Lines(100));
  V := TTveView.Create(Rc, H, B, D, True);
  Result.Insert(V);
end;

procedure Wheel(V: TView; X, Y: Integer; Dir: Byte);
var
  E: TEvent;
begin
  ClearEvent(E);
  E.What := evMouseWheel;
  E.Mouse.Where := V.MakeGlobal(Point(X, Y));
  E.Mouse.Wheel := Dir;
  TProgram.Application.HandleEvent(E);
end;

procedure Press(Code, Mods: Word);
var
  E: TEvent;
begin
  MakeKeyEvent(E, Code, Mods);
  TProgram.Application.HandleEvent(E);
end;

var
  App: TApplication;
  W1, W2: TWindow;
  V1, V2: TTveView;
  Map: TTveKeymap;
  Err: AnsiString;
begin
  CpSelect(866);
  MemInit(100, 30);
  App := TApplication.Create;
  W1 := MakeWin(R(1, 1, 40, 14), 'one', 1, V1);
  W2 := MakeWin(R(45, 1, 90, 14), 'two', 2, V2);
  App.InsertWindow(W1);
  App.InsertWindow(W2);
  V1.Refresh;
  V2.Refresh;
  Check(TProgram.DeskTop.Current = W2, 'the second window has the focus');
  Wheel(V1, 5, 3, mwDown);
  Check(V1.Delta.Y = V1.WheelStep, 'the wheel over the editor of the unfocused window scrolls it');
  Check(V2.Delta.Y = 0, '... and not the focused one');
  Check(TProgram.DeskTop.Current = W2, '... the focus stays');
  Wheel(V2, 5, 3, mwDown);
  Wheel(V2, 5, 3, mwDown);
  Check((V2.Delta.Y = 2 * V2.WheelStep) and (V1.Delta.Y = V1.WheelStep), 'over the focused one it scrolls the focused one');
  Wheel(V1, 5, 3, mwUp);
  Check(V1.Delta.Y = 0, 'the wheel up scrolls back');
  UxWheelUnderCursor := False;
  Wheel(V1, 5, 3, mwDown);
  Check((V1.Delta.Y = 0) and (V2.Delta.Y = 3 * V2.WheelStep), 'UxWheelUnderCursor = False: the old way, the focused window gets it');
  UxWheelUnderCursor := True;

  { the optional key map of the word movement of the guidelines on the view }
  V2.Editor.GotoLineCell(0, 0);
  V2.Keymap := TveNewKeymap(False, TveNavWordsKeymapText, Err);
  Press(kbCtrlRight, kbCtrlShift);
  Press(kbCtrlRight, kbCtrlShift);
  Check(V2.Editor.Cell = 7, 'nav keys: foo.bar takes two jumps (foo|.bar, foo.bar|)');
  V2.Editor.GotoLineCell(0, 0);
  V2.Keymap := TveKeymapA;
  Press(kbCtrlRight, kbCtrlShift);
  Press(kbCtrlRight, kbCtrlShift);
  Check(V2.Editor.Cell = 4, 'the shipped map: the word rules of the editor (foo|.bar, foo.|bar)');
  App.Free;
  Finish;
end.
