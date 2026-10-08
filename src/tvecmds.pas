{ TveCmds: the editor commands, their names, and the key maps.

  MIT.

  A command is a number (tc...) with a name (the name is used in key map files, in macros, in menus of the host). A key map turns a key or a chord of two keys
  (Ctrl+K B) into a command. Two maps are shipped, because the two editors that tve replaces conflict in some keys: TveKeymapA (the style of Double-Commander-like
  file manager editors: Ctrl+Y deletes the line, Alt+Backspace undoes) and TveKeymapB (the style of the Borland IDE: Ctrl+K and Ctrl+Q chords). A map is text, one
  binding per line: "Ctrl+K B = BlockBegin"; a line that starts with ; or # is a comment; "Key = " with an empty command removes a binding. }
unit TveCmds;

{$I tvdefs.inc}
{$H+}

interface

uses
  TvKeys;

const
  tcNone = 0;
  { moving }
  tcLeft = 1; tcRight = 2; tcUp = 3; tcDown = 4; tcPageUp = 5; tcPageDown = 6;
  tcHome = 7; tcEnd = 8; tcWordLeft = 9; tcWordRight = 10; tcTextStart = 11; tcTextEnd = 12;
  tcWindowTop = 13; tcWindowBottom = 14; tcScrollUp = 15; tcScrollDown = 16;
  { the same, extending the selection }
  tcSelLeft = 20; tcSelRight = 21; tcSelUp = 22; tcSelDown = 23; tcSelPageUp = 24; tcSelPageDown = 25;
  tcSelHome = 26; tcSelEnd = 27; tcSelWordLeft = 28; tcSelWordRight = 29; tcSelTextStart = 30; tcSelTextEnd = 31;
  { editing }
  tcNewLine = 40; tcTab = 41; tcBackspace = 42; tcDelete = 43; tcDeleteLine = 44; tcDeleteToEol = 45; tcDeleteToBol = 46;
  tcDeleteWordRight = 47; tcDeleteWordLeft = 48; tcInsertLineBelow = 49; tcInsertLineAbove = 50; tcDuplicateLine = 51;
  tcBreakLineStay = 52; tcJoinLine = 53; tcToggleInsert = 54; tcUndo = 55; tcRedo = 56;
  { clipboard }
  tcCopy = 60; tcCut = 61; tcPaste = 62; tcDeleteBlock = 63;
  { blocks }
  tcBlockBegin = 70; tcBlockEnd = 71; tcSelectAll = 72; tcSelectLine = 73; tcSelectWord = 74; tcHideBlock = 75;
  tcColumnBlock = 76; tcLineBlock = 77; tcStreamBlock = 78; tcGotoBlockBegin = 79; tcGotoBlockEnd = 80;
  tcCopyBlockHere = 81; tcMoveBlockHere = 82; tcIndent = 83; tcUnindent = 84; tcUpperCase = 85; tcLowerCase = 86;
  tcTitleCase = 87; tcToggleCase = 88; tcSortAsc = 89; tcSortDesc = 90; tcWriteBlock = 91; tcReadBlock = 92;
  tcCalculate = 93; tcFormatParagraph = 94; tcTrimTrailing = 95; tcExpandTabs = 96; tcTabify = 97;
  { searching }
  tcFind = 110; tcReplace = 111; tcFindNext = 112; tcFindPrev = 113; tcGotoLine = 114; tcMatchBracket = 115;
  tcFindInAllCodePages = 116; tcHexSearch = 117;
  { bookmarks: tcSetMark0 + N, tcGotoMark0 + N }
  tcSetMark0 = 120; tcGotoMark0 = 130; tcClearMarks = 140;
  { insertion }
  tcInsertDate = 150; tcInsertTime = 151; tcInsertChar = 152; tcCompletion = 153; tcTemplate = 154;
  tcMacroRecord = 155; tcMacroPlay = 156; tcDrawMode = 157; tcOpenAtCursor = 158;
  { folding }
  tcFoldToggle = 165; tcFoldCollapse = 166; tcFoldExpand = 167; tcFoldFromBlock = 168;
  { the file }
  tcSave = 170; tcSaveAs = 171; tcReload = 172; tcClose = 173; tcCursorBack = 174; tcWrap = 175;
  tcCommandCount = 180;

type
  TTveChord = record
    First, Second: TKey;     { Second.Code = 0: a single key }
  end;

  TTveKeymap = class
  private
    FKeys: array of TTveChord;
    FCmds: array of Integer;
    FPrefixes: array of TKey;
  public
    procedure Clear;
    procedure Bind(const First: TKey; const Second: TKey; Cmd: Integer);
    procedure Unbind(const First: TKey; const Second: TKey);
    { Applies the text of a map; Err names the first bad line and False is returned when there is one (the good lines are applied). }
    function LoadText(const Text: AnsiString; out Err: AnsiString): Boolean;
    function SaveText: AnsiString;
    { A single key: the command, -1 if it is bound to nothing, -2 if it starts a chord. }
    function Lookup(const K: TKey): Integer;
    function LookupChord(const First, Second: TKey): Integer;
    function IsPrefix(const K: TKey): Boolean;
    function Count: Integer;
  end;

function TveCommandName(Cmd: Integer): AnsiString;
function TveCommandByName(const Name: AnsiString): Integer;     { -1 if unknown }
function TveKeymapA: TTveKeymap;
function TveKeymapB: TTveKeymap;
function TveKeymapAText: AnsiString;
function TveKeymapBText: AnsiString;

implementation

uses
  SysUtils, TvKeyName;

const
  LF = #10;

  Names: array[0..tcCommandCount - 1] of AnsiString = (
    '', 'Left', 'Right', 'Up', 'Down', 'PageUp', 'PageDown', 'Home', 'End', 'WordLeft',
    'WordRight', 'TextStart', 'TextEnd', 'WindowTop', 'WindowBottom', 'ScrollUp', 'ScrollDown', '', '', '',
    'SelLeft', 'SelRight', 'SelUp', 'SelDown', 'SelPageUp', 'SelPageDown', 'SelHome', 'SelEnd', 'SelWordLeft', 'SelWordRight',
    'SelTextStart', 'SelTextEnd', '', '', '', '', '', '', '', '',
    'NewLine', 'Tab', 'Backspace', 'Delete', 'DeleteLine', 'DeleteToEol', 'DeleteToBol', 'DeleteWordRight', 'DeleteWordLeft', 'InsertLineBelow',
    'InsertLineAbove', 'DuplicateLine', 'BreakLineStay', 'JoinLine', 'ToggleInsert', 'Undo', 'Redo', '', '', '',
    'Copy', 'Cut', 'Paste', 'DeleteBlock', '', '', '', '', '', '',
    'BlockBegin', 'BlockEnd', 'SelectAll', 'SelectLine', 'SelectWord', 'HideBlock', 'ColumnBlock', 'LineBlock', 'StreamBlock', 'GotoBlockBegin',
    'GotoBlockEnd', 'CopyBlockHere', 'MoveBlockHere', 'Indent', 'Unindent', 'UpperCase', 'LowerCase', 'TitleCase', 'ToggleCase', 'SortAsc',
    'SortDesc', 'WriteBlock', 'ReadBlock', 'Calculate', 'FormatParagraph', 'TrimTrailing', 'ExpandTabs', 'Tabify', '', '',
    '', '', '', '', '', '', '', '', '', '',
    'Find', 'Replace', 'FindNext', 'FindPrev', 'GotoLine', 'MatchBracket', 'FindInAllCodePages', 'HexSearch', '', '',
    'SetMark0', 'SetMark1', 'SetMark2', 'SetMark3', 'SetMark4', 'SetMark5', 'SetMark6', 'SetMark7', 'SetMark8', 'SetMark9',
    'GotoMark0', 'GotoMark1', 'GotoMark2', 'GotoMark3', 'GotoMark4', 'GotoMark5', 'GotoMark6', 'GotoMark7', 'GotoMark8', 'GotoMark9',
    'ClearMarks', '', '', '', '', '', '', '', '', '',
    'InsertDate', 'InsertTime', 'InsertChar', 'Completion', 'Template', 'MacroRecord', 'MacroPlay', 'DrawMode', 'OpenAtCursor', '',
    '', '', '', '', '', 'FoldToggle', 'FoldCollapse', 'FoldExpand', 'FoldFromBlock', '',
    'Save', 'SaveAs', 'Reload', 'Close', 'CursorBack', 'Wrap', '', '', '', '');

function TveCommandName(Cmd: Integer): AnsiString;
begin
  if (Cmd >= 0) and (Cmd < tcCommandCount) then
    Result := Names[Cmd]
  else
    Result := '';
end;

function TveCommandByName(const Name: AnsiString): Integer;
var
  I: Integer;
begin
  Result := -1;
  if Name = '' then
    Exit;
  for I := 1 to tcCommandCount - 1 do
    if SameText(Names[I], Name) then
      Exit(I);
end;

function SameKey(const A, B: TKey): Boolean;
begin
  Result := (A.Code = B.Code) and (A.Mods = B.Mods);
end;

procedure TTveKeymap.Clear;
begin
  FKeys := nil;
  FCmds := nil;
  FPrefixes := nil;
end;

function TTveKeymap.Count: Integer;
begin
  Result := Length(FKeys);
end;

function TTveKeymap.IsPrefix(const K: TKey): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FPrefixes) do
    if SameKey(FPrefixes[I], K) then
      Exit(True);
  Result := False;
