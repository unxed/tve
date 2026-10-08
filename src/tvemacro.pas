{ TveMacro: a recorded macro and its text form.

  MIT.

  A macro is a list of steps: a command (by number, see TveCmds) or a piece of typed text. The text form has one step per line:

      ; a comment (also a line that starts with #)
      Find                    a command, by its name
      "hello\n"               typed text; \\ \" \n \r \t \xHH are escapes, other bytes (UTF-8) stand for themselves
      prompt "Name?"          asks the user (the view's OnPrompt) and types the answer; a cancelled prompt stops the macro
      find "x" case word      finds the next match; the options are any of case, word, regex, back, hex; no match stops the macro
      replace "x" "y" regex   replaces the next match (no match stops the macro)
      replaceall "x" "y"      replaces every match
      goto 12:5               moves the cursor to the line 12, column 5 (goto 12: the start of the line; goto +100: the byte offset 100)
      if eof                  the next step is done only when the condition holds (if not ...: when it does not); the conditions: eof, bof, eol, bol
                              (the cursor at an end of the text or of the line), blank (the line is blank), selection, at "x" (the text at the cursor
                              starts with x), match "re" (the line matches the regular expression)
      stop                    ends the playing (all the rounds) without a failure
      play "name"             plays the macro of that name of the same list once (a failure in it is a failure here)

  Blank lines are skipped. The macro commands themselves (MacroRecord, MacroPlay, MacroPlayAll) cannot be steps.

  A list of named macros (TTveMacroList) has the same text form: the steps before the first line "macro NAME" are those of the macro without a name, the
  lines after it those of NAME, up to the next "macro" line. }
unit TveMacro;

{$I tvdefs.inc}
{$H+}

interface

const
  { the kinds of steps that are no commands (TTveMacroStep.Cmd) }
  msText = 0;
  msPrompt = -1;                 { Text: the question }
  msFind = -2;                   { Text: the pattern; Flags }
  msReplace = -3;                { Text: the pattern; Repl; Flags }
  msReplaceAll = -4;
  msGoto = -5;                   { Text: "LINE", "LINE:COLUMN" (1-based) or "+OFFSET" }
  msIf = -6;                     { Text: the condition (eof, bof, eol, bol, blank, selection, at, match); Repl: its text; Flags: mfNot }
  msStop = -7;
  msPlay = -8;                   { Text: the name of the macro }
  { the search options of a step (Flags) }
  mfCase = 1; mfWord = 2; mfRegex = 4; mfBack = 8; mfHex = 16;
  mfNot = 1;                     { of an if step }

type
  TTveMacroStep = record
    Cmd: Integer;                { > 0: a command; else msText, msPrompt, msFind ... }
    Text: AnsiString;
    Repl: AnsiString;
    Flags: Integer;
  end;

  TTveMacro = class
  private
    FSteps: array of TTveMacroStep;
  public
    procedure Clear;
    function Count: Integer;
    function Step(I: Integer): TTveMacroStep;
    procedure AddCommand(Cmd: Integer);
    { Typed text; it joins the text step before it. }
    procedure AddText(const S: AnsiString);
    procedure AddPrompt(const Question: AnsiString);
    { msFind, msReplace or msReplaceAll }
    procedure AddSearch(Kind: Integer; const Pattern, Repl: AnsiString; Flags: Integer);
    { Err is the first bad line; the good lines are kept and False is returned when there is a bad one. The old steps are dropped. }
    function LoadText(const Text: AnsiString; out Err: AnsiString): Boolean;
    function SaveText: AnsiString;
    function LoadFile(const FileName: AnsiString; out Err: AnsiString): Boolean;
    function SaveFile(const FileName: AnsiString): Boolean;
  end;

  { Named macros; the one without a name ('') is always there. }
  TTveMacroList = class
  private
    FNames: array of AnsiString;
    FItems: array of TTveMacro;
  public
    constructor Create;
    destructor Destroy; override;
    { Drops every macro and leaves the one without a name, empty. }
    procedure Clear;
    function Count: Integer;
    function Name(I: Integer): AnsiString;
    function Item(I: Integer): TTveMacro;
    { The macro of a name (the case of the letters counts), nil if there is none. }
    function Find(const AName: AnsiString): TTveMacro;
    { The macro of a name; a new empty one when there is none. }
    function Get(const AName: AnsiString): TTveMacro;
    procedure Remove(const AName: AnsiString);
    { All the macros of a text (see the header); the old ones are dropped. Err is the first bad line. }
    function LoadText(const Text: AnsiString; out Err: AnsiString): Boolean;
    function SaveText: AnsiString;
    function LoadFile(const FileName: AnsiString; out Err: AnsiString): Boolean;
    function SaveFile(const FileName: AnsiString): Boolean;
  end;

{ A name of a macro: letters, digits and _ - . }
function TveGoodMacroName(const S: AnsiString): Boolean;

implementation

uses
  SysUtils, TveCmds;

const
  LF = #10;

procedure TTveMacro.Clear;
begin
  FSteps := nil;
end;

function TTveMacro.Count: Integer;
begin
  Result := Length(FSteps);
end;

function TTveMacro.Step(I: Integer): TTveMacroStep;
begin
  Result := FSteps[I];
end;

procedure TTveMacro.AddCommand(Cmd: Integer);
begin
  AddSearch(Cmd, '', '', 0);
end;

procedure TTveMacro.AddPrompt(const Question: AnsiString);
begin
  AddSearch(msPrompt, Question, '', 0);
end;

procedure TTveMacro.AddSearch(Kind: Integer; const Pattern, Repl: AnsiString; Flags: Integer);
begin
  SetLength(FSteps, Length(FSteps) + 1);
  FSteps[High(FSteps)].Cmd := Kind;
  FSteps[High(FSteps)].Text := Pattern;
  FSteps[High(FSteps)].Repl := Repl;
  FSteps[High(FSteps)].Flags := Flags;
end;

procedure TTveMacro.AddText(const S: AnsiString);
begin
  if S = '' then
    Exit;
  if (Length(FSteps) > 0) and (FSteps[High(FSteps)].Cmd = 0) then
    FSteps[High(FSteps)].Text := FSteps[High(FSteps)].Text + S
  else
    AddSearch(msText, S, '', 0);
end;

function HexVal(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - 48;
    'a'..'f': Result := Ord(C) - 87;
    'A'..'F': Result := Ord(C) - 55;
  else
    Result := -1;
  end;
end;

{ A quoted text that starts at Line[I]: S is the text between the quotes and I goes past the closing quote; False if it is not well formed. }
function NextQuoted(const Line: AnsiString; var I: Integer; out S: AnsiString): Boolean;
var
  H1, H2: Integer;
  C: Char;
begin
  S := '';
  Result := False;
  if (I > Length(Line)) or (Line[I] <> '"') then
    Exit;
  Inc(I);
  while I <= Length(Line) do
  begin
    C := Line[I];
    if C = '"' then
    begin
      Inc(I);
      Exit(True);
    end;
    if C = '\' then
    begin
      Inc(I);
      if I > Length(Line) then
        Exit;
      case Line[I] of
        '\': S := S + '\';
        '"': S := S + '"';
        'n': S := S + #10;
        'r': S := S + #13;
        't': S := S + #9;
        'x':
          begin
            if I + 2 > Length(Line) then
              Exit;
            H1 := HexVal(Line[I + 1]);
            H2 := HexVal(Line[I + 2]);
            if (H1 < 0) or (H2 < 0) then
              Exit;
            S := S + Chr(H1 * 16 + H2);
            Inc(I, 2);
          end;
      else
        Exit;
      end;
    end
    else
      S := S + C;
    Inc(I);
  end;
end;

{ Line = "...": the text between the quotes; False if it is not well formed. }
function ParseQuoted(const Line: AnsiString; out S: AnsiString): Boolean;
var
  I: Integer;
begin
  I := 1;
  Result := NextQuoted(Line, I, S) and (I = Length(Line) + 1);
end;

const
  FlagNames: array[0..4] of AnsiString = ('case', 'word', 'regex', 'back', 'hex');
  KindNames: array[1..4] of AnsiString = ('prompt', 'find', 'replace', 'replaceall');
  CondNames: array[0..7] of AnsiString = ('eof', 'bof', 'eol', 'bol', 'blank', 'selection', 'at', 'match');

function TveGoodMacroName(const S: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not (S[I] in ['a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.']) then
      Exit(False);
end;

procedure SkipBlanks(const Line: AnsiString; var I: Integer);
begin
  while (I <= Length(Line)) and (Line[I] in [' ', #9]) do
    Inc(I);
end;

{ "LINE", "LINE:COLUMN" (1-based) or "+OFFSET" }
function GoodPlace(const S: AnsiString): Boolean;
var
  I, Colons, Digits: Integer;
begin
  Result := False;
  if S = '' then
    Exit;
  Colons := 0;
  Digits := 0;
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9'] then
      Inc(Digits)
    else if (S[I] = ':') and (I > 1) and (I < Length(S)) and (S[1] <> '+') then
      Inc(Colons)
    else if not ((S[I] = '+') and (I = 1)) then
      Exit;
  Result := (Colons <= 1) and (Digits > 0);
end;

{ "prompt ...", "find ...", "replace ...", "replaceall ...", "goto ..." as a step; False if Line is none of them or is not well formed. }
function ParseSearch(M: TTveMacro; const Line: AnsiString): Boolean;
var
  I, J, Kind, Flags, F: Integer;
  Word_, Pat, Repl: AnsiString;
begin
  Result := False;
  I := 1;
  while (I <= Length(Line)) and (Line[I] in ['a'..'z', 'A'..'Z']) do
    Inc(I);
  Word_ := LowerCase(Copy(Line, 1, I - 1));
  if Word_ = 'stop' then
  begin
    Result := Trim(Copy(Line, I, MaxInt)) = '';
    if Result then
      M.AddSearch(msStop, '', '', 0);
    Exit;
  end;
  if Word_ = 'play' then
  begin
    SkipBlanks(Line, I);
    Result := NextQuoted(Line, I, Pat) and (I = Length(Line) + 1) and TveGoodMacroName(Pat);
    if Result then
      M.AddSearch(msPlay, Pat, '', 0);
    Exit;
  end;
  if Word_ = 'if' then
  begin
    Flags := 0;
    SkipBlanks(Line, I);
    J := I;
    while (I <= Length(Line)) and (Line[I] in ['a'..'z', 'A'..'Z']) do
      Inc(I);
    Word_ := LowerCase(Copy(Line, J, I - J));
    if Word_ = 'not' then
    begin
      Flags := mfNot;
      SkipBlanks(Line, I);
      J := I;
      while (I <= Length(Line)) and (Line[I] in ['a'..'z', 'A'..'Z']) do
        Inc(I);
      Word_ := LowerCase(Copy(Line, J, I - J));
    end;
    F := -1;
    for J := 0 to High(CondNames) do
      if Word_ = CondNames[J] then
        F := J;
    if F < 0 then
      Exit;
    Repl := '';
    SkipBlanks(Line, I);
    if F >= 6 then                       { at "x", match "re" }
    begin
      if not NextQuoted(Line, I, Repl) or (Repl = '') then
        Exit;
      SkipBlanks(Line, I);
    end;
    Result := I > Length(Line);
    if Result then
      M.AddSearch(msIf, Word_, Repl, Flags);
    Exit;
  end;
  if Word_ = 'goto' then
  begin
    Pat := Trim(Copy(Line, I, MaxInt));
    Result := GoodPlace(Pat) and (I <= Length(Line)) and (Line[I] in [' ', #9]);
    if Result then
      M.AddSearch(msGoto, Pat, '', 0);
    Exit;
  end;
  Kind := 0;
  for J := 1 to 4 do
    if Word_ = KindNames[J] then
      Kind := -J;
  if Kind = 0 then
    Exit;
  SkipBlanks(Line, I);
  if not NextQuoted(Line, I, Pat) then
    Exit;
  Repl := '';
  if Kind <= msReplace then
  begin
    SkipBlanks(Line, I);
    if not NextQuoted(Line, I, Repl) then
      Exit;
  end;
  Flags := 0;
  SkipBlanks(Line, I);
  while I <= Length(Line) do
  begin
    J := I;
    while (I <= Length(Line)) and not (Line[I] in [' ', #9]) do
      Inc(I);
    Word_ := LowerCase(Copy(Line, J, I - J));
    F := -1;
    for J := 0 to High(FlagNames) do
      if Word_ = FlagNames[J] then
        F := J;
    if (F < 0) or (Kind = msPrompt) then
      Exit;
    Flags := Flags or (1 shl F);
    SkipBlanks(Line, I);
  end;
  M.AddSearch(Kind, Pat, Repl, Flags);
  Result := True;
end;

function Quote(const S: AnsiString): AnsiString;
var
  I: Integer;
  C, E: Char;
begin
  Result := '"';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    E := #0;
    case C of
      '\', '"': E := C;
      #10: E := 'n';
      #13: E := 'r';
      #9: E := 't';
    end;
    if E <> #0 then
      Result := Result + '\' + E
    else if (C < ' ') or (C = #127) then
      Result := Result + '\x' + IntToHex(Ord(C), 2)
    else
      Result := Result + C;
  end;
  Result := Result + '"';
end;

function TTveMacro.LoadText(const Text: AnsiString; out Err: AnsiString): Boolean;
var
  P, E, Cmd: Integer;
  Line, S: AnsiString;
  Bad: Boolean;
begin
  Clear;
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
    Bad := False;
    if Line[1] = '"' then
    begin
      if ParseQuoted(Line, S) then
        AddText(S)
      else
        Bad := True;
    end
    else if ParseSearch(Self, Line) then
    else
    begin
      Cmd := TveCommandByName(Line);
      if (Cmd <= 0) or (Cmd = tcMacroRecord) or (Cmd = tcMacroPlay) or (Cmd = tcMacroPlayAll) then
        Bad := True
      else
        AddCommand(Cmd);
    end;
    if Bad then
    begin
      if Result then
        Err := Line;
      Result := False;
    end;
  end;
end;

function TTveMacro.SaveText: AnsiString;
var
  I, J: Integer;
  St: TTveMacroStep;
begin
  Result := '';
  for I := 0 to High(FSteps) do
  begin
    St := FSteps[I];
    if St.Cmd = msText then
      Result := Result + Quote(St.Text)
    else if St.Cmd > 0 then
      Result := Result + TveCommandName(St.Cmd)
    else if St.Cmd = msGoto then
      Result := Result + 'goto ' + St.Text
    else if St.Cmd = msStop then
      Result := Result + 'stop'
    else if St.Cmd = msPlay then
      Result := Result + 'play ' + Quote(St.Text)
    else if St.Cmd = msIf then
    begin
      Result := Result + 'if ';
      if St.Flags and mfNot <> 0 then
        Result := Result + 'not ';
      Result := Result + St.Text;
      if St.Repl <> '' then
        Result := Result + ' ' + Quote(St.Repl);
    end
    else
    begin
      Result := Result + KindNames[-St.Cmd] + ' ' + Quote(St.Text);
      if St.Cmd <= msReplace then
        Result := Result + ' ' + Quote(St.Repl);
      for J := 0 to High(FlagNames) do
        if St.Flags and (1 shl J) <> 0 then
          Result := Result + ' ' + FlagNames[J];
    end;
    Result := Result + LF;
  end;
end;

function TTveMacro.LoadFile(const FileName: AnsiString; out Err: AnsiString): Boolean;
var
  T: AnsiString;
begin
  if not TveReadTextFile(FileName, T) then
  begin
    Clear;
    Err := FileName;
    Exit(False);
  end;
  if Copy(T, 1, 3) = #$EF#$BB#$BF then
    Delete(T, 1, 3);
  Result := LoadText(T, Err);
end;

function TTveMacro.SaveFile(const FileName: AnsiString): Boolean;
begin
  Result := TveWriteTextFile(FileName, SaveText);
end;

{ --- the list of named macros --- }

constructor TTveMacroList.Create;
begin
  inherited Create;
  Clear;
end;

destructor TTveMacroList.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    FItems[I].Free;
  inherited Destroy;
end;

procedure TTveMacroList.Clear;
var
  I: Integer;
begin
  { the macro without a name stays the same object: a view holds it }
  for I := 1 to High(FItems) do
    FItems[I].Free;
  if Length(FItems) = 0 then
  begin
    SetLength(FItems, 1);
    FItems[0] := TTveMacro.Create;
  end;
  SetLength(FItems, 1);
  SetLength(FNames, 1);
  FNames[0] := '';
  FItems[0].Clear;
end;

function TTveMacroList.Count: Integer;
begin
  Result := Length(FItems);
end;

function TTveMacroList.Name(I: Integer): AnsiString;
begin
  Result := FNames[I];
end;

function TTveMacroList.Item(I: Integer): TTveMacro;
begin
  Result := FItems[I];
end;

function TTveMacroList.Find(const AName: AnsiString): TTveMacro;
var
  I: Integer;
begin
  for I := 0 to High(FNames) do
    if FNames[I] = AName then
      Exit(FItems[I]);
  Result := nil;
end;

function TTveMacroList.Get(const AName: AnsiString): TTveMacro;
begin
  Result := Find(AName);
  if Result <> nil then
    Exit;
  Result := TTveMacro.Create;
  SetLength(FItems, Length(FItems) + 1);
  SetLength(FNames, Length(FNames) + 1);
  FItems[High(FItems)] := Result;
  FNames[High(FNames)] := AName;
end;

procedure TTveMacroList.Remove(const AName: AnsiString);
var
  I, J: Integer;
begin
  if AName = '' then
  begin
    FItems[0].Clear;
    Exit;
  end;
  for I := 1 to High(FNames) do
    if FNames[I] = AName then
    begin
      FItems[I].Free;
      for J := I to High(FNames) - 1 do
      begin
        FNames[J] := FNames[J + 1];
        FItems[J] := FItems[J + 1];
      end;
      SetLength(FNames, Length(FNames) - 1);
      SetLength(FItems, Length(FItems) - 1);
      Exit;
    end;
end;

function TTveMacroList.LoadText(const Text: AnsiString; out Err: AnsiString): Boolean;
var
  P, E: Integer;
  Line, Cur, Part, E2: AnsiString;

  procedure Flush;
  begin
    if not Get(Cur).LoadText(Part, E2) and Result then
    begin
      Err := E2;
      Result := False;
    end;
    Part := '';
  end;

begin
  Clear;
  Result := True;
  Err := '';
  Cur := '';
  Part := '';
  P := 1;
  while P <= Length(Text) do
  begin
    E := P;
    while (E <= Length(Text)) and (Text[E] <> #10) do
      Inc(E);
    Line := Trim(Copy(Text, P, E - P));
    P := E + 1;
    if LowerCase(Copy(Line, 1, 6)) = 'macro ' then
    begin
      Flush;
      Cur := Trim(Copy(Line, 7, MaxInt));
      if not TveGoodMacroName(Cur) then
      begin
        if Result then
          Err := Line;
        Result := False;
        Cur := '';
      end
      else
        Get(Cur);
      Continue;
    end;
    Part := Part + Line + LF;
  end;
  Flush;
end;

function TTveMacroList.SaveText: AnsiString;
var
  I: Integer;
begin
  Result := FItems[0].SaveText;
  for I := 1 to High(FItems) do
    Result := Result + 'macro ' + FNames[I] + LF + FItems[I].SaveText;
end;

function TTveMacroList.LoadFile(const FileName: AnsiString; out Err: AnsiString): Boolean;
var
  T: AnsiString;
begin
  if not TveReadTextFile(FileName, T) then
  begin
    Clear;
    Err := FileName;
    Exit(False);
  end;
  if Copy(T, 1, 3) = #$EF#$BB#$BF then
    Delete(T, 1, 3);
  Result := LoadText(T, Err);
end;

function TTveMacroList.SaveFile(const FileName: AnsiString): Boolean;
begin
  Result := TveWriteTextFile(FileName, SaveText);
end;

end.
