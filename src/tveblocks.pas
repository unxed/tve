{ TveBlocks: the commands that work on blocks and lines.

  MIT. Each command is one undo step; the cursor stays on the text it was on (it is pinned to an anchor of the document while the text changes).
  Commands that need a selection do nothing without one; the line commands work on the lines of the selection, or on the current line. All of them return False when
  nothing was done (read-only, no selection, nothing to change). }
unit TveBlocks;

{$I tvdefs.inc}

interface

uses
  TveEditor;

type
  TTveCase = (caseUpper, caseLower, caseTitle, caseToggle);
  TTveAlign = (alLeft, alRight, alCenter, alFull);

{ indent / unindent by Opt.IndentSize (a real tab for the indent when the size is the tab size and the tabs are on) }
function BlockIndent(E: TTveEditor): Boolean;
function BlockUnindent(E: TTveEditor): Boolean;

{ upper / lower / title / toggle case of the selection, else of the word at the cursor }
function ChangeCase(E: TTveEditor; Mode: TTveCase): Boolean;
{ the same for the whole lines of the selection or the current line }
function ChangeCaseLines(E: TTveEditor; Mode: TTveCase): Boolean;

{ sorts the lines of the selection (of a column block: by the text of the columns, whole lines move) }
function SortLines(E: TTveEditor; Descending: Boolean; CaseSensitive: Boolean = False): Boolean;

function DuplicateLine(E: TTveEditor): Boolean;
{ joins the current line with the next: the blanks at the start of the next line become one blank }
function JoinLine(E: TTveEditor): Boolean;
{ a line end at the cursor; the cursor stays before it (break the line and stay) }
function BreakLineStay(E: TTveEditor): Boolean;
{ an empty line below / above the current one; the cursor stays on its line }
function InsertLineBelow(E: TTveEditor): Boolean;
function InsertLineAbove(E: TTveEditor): Boolean;

{ the selected text is copied / moved to the cursor; the inserted text becomes the selection }
function CopyBlockHere(E: TTveEditor): Boolean;
function MoveBlockHere(E: TTveEditor): Boolean;
{ Drag and drop of the selection (a stream or line selection) to the offset Dest: moved, or copied when Copy is True; one undo step; the dropped text becomes the
  selection. False (nothing changed) when there is no such selection, the text is read only, or Dest is inside the selection (also at its ends, for a move). }
function DragBlock(E: TTveEditor; Dest: Int64; Copy: Boolean): Boolean;
{ the selection to a file / a file at the cursor (UTF-8 with LF is converted to the encoding and line ends of the document) }
function WriteBlock(E: TTveEditor; const Name: AnsiString): Boolean;
function ReadBlock(E: TTveEditor; const Name: AnsiString): Boolean;

{ the tabs of the selection (or of the whole text when nothing is selected) become blanks / the blanks at the start of the lines become tabs }
function ExpandTabs(E: TTveEditor): Boolean;
function TabifyIndent(E: TTveEditor): Boolean;
{ removes the blanks at the ends of the lines of the selection (or of the whole text) }
function TrimTrailing(E: TTveEditor): Boolean;

{ aligns a paragraph (the selected lines, or the lines around the cursor up to an empty line) between the margins; the first line is indented by ParaIndent more }
function FormatParagraph(E: TTveEditor; Align: TTveAlign; LeftMargin, RightMargin, ParaIndent: Integer): Boolean;
{ aligns the lines one by one }
function AlignLines(E: TTveEditor; Align: TTveAlign; LeftMargin, RightMargin: Integer): Boolean;

implementation

uses
  SysUtils, TveBuf, TveDoc, TveLayout, TveFile, TvUStr, TvUtf8;

{ --- helpers --- }

function LineStartOff(E: TTveEditor; L: Int64): Int64;
begin
  Result := E.Doc.Buffer.LineStart(L);
end;

function LineEndOff(E: TTveEditor; L: Int64): Int64;
begin
  Result := E.Doc.Buffer.LineEnd(L);
end;