end;

procedure TTveKeymap.Unbind(const First: TKey; const Second: TKey);
var
  I, J: Integer;
begin
  for I := 0 to High(FKeys) do
    if SameKey(FKeys[I].First, First) and SameKey(FKeys[I].Second, Second) then
    begin
      for J := I to High(FKeys) - 1 do
      begin
        FKeys[J] := FKeys[J + 1];
        FCmds[J] := FCmds[J + 1];
      end;
      SetLength(FKeys, Length(FKeys) - 1);
      SetLength(FCmds, Length(FCmds) - 1);
      Break;
    end;
  { the prefixes are the first keys of the chords that are left }
  FPrefixes := nil;
  for I := 0 to High(FKeys) do
    if (FKeys[I].Second.Code <> 0) and not IsPrefix(FKeys[I].First) then
    begin
      SetLength(FPrefixes, Length(FPrefixes) + 1);
      FPrefixes[High(FPrefixes)] := FKeys[I].First;
    end;
end;

procedure TTveKeymap.Bind(const First: TKey; const Second: TKey; Cmd: Integer);
var
  I: Integer;
begin
  for I := 0 to High(FKeys) do
    if SameKey(FKeys[I].First, First) and SameKey(FKeys[I].Second, Second) then
    begin
      FCmds[I] := Cmd;
      Exit;
    end;
  I := Length(FKeys);
  SetLength(FKeys, I + 1);
  SetLength(FCmds, I + 1);
  FKeys[I].First := First;
  FKeys[I].Second := Second;
  FCmds[I] := Cmd;
  if (Second.Code <> 0) and not IsPrefix(First) then
  begin
    SetLength(FPrefixes, Length(FPrefixes) + 1);
    FPrefixes[High(FPrefixes)] := First;
  end;
