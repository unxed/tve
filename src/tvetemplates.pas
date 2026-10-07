{ TveTemplates: code templates.

  MIT.

  A template is a text with variables: $DATE and $TIME (or $DATE(format), $TIME(format), the format is the one of FormatDateTime), $PROMPT(question) (the host asks the
  user), $CURSOR (where the cursor goes after the insertion), $$ (a dollar sign). The lines after the first are indented like the line that the template goes into.

  A set of templates is a text: a line "[shortcut] description" starts a template, the lines up to the next such line are its body (a "[" at the start of a body line is
  written "[[").  }
unit TveTemplates;

{$I tvdefs.inc}
{$H+}

interface

uses
  TveEditor;

type
  TTvePrompt = function(const Question: AnsiString; out Value: AnsiString): Boolean of object;

  TTveTemplates = class
  private
    FNames, FDescs, FBodies: array of AnsiString;
  public
    procedure Clear;
    function LoadText(const Text: AnsiString): Integer;
    function Count: Integer;
    function Name(I: Integer): AnsiString;
    function Description(I: Integer): AnsiString;
    function Body(I: Integer): AnsiString;
    function IndexOf(const ShortCut: AnsiString): Integer;
    procedure Add(const ShortCut, Desc, ABody: AnsiString);
  end;

{ Expands the variables. Cursor is the byte offset in Text where $CURSOR was (-1: none). False if the user cancelled a prompt. }
function TveExpandTemplate(const Body, Indent: AnsiString; Prompt: TTvePrompt; out Text: AnsiString; out Cursor: Integer): Boolean;
{ Inserts a template at the cursor (it replaces the selection); one undo step. }
function TveInsertTemplate(E: TTveEditor; const Body: AnsiString; Prompt: TTvePrompt): Boolean;
{ The word before the cursor is a shortcut: it is replaced by the template. False if there is no such template. }
function TveExpandShortcut(E: TTveEditor; T: TTveTemplates; Prompt: TTvePrompt): Boolean;

implementation

uses
  SysUtils, TveLayout;

procedure TTveTemplates.Clear;
begin
  FNames := nil;
  FDescs := nil;
  FBodies := nil;
end;

procedure TTveTemplates.Add(const ShortCut, Desc, ABody: AnsiString);
var
  N: Integer;
begin
  N := Length(FNames);
  SetLength(FNames, N + 1);
  SetLength(FDescs, N + 1);
  SetLength(FBodies, N + 1);
  FNames[N] := ShortCut;
  FDescs[N] := Desc;
  FBodies[N] := ABody;
end;

