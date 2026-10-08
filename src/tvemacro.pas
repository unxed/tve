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

  Blank lines are skipped. The macro commands themselves (MacroRecord, MacroPlay, MacroPlayAll) cannot be steps. }
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
  { the search options of a step (Flags) }
  mfCase = 1; mfWord = 2; mfRegex = 4; mfBack = 8; mfHex = 16;

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

procedure SkipBlanks(const Line: AnsiString; var I: Integer);
begin
  while (I <= Length(Line)) and (Line[I] in [' ', #9]) do
    Inc(I);
end;

{ "prompt ...", "find ...", "replace ...", "replaceall ..." as a step; False if Line is none of them or is not well formed. }
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

end.