end;

function TTveKeymap.Lookup(const K: TKey): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FKeys) do
    if (FKeys[I].Second.Code = 0) and SameKey(FKeys[I].First, K) then
      Exit(FCmds[I]);
  if IsPrefix(K) then
    Result := -2
  else
    Result := -1;
end;

function TTveKeymap.LookupChord(const First, Second: TKey): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FKeys) do
    if SameKey(FKeys[I].First, First) and SameKey(FKeys[I].Second, Second) then
      Exit(FCmds[I]);
  Result := -1;
end;

function TTveKeymap.LoadText(const Text: AnsiString; out Err: AnsiString): Boolean;
var
  P, E, EqPos, Sp: Integer;
  Line, Left, Right, A, B: AnsiString;
  K1, K2: TKey;
  Cmd: Integer;
begin
  Result := True;
  Err := '';
  P := 1;
  while P <= Length(Text) do
  begin
    E := P;
    while (E <= Length(Text)) and (Text[E] <> #10) do
      Inc(E);
    Line := Trim(Copy(Text, P, E - P));
    P := E + 1;
    if (Line = '') or (Line[1] in [';', '#']) then
      Continue;
    EqPos := Pos(' = ', Line);
    if EqPos = 0 then
    begin
      if (Length(Line) > 2) and (Copy(Line, Length(Line) - 1, 2) = ' =') then
        EqPos := Length(Line) - 1
      else
      begin
        if Result then Err := Line;
        Result := False;
        Continue;
      end;
    end;
    Left := Trim(Copy(Line, 1, EqPos - 1));
    Right := Trim(Copy(Line, EqPos + 2, MaxInt));
    Sp := Pos(' ', Left);
    if Sp > 0 then
    begin
      A := Copy(Left, 1, Sp - 1);
      B := Trim(Copy(Left, Sp + 1, MaxInt));
    end
    else
    begin
      A := Left;
      B := '';
    end;
    if not StrToKey(A, K1) or ((B <> '') and not StrToKey(B, K2)) then
    begin
      if Result then Err := Line;
      Result := False;
      Continue;
    end;
    if B = '' then
    begin
      K2.Code := 0;
      K2.Mods := 0;
    end;
    if Right = '' then
    begin
      Unbind(K1, K2);
      Continue;
    end;
    Cmd := TveCommandByName(Right);
    if Cmd < 0 then
    begin
      if Result then Err := Line;
      Result := False;
      Continue;
    end;
    Bind(K1, K2, Cmd);
  end;
end;

function TTveKeymap.SaveText: AnsiString;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FKeys) do
  begin
    Result := Result + KeyToStr(FKeys[I].First);
    if FKeys[I].Second.Code <> 0 then
      Result := Result + ' ' + KeyToStr(FKeys[I].Second);
    Result := Result + ' = ' + TveCommandName(FCmds[I]) + LF;
  end;
