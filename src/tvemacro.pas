{ TveMacro: a recorded macro and its text form.

  MIT.

  A macro is a list of steps: a command (by number, see TveCmds) or a piece of typed text. The text form has one step per line:

      ; a comment (also a line that starts with #)
      Find                    a command, by its name
      "hello\n"               typed text; \\ \" \n \r \t \xHH are escapes, other bytes (UTF-8) stand for themselves

  Blank lines are skipped. The macro commands themselves (MacroRecord, MacroPlay) cannot be steps. }
unit TveMacro;

{$I tvdefs.inc}
{$H+}

interface

type
  TTveMacroStep = record
    Cmd: Integer;                { > 0: a command; 0: typed text }
    Text: AnsiString;
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
  SetLength(FSteps, Length(FSteps) + 1);
  FSteps[High(FSteps)].Cmd := Cmd;
  FSteps[High(FSteps)].Text := '';
end;

procedure TTveMacro.AddText(const S: AnsiString);
begin
  if S = '' then
    Exit;
  if (Length(FSteps) > 0) and (FSteps[High(FSteps)].Cmd = 0) then
    FSteps[High(FSteps)].Text := FSteps[High(FSteps)].Text + S
  else
  begin
    SetLength(FSteps, Length(FSteps) + 1);
    FSteps[High(FSteps)].Cmd := 0;
    FSteps[High(FSteps)].Text := S;
  end;
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

{ Line = "...": the text between the quotes; False if it is not well formed. }
function ParseQuoted(const Line: AnsiString; out S: AnsiString): Boolean;
var
  I, H1, H2: Integer;
  C: Char;
begin
  S := '';
  Result := False;
  if (Length(Line) < 2) or (Line[1] <> '"') or (Line[Length(Line)] <> '"') then
    Exit;
  I := 2;
  while I < Length(Line) do
  begin
    C := Line[I];
    if C = '"' then
      Exit;                      { an unescaped quote inside }
    if C = '\' then
    begin
      Inc(I);
      if I >= Length(Line) then
        Exit;
      case Line[I] of
        '\': S := S + '\';
        '"': S := S + '"';
        'n': S := S + #10;
        'r': S := S + #13;
        't': S := S + #9;
        'x':
          begin
            if I + 2 >= Length(Line) + 0 then
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
    else
    begin
      Cmd := TveCommandByName(Line);
      if (Cmd <= 0) or (Cmd = tcMacroRecord) or (Cmd = tcMacroPlay) then
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
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FSteps) do
    if FSteps[I].Cmd = 0 then
      Result := Result + Quote(FSteps[I].Text) + LF
    else
      Result := Result + TveCommandName(FSteps[I].Cmd) + LF;
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
