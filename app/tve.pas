program tve;
{ tve: the editor as a program (and the test bench of the editor view).
  Usage: tve [--keys=a|b] [file]. F2 saves, Alt-X quits. MIT. }
{$I tvdefs.inc}
{$H+}
uses SysUtils, TvGeom, TvColors, TvEvents, TvKeys, TvViews, TvWindow, TvMenus, TvApp, TvUnix,
  TveDoc, TveFile, TveView, TveCmds, TveHl, TveLang;

const
  cmSaveFile = 200;

type
  TTveApp = class(TApplication)
    Win: TWindow;
    View: TTveView;
    Doc: TTveDoc;
    Name: AnsiString;
    procedure InitMenuBar; override;
    procedure InitStatusLine; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure OpenFile(const FileName: AnsiString; MapB: Boolean);
  end;

procedure TTveApp.InitMenuBar;
var
  R: TRect;
begin
  R := GetExtent;
  R.B.Y := R.A.Y + 1;
  MenuBar := TMenuBar.Create(R, NewMenu(
    NewSubMenu('~F~ile', hcNoContext, NewMenu(
      NewItem('~S~ave', 'F2', kbF2, cmSaveFile, hcNoContext,
      NewLine(
      NewItem('E~x~it', 'Alt-X', kbAltX, cmQuit, hcNoContext, nil)))), nil)));
end;

procedure TTveApp.InitStatusLine;
var
  R: TRect;
begin
  R := GetExtent;
  R.A.Y := R.B.Y - 1;
  StatusLine := TStatusLine.Create(R,
    NewStatusDef(0, $FFFF,
      NewStatusKey('~F2~ Save', kbF2, cmSaveFile,
      NewStatusKey('~Alt-X~ Exit', kbAltX, cmQuit, nil)), nil));
end;

procedure TTveApp.OpenFile(const FileName: AnsiString; MapB: Boolean);
var
  R: TRect;
  H, V: TScrollBar;
  Err: AnsiString;
  Lang: TTveLanguage;
begin
  Name := FileName;
  Doc := TTveDoc.Create;
  if (FileName <> '') and FileExists(FileName) then
    TveLoadDoc(Doc, FileName, TveDefaultOptions, Err);
  R := DeskTop.GetExtent;
  Win := TWindow.Create(R, ExtractFileName(FileName), 1);
  H := Win.StandardScrollBar(sbHorizontal or sbHandleKeyboard);
  V := Win.StandardScrollBar(sbVertical or sbHandleKeyboard);
  R := Win.GetExtent;
  R.Grow(-1, -1);
  View := TTveView.Create(R, H, V, Doc, True);
  if MapB then
    View.Keymap := TveKeymapB;
  View.Gutter := True;
  Lang := TveLangForFile(FileName);
  View.SetLanguage(Lang);
  Win.Insert(View);
  InsertWindow(Win);
end;

procedure TTveApp.HandleEvent(var Event: TEvent);
var
  Err: AnsiString;
  Lost: Integer;
begin
  inherited HandleEvent(Event);
  if (Event.What = evCommand) and (Event.Command = cmSaveFile) then
  begin
    if (Name <> '') and (View <> nil) then
      TveSaveDoc(View.Doc, Name, TveDefaultOptions, Lost, Err);
    ClearEvent(Event);
  end;
end;

var
  App: TTveApp;
  I: Integer;
  F: AnsiString;
  MapB: Boolean;
begin
  F := '';
  MapB := False;
  for I := 1 to ParamCount do
    if ParamStr(I) = '--keys=b' then
      MapB := True
    else if ParamStr(I) = '--keys=a' then
      MapB := False
    else
      F := ParamStr(I);
  if not UnixInit then
  begin
    WriteLn('tve needs a terminal');
    Halt(1);
  end;
  App := TTveApp.Create;
  App.OpenFile(F, MapB);
  App.Run;
  App.Free;
  UnixDone;
end.
