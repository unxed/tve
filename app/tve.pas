program tve;
{ tve: the editor as a program (and the test bench of the editor view).
  Usage: tve [--keys=a|b] [--keymap=FILE] [--macro=FILE] [file]. F2 saves, Alt-X quits.
  --keymap applies a user key map file over the chosen one; --macro loads a macro (text form); the File menu saves and loads the macro as tve.macro. MIT. }
{$I tvdefs.inc}
{$H+}
uses SysUtils, TvGeom, TvColors, TvEvents, TvKeys, TvViews, TvWindow, TvMenus, TvApp, TvUnix,
  TveDoc, TveFile, TveView, TveCmds, TveHl, TveLang, TveSearch, TveDialogs, TveComplete, TveExtras;

const
  cmSaveFile = 200;
  cmSaveMacro = 201;
  cmLoadMacro = 202;

type
  TTveApp = class(TApplication)
    Win: TWindow;
    View: TTveView;
    Doc: TTveDoc;
    Name: AnsiString;
    Compl: TTveCompletion;
    procedure InitMenuBar; override;
    procedure InitStatusLine; override;
    procedure HandleEvent(var Event: TEvent); override;
    function Host(Sender: TObject; Cmd: Integer): Boolean;
    procedure OpenFile(const FileName: AnsiString; MapB: Boolean; const KeymapFile: AnsiString);
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
      NewItem('Save ~m~acro', '', kbNoKey, cmSaveMacro, hcNoContext,
      NewItem('~L~oad macro', '', kbNoKey, cmLoadMacro, hcNoContext,
      NewLine(
      NewItem('E~x~it', 'Alt-X', kbAltX, cmQuit, hcNoContext, nil)))))), nil)));
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

procedure TTveApp.OpenFile(const FileName: AnsiString; MapB: Boolean; const KeymapFile: AnsiString);
var
  R: TRect;
  H, V: TScrollBar;
  Err: AnsiString;
  Lang: TTveLanguage;
  Map: TTveKeymap;
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
  if KeymapFile <> '' then
  begin
    Map := TveNewKeymapFromFile(MapB, KeymapFile, Err);
    if Err <> '' then
      WriteLn(StdErr, 'tve: key map: ', Err);
    View.Keymap := Map;
  end
  else if MapB then
    View.Keymap := TveKeymapB;
  View.Gutter := True;
  View.MarkOccurrences := True;
  View.OnHostCommand := @Host;
  Lang := TveLangForFile(FileName);
  View.SetLanguage(Lang);
  Compl := TTveCompletion.Create;
  if Lang <> nil then
    Compl.SetKeywords(Lang.KeywordText);
  View.Completion := Compl;
  Win.Insert(View);
  InsertWindow(Win);
end;

function TTveApp.Host(Sender: TObject; Cmd: Integer): Boolean;
var
  O: TTveSearchOptions;
  Repl, T: AnsiString;
  All: Boolean;
  L, Ofs: Int64;
  C: Integer;
  IsOfs: Boolean;
  CP: LongWord;
begin
  Result := True;
  case Cmd of
    tcFind:
      begin
        O := View.SearchOptions;
        if TveFindDialog(O) then
        begin
          View.SearchOptions := O;
          View.FindNext;
          View.Refresh;
        end;
      end;
    tcReplace:
      begin
        O := View.SearchOptions;
        Repl := '';
        if TveReplaceDialog(O, Repl, All) then
        begin
          View.SearchOptions := O;
          if All then
            View.ReplaceAll(Repl)
          else
            View.ReplaceNext(Repl);
        end;
      end;
    tcInsertChar:
      begin
        T := '';
        if TveCodePointDialog(T) and TveParseCodePoint(T, CP) then
        begin
          InsertCodePoint(View.Editor, CP);
          View.Refresh;
        end;
      end;
    tcGotoLine:
      begin
        T := '';
        if TveGotoDialog(T) and TveParseGoto(T, L, C, Ofs, IsOfs) then
        begin
          if IsOfs then
            View.Editor.GotoOffset(Ofs)
          else
            View.Editor.GotoLineCell(L, C);
          View.Refresh;
        end;
      end;
  else
    Result := False;
  end;
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
  end
  else if (Event.What = evCommand) and (Event.Command = cmSaveMacro) then
  begin
    if View <> nil then
      View.SaveMacroFile('tve.macro');
    ClearEvent(Event);
  end
  else if (Event.What = evCommand) and (Event.Command = cmLoadMacro) then
  begin
    if View <> nil then
      View.LoadMacroFile('tve.macro', Err);
    ClearEvent(Event);
  end;
end;

var
  App: TTveApp;
  I: Integer;
  F: AnsiString;
  MapB: Boolean;
  KeyFile, MacroFile: AnsiString;
begin
  F := '';
  KeyFile := '';
  MacroFile := '';
  MapB := False;
  for I := 1 to ParamCount do
    if ParamStr(I) = '--keys=b' then
      MapB := True
    else if ParamStr(I) = '--keys=a' then
      MapB := False
    else if Copy(ParamStr(I), 1, 9) = '--keymap=' then
      KeyFile := Copy(ParamStr(I), 10, MaxInt)
    else if Copy(ParamStr(I), 1, 8) = '--macro=' then
      MacroFile := Copy(ParamStr(I), 9, MaxInt)
    else
      F := ParamStr(I);
  if not UnixInit then
  begin
    WriteLn('tve needs a terminal');
    Halt(1);
  end;
  App := TTveApp.Create;
  App.OpenFile(F, MapB, KeyFile);
  if MacroFile <> '' then
    App.View.LoadMacroFile(MacroFile, F);
  App.Run;
  App.Free;
  UnixDone;
end.
