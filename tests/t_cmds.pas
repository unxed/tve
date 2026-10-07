program t_cmds;
{ TveCmds: command names, key map text, chords, the shipped maps. }
{$mode objfpc}{$H+}
uses SysUtils, TvKeys, TvKeyName, TveCmds;
{$I testlib.inc}

function K(const S: AnsiString): TKey;
begin
  if not StrToKey(S, Result) then
  begin
    Result.Code := 0;
    Result.Mods := 0;
  end;
end;

var
  M: TTveKeymap;
  Err: AnsiString;
  Z: TKey;
  I, Bad: Integer;
begin
  Check(TveCommandByName('find') = tcFind, 'name lookup is not case sensitive');
  Check(TveCommandByName('nosuch') = -1, 'unknown name');
  Check(TveCommandName(tcGotoMark0 + 3) = 'GotoMark3', 'mark names');
  Check(TveCommandByName('SetMark9') = tcSetMark0 + 9, 'SetMark9');
  Check(TveCommandByName('FoldToggle') = tcFoldToggle, 'fold toggle index');
  Check(TveCommandByName('FoldFromBlock') = tcFoldFromBlock, 'fold from block index');
  Check(TveCommandByName('Save') = tcSave, 'save index');
  Check(TveCommandByName('CursorBack') = tcCursorBack, 'cursor back index');
  Check(TveCommandByName('InsertDate') = tcInsertDate, 'insert date index');
  Check(TveCommandByName('FindInAllCodePages') = tcFindInAllCodePages, 'find in all code pages index');
  Check(TveCommandByName('ClearMarks') = tcClearMarks, 'clear marks index');
  Check(TveCommandByName('Calculate') = tcCalculate, 'calculate index');
  Check(TveCommandByName('SelTextEnd') = tcSelTextEnd, 'sel text end index');
  Check(TveCommandByName('DeleteBlock') = tcDeleteBlock, 'delete block index');
  Bad := 0;
  for I := 1 to tcCommandCount - 1 do
    if (TveCommandName(I) <> '') and (TveCommandByName(TveCommandName(I)) <> I) then
      Inc(Bad);
  Check(Bad = 0, 'names are unique and round-trip');
  M := TTveKeymap.Create;
  Z.Code := 0; Z.Mods := 0;
  Check(M.LoadText('Ctrl+K B = BlockBegin' + #10 + '; comment' + #10 + 'F7 = Find' + #10, Err), 'load ' + Err);
  Check(M.Lookup(K('F7')) = tcFind, 'single key');
  Check(M.Lookup(K('Ctrl+K')) = -2, 'prefix');
  Check(M.LookupChord(K('Ctrl+K'), K('B')) = tcBlockBegin, 'chord');
  Check(M.LookupChord(K('Ctrl+K'), K('X')) = -1, 'chord not bound');
  Check(M.Lookup(K('F8')) = -1, 'not bound');
  Check(not M.LoadText('F9 = NoSuchCommand', Err) and (Err = 'F9 = NoSuchCommand'), 'bad command reported');
  Check(M.LoadText('F7 =' + #10, Err), 'unbind');
  Check(M.Lookup(K('F7')) = -1, 'unbound');
  Check(M.LoadText('Ctrl+K B =' + #10, Err) and (M.Lookup(K('Ctrl+K')) = -1), 'prefix goes when its last chord goes');
  M.Free;
  Check(TveKeymapA.Lookup(K('Ctrl+Y')) = tcDeleteLine, 'A: Ctrl+Y');
  Check(TveKeymapA.Lookup(K('Ctrl+N')) = tcInsertLineBelow, 'A: Ctrl+N');
  Check(TveKeymapB.Lookup(K('Ctrl+N')) = tcBreakLineStay, 'B: Ctrl+N');
  Check(TveKeymapA.Lookup(K('Ctrl+Home')) = tcTextStart, 'A: Ctrl+Home');
  Check(TveKeymapB.Lookup(K('Ctrl+Home')) = tcWindowTop, 'B: Ctrl+Home');
  Check(TveKeymapB.LookupChord(K('Ctrl+Q'), K('F')) = tcFind, 'B: Ctrl+Q F');
  M := TTveKeymap.Create;
  Check(M.LoadText(TveKeymapA.SaveText, Err) and (M.Count = TveKeymapA.Count), 'save and load again');
  M.Free;
  Finish;
end.
