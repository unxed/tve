program t_macro;
{ TveMacro and the key map files: the text form of a macro, a user key map over A or B, recording and playing in a view. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, TvGeom, TvKeys, TvKeyName, TvEvents, TveDoc, TveEditor, TveView, TveCmds, TveMacro;
{$I testlib.inc}

function K(const S: AnsiString): TKey;
begin
  if not StrToKey(S, Result) then
  begin
    Result.Code := 0;
    Result.Mods := 0;
  end;
end;

procedure TypeKey(V: TTveView; C: Char);
var
  E: TEvent;
begin
  E := Default(TEvent);
  E.What := evKeyDown;
  E.KeyCode := Ord(C);
  E.TextLength := 1;
  E.Text[0] := C;
  V.HandleEvent(E);
end;

var
  M: TTveMacro;
  Km: TTveKeymap;
  Err, Path, T: AnsiString;
  D: TTveDoc;
  V: TTveView;
  R: TRect;
  F: TextFile;
  I: Integer;
begin
  { --- the macro text --- }
  M := TTveMacro.Create;
  Check(M.LoadText('; a macro' + #10 + 'Home' + #13#10 + '"Hello, \"world\"\n\t\x01"' + #10 + '# c' + #10 + '' + #10 + 'DeleteLine' + #10, Err), 'load: ' + Err);
  Check(M.Count = 3, 'three steps');
  Check((M.Step(0).Cmd = tcHome) and (M.Step(1).Cmd = 0) and (M.Step(2).Cmd = tcDeleteLine), 'step kinds');
  Check(M.Step(1).Text = 'Hello, "world"'#10#9#1, 'escapes');
  T := M.SaveText;
  Check(T = 'Home'#10'"Hello, \"world\"\n\t\x01"'#10'DeleteLine'#10, 'save: ' + T);
  Check(not M.LoadText('Home'#10'NoSuchCommand'#10'End'#10, Err) and (Err = 'NoSuchCommand') and (M.Count = 2), 'bad command: the good lines are kept');
  Check(not M.LoadText('"open'#10, Err) and (Err = '"open'), 'unterminated text');
  Check(not M.LoadText('"a\qb"'#10, Err), 'bad escape');
  Check(not M.LoadText('"a\x4"'#10, Err), 'short hex escape');
  Check(not M.LoadText('MacroPlay'#10, Err), 'a macro cannot play a macro');
  Check(not M.LoadText('MacroRecord'#10, Err), 'nor record');
  M.Clear;
  M.AddText('ab');
  M.AddText('cd');
  M.AddCommand(tcNewLine);
  M.AddText('x');
  Check((M.Count = 3) and (M.Step(0).Text = 'abcd'), 'adjacent text joins');
  Path := GetTempDir + 'tve_t_macro.txt';
  Check(M.SaveFile(Path), 'save file');
  M.Clear;
  Check(M.LoadFile(Path, Err) and (M.Count = 3) and (M.Step(2).Text = 'x'), 'load file');
  DeleteFile(Path);
  Check(not M.LoadFile(Path, Err) and (Err = Path), 'missing file');
  M.Free;

  { --- user key map over A or B --- }
  Km := TveNewKeymap(False, 'F9 = Find'#10'Ctrl+Y ='#10'Ctrl+K Q = Undo'#10, Err);
  Check(Err = '', 'override ok');
  Check((Km.Lookup(K('F9')) = tcFind) and (Km.Lookup(K('Ctrl+Y')) = -1), 'bind and unbind');
  Check(Km.LookupChord(K('Ctrl+K'), K('Q')) = tcUndo, 'new chord');
  Check(Km.LookupChord(K('Ctrl+K'), K('B')) = tcBlockBegin, 'the rest of A is kept');
  Check(Km.Lookup(K('Ctrl+N')) = tcInsertLineBelow, 'A base');
  Check(TveKeymapA.Lookup(K('F9')) = -1, 'shipped map A is not changed');
  Km.Free;
  Km := TveNewKeymap(True, 'Ctrl+N = Down'#10'bogus'#10, Err);
  Check((Err = 'bogus') and (Km.Lookup(K('Ctrl+N')) = tcDown), 'B base, bad line reported, good applied');
  Km.Free;
  Path := GetTempDir + 'tve_t_keys.txt';
  AssignFile(F, Path);
  Rewrite(F);
  Write(F, #$EF#$BB#$BF, '; my keys', #13#10, 'F9 = Save', #13#10, 'Ctrl+K B = Undo', #13#10);
  CloseFile(F);
  Km := TveNewKeymapFromFile(True, Path, Err);
  Check((Err = '') and (Km.Lookup(K('F9')) = tcSave) and (Km.LookupChord(K('Ctrl+K'), K('B')) = tcUndo), 'file with BOM and CRLF');
  Check(Km.Lookup(K('F7')) = tcFind, 'B base under the file');
  Km.Free;
  DeleteFile(Path);
  Km := TveNewKeymapFromFile(False, Path, Err);
  Check((Err = Path) and (Km.Lookup(K('F7')) = tcFind), 'missing file: the plain map and the name in Err');
  Km.Free;

  { --- recording and playing in a view --- }
  D := TTveDoc.Create;
  D.LoadText('one'#10'two'#10'three'#10);
  R.Assign(0, 0, 40, 10);
  V := TTveView.Create(R, nil, nil, D);
  V.Execute(tcMacroRecord);
  Check(V.Recording, 'recording');
  TypeKey(V, 'A');
  TypeKey(V, 'B');
  V.Execute(tcDown);
  V.Execute(tcHome);
  V.Execute(tcMacroRecord);
  Check(not V.Recording, 'stopped');
  Check(V.Macro.SaveText = '"AB"'#10'Down'#10'Home'#10, 'recorded: ' + V.Macro.SaveText);
  V.Editor.GotoLineCell(0, 0);
  V.Execute(tcMacroPlay);
  Check(D.Buffer.LineCount >= 3, 'lines');
  T := D.Buffer.AsString;
  Check(T = 'ABABone'#10'two'#10'three'#10, 'played: ' + T);
  Check(V.Editor.Line = 1, 'cursor after play');
  Check(V.LoadMacroFile('/nonexistent/m.txt', Err) = False, 'view: missing macro file');
  Check(V.Macro.Count = 0, 'view: macro is empty after a failed load');
  V.Macro.LoadText('"X"'#10'Down'#10, Err);
  V.Execute(tcMacroPlay);
  V.Execute(tcMacroPlay);
  Check(Copy(D.Buffer.AsString, 1, 7) = 'ABABone', 'unchanged');
  I := Pos('X', D.Buffer.AsString);
  Check(I > 0, 'loaded macro typed X');
  V.Free;
  D.Free;
  Finish;
end.