end;

{ --- the shipped maps --- }

const
  CommonText =
    'Left = Left' + LF + 'Right = Right' + LF + 'Up = Up' + LF + 'Down = Down' + LF + 'PgUp = PageUp' + LF + 'PgDn = PageDown' + LF +
    'Home = Home' + LF + 'End = End' + LF + 'Ctrl+Left = WordLeft' + LF + 'Ctrl+Right = WordRight' + LF +
    'Shift+Left = SelLeft' + LF + 'Shift+Right = SelRight' + LF + 'Shift+Up = SelUp' + LF + 'Shift+Down = SelDown' + LF +
    'Shift+PgUp = SelPageUp' + LF + 'Shift+PgDn = SelPageDown' + LF + 'Shift+Home = SelHome' + LF + 'Shift+End = SelEnd' + LF +
    'Ctrl+Shift+Left = SelWordLeft' + LF + 'Ctrl+Shift+Right = SelWordRight' + LF +
    'Ctrl+PgUp = TextStart' + LF + 'Ctrl+PgDn = TextEnd' + LF +
    'Enter = NewLine' + LF + 'Tab = Tab' + LF + 'Backspace = Backspace' + LF + 'Del = Delete' + LF + 'Ins = ToggleInsert' + LF +
    'Ctrl+Ins = Copy' + LF + 'Shift+Del = Cut' + LF + 'Shift+Ins = Paste' + LF +
    'Ctrl+S = Left' + LF + 'Ctrl+D = Right' + LF + 'Ctrl+E = Up' + LF + 'Ctrl+X = Down' + LF + 'Ctrl+R = PageUp' + LF + 'Ctrl+C = PageDown' + LF +
    'Ctrl+A = WordLeft' + LF + 'Ctrl+F = WordRight' + LF + 'Ctrl+G = Delete' + LF + 'Ctrl+H = Backspace' + LF +
    'Ctrl+Y = DeleteLine' + LF + 'Ctrl+T = DeleteWordRight' + LF + 'Ctrl+Backspace = DeleteWordLeft' + LF +
    'Ctrl+L = FindNext' + LF + 'Ctrl+Space = Completion' + LF + 'Ctrl+@ = Completion' + LF + 'Ctrl+V = ToggleInsert' + LF +
    'Ctrl+K B = BlockBegin' + LF + 'Ctrl+K K = BlockEnd' + LF + 'Ctrl+K L = LineBlock' + LF + 'Ctrl+K T = SelectWord' + LF +
    'Ctrl+K H = HideBlock' + LF + 'Ctrl+K C = CopyBlockHere' + LF + 'Ctrl+K V = MoveBlockHere' + LF + 'Ctrl+K Y = DeleteBlock' + LF +
    'Ctrl+K Z = FoldToggle' + LF + 'Alt+U = InsertChar' + LF + 'Alt+W = Wrap' + LF + 'Ctrl+K W = WriteBlock' + LF + 'Ctrl+K R = ReadBlock' + LF + 'Ctrl+K I = Indent' + LF + 'Ctrl+K U = Unindent' + LF +
    'Ctrl+Q B = GotoBlockBegin' + LF + 'Ctrl+Q K = GotoBlockEnd' + LF + 'Ctrl+Q F = Find' + LF + 'Ctrl+Q A = Replace' + LF +
    'Ctrl+Q G = GotoLine' + LF + 'Ctrl+Q Y = DeleteToEol' + LF + 'Ctrl+Q [ = MatchBracket' + LF + 'Ctrl+Q ] = MatchBracket' + LF +
    'Ctrl+Q S = Home' + LF + 'Ctrl+Q D = End' + LF + 'Ctrl+Q R = TextStart' + LF + 'Ctrl+Q C = TextEnd' + LF +
    'Ctrl+Q 0 = GotoMark0' + LF + 'Ctrl+Q 1 = GotoMark1' + LF + 'Ctrl+Q 2 = GotoMark2' + LF + 'Ctrl+Q 3 = GotoMark3' + LF + 'Ctrl+Q 4 = GotoMark4' + LF +
    'Ctrl+Q 5 = GotoMark5' + LF + 'Ctrl+Q 6 = GotoMark6' + LF + 'Ctrl+Q 7 = GotoMark7' + LF + 'Ctrl+Q 8 = GotoMark8' + LF + 'Ctrl+Q 9 = GotoMark9' + LF +
    'Ctrl+K 0 = SetMark0' + LF + 'Ctrl+K 1 = SetMark1' + LF + 'Ctrl+K 2 = SetMark2' + LF + 'Ctrl+K 3 = SetMark3' + LF + 'Ctrl+K 4 = SetMark4' + LF +
    'Ctrl+K 5 = SetMark5' + LF + 'Ctrl+K 6 = SetMark6' + LF + 'Ctrl+K 7 = SetMark7' + LF + 'Ctrl+K 8 = SetMark8' + LF + 'Ctrl+K 9 = SetMark9' + LF;

  { A: Ctrl+U/Alt+Backspace undo, Ctrl+N inserts a line, Ctrl+Home/End are the text ends, F7 searches }
  ATextOnly =
    'Alt+Backspace = Undo' + LF + 'Ctrl+U = Undo' + LF + 'Ctrl+Shift+Backspace = Redo' + LF + 'Ctrl+N = InsertLineBelow' + LF +
    'Ctrl+Home = TextStart' + LF + 'Ctrl+End = TextEnd' + LF + 'Ctrl+W = ScrollUp' + LF + 'Ctrl+Z = ScrollDown' + LF +
    'Ctrl+Shift+Home = SelTextStart' + LF + 'Ctrl+Shift+End = SelTextEnd' + LF +
    'F7 = Find' + LF + 'Ctrl+F7 = Replace' + LF + 'Shift+F7 = FindNext' + LF + 'Alt+F7 = FindPrev' + LF + 'Alt+G = GotoLine' + LF +
    'Ctrl+Del = DeleteBlock' + LF + 'Alt+Right = Indent' + LF + 'Alt+Left = Unindent' + LF + 'Alt+T = SortAsc' + LF + 'Alt+Ins = Calculate' + LF +
    'Ctrl+Q D = InsertDate' + LF + 'Ctrl+Q T = InsertTime' + LF + 'Ctrl+K A = SelectAll' + LF + 'Ctrl+K S = SortAsc' + LF +
    'Ctrl+Q L = Undo' + LF + 'Ctrl+Enter = OpenAtCursor' + LF + 'F2 = Save' + LF + 'Ctrl+Q M = DrawMode' + LF + 'Ctrl+J = Template' + LF;

  { B: Ctrl+U undo, Ctrl+N breaks the line and stays, Ctrl+Home/End are the window ends }
  BTextOnly =
    'Alt+Backspace = Undo' + LF + 'Ctrl+U = Undo' + LF + 'Shift+Alt+Backspace = Redo' + LF + 'Ctrl+N = BreakLineStay' + LF +
    'Ctrl+Home = WindowTop' + LF + 'Ctrl+End = WindowBottom' + LF + 'Ctrl+Q E = WindowTop' + LF + 'Ctrl+Q X = WindowBottom' + LF +
    'Ctrl+Q P = CursorBack' + LF + 'Ctrl+Q H = DeleteToBol' + LF + 'Ctrl+Q L = Undo' + LF +
    'Ctrl+K N = UpperCase' + LF + 'Ctrl+K O = LowerCase' + LF + 'Ctrl+K A = FoldFromBlock' + LF + 'Ctrl+K S = Save' + LF +
    'Ctrl+J = Template' + LF + 'Ctrl+Enter = OpenAtCursor' + LF +
    'F7 = Find' + LF + 'F2 = Save' + LF + 'Ctrl+Num- = FoldCollapse' + LF + 'Ctrl+Num+ = FoldExpand' + LF;

var
  MapA, MapB: TTveKeymap;

function TveKeymapAText: AnsiString;
begin
  Result := CommonText + ATextOnly;
end;

function TveKeymapBText: AnsiString;
begin
  Result := CommonText + BTextOnly;
end;

function Build(const Text: AnsiString): TTveKeymap;
var
  Err: AnsiString;
begin
  Result := TTveKeymap.Create;
  Result.LoadText(Text, Err);
end;

function TveKeymapA: TTveKeymap;
begin
  if MapA = nil then
    MapA := Build(TveKeymapAText);
  Result := MapA;
end;

function TveKeymapB: TTveKeymap;
begin
  if MapB = nil then
    MapB := Build(TveKeymapBText);
  Result := MapB;
end;

finalization
  MapA.Free;
  MapB.Free;
end.