function LeadingBlanks(const S: AnsiString): Integer;
begin
  Result := 0;
  while (Result < Length(S)) and ((S[Result + 1] = ' ') or (S[Result + 1] = #9)) do
    Inc(Result);
end;

function IndentCells(const S: AnsiString; TabSize: Integer): Integer;
begin
  Result := LayoutCells(Copy(S, 1, LeadingBlanks(S)), TabSize);
end;

{ the blanks that make Cells cells from the start of a line }
function MakeIndent(E: TTveEditor; Cells: Integer): AnsiString;
var
  Tabs: Integer;
begin
  Result := '';
  if Cells <= 0 then
    Exit;
  if E.Opt.UseTabChars and (E.Opt.TabSize > 0) then
  begin
    Tabs := Cells div E.Opt.TabSize;
    Result := StringOfChar(#9, Tabs);
    Cells := Cells - Tabs * E.Opt.TabSize;
  end;
  Result := Result + StringOfChar(' ', Cells);
end;

{ Replaces the lines L1..L2 (without the last line end) by the lines in Lines, in one edit }
procedure ReplaceLines(E: TTveEditor; L1, L2: Int64; const Lines: array of AnsiString);
var
  A, B: Int64;
  I: Integer;
  T: AnsiString;
begin
  A := LineStartOff(E, L1);
  B := LineEndOff(E, L2);
  T := '';
  for I := 0 to High(Lines) do
  begin
    if I > 0 then
      T := T + #10;
    T := T + Lines[I];
  end;
  if E.Doc.Buffer.Copy(A, B - A) <> T then
    E.Doc.Replace(A, B - A, T);
end;

function ReadOnlyNow(E: TTveEditor): Boolean;
begin
  Result := E.Doc.ReadOnly;
end;

{ --- indent --- }

function BlockIndent(E: TTveEditor): Boolean;
var
  L1, L2: Int64;
  L: LongInt;
  Pin: Integer;
  Changed: Boolean;
  Ind: AnsiString;
  S: AnsiString;
begin
  Result := False;
  if ReadOnlyNow(E) or not E.AffectedLines(L1, L2) then
    Exit;
  Ind := MakeIndent(E, E.Opt.IndentSize);
  if Ind = '' then
    Exit;
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  Changed := False;
  for L := L2 downto L1 do
  begin
    S := E.Doc.Buffer.LineText(L);
    if S = '' then
      Continue;
    E.Doc.Insert(LineStartOff(E, L), Ind);
    Changed := True;
  end;
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := Changed;
end;

function BlockUnindent(E: TTveEditor): Boolean;
var
  L1, L2: Int64;
  L: LongInt;
  Pin: Integer;
  S: AnsiString;
  Size, I, Cells, Remove, Idx: Integer;
  Cant: Boolean;
  Changed: Boolean;
begin
  Result := False;
  if ReadOnlyNow(E) or not E.AffectedLines(L1, L2) then
    Exit;
  Size := E.Opt.IndentSize;
  if Size <= 0 then
    Exit;
  if not E.Opt.UnlimitedUnindent then
  begin
    Cant := False;
    for L := L1 to L2 do
    begin
      S := E.Doc.Buffer.LineText(L);
      if (S <> '') and (IndentCells(S, E.Opt.TabSize) < Size) then
        Cant := True;
    end;
    if Cant then
      Exit;
  end;
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  Changed := False;
  for L := L2 downto L1 do
  begin
    S := E.Doc.Buffer.LineText(L);
    if LeadingBlanks(S) = 0 then
      Continue;
    { remove up to Size cells of the indent: whole blanks only (a tab goes whole and the rest is made up with blanks) }
    Cells := 0;
    Idx := 1;
    while (Idx <= Length(S)) and (Cells < Size) and ((S[Idx] = ' ') or (S[Idx] = #9)) do
    begin
      if S[Idx] = #9 then
        Inc(Cells, E.Opt.TabSize - (Cells mod E.Opt.TabSize))
      else
        Inc(Cells);
      Inc(Idx);
    end;
    Remove := Idx - 1;
    E.Doc.Delete(LineStartOff(E, L), Remove);
    if Cells > Size then
      E.Doc.Insert(LineStartOff(E, L), StringOfChar(' ', Cells - Size));        { a tab was cut: its rest stays as blanks }
    Changed := True;
  end;
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := Changed;
end;

{ --- case --- }

function MapText(const S: AnsiString; Mode: TTveCase): AnsiString;
var
  I, N, Used: Integer;
  CP: LongWord;
  StartOfWord: Boolean;
  Piece: AnsiString;
begin
  case Mode of
    caseUpper: Exit(U8Upper(S));
    caseLower: Exit(U8Lower(S));
  end;
  Result := '';
  I := 1;
  N := Length(S);
  StartOfWord := True;
  while I <= N do
  begin
    Used := 1;
    CP := Byte(S[I]);
    if (CP >= $80) and Utf8Enabled then
      if not (Utf8Decode(@S[I], N - I + 1, CP, Used) and (Used > 1)) then
      begin
        CP := Byte(S[I]);
        Used := 1;
      end;
    Piece := Copy(S, I, Used);
    if Mode = caseTitle then
    begin
      if IsWordCp(CP) then
      begin
        if StartOfWord then
          Piece := U8Upper(Piece)
        else
          Piece := U8Lower(Piece);
        StartOfWord := False;
      end
      else
        StartOfWord := True;
    end
    else
    begin
      { toggle: a capital becomes lower, a small letter capital }
      if CpLower(CP) <> CP then
        Piece := U8Lower(Piece)
      else if CpUpper(CP) <> CP then
        Piece := U8Upper(Piece);
    end;
    Result := Result + Piece;
    Inc(I, Used);
  end;
end;

function ChangeCase(E: TTveEditor; Mode: TTveCase): Boolean;
var
  A, B: Int64;
  Old, New_: AnsiString;
  Pin: Integer;
  Col: Boolean;
  L1, L2: Int64;
  L: LongInt;
  C1, C2: Integer;
  S, T: AnsiString;
  OffA: Int64;
  Pad: Integer;
begin
  Result := False;
  if ReadOnlyNow(E) then
    Exit;
  if not E.HasSelection then
  begin
    E.SelectWord;
    if not E.HasSelection then
      Exit;
    if not E.SelectionRange(A, B) then
      Exit;
    Old := E.Doc.Buffer.Copy(A, B - A);
    New_ := MapText(Old, Mode);
    E.ClearSelection;
    if New_ = Old then
      Exit;
    E.NoteBefore;
    Pin := E.PinCursor;
    E.Doc.Replace(A, B - A, New_);
    E.UnpinCursor(Pin);
    E.NoteAfter;
    Exit(True);
  end;
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  if E.SelKind = skColumn then
  begin
    E.ColumnRect(L1, L2, C1, C2);
    for L := L1 to L2 do
    begin
      S := E.Doc.Buffer.LineText(L);
      A := E.LineCellToOffset(L, C1);
      B := E.LineCellToOffset(L, C2);
      if B > A then
      begin
        Old := E.Doc.Buffer.Copy(A, B - A);
        New_ := MapText(Old, Mode);
        if New_ <> Old then
          E.Doc.Replace(A, B - A, New_);
      end;
    end;
  end
  else if E.SelectionRange(A, B) then
  begin
    Old := E.Doc.Buffer.Copy(A, B - A);
    New_ := MapText(Old, Mode);
    if New_ <> Old then
      E.Doc.Replace(A, B - A, New_);
  end;
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := True;
end;

function ChangeCaseLines(E: TTveEditor; Mode: TTveCase): Boolean;
var
  L1, L2: Int64;
  L: LongInt;
  Pin: Integer;
  S, T: AnsiString;
  Changed: Boolean;
begin
  Result := False;
  if ReadOnlyNow(E) or not E.AffectedLines(L1, L2) then
    Exit;
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  Changed := False;
  for L := L1 to L2 do
  begin
    S := E.Doc.Buffer.LineText(L);
    T := MapText(S, Mode);
    if T <> S then
    begin
      E.Doc.Replace(LineStartOff(E, L), Length(S), T);
      Changed := True;
    end;
  end;
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := Changed;
end;

{ --- sort --- }

function SortLines(E: TTveEditor; Descending: Boolean; CaseSensitive: Boolean): Boolean;
var
  L1, L2, L: Int64;
  N, I, J, C1, C2, K1, K2: Integer;
  Lines, Keys: array of AnsiString;
  Idx: array of Integer;
  Tmp: Integer;
  Col: Boolean;
  Pin: Integer;
  Sorted: array of AnsiString;
  Ra, Rb: Int64;
  Changed: Boolean;

  function Less(A, B: Integer): Boolean;
  var
    Cmp: Integer;
  begin
    if CaseSensitive then
      Cmp := CompareStr(Keys[A], Keys[B])
    else
      Cmp := CompareStr(U8Lower(Keys[A]), U8Lower(Keys[B]));
    if Descending then
      Cmp := -Cmp;
    if Cmp = 0 then
      Result := A < B                       { stable }
    else
      Result := Cmp < 0;
  end;

begin
  Result := False;
  if ReadOnlyNow(E) or not E.HasSelection or not E.AffectedLines(L1, L2) or (L2 <= L1) then
    Exit;
  N := Integer(L2 - L1 + 1);
  SetLength(Lines, N);
  SetLength(Keys, N);
  SetLength(Idx, N);
  Col := E.SelKind = skColumn;
  C1 := 0; C2 := 0;
  if Col then
    E.ColumnRect(Ra, Rb, C1, C2);
  for I := 0 to N - 1 do
  begin
    Lines[I] := E.Doc.Buffer.LineText(L1 + I);
    Idx[I] := I;
    if Col then
    begin
      K1 := LayoutCellToIndex(Lines[I], C1, E.Opt.TabSize);
      K2 := LayoutCellToIndex(Lines[I], C2, E.Opt.TabSize);
      Keys[I] := Copy(Lines[I], K1, K2 - K1);
    end
    else
      Keys[I] := Lines[I];
  end;
  { insertion sort is stable and the blocks are small; a merge sort takes over for big ones }
  if N > 64 then
  begin
    { merge sort on Idx }
    Sorted := nil;
    I := 1;
    while I < N do
    begin
      J := 0;
      while J < N do
      begin
        { merge Idx[J .. J+I-1] and Idx[J+I .. J+2I-1] }
        K1 := J;
        K2 := J + I;
        Tmp := J;
        while (K1 < J + I) and (K1 < N) or (K2 < J + 2 * I) and (K2 < N) do
        begin
          if (K1 < J + I) and (K1 < N) and ((K2 >= J + 2 * I) or (K2 >= N) or not Less(Idx[K2], Idx[K1])) then
          begin
            Idx[Tmp] := Idx[K1]; Inc(K1);
          end
          else
          begin
            Idx[Tmp] := Idx[K2]; Inc(K2);
          end;
          Inc(Tmp);
        end;
        Inc(J, 2 * I);
      end;
      Inc(I, I);
    end;
  end
  else
    for I := 1 to N - 1 do
    begin
      Tmp := Idx[I];
      J := I - 1;
      while (J >= 0) and Less(Tmp, Idx[J]) do
      begin
        Idx[J + 1] := Idx[J];
        Dec(J);
      end;
      Idx[J + 1] := Tmp;
    end;
  Changed := False;
  for I := 0 to N - 1 do
    if Idx[I] <> I then
      Changed := True;
  if not Changed then
    Exit;
  SetLength(Sorted, N);
  for I := 0 to N - 1 do
    Sorted[I] := Lines[Idx[I]];
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  ReplaceLines(E, L1, L2, Sorted);
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := True;
end;

{ --- line commands --- }

function DuplicateLine(E: TTveEditor): Boolean;
var
  S: AnsiString;
  Cell: Integer;
  L: Int64;
begin
  Result := False;
  if ReadOnlyNow(E) then
    Exit;
  L := E.Line;
  Cell := E.Cell;
  S := E.Doc.Buffer.LineText(L);
  E.NoteBefore;
  E.Doc.Insert(LineEndOff(E, L), #10 + S);
  E.GotoLineCell(L + 1, Cell);
  E.NoteAfter;
  Result := True;
end;

function JoinLine(E: TTveEditor): Boolean;
var
  L: Int64;
  Next: AnsiString;
  Blanks: Integer;
  A, B: Int64;
  Mine: AnsiString;
  Sep: AnsiString;
begin
  Result := False;
  L := E.Line;
  if ReadOnlyNow(E) or (L + 1 >= E.Doc.Buffer.LineCount) then
    Exit;
  Next := E.Doc.Buffer.LineText(L + 1);
  Mine := E.Doc.Buffer.LineText(L);
  Blanks := LeadingBlanks(Next);
  A := LineEndOff(E, L);
  B := LineStartOff(E, L + 1) + Blanks;
  Sep := '';
  if (Mine <> '') and (Next <> '') and (Mine[Length(Mine)] <> ' ') and (Mine[Length(Mine)] <> #9) then
    Sep := ' ';
  E.NoteBefore;
  E.Doc.Replace(A, B - A, Sep);
  E.GotoOffset(A);
  E.NoteAfter;
  Result := True;
end;

function BreakLineStay(E: TTveEditor): Boolean;
var
  Off: Int64;
  Pad: Integer;
begin
  Result := False;
  if ReadOnlyNow(E) then
    Exit;
  E.NoteBefore;
  Off := E.Offset;
  E.Doc.Insert(Off, #10);
  E.GotoOffset(Off);
  E.NoteAfter;
  Result := True;
end;

function InsertLineBelow(E: TTveEditor): Boolean;
var
  L: Int64;
  Cell: Integer;
begin
  Result := False;
  if ReadOnlyNow(E) then
    Exit;
  L := E.Line;
  Cell := E.Cell;
  E.NoteBefore;
  E.Doc.Insert(LineEndOff(E, L), #10);
  E.GotoLineCell(L, Cell);
  E.NoteAfter;
  Result := True;
end;

function InsertLineAbove(E: TTveEditor): Boolean;
var
  L: Int64;
  Cell: Integer;
begin
  Result := False;
  if ReadOnlyNow(E) then
    Exit;
  L := E.Line;
  Cell := E.Cell;
  E.NoteBefore;
  E.Doc.Insert(LineStartOff(E, L), #10);
  E.GotoLineCell(L + 1, Cell);
  E.NoteAfter;
  Result := True;
end;

{ --- copy / move / files --- }

function CopyBlockHere(E: TTveEditor): Boolean;
var
  Col: Boolean;
  T: AnsiString;
  A: Int64;
begin
  Result := False;
  if ReadOnlyNow(E) or not E.HasSelection then
    Exit;
  T := E.SelectionText(Col);
  if T = '' then
    Exit;
  E.ClearSelection;
  A := E.Offset;
  E.PasteText(T, Col);
  if not Col then
  begin
    E.SetSelection(skStream, A);
  end;
  Result := True;
end;

function MoveBlockHere(E: TTveEditor): Boolean;
var
  Col: Boolean;
  T: AnsiString;
  A, B, Dest: Int64;
  Pin: Integer;
begin
  Result := False;
  if ReadOnlyNow(E) or not E.HasSelection or (E.SelKind = skColumn) then
    Exit;
  if not E.SelectionRange(A, B) then
    Exit;
  Dest := E.Offset;
  if (Dest > A) and (Dest < B) then
    Exit;                                   { into itself }
  T := E.SelectionText(Col);
  E.ClearSelection;
  E.NoteBefore;
  E.Doc.BeginGroup;
  Pin := E.Doc.AddAnchor(Dest, False);
  E.Doc.Delete(A, B - A);
  Dest := E.Doc.AnchorPos(Pin);
  E.Doc.RemoveAnchor(Pin);
  E.Doc.Insert(Dest, T);
  E.Doc.EndGroup;
  E.GotoOffset(Dest + Length(T));
  E.SetSelection(skStream, Dest);
  E.NoteAfter;
  Result := True;
end;

function DragBlock(E: TTveEditor; Dest: Int64; Copy: Boolean): Boolean;
var
  A, B: Int64;
begin
  Result := False;
  if ReadOnlyNow(E) or not E.HasSelection or (E.SelKind = skColumn) then
    Exit;
  if not E.SelectionRange(A, B) then
    Exit;
  if Copy then
  begin
    if (Dest > A) and (Dest < B) then
      Exit;
  end
  else if (Dest >= A) and (Dest <= B) then
    Exit;
  E.GotoOffset(Dest);
  if Copy then
    Result := CopyBlockHere(E)
  else
    Result := MoveBlockHere(E);
end;

function WriteBlock(E: TTveEditor; const Name: AnsiString): Boolean;
var
  Col: Boolean;
  T, Err: AnsiString;
  Info: TTveFileInfo;
  Lost: Integer;
begin
  Result := False;
  if not E.HasSelection then
    Exit;
  T := E.SelectionText(Col);
  Info := E.Doc.Info;
  Info.Eol := E.Doc.Eol;
  Result := TveWriteFile(Name, T, Info, TveDefaultOptions, Lost, Err);
end;

function ReadBlock(E: TTveEditor; const Name: AnsiString): Boolean;
var
  T, Err: AnsiString;
  Info: TTveFileInfo;
  A: Int64;
begin
  Result := False;
  if ReadOnlyNow(E) then
    Exit;
  if not TveReadFile(Name, TveDefaultOptions, T, Info, Err) then
    Exit;
  E.ClearSelection;
  A := E.Offset;
  E.PasteText(T, False);
  E.SetSelection(skStream, A);
  Result := True;
end;

{ --- tabs --- }

function RangeOrAll(E: TTveEditor; out L1, L2: Int64): Boolean;
begin
  Result := True;
  if E.HasSelection then
    E.AffectedLines(L1, L2)
  else
  begin
    L1 := 0;
    L2 := E.Doc.Buffer.LineCount - 1;
  end;
end;

function ExpandTabs(E: TTveEditor): Boolean;
var
  L1, L2: Int64;
  L: LongInt;
  S, T: AnsiString;
  I, Cells: Integer;
  C: TTveCharInfo;
  Pin: Integer;
  Changed: Boolean;
begin
  Result := False;
  if ReadOnlyNow(E) then
    Exit;
  RangeOrAll(E, L1, L2);
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  Changed := False;
  for L := L2 downto L1 do
  begin
    S := E.Doc.Buffer.LineText(L);
    if Pos(#9, S) = 0 then
      Continue;
    T := '';
    I := 1;
    Cells := 0;
    while I <= Length(S) do
    begin
      LayoutChar(S, I, Cells, E.Opt.TabSize, C);
      if S[I] = #9 then
        T := T + StringOfChar(' ', C.Cells)
      else
        T := T + Copy(S, I, C.Bytes);
      Inc(Cells, C.Cells);
      Inc(I, C.Bytes);
    end;
    E.Doc.Replace(LineStartOff(E, L), Length(S), T);
    Changed := True;
  end;
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := Changed;
end;

function TabifyIndent(E: TTveEditor): Boolean;
var
  L1, L2: Int64;
  L: LongInt;
  S, Ind, NewInd: AnsiString;
  Cells, Tabs: Integer;
  Pin: Integer;
  Changed: Boolean;
begin
  Result := False;
  if ReadOnlyNow(E) or (E.Opt.TabSize < 2) then
    Exit;
  RangeOrAll(E, L1, L2);
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  Changed := False;
  for L := L2 downto L1 do
  begin
    S := E.Doc.Buffer.LineText(L);
    Ind := Copy(S, 1, LeadingBlanks(S));
    if Ind = '' then
      Continue;
    Cells := LayoutCells(Ind, E.Opt.TabSize);
    Tabs := Cells div E.Opt.TabSize;
    NewInd := StringOfChar(#9, Tabs) + StringOfChar(' ', Cells - Tabs * E.Opt.TabSize);
    if NewInd <> Ind then
    begin
      E.Doc.Replace(LineStartOff(E, L), Length(Ind), NewInd);
      Changed := True;
    end;
  end;
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := Changed;
end;

function TrimTrailing(E: TTveEditor): Boolean;
var
  L1, L2: Int64;
  L: LongInt;
  S: AnsiString;
  N: Integer;
  Pin: Integer;
  Changed: Boolean;
begin
  Result := False;
  if ReadOnlyNow(E) then
    Exit;
  RangeOrAll(E, L1, L2);
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  Changed := False;
  for L := L2 downto L1 do
  begin
    S := E.Doc.Buffer.LineText(L);
    N := Length(S);
    while (N > 0) and ((S[N] = ' ') or (S[N] = #9)) do
      Dec(N);
    if N < Length(S) then
    begin
      E.Doc.Delete(LineStartOff(E, L) + N, Length(S) - N);
      Changed := True;
    end;
  end;
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := Changed;
end;

{ --- format --- }

type
  TWordList = array of AnsiString;

function Words(const S: AnsiString): TWordList;
var
  I, Start, N: Integer;
begin
  Result := nil;
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    while (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) do
      Inc(I);
    if I > Length(S) then
      Break;
    Start := I;
    while (I <= Length(S)) and (S[I] <> ' ') and (S[I] <> #9) do
      Inc(I);
    SetLength(Result, N + 1);
    Result[N] := Copy(S, Start, I - Start);
    Inc(N);
  end;
end;

{ one line from the words W[First .. Last] aligned in Width cells }
function SetLine(const W: TWordList; First, Last, Width: Integer; Align: TTveAlign; IsLast: Boolean): AnsiString;
var
  I, Gaps, Total, Extra, Each, Rest, Pad: Integer;
begin
  Result := '';
  Total := 0;
  for I := First to Last do
    Inc(Total, U8Cols(W[I]));
  Gaps := Last - First;
  case Align of
    alFull:
      if IsLast or (Gaps = 0) then
        for I := First to Last do
        begin
          if I > First then Result := Result + ' ';
          Result := Result + W[I];
        end
      else
      begin
        Extra := Width - Total;
        Each := Extra div Gaps;
        Rest := Extra mod Gaps;
        for I := First to Last do
        begin
          Result := Result + W[I];
          if I < Last then
          begin
            Pad := Each;
            if I - First < Rest then Inc(Pad);
            Result := Result + StringOfChar(' ', Pad);
          end;
        end;
      end;
  else
    begin
      for I := First to Last do
      begin
        if I > First then Result := Result + ' ';
        Result := Result + W[I];
      end;
      Total := U8Cols(Result);
      if Align = alRight then
        Result := StringOfChar(' ', Width - Total) + Result
      else if Align = alCenter then
        Result := StringOfChar(' ', (Width - Total) div 2) + Result;
    end;
  end;
end;

function FormatParagraph(E: TTveEditor; Align: TTveAlign; LeftMargin, RightMargin, ParaIndent: Integer): Boolean;
var
  L1, L2: Int64;
  L: LongInt;
  Text: AnsiString;
  W: TWordList;
  Out_: array of AnsiString;
  First, I, Cols, Width, Lead, N: Integer;
  Pin: Integer;
  Cnt: Integer;
  FirstLine: Boolean;
begin
  Result := False;
  if ReadOnlyNow(E) or (RightMargin <= LeftMargin) then
    Exit;
  if E.HasSelection then
    E.AffectedLines(L1, L2)
  else
  begin
    L1 := E.Line;
    if Trim(E.Doc.Buffer.LineText(L1)) = '' then
      Exit;
    while (L1 > 0) and (Trim(E.Doc.Buffer.LineText(L1 - 1)) <> '') do
      Dec(L1);
    L2 := E.Line;
    while (L2 + 1 < E.Doc.Buffer.LineCount) and (Trim(E.Doc.Buffer.LineText(L2 + 1)) <> '') do
      Inc(L2);
  end;
  Text := '';
  for L := L1 to L2 do
    Text := Text + E.Doc.Buffer.LineText(L) + ' ';
  W := Words(Text);
  if Length(W) = 0 then
    Exit;
  Out_ := nil;
  N := 0;
  First := 0;
  FirstLine := True;
  while First <= High(W) do
  begin
    Lead := LeftMargin;
    if FirstLine then
      Inc(Lead, ParaIndent);
    Width := RightMargin - Lead;
    if Width < 1 then Width := 1;
    I := First;
    Cols := U8Cols(W[I]);
    while (I < High(W)) and (Cols + 1 + U8Cols(W[I + 1]) <= Width) do
    begin
      Inc(I);
      Inc(Cols, 1 + U8Cols(W[I]));
    end;
    SetLength(Out_, N + 1);
    Out_[N] := StringOfChar(' ', Lead) + SetLine(W, First, I, Width, Align, I = High(W));
    if Align in [alRight, alCenter] then
      Out_[N] := StringOfChar(' ', LeftMargin) + SetLine(W, First, I, RightMargin - LeftMargin, Align, I = High(W));
    Inc(N);
    First := I + 1;
    FirstLine := False;
  end;
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  ReplaceLines(E, L1, L2, Out_);
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := True;
end;

function AlignLines(E: TTveEditor; Align: TTveAlign; LeftMargin, RightMargin: Integer): Boolean;
var
  L1, L2: Int64;
  L: LongInt;
  S: AnsiString;
  W: TWordList;
  Out_: array of AnsiString;
  I: Integer;
  Pin: Integer;
begin
  Result := False;
  if ReadOnlyNow(E) or (RightMargin <= LeftMargin) or not E.AffectedLines(L1, L2) then
    Exit;
  SetLength(Out_, Integer(L2 - L1 + 1));
  for L := L1 to L2 do
  begin
    S := E.Doc.Buffer.LineText(L);
    W := Words(S);
    I := Integer(L - L1);
    if Length(W) = 0 then
      Out_[I] := ''
    else
      Out_[I] := StringOfChar(' ', LeftMargin) + SetLine(W, 0, High(W), RightMargin - LeftMargin, Align, True);
  end;
  E.NoteBefore;
  Pin := E.PinCursor;
  E.Doc.BeginGroup;
  ReplaceLines(E, L1, L2, Out_);
  E.Doc.EndGroup;
  E.UnpinCursor(Pin);
  E.NoteAfter;
  Result := True;
end;

end.