function TTveTemplates.LoadText(const Text: AnsiString): Integer;
var
  P, E, Close_: Integer;
  Line, CurName, CurDesc, CurBody: AnsiString;
  Have: Boolean;

  procedure Flush;
  begin
    if Have then
    begin
      // the last line break belongs to the file, not to the body
      if (CurBody <> '') and (CurBody[Length(CurBody)] = #10) then
        SetLength(CurBody, Length(CurBody) - 1);
      Add(CurName, CurDesc, CurBody);
      Inc(Result);
    end;
    Have := False;
    CurBody := '';
  end;

begin
  Result := 0;
  Have := False;
  CurBody := '';
  P := 1;
  while P <= Length(Text) do
  begin
    E := P;
    while (E <= Length(Text)) and (Text[E] <> #10) do
      Inc(E);
    Line := Copy(Text, P, E - P);
    if (Line <> '') and (Line[Length(Line)] = #13) then
      SetLength(Line, Length(Line) - 1);
    P := E + 1;
    if (Line <> '') and (Line[1] = '[') and not ((Length(Line) > 1) and (Line[2] = '[')) then
    begin
      Close_ := Pos(']', Line);
      if Close_ > 0 then
      begin
        Flush;
        CurName := Copy(Line, 2, Close_ - 2);
        CurDesc := Trim(Copy(Line, Close_ + 1, MaxInt));
        Have := True;
        Continue;
      end;
    end;
    if not Have then
      Continue;
    if (Length(Line) > 1) and (Line[1] = '[') and (Line[2] = '[') then
      Delete(Line, 1, 1);
    CurBody := CurBody + Line + #10;
  end;
  Flush;
end;

function TTveTemplates.Count: Integer;
begin
  Result := Length(FNames);
end;

function TTveTemplates.Name(I: Integer): AnsiString;
begin
  Result := FNames[I];
end;

function TTveTemplates.Description(I: Integer): AnsiString;
begin
  Result := FDescs[I];
end;

function TTveTemplates.Body(I: Integer): AnsiString;
begin
  Result := FBodies[I];
end;

function TTveTemplates.IndexOf(const ShortCut: AnsiString): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNames) do
    if SameText(FNames[I], ShortCut) then
      Exit(I);
  Result := -1;
end;

function TveExpandTemplate(const Body, Indent: AnsiString; Prompt: TTvePrompt; out Text: AnsiString; out Cursor: Integer): Boolean;
var
  I, J, Depth: Integer;
  Name, Arg, V: AnsiString;
  HasArg: Boolean;
  Out_: AnsiString;
begin
  Result := False;
  Text := '';
  Cursor := -1;
  Out_ := '';
  I := 1;
  while I <= Length(Body) do
  begin
    if Body[I] = #10 then
    begin
      Out_ := Out_ + #10 + Indent;
      Inc(I);
      Continue;
    end;
    if (Body[I] <> '$') or (I = Length(Body)) then
    begin
      Out_ := Out_ + Body[I];
      Inc(I);
      Continue;
    end;
    if Body[I + 1] = '$' then
    begin
      Out_ := Out_ + '$';
      Inc(I, 2);
      Continue;
    end;
    J := I + 1;
    while (J <= Length(Body)) and (Body[J] in ['A'..'Z', 'a'..'z']) do
      Inc(J);
    Name := UpperCase(Copy(Body, I + 1, J - I - 1));
    if (Name <> 'DATE') and (Name <> 'TIME') and (Name <> 'PROMPT') and (Name <> 'CURSOR') then
    begin
      Out_ := Out_ + '$';
      Inc(I);
      Continue;
    end;
    HasArg := (J <= Length(Body)) and (Body[J] = '(');
    Arg := '';
    if HasArg then
    begin
      Depth := 1;
      Inc(J);
      while (J <= Length(Body)) and (Depth > 0) do
      begin
        if Body[J] = '(' then
          Inc(Depth)
        else if Body[J] = ')' then
        begin
          Dec(Depth);
          if Depth = 0 then
            Break;
        end;
        Arg := Arg + Body[J];
        Inc(J);
      end;
      Inc(J);
      if (Length(Arg) >= 2) and (Arg[1] = '''') and (Arg[Length(Arg)] = '''') then
        Arg := Copy(Arg, 2, Length(Arg) - 2);
    end;
    if Name = 'DATE' then
    begin
      if Arg = '' then Arg := 'yyyy-mm-dd';
      Out_ := Out_ + FormatDateTime(Arg, Now);
    end
    else if Name = 'TIME' then
    begin
      if Arg = '' then Arg := 'hh:nn:ss';
      Out_ := Out_ + FormatDateTime(Arg, Now);
    end
    else if Name = 'CURSOR' then
      Cursor := Length(Out_)
    else
    begin
      V := '';
      if Assigned(Prompt) then
      begin
        if not Prompt(Arg, V) then
          Exit;
      end;
      Out_ := Out_ + V;
    end;
    I := J;
  end;
  Text := Out_;
  Result := True;
end;

function IndentOfCursor(E: TTveEditor): AnsiString;
var
  S: AnsiString;
  I: Integer;
begin
  S := E.Doc.Buffer.LineText(E.Line);
  I := 1;
  while (I <= Length(S)) and (S[I] in [' ', #9]) do
    Inc(I);
  Result := Copy(S, 1, I - 1);
end;

function TveInsertTemplate(E: TTveEditor; const Body: AnsiString; Prompt: TTvePrompt): Boolean;
var
  Text: AnsiString;
  Cursor: Integer;
  Start: Int64;
begin
  Result := False;
  if not TveExpandTemplate(Body, IndentOfCursor(E), Prompt, Text, Cursor) then
    Exit;
  E.Doc.BeginGroup;
  try
    if E.HasSelection then
      E.DeleteSelection;
    Start := E.Offset;
    Result := E.TypeText(Text);
    if Result and (Cursor >= 0) then
      E.GotoOffset(Start + Cursor);
  finally
    E.Doc.EndGroup;
  end;
end;

function TveExpandShortcut(E: TTveEditor; T: TTveTemplates; Prompt: TTvePrompt): Boolean;
var
  S: AnsiString;
  I, Idx, Cut: Integer;
begin
  Result := False;
  S := E.Doc.Buffer.LineText(E.Line);
  Cut := LayoutCellToIndex(S, E.Cell, E.Opt.TabSize);     // the byte index of the cursor
  I := Cut;
  while (I > 1) and (S[I - 1] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Dec(I);
  if I = Cut then
    Exit;
  Idx := T.IndexOf(Copy(S, I, Cut - I));
  if Idx < 0 then
    Exit;
  E.Doc.BeginGroup;
  try
    E.Doc.Delete(E.Doc.Buffer.LineStart(E.Line) + I - 1, Cut - I);
    E.GotoLineCell(E.Line, LayoutIndexToCell(S, I, E.Opt.TabSize));
    Result := TveInsertTemplate(E, T.Body(Idx), Prompt);
  finally
    E.Doc.EndGroup;
  end;
end;

end.
