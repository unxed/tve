program t_cmds;
{ TveCmds: command names, key map text, chords, the shipped maps. }
{$mode objfpc}{$H+}
uses SysUtils, TvGeom, TvKeys, TvKeyName, TvEvents, TveDoc, TveView, TveCmds;
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
  THost = class
    Last: Integer;
    function Run(Sender: TTveSender; Cmd: Integer): Boolean;
  end;

function THost.Run(Sender: TTveSender; Cmd: Integer): Boolean;
begin
  Last := Cmd;
  Result := True;
end;

procedure Press(V: TTveView; Code, Shift: Word);
var
  E: TEvent;
begin
  E := Default(TEvent);
  E.What := evKeyDown;
  E.KeyCode := Code;
  E.ControlKeyState := Shift;
  V.HandleEvent(E);
end;

{ The lines of a shipped map text that bind a key that an earlier line binds already (to something else). }
function Rebound(const Text: AnsiString; const Allowed: array of AnsiString): AnsiString;
var
  L: TStringArray;
  Seen: array of AnsiString;
  I, J, Eq: Integer;
  Key: AnsiString;
  Ok: Boolean;
begin
  Result := '';
  Seen := nil;
  L := Text.Split([#10]);
  for I := 0 to High(L) do
  begin
    Eq := Pos(' = ', L[I]);
    if Eq = 0 then
      Continue;
    Key := Copy(L[I], 1, Eq - 1);
    for J := 0 to High(Seen) do
      if Seen[J] = Key then
      begin
        Ok := False;
        for Eq := 0 to High(Allowed) do
          if Allowed[Eq] = Key then
            Ok := True;
        if not Ok then
          Result := Result + Key + '; ';
      end;
    SetLength(Seen, Length(Seen) + 1);
    Seen[High(Seen)] := Key;
  end;
end;

var
  H: THost;
  D: TTveDoc;
  V: TTveView;
  R: TRect;
  M: TTveKeymap;
  Err, T: AnsiString;
  Z: TKey;
  I, Bad: Integer;
  OkA: Boolean;
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
  Check((TveKeymapA.Lookup(K('Alt+O')) = tcOutline) and (TveKeymapB.Lookup(K('Alt+O')) = tcOutline), 'Alt+O is the outline in both maps');
  Check(TveCommandByName('Outline') = tcOutline, 'outline name');
  Check((TveCommandByName('NavWordLeft') = tcNavWordLeft) and (TveCommandByName('SelNavWordRight') = tcSelNavWordRight), 'nav word commands have names');
  Check((TveKeymapA.Lookup(K('Ctrl+Left')) = tcWordLeft) and (TveKeymapB.Lookup(K('Ctrl+Right')) = tcWordRight), 'the shipped maps keep the word rules of the editor');
  Check((TveKeymapA.Lookup(K('Ctrl+Shift+Left')) = tcSelWordLeft) and (TveKeymapB.Lookup(K('Ctrl+Shift+Right')) = tcSelWordRight), '... also selecting');
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
  { the optional map of the word movement of the guidelines, over each of the shipped maps }
  M := TveNewKeymap(False, TveNavWordsKeymapText, Err);
  Check(Err = '', 'the words map of the guidelines loads ' + Err);
  Check((M.Lookup(K('Ctrl+Left')) = tcNavWordLeft) and (M.Lookup(K('Ctrl+Right')) = tcNavWordRight), 'nav words: Ctrl+Left, Ctrl+Right');
  Check((M.Lookup(K('Ctrl+Shift+Left')) = tcSelNavWordLeft) and (M.Lookup(K('Ctrl+Shift+Right')) = tcSelNavWordRight), 'nav words: with Shift');
  Check((M.Lookup(K('Ctrl+A')) = tcWordLeft) and (M.Lookup(K('Ctrl+Y')) = tcDeleteLine), 'nav words: the rest of map A is as it was (WordStar Ctrl+A, Ctrl+Y)');
  M.Free;
  M := TveNewKeymap(True, TveNavWordsKeymapText, Err);
  Check((Err = '') and (M.Lookup(K('Ctrl+Right')) = tcNavWordRight) and (M.Lookup(K('Ctrl+N')) = tcBreakLineStay), 'nav words over map B');
  M.Free;
  Check(TveKeymapA.Lookup(K('Ctrl+Y')) = tcDeleteLine, 'A: Ctrl+Y');
  Check(TveKeymapA.Lookup(K('Ctrl+N')) = tcInsertLineBelow, 'A: Ctrl+N');
  Check(TveKeymapB.Lookup(K('Ctrl+N')) = tcBreakLineStay, 'B: Ctrl+N');
  Check(TveKeymapA.Lookup(K('Ctrl+Home')) = tcTextStart, 'A: Ctrl+Home');
  Check(TveKeymapB.Lookup(K('Ctrl+Home')) = tcWindowTop, 'B: Ctrl+Home');
  Check(TveKeymapB.LookupChord(K('Ctrl+Q'), K('F')) = tcFind, 'B: Ctrl+Q F');
  M := TTveKeymap.Create;
  OkA := M.LoadText(TveKeymapAText, Err);
  Check(OkA, 'map A has no bad line: ' + Err);
  M.Clear;
  OkA := M.LoadText(TveKeymapBText, Err);
  Check(OkA, 'map B has no bad line: ' + Err);
  M.Free;
  M := TTveKeymap.Create;
  Check(M.LoadText(TveKeymapA.SaveText, Err) and (M.Count = TveKeymapA.Count), 'save and load again');
  M.Free;

  { --- folding all, playing the macro to the end, the hex search --- }
  Check((TveKeymapA.LookupChord(K('Ctrl+K'), K('-')) = tcFoldAll) and (TveKeymapB.LookupChord(K('Ctrl+K'), K('-')) = tcFoldAll), 'Ctrl+K - folds all in both maps');
  Check((TveKeymapA.LookupChord(K('Ctrl+K'), K('+')) = tcUnfoldAll) and (TveKeymapB.LookupChord(K('Ctrl+K'), K('+')) = tcUnfoldAll), 'Ctrl+K + unfolds all in both maps');
  Check((TveKeymapB.Lookup(K('Ctrl+Shift+Num-')) = tcFoldAll) and (TveKeymapB.Lookup(K('Ctrl+Shift+Num+')) = tcUnfoldAll), 'B: Ctrl+Shift+Num- and Num+');
  Check((TveKeymapB.Lookup(K('Ctrl+Num-')) = tcFoldCollapse) and (TveKeymapA.Lookup(K('Ctrl+Shift+Num-')) = -1), '... next to Ctrl+Num-; A has no Num keys');
  Check((TveKeymapA.LookupChord(K('Ctrl+K'), K('P')) = tcMacroPlayAll) and (TveKeymapB.LookupChord(K('Ctrl+K'), K('P')) = tcMacroPlayAll), 'Ctrl+K P plays the macro to the end in both maps');
  Check((TveKeymapA.Lookup(K('Alt+Shift+F7')) = tcHexSearch) and (TveKeymapB.Lookup(K('Alt+Shift+F7')) = tcHexSearch), 'Alt+Shift+F7 is the hex search in both maps');
  Check((TveKeymapA.Lookup(K('Shift+F7')) = tcFindNext) and (TveKeymapA.Lookup(K('Alt+F7')) = tcFindPrev) and (TveKeymapA.Lookup(K('F7')) = tcFind), '... and F7 keeps its family in A');
  { a key bound twice in a shipped text is an override that is meant, never a new binding over an old one }
  T := Rebound(TveKeymapAText, ['Ctrl+Q D', 'Ctrl+Q L']);
  Check(T = '', 'A binds no key twice by mistake: ' + T);
  T := Rebound(TveKeymapBText, ['Ctrl+Q L']);
  Check(T = '', 'B binds no key twice by mistake: ' + T);
  { in a view: the second key of a chord typed with Shift (+ is Shift+= on many keyboards) or on the keypad }
  H := THost.Create;
  D := TTveDoc.Create;
  R.Assign(0, 0, 40, 10);
  V := TTveView.Create(R, nil, nil, D);
  V.OnHostCommand := @H.Run;
  for I := 0 to 2 do
  begin
    H.Last := 0;
    Press(V, kbCtrlK, kbCtrlShift);
    case I of
      0: Press(V, Ord('+'), 0);
      1: Press(V, $0D2B, kbShift);
      2: Press(V, kbGrayPlus, 0);
    end;
    Check(H.Last = tcUnfoldAll, 'Ctrl+K + in a view, way ' + IntToStr(I));
  end;
  H.Last := 0;
  Press(V, kbCtrlK, kbCtrlShift);
  Press(V, Ord('-'), 0);
  Check(H.Last = tcFoldAll, 'Ctrl+K - in a view');
  H.Last := 0;
  Press(V, kbCtrlK, kbCtrlShift);
  Press(V, Ord('P'), kbShift);
  Check(H.Last = tcMacroPlayAll, 'Ctrl+K Shift+P in a view');
  V.Free;
  D.Free;
  H.Free;
  Finish;
end.
