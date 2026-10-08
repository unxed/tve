program t_macro;
{ TveMacro and the key map files: the text form of a macro, a user key map over A or B, recording and playing in a view. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, TvGeom, TvKeys, TvKeyName, TvEvents, TveDoc, TveEditor, TveView, TveCmds, TveMacro, TveSearch;
{$I testlib.inc}

function K(const S: AnsiString): TKey;
begin
  if not StrToKey(S, Result) then
  begin
    Result.Code := 0;
    Result.Mods := 0;
  end;
end;

type
  TPrompter = class
    Cancel: Boolean;
    function Ask(const Question: AnsiString; out Value: AnsiString): Boolean;
  end;

function TPrompter.Ask(const Question: AnsiString; out Value: AnsiString): Boolean;
begin
  Value := Question + '!';
  Result := not Cancel;
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
  O: TTveSearchOptions;
  P: TPrompter;
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
  Check(V.RecordedMacro.SaveText = '"AB"'#10'Down'#10'Home'#10, 'recorded: ' + V.RecordedMacro.SaveText);
  V.Editor.GotoLineCell(0, 0);
  V.Execute(tcMacroPlay);
  Check(D.Buffer.LineCount >= 3, 'lines');
  T := D.Buffer.AsString;
  Check(T = 'ABABone'#10'two'#10'three'#10, 'played: ' + T);
  Check(V.Editor.Line = 1, 'cursor after play');
  Check(V.LoadMacroFile('/nonexistent/m.txt', Err) = False, 'view: missing macro file');
  Check(V.RecordedMacro.Count = 0, 'view: macro is empty after a failed load');
  V.RecordedMacro.LoadText('"X"'#10'Down'#10, Err);
  V.Execute(tcMacroPlay);
  V.Execute(tcMacroPlay);
  Check(Copy(D.Buffer.AsString, 1, 7) = 'ABABone', 'unchanged');
  I := Pos('X', D.Buffer.AsString);
  Check(I > 0, 'loaded macro typed X');
  V.Free;
  D.Free;
  { --- the steps that are no commands, repeat counts, playing until a step fails --- }
  M := TTveMacro.Create;
  Check(M.LoadText('prompt "Name?"'#10'find "a\"b" case word regex back hex'#10'replace "x" "y z"'#10'replaceall "1" "" regex'#10, Err), 'search steps: ' + Err);
  Check((M.Count = 4) and (M.Step(0).Cmd = msPrompt) and (M.Step(0).Text = 'Name?'), 'prompt step');
  Check((M.Step(1).Cmd = msFind) and (M.Step(1).Text = 'a"b') and (M.Step(1).Flags = mfCase or mfWord or mfRegex or mfBack or mfHex), 'find step');
  Check((M.Step(2).Cmd = msReplace) and (M.Step(2).Repl = 'y z') and (M.Step(2).Flags = 0), 'replace step');
  Check((M.Step(3).Cmd = msReplaceAll) and (M.Step(3).Repl = '') and (M.Step(3).Flags = mfRegex), 'replaceall step');
  T := M.SaveText;
  Check(T = 'prompt "Name?"'#10'find "a\"b" case word regex back hex'#10'replace "x" "y z"'#10'replaceall "1" "" regex'#10, 'saved: ' + T);
  Check(not M.LoadText('find "x" sideways'#10, Err), 'unknown option');
  Check(not M.LoadText('replace "x"'#10, Err), 'replace without the new text');
  Check(not M.LoadText('prompt "x" case'#10, Err), 'a prompt has no options');
  Check(not M.LoadText('find x'#10, Err), 'unquoted pattern');
  Check(not M.LoadText('MacroPlayAll'#10, Err), 'a macro cannot play itself again and again');
  M.Free;

  D := TTveDoc.Create;
  D.LoadText('a1 b a2'#10'a3'#10'x'#10);
  V := TTveView.Create(R, nil, nil, D);
  { a search from the host (a dialog) is recorded with its options }
  V.Execute(tcMacroRecord);
  O := V.SearchOptions;
  O.Pattern := 'a';
  O.CaseSensitive := True;
  V.SearchOptions := O;
  V.FindNext;
  TypeKey(V, '_');
  V.Execute(tcMacroRecord);
  Check(V.RecordedMacro.SaveText = 'find "a" case'#10'"_"'#10, 'host search recorded: ' + V.RecordedMacro.SaveText);
  Check(D.Buffer.AsString = '_1 b a2'#10'a3'#10'x'#10, 'recorded run: ' + D.Buffer.AsString);
  Check(V.PlayMacro(1) and (D.Buffer.AsString = '_1 b _2'#10'a3'#10'x'#10), 'once: ' + D.Buffer.AsString);
  Check(not V.PlayMacro(0) and (D.Buffer.AsString = '_1 b _2'#10'_3'#10'x'#10), 'until the search fails: ' + D.Buffer.AsString);
  { counts }
  D.LoadText('');
  V.Editor.GotoOffset(0);
  V.RecordedMacro.LoadText('"ab"'#10, Err);
  Check(V.PlayMacro(3) and (D.Buffer.AsString = 'ababab'), 'three times: ' + D.Buffer.AsString);
  { a movement that cannot move ends the playing }
  D.LoadText('p'#10'q'#10'r');
  V.Editor.GotoOffset(0);
  V.RecordedMacro.LoadText('Home'#10'"# "'#10'Down'#10, Err);
  V.Execute(tcMacroPlayAll);
  Check(D.Buffer.AsString = '# p'#10'# q'#10'# r', 'comment every line: ' + D.Buffer.AsString);
  { a round that changes nothing ends the playing }
  V.RecordedMacro.LoadText('Home'#10, Err);
  Check(V.PlayMacro(0), 'nothing changes: stops');
  { prompts: the answer is typed; no OnPrompt or a cancel fails }
  V.RecordedMacro.LoadText('prompt "who"'#10, Err);
  Check(not V.PlayMacro(1), 'no OnPrompt');
  P := TPrompter.Create;
  V.OnPrompt := @P.Ask;
  D.LoadText('');
  V.Editor.GotoOffset(0);
  Check(V.PlayMacro(2) and (D.Buffer.AsString = 'who!who!'), 'prompt answers: ' + D.Buffer.AsString);
  P.Cancel := True;
  Check(not V.PlayMacro(1), 'cancelled prompt');
  { replace steps }
  D.LoadText('x x x');
  V.Editor.GotoOffset(0);
  V.RecordedMacro.LoadText('replace "x" "y"'#10, Err);
  Check(not V.PlayMacro(0) and (D.Buffer.AsString = 'y y y'), 'replace until none: ' + D.Buffer.AsString);
  V.RecordedMacro.LoadText('replaceall "y" "zz"'#10, Err);
  Check(V.PlayMacro(1) and (D.Buffer.AsString = 'zz zz zz'), 'replace all: ' + D.Buffer.AsString);
  { the places and the text that a host gives (its own dialogs) are recorded; goto steps }
  D.LoadText('a'#10'b'#10'c'#10);
  V.Editor.ClearSelection;
  V.Execute(tcMacroRecord);
  V.GotoPlace(1, 1);
  V.TypeText('X');
  V.GotoOffsetPlace(0);
  V.Execute(tcMacroRecord);
  Check(V.RecordedMacro.SaveText = 'goto 2:2'#10'"X"'#10'goto +0'#10, 'host steps recorded: ' + V.RecordedMacro.SaveText);
  Check(D.Buffer.AsString = 'a'#10'bX'#10'c'#10, 'host steps done: ' + D.Buffer.AsString);
  Check(V.PlayMacro(1) and (D.Buffer.AsString = 'a'#10'bXX'#10'c'#10), 'host steps played: ' + D.Buffer.AsString);
  Check(V.RecordedMacro.LoadText('goto 3'#10'"!"'#10, Err) and V.PlayMacro(1) and (D.Buffer.AsString = 'a'#10'bXX'#10'!c'#10), 'goto a line: ' + D.Buffer.AsString);
  Check(V.RecordedMacro.LoadText('goto 9:1'#10, Err) and not V.PlayMacro(1), 'a line past the end fails');
  Check(not V.RecordedMacro.LoadText('goto x'#10, Err) and not V.RecordedMacro.LoadText('goto 1:'#10, Err) and
    not V.RecordedMacro.LoadText('goto +1:2'#10, Err) and not V.RecordedMacro.LoadText('goto'#10, Err), 'bad places');
  V.Free;
  P.Free;
  D.Free;
  Finish;
end.
