program t_drag;
{ Drag and drop of the selection with the mouse: the drop place is marked while dragging, the view scrolls by the distance of the pointer beyond its edge,
  and the text can be dropped into another editor (moved, or copied with Ctrl). The events are a script of the memory backend. }
{$mode objfpc}{$H+}
uses SysUtils, TvGeom, TvCodePg, TvColors, TvEvents, TvKeys, TvViews, TvMem, TvApp, TvWindow, TveDoc, TveEditor, TveView;
{$I testlib.inc}

type
  TProbe = class(TTveView)
    SawDrop: Boolean;
    DropOk: Boolean;
    procedure Draw; override;
  end;

procedure TProbe.Draw;
var
  P: TPoint;
begin
  inherited Draw;
  if DropShown then
  begin
    SawDrop := True;
    { the marked cell on the screen has the drop colour }
    P := MakeGlobal(Point(DropCell - Delta.X, LineToView(DropLine) - Delta.Y));
    DropOk := MemAttr(P.X, P.Y) = Byte(DropAttr);
  end;
end;

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

function MakeWin(const Bounds: TRect; const Title, Text: AnsiString; Num: Integer; out V: TProbe): TWindow;
var
  D: TTveDoc;
  Rc: TRect;
  H, B: TScrollBar;
begin
  Result := TWindow.Create(Bounds, Title, Num);
  H := Result.StandardScrollBar(sbHorizontal or sbHandleKeyboard);
  B := Result.StandardScrollBar(sbVertical or sbHandleKeyboard);
  Rc := Result.GetExtent;
  Rc.Grow(-1, -1);
  D := TTveDoc.Create;
  D.LoadText(Text);
  V := TProbe.Create(Rc, H, B, D, True);
  Result.Insert(V);
end;

{ the global place of a cell of a view }
function At(V: TView; X, Y: Integer): TPoint;
begin
  Result := V.MakeGlobal(Point(X, Y));
end;

procedure Mouse(What: Word; const P: TPoint; Ctrl: Boolean = False);
var
  E: TEvent;
begin
  ClearEvent(E);
  E.What := What;
  E.Mouse.Where := P;
  E.Mouse.Buttons := mbLeftButton;
  if Ctrl then
    E.KeyDown.ControlKeyState := kbCtrlShift;
  MemEvent(E);
end;

procedure Run;
var
  E: TEvent;
begin
  while MemPending > 0 do
  begin
    TProgram.Application.GetEvent(E);
    if E.What <> evNothing then
      TProgram.Application.HandleEvent(E);
  end;
end;

procedure Select(V: TTveView; A, B: Int64);
begin
  V.Editor.SetSelection(skStream, A);
  V.Editor.GotoOffset(B);
  V.Refresh;
end;

var
  App: TApplication;
  W1, W2: TWindow;
  V1, V2: TProbe;
  P: TPoint;
  Top: Int64;
begin
  CpSelect(866);
  MemInit(100, 30);
  App := TApplication.Create;
  W1 := MakeWin(R(1, 1, 40, 14), 'one', 'hello world'#10 + Lines(100), 1, V1);
  W2 := MakeWin(R(45, 1, 90, 14), 'two', 'abc'#10'def'#10, 2, V2);
  App.InsertWindow(W1);
  App.InsertWindow(W2);
  W1.Focus;

  { inside one view: the drop place is marked while dragging, the text moves }
  Select(V1, 0, 5);
  Mouse(evMouseDown, At(V1, 1, 0));
  Mouse(evMouseMove, At(V1, 8, 0));
  Mouse(evMouseMove, At(V1, 11, 0));
  Mouse(evMouseUp, At(V1, 11, 0));
  Run;
  Check(V1.SawDrop, 'the drop place is shown while dragging');
  Check(V1.DropOk, 'in the drop colour');
  Check(not V1.DropShown, 'and not after the drop');
  Check(V1.Doc.Buffer.LineText(0) = ' worldhello', 'moved: ' + V1.Doc.Buffer.LineText(0));
  V1.Editor.Undo;
  Check(V1.Doc.Buffer.LineText(0) = 'hello world', 'one undo step');

  { below the view: it scrolls by the distance of the pointer }
  Select(V1, 0, 5);
  Top := V1.Delta.Y;
  Mouse(evMouseDown, At(V1, 1, 0));
  Mouse(evMouseMove, At(V1, 1, V1.Size.Y + 2));
  Mouse(evMouseUp, At(V1, 1, V1.Size.Y - 1));
  Run;
  Check(V1.Delta.Y - Top = 3, 'three rows beyond the edge scroll three rows: ' + IntToStr(V1.Delta.Y - Top));
  Check(Pos('hello', V1.Doc.Buffer.LineText(0)) = 0, 'and the text went down there');
  V1.Editor.Undo;
  V1.ScrollTo(0, 0);
  Check(V1.Doc.Buffer.LineText(0) = 'hello world', 'undone');

  { selecting with the mouse scrolls the same way }
  V1.Editor.ClearSelection;
  V1.Editor.GotoLineCell(0, 0);
  V1.Refresh;
  Top := V1.Delta.Y;
  Mouse(evMouseDown, At(V1, 0, 0));
  Mouse(evMouseMove, At(V1, 0, V1.Size.Y + 1));
  Mouse(evMouseUp, At(V1, 0, V1.Size.Y + 1));
  Run;
  Check(V1.Delta.Y - Top = 2, 'selecting: two rows beyond the edge scroll two rows: ' + IntToStr(V1.Delta.Y - Top));
  Check(V1.Editor.HasSelection and (V1.Editor.Line = V1.Delta.Y + V1.Size.Y - 1), 'the selection ends at the edge row');
  V1.Editor.ClearSelection;
  V1.ScrollTo(0, 0);
  V1.Editor.GotoLineCell(0, 0);
  V1.Refresh;

  { into another editor: moved, the other one shows where it would go and gets the focus }
  V2.SawDrop := False;
  Select(V1, 6, 11);
  Mouse(evMouseDown, At(V1, 7, 0));
  Mouse(evMouseMove, At(V2, 1, 1));
  Mouse(evMouseUp, At(V2, 1, 1));
  Run;
  Check(V2.SawDrop and V2.DropOk, 'the other editor marks the drop place');
  Check(not V1.SawDrop or not V1.DropShown, 'the first one does not');
  Check(V2.Doc.Buffer.AsString = 'abc'#10'dworldef'#10, 'dropped into the other document: ' + V2.Doc.Buffer.AsString);
  Check(V1.Doc.Buffer.LineText(0) = 'hello ', 'moved out of the first: ' + V1.Doc.Buffer.LineText(0));
  Check(V2.Editor.HasSelection, 'the dropped text is selected');
  Check(TProgram.DeskTop.Current = W2, 'the other window has the focus');

  { with Ctrl: copied }
  W1.Focus;
  Select(V1, 0, 5);
  Mouse(evMouseDown, At(V1, 1, 0));
  Mouse(evMouseMove, At(V2, 0, 0), True);
  Mouse(evMouseUp, At(V2, 0, 0), True);
  Run;
  Check(V2.Doc.Buffer.LineText(0) = 'helloabc', 'copied: ' + V2.Doc.Buffer.LineText(0));
  Check(V1.Doc.Buffer.LineText(0) = 'hello ', 'the first keeps it');
  App.Free;
  Finish;
end.
