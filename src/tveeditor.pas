{ TveEditor: the editing logic of one view of a document, with no screen: the cursor, the movements, typing and deleting, the selection and the clipboard.

  MIT. TveView (the TView) draws a TTveEditor and gives it the keys; everything that a key does is a method here, so it can be tested.

  The cursor is a line and a cell (see TveLayout). With the free cursor it can be past the end of the line; typing there pads the line with blanks. A cell inside a tab or a
  wide character is snapped to the start of that character. WantCell is the cell that Up and Down try to keep.

  The selection is one of three kinds: a stream (from the anchor to the cursor), whole lines, or a column block (the rectangle between the anchor and the cursor). Extend = True
  in a movement keeps the anchor (Shift+key); a movement without it drops the selection unless the blocks are persistent. }
unit TveEditor;

{$I tvdefs.inc}

interface

uses
  TveBuf, TveDoc, TveLayout;

type
  TTveSelKind = (skNone, skStream, skLine, skColumn);

  TTveOptions = record
    TabSize: Integer;
    IndentSize: Integer;
    InsertMode: Boolean;
    AutoIndent: Boolean;
    FreeCursor: Boolean;
    UseTabChars: Boolean;           { the Tab key and the filling of an indent use real tabs }
    SmartTab: Boolean;
    BackspaceUnindent: Boolean;
    PersistentBlocks: Boolean;
    OverwriteBlocks: Boolean;       { typing replaces the selection }
    AutoBrackets: Boolean;
    BracketPairs: AnsiString;       { opening and closing characters in pairs: '()[]{}' }
    SmartHome: Boolean;             { Home goes to the first non-blank first }
    UnlimitedUnindent: Boolean;     { unindent the lines that can, even when some cannot }
    ColumnBlocks: Boolean;          { a selection made by Shift and the arrows or by the mouse is a column block }
    WrapColumn: Integer;            { > 0: a word that goes past this cell moves to the next line while typing }
  end;

  TTveClipSet = procedure(const Text: AnsiString; Column: Boolean) of object;
  TTveClipGet = function(out Text: AnsiString; out Column: Boolean): Boolean of object;

  TTveEditor = class
  private
    FDoc: TTveDoc;
    FLine: Int64;
    FCell: Integer;
    FWant: Integer;
    FSelKind: TTveSelKind;
    FAnchorLine: Int64;
    FAnchorCell: Integer;
    FAnchorId: Integer;             { the anchor of a stream or line selection follows the edits }
    FEndId: Integer;                { >= 0: the far end is fixed too (marks of a block, not the cursor) }
    FMarks: array[0..9] of Integer; { anchors of the bookmarks, -1 where a bookmark is not set }
    FRows: Integer;
    FOnClipSet: TTveClipSet;
    FOnClipGet: TTveClipGet;
    function GetLineText(L: Int64): AnsiString;
    function CellsOf(L: Int64): Integer;
    procedure SetCursor(L: Int64; C: Integer; KeepWant: Boolean);
    procedure SnapCell(L: Int64; var C: Integer);
    function OffsetAt(L: Int64; C: Integer; out Pad: Integer): Int64;
    function CursorOffset: Int64;
    procedure PlaceAtOffset(Offset: Int64);
    procedure BeforeEdit;
    procedure AfterEdit;
    procedure BeginMove(Extend: Boolean);
    function IndentOf(const S: AnsiString): AnsiString;
    procedure WrapAtCursor;
    function FillCells(FromCell, ToCell: Integer): AnsiString;
    function PrevIndentCell(L: Int64; Cell: Integer): Integer;
    procedure SelBounds(out A, B: Int64);
    function SelectionLines(out L1, L2: Int64): Boolean;
  public
    Opt: TTveOptions;
    constructor Create(ADoc: TTveDoc);
    destructor Destroy; override;
    property Doc: TTveDoc read FDoc;
    property Line: Int64 read FLine;
    property Cell: Integer read FCell;
    property Rows: Integer read FRows write FRows;
    property SelKind: TTveSelKind read FSelKind;
    property OnClipSet: TTveClipSet read FOnClipSet write FOnClipSet;
    property OnClipGet: TTveClipGet read FOnClipGet write FOnClipGet;

    { The lines that a line command works on: the lines of the selection (a stream selection that ends at the start of a line does not take that line), else the current line. }
    function AffectedLines(out L1, L2: Int64): Boolean;
    { The cursor follows an edit: pin it before, put it back after (a position that moves with the text) }
    function PinCursor: Integer;
    procedure UnpinCursor(Id: Integer);
    procedure NoteBefore;
    procedure NoteAfter;
    procedure SetSelection(Kind: TTveSelKind; AnchorOffset: Int64);
    { A block with fixed ends (the marks of WordStar): it does not follow the cursor. Block = False: the selection is the cursor and the anchor again. }
    procedure SetBlockMarks(A, B: Int64);
    procedure FreezeSelection;
    function IsFrozen: Boolean;

    { bookmarks 0..9: they follow the edits }
    procedure SetBookmark(N: Integer);
    procedure ClearBookmark(N: Integer);
    function GotoBookmark(N: Integer): Boolean;
    function BookmarkLine(N: Integer): Int64;
    { the bracket that pairs with the one at the cursor (the pairs are Opt.BracketPairs and <>), False if there is none }
    function FindMatchingBracket(out Match: Int64): Boolean;
    function GotoMatchingBracket: Boolean;

    { positions }
    procedure GotoLineCell(L: Int64; C: Integer);
    procedure GotoOffset(Offset: Int64);
    function Offset: Int64;
    function LineCellToOffset(L: Int64; C: Integer): Int64;
    function CharAtCursor: AnsiString;

    { movements; Extend keeps the selection anchor (Shift) }
    procedure MoveLeft(Extend: Boolean = False);
    procedure MoveRight(Extend: Boolean = False);
    procedure MoveUp(Extend: Boolean = False);
    procedure MoveDown(Extend: Boolean = False);
    procedure MovePageUp(Extend: Boolean = False);
    procedure MovePageDown(Extend: Boolean = False);
    procedure MoveHome(Extend: Boolean = False);
    procedure MoveEnd(Extend: Boolean = False);
    procedure MoveWordLeft(Extend: Boolean = False);
    procedure MoveWordRight(Extend: Boolean = False);
    procedure MoveTextStart(Extend: Boolean = False);
    procedure MoveTextEnd(Extend: Boolean = False);

    { editing }
    function TypeText(const S: AnsiString): Boolean;
    function NewLine: Boolean;
    function Tab: Boolean;
    function Backspace: Boolean;
    function DeleteChar: Boolean;
    function DeleteLine: Boolean;
    function DeleteToEol: Boolean;
    function DeleteToBol: Boolean;
    function DeleteWordRight: Boolean;
    function DeleteWordLeft: Boolean;
    function Undo: Boolean;
    function Redo: Boolean;

    { selection and clipboard }
    procedure SelectAll;
    procedure SelectLine;
    procedure SelectWord;
    procedure StartSelection(Kind: TTveSelKind);
    procedure ClearSelection;
    function HasSelection: Boolean;
    function SelectionText(out Column: Boolean): AnsiString;
    function DeleteSelection: Boolean;
    function CopyBlock: Boolean;
    function CutBlock: Boolean;
    function Paste: Boolean;
    function PasteText(const Text: AnsiString; Column: Boolean): Boolean;
    { the rectangle of a column selection (cells, last exclusive) and the lines of the selection, False if the selection is not of that kind }
    function ColumnRect(out L1, L2: Int64; out C1, C2: Integer): Boolean;
    function SelectionRange(out A, B: Int64): Boolean;
  end;

function TveDefaultEditorOptions: TTveOptions;

implementation

uses
  SysUtils, TvUtf8;

function TveDefaultEditorOptions: TTveOptions;
begin
  Result.TabSize := 8;
  Result.IndentSize := 2;
  Result.InsertMode := True;
  Result.AutoIndent := True;
  Result.FreeCursor := True;
  Result.UseTabChars := False;
  Result.SmartTab := False;
  Result.BackspaceUnindent := True;
  Result.PersistentBlocks := False;
  Result.OverwriteBlocks := True;
  Result.AutoBrackets := False;
  Result.BracketPairs := '()[]{}';
  Result.SmartHome := True;
  Result.UnlimitedUnindent := False;
  Result.ColumnBlocks := False;
  Result.WrapColumn := 0;
end;

constructor TTveEditor.Create(ADoc: TTveDoc);
var
  I: Integer;
begin
  inherited Create;
  FDoc := ADoc;
  Opt := TveDefaultEditorOptions;
  FRows := 24;
  FAnchorId := -1;
  FEndId := -1;
  for I := 0 to 9 do
    FMarks[I] := -1;
end;

destructor TTveEditor.Destroy;
var
  I: Integer;
begin
  if FAnchorId >= 0 then
    FDoc.RemoveAnchor(FAnchorId);
  if FEndId >= 0 then
    FDoc.RemoveAnchor(FEndId);
  for I := 0 to 9 do
    if FMarks[I] >= 0 then
      FDoc.RemoveAnchor(FMarks[I]);
  inherited Destroy;
end;

{ --- positions --- }

function TTveEditor.GetLineText(L: Int64): AnsiString;
begin
  Result := FDoc.Buffer.LineText(L);
end;

function TTveEditor.CellsOf(L: Int64): Integer;
begin
  Result := LayoutCells(GetLineText(L), Opt.TabSize);
end;

{ A cell inside a character is snapped to the start of it (past the end of the line it stays, with the free cursor) }
procedure TTveEditor.SnapCell(L: Int64; var C: Integer);
var
  S: AnsiString;
  Info: TTveCharInfo;
  Cells: Integer;
begin
  if C < 0 then
    C := 0;
  S := GetLineText(L);
  Cells := LayoutCells(S, Opt.TabSize);
  if C >= Cells then
  begin
    if not Opt.FreeCursor then
      C := Cells;
    Exit;
  end;
  LayoutAtCell(S, C, Opt.TabSize, Info);
  C := Info.CellStart;
end;

procedure TTveEditor.SetCursor(L: Int64; C: Integer; KeepWant: Boolean);
begin
  if L < 0 then L := 0;
  if L >= FDoc.Buffer.LineCount then L := FDoc.Buffer.LineCount - 1;
  SnapCell(L, C);
  FLine := L;
  FCell := C;
  if not KeepWant then
    FWant := C;
end;

{ The offset of a cell; Pad is how many blanks the cell is past the end of the line }
function TTveEditor.OffsetAt(L: Int64; C: Integer; out Pad: Integer): Int64;
var
  S: AnsiString;
  Cells, Idx: Integer;
begin
  S := GetLineText(L);
  Cells := LayoutCells(S, Opt.TabSize);
  Pad := 0;
  if C >= Cells then
  begin
    Pad := C - Cells;
    Exit(FDoc.Buffer.LineStart(L) + Length(S));
  end;
  Idx := LayoutCellToIndex(S, C, Opt.TabSize);
  Result := FDoc.Buffer.LineStart(L) + Idx - 1;
end;

function TTveEditor.LineCellToOffset(L: Int64; C: Integer): Int64;
var
  Pad: Integer;
begin
  Result := OffsetAt(L, C, Pad);
end;

function TTveEditor.CursorOffset: Int64;
var
  Pad: Integer;
begin
  Result := OffsetAt(FLine, FCell, Pad);
end;

function TTveEditor.Offset: Int64;
begin
  Result := CursorOffset;
end;

function TTveEditor.PinCursor: Integer;
begin
  Result := FDoc.AddAnchor(CursorOffset, False);
end;

procedure TTveEditor.UnpinCursor(Id: Integer);
begin
  PlaceAtOffset(FDoc.AnchorPos(Id));
  FDoc.RemoveAnchor(Id);
end;

procedure TTveEditor.NoteBefore;
begin
  BeforeEdit;
end;

procedure TTveEditor.NoteAfter;
begin
  AfterEdit;
end;

procedure TTveEditor.SetSelection(Kind: TTveSelKind; AnchorOffset: Int64);
begin
  ClearSelection;
  FSelKind := Kind;
  FAnchorId := FDoc.AddAnchor(AnchorOffset);
  FAnchorLine := FDoc.Buffer.LineOfOffset(AnchorOffset);
  FAnchorCell := LayoutIndexToCell(GetLineText(FAnchorLine), AnchorOffset - FDoc.Buffer.LineStart(FAnchorLine) + 1, Opt.TabSize);
end;

procedure TTveEditor.SetBlockMarks(A, B: Int64);
begin
  ClearSelection;
  FSelKind := skStream;
  FAnchorId := FDoc.AddAnchor(A);
  FEndId := FDoc.AddAnchor(B);
  FAnchorLine := FDoc.Buffer.LineOfOffset(A);
  FAnchorCell := 0;
end;

procedure TTveEditor.FreezeSelection;
var
  A, B: Int64;
begin
  if (FSelKind in [skStream, skLine]) and (FEndId < 0) and SelectionRange(A, B) then
  begin
    ClearSelection;
    SetBlockMarks(A, B);
  end;
end;

function TTveEditor.IsFrozen: Boolean;
begin
  Result := FEndId >= 0;
end;

procedure TTveEditor.SetBookmark(N: Integer);
begin
  if (N < 0) or (N > 9) then
    Exit;
  if FMarks[N] >= 0 then
    FDoc.RemoveAnchor(FMarks[N]);
  FMarks[N] := FDoc.AddAnchor(FDoc.Buffer.LineStart(FLine));
end;

procedure TTveEditor.ClearBookmark(N: Integer);
begin
  if (N < 0) or (N > 9) or (FMarks[N] < 0) then
    Exit;
  FDoc.RemoveAnchor(FMarks[N]);
  FMarks[N] := -1;
end;

function TTveEditor.BookmarkLine(N: Integer): Int64;
begin
  Result := -1;
  if (N < 0) or (N > 9) or (FMarks[N] < 0) then
    Exit;
  Result := FDoc.Buffer.LineOfOffset(FDoc.AnchorPos(FMarks[N]));
end;

function TTveEditor.GotoBookmark(N: Integer): Boolean;
var
  L: Int64;
begin
  L := BookmarkLine(N);
  Result := L >= 0;
  if Result then
  begin
    BeginMove(False);
    SetCursor(L, FWant, True);
  end;
end;

function TTveEditor.FindMatchingBracket(out Match: Int64): Boolean;
var
  Pairs: AnsiString;
  Off, Len, P: Int64;
  Ch, Other: Char;
  K, Depth: Integer;
  Forward: Boolean;
begin
  Result := False;
  Match := -1;
  Pairs := Opt.BracketPairs + '<>';
  Off := CursorOffset;
  Len := FDoc.Buffer.Length;
  if Off >= Len then
    Exit;
  Ch := Char(FDoc.Buffer.ByteAt(Off));
  K := Pos(Ch, Pairs);
  if K = 0 then
    Exit;
  Forward := K mod 2 = 1;
  if Forward then
    Other := Pairs[K + 1]
  else
    Other := Pairs[K - 1];
  Depth := 0;
  P := Off;
  while True do
  begin
    if Forward then
      Inc(P)
    else
      Dec(P);
    if (P < 0) or (P >= Len) then
      Exit;
    if Char(FDoc.Buffer.ByteAt(P)) = Ch then
      Inc(Depth)
    else if Char(FDoc.Buffer.ByteAt(P)) = Other then
    begin
      if Depth = 0 then
      begin
        Match := P;
        Exit(True);
      end;
      Dec(Depth);
    end;
  end;
end;

function TTveEditor.GotoMatchingBracket: Boolean;
var
  M: Int64;
begin
  Result := FindMatchingBracket(M);
  if Result then
  begin
    BeginMove(False);
    PlaceAtOffset(M);
  end;
end;

function TTveEditor.AffectedLines(out L1, L2: Int64): Boolean;
var
  A, B: Int64;
  C1, C2: Integer;
begin
  Result := True;
  if (FSelKind = skColumn) and HasSelection then
  begin
    ColumnRect(L1, L2, C1, C2);
    Exit;
  end;
  if HasSelection and SelectionRange(A, B) then
  begin
    L1 := FDoc.Buffer.LineOfOffset(A);
    L2 := FDoc.Buffer.LineOfOffset(B);
    if (L2 > L1) and (B = FDoc.Buffer.LineStart(L2)) then
      Dec(L2);
    Exit;
  end;
  L1 := FLine;
  L2 := FLine;
end;

procedure TTveEditor.PlaceAtOffset(Offset: Int64);
var
  L: Int64;
  S: AnsiString;
begin
  if Offset < 0 then Offset := 0;
  if Offset > FDoc.Buffer.Length then Offset := FDoc.Buffer.Length;
  L := FDoc.Buffer.LineOfOffset(Offset);
  S := GetLineText(L);
  SetCursor(L, LayoutIndexToCell(S, Offset - FDoc.Buffer.LineStart(L) + 1, Opt.TabSize), False);
end;

procedure TTveEditor.GotoLineCell(L: Int64; C: Integer);
begin
  SetCursor(L, C, False);
end;

procedure TTveEditor.GotoOffset(Offset: Int64);
begin
  PlaceAtOffset(Offset);
end;

function TTveEditor.CharAtCursor: AnsiString;
var
  S: AnsiString;
  Info: TTveCharInfo;
begin
  S := GetLineText(FLine);
  LayoutAtCell(S, FCell, Opt.TabSize, Info);
  if Info.Bytes = 0 then
    Result := ''
  else
    Result := Copy(S, Info.Index, Info.Bytes);
end;

{ --- movements --- }

procedure TTveEditor.BeginMove(Extend: Boolean);
begin
  if Extend then
  begin
    if (FSelKind = skNone) or (FEndId >= 0) then
    begin
      if Opt.ColumnBlocks then
        StartSelection(skColumn)
      else
        StartSelection(skStream);
    end;
  end
  else if not Opt.PersistentBlocks then
    ClearSelection;
end;

procedure TTveEditor.MoveLeft(Extend: Boolean);
var
  S: AnsiString;
  Info: TTveCharInfo;
  Cells: Integer;
begin
  BeginMove(Extend);
  S := GetLineText(FLine);
  Cells := LayoutCells(S, Opt.TabSize);
  if FCell > Cells then
    SetCursor(FLine, FCell - 1, False)
  else if FCell > 0 then
  begin
    LayoutAtCell(S, FCell - 1, Opt.TabSize, Info);
    SetCursor(FLine, Info.CellStart, False);
  end
  else if FLine > 0 then
    SetCursor(FLine - 1, CellsOf(FLine - 1), False);
end;

procedure TTveEditor.MoveRight(Extend: Boolean);
var
  S: AnsiString;
  Info: TTveCharInfo;
  Cells: Integer;
begin
  BeginMove(Extend);
  S := GetLineText(FLine);
  Cells := LayoutCells(S, Opt.TabSize);
  if FCell >= Cells then
  begin
    if Opt.FreeCursor then
      SetCursor(FLine, FCell + 1, False)
    else if FLine < FDoc.Buffer.LineCount - 1 then
      SetCursor(FLine + 1, 0, False);
    Exit;
  end;
  LayoutAtCell(S, FCell, Opt.TabSize, Info);
  SetCursor(FLine, Info.CellStart + Info.Cells, False);
end;

procedure TTveEditor.MoveUp(Extend: Boolean);
begin
  BeginMove(Extend);
  if FLine > 0 then
    SetCursor(FLine - 1, FWant, True);
end;

procedure TTveEditor.MoveDown(Extend: Boolean);
begin
  BeginMove(Extend);
  if FLine < FDoc.Buffer.LineCount - 1 then
    SetCursor(FLine + 1, FWant, True);
end;

procedure TTveEditor.MovePageUp(Extend: Boolean);
begin
  BeginMove(Extend);
  SetCursor(FLine - FRows + 1, FWant, True);
end;

procedure TTveEditor.MovePageDown(Extend: Boolean);
begin
  BeginMove(Extend);
  SetCursor(FLine + FRows - 1, FWant, True);
end;

procedure TTveEditor.MoveHome(Extend: Boolean);
var
  S: AnsiString;
  I, Cells: Integer;
  C: TTveCharInfo;
  First: Integer;
begin
  BeginMove(Extend);
  First := 0;
  if Opt.SmartHome then
  begin
    S := GetLineText(FLine);
    I := 1;
    Cells := 0;
    while I <= Length(S) do
    begin
      LayoutChar(S, I, Cells, Opt.TabSize, C);
      if (S[I] <> ' ') and (S[I] <> #9) then
        Break;
      Inc(Cells, C.Cells);
      Inc(I, C.Bytes);
    end;
    if I <= Length(S) then
      First := Cells;
  end;
  if (First > 0) and (FCell <> First) then
    SetCursor(FLine, First, False)
  else
    SetCursor(FLine, 0, False);
end;

procedure TTveEditor.MoveEnd(Extend: Boolean);
begin
  BeginMove(Extend);
  SetCursor(FLine, CellsOf(FLine), False);
end;

procedure TTveEditor.MoveWordLeft(Extend: Boolean);
var
  Off, A: Int64;
  S: AnsiString;
  Used: Integer;
  CP: LongWord;
  Buf: AnsiString;
  I: Integer;

  function CpBefore(O: Int64): LongWord;
  var
    K: Integer;
  begin
    { the code point that ends at O }
    K := 1;
    while (K <= 4) and (O - K >= 0) and ((FDoc.Buffer.ByteAt(O - K) and $C0) = $80) do
      Inc(K);
    Buf := FDoc.Buffer.Copy(O - K, K);
    if Utf8Enabled and (K >= 1) and (Byte(Buf[1]) >= $80) and Utf8Decode(@Buf[1], Length(Buf), CP, Used) then
      Result := CP
    else
      Result := FDoc.Buffer.ByteAt(O - 1);
  end;

  function SizeBefore(O: Int64): Integer;
  var
    K: Integer;
  begin
    K := 1;
    if Utf8Enabled then
      while (K <= 4) and (O - K >= 0) and ((FDoc.Buffer.ByteAt(O - K) and $C0) = $80) do
        Inc(K);
    Result := K;
  end;

begin
  BeginMove(Extend);
  Off := CursorOffset;
  { blanks (and line ends) first, then a word or a run of signs }
  while (Off > 0) and (CpBefore(Off) <= 32) do
    Dec(Off, SizeBefore(Off));
  if Off > 0 then
  begin
    if IsWordCp(CpBefore(Off)) then
      while (Off > 0) and IsWordCp(CpBefore(Off)) do
        Dec(Off, SizeBefore(Off))
    else
      while (Off > 0) and (CpBefore(Off) > 32) and not IsWordCp(CpBefore(Off)) do
        Dec(Off, SizeBefore(Off));
  end;
  A := Off;
  PlaceAtOffset(A);
end;

procedure TTveEditor.MoveWordRight(Extend: Boolean);
var
  Off, Len: Int64;
  Buf: AnsiString;
  CP: LongWord;
  Used: Integer;

  function CpAt(O: Int64): LongWord;
  begin
    Buf := FDoc.Buffer.Copy(O, 4);
    if Buf = '' then Exit(0);
    if Utf8Enabled and (Byte(Buf[1]) >= $80) and Utf8Decode(@Buf[1], Length(Buf), CP, Used) and (Used > 1) then
      Result := CP
    else
      Result := Byte(Buf[1]);
  end;

  function SizeAt(O: Int64): Integer;
  begin
    Buf := FDoc.Buffer.Copy(O, 4);
    if (Buf <> '') and Utf8Enabled and (Byte(Buf[1]) >= $80) and Utf8Decode(@Buf[1], Length(Buf), CP, Used) and (Used > 1) then
      Result := Used
    else
      Result := 1;
  end;

begin
  BeginMove(Extend);
  Off := CursorOffset;
  Len := FDoc.Buffer.Length;
  if Off < Len then
  begin
    if IsWordCp(CpAt(Off)) then
      while (Off < Len) and IsWordCp(CpAt(Off)) do
        Inc(Off, SizeAt(Off))
    else if CpAt(Off) > 32 then
      while (Off < Len) and (CpAt(Off) > 32) and not IsWordCp(CpAt(Off)) do
        Inc(Off, SizeAt(Off));
    while (Off < Len) and (CpAt(Off) <= 32) and (CpAt(Off) <> 10) do
      Inc(Off);
    if (Off < Len) and (CpAt(Off) = 10) and (Off = CursorOffset) then
      Inc(Off);
  end;
  PlaceAtOffset(Off);
end;

procedure TTveEditor.MoveTextStart(Extend: Boolean);
begin
  BeginMove(Extend);
  SetCursor(0, 0, False);
end;

procedure TTveEditor.MoveTextEnd(Extend: Boolean);
begin
  BeginMove(Extend);
  SetCursor(FDoc.Buffer.LineCount - 1, CellsOf(FDoc.Buffer.LineCount - 1), False);
end;

{ --- the selection --- }

procedure TTveEditor.StartSelection(Kind: TTveSelKind);
begin
  if FAnchorId >= 0 then
    FDoc.RemoveAnchor(FAnchorId);
  if FEndId >= 0 then
    FDoc.RemoveAnchor(FEndId);
  FEndId := -1;
  FSelKind := Kind;
  FAnchorLine := FLine;
  FAnchorCell := FCell;
  FAnchorId := FDoc.AddAnchor(CursorOffset);
end;

procedure TTveEditor.ClearSelection;
begin
  if FAnchorId >= 0 then
    FDoc.RemoveAnchor(FAnchorId);
  if FEndId >= 0 then
    FDoc.RemoveAnchor(FEndId);
  FEndId := -1;
  FAnchorId := -1;
  FSelKind := skNone;
end;

function TTveEditor.HasSelection: Boolean;
var
  A, B: Int64;
  L1, L2: Int64;
  C1, C2: Integer;
begin
  case FSelKind of
    skNone: Result := False;
    skStream, skLine: Result := SelectionRange(A, B) and (B > A);
    skColumn: Result := ColumnRect(L1, L2, C1, C2) and (C2 > C1);
  end;
end;

function TTveEditor.SelectionLines(out L1, L2: Int64): Boolean;
begin
  Result := FSelKind <> skNone;
  if not Result then Exit;
  if FSelKind = skColumn then
  begin
    L1 := FAnchorLine; L2 := FLine;
  end
  else
  begin
    L1 := FDoc.Buffer.LineOfOffset(FDoc.AnchorPos(FAnchorId));
    L2 := FLine;
    if FEndId >= 0 then
      L2 := FDoc.Buffer.LineOfOffset(FDoc.AnchorPos(FEndId));
  end;
  if L2 < L1 then
  begin
    L1 := L1 xor L2; L2 := L1 xor L2; L1 := L1 xor L2;
  end;
end;

{ The byte range of a stream or line selection }
function TTveEditor.SelectionRange(out A, B: Int64): Boolean;
var
  P, Q, T: Int64;
  L1, L2: Int64;
begin
  Result := False;
  A := 0; B := 0;
  if FSelKind in [skNone, skColumn] then
    Exit;
  P := FDoc.AnchorPos(FAnchorId);
  if FEndId >= 0 then
    Q := FDoc.AnchorPos(FEndId)
  else
    Q := CursorOffset;
  if Q < P then
  begin
    T := P; P := Q; Q := T;
  end;
  if FSelKind = skLine then
  begin
    L1 := FDoc.Buffer.LineOfOffset(P);
    L2 := FDoc.Buffer.LineOfOffset(Q);
    P := FDoc.Buffer.LineStart(L1);
    if L2 + 1 < FDoc.Buffer.LineCount then
      Q := FDoc.Buffer.LineStart(L2 + 1)
    else
      Q := FDoc.Buffer.Length;
  end;
  A := P; B := Q;
  Result := True;
end;

procedure TTveEditor.SelBounds(out A, B: Int64);
begin
  SelectionRange(A, B);
end;

function TTveEditor.ColumnRect(out L1, L2: Int64; out C1, C2: Integer): Boolean;
begin
  Result := FSelKind = skColumn;
  if not Result then Exit;
  L1 := FAnchorLine; L2 := FLine;
  if L2 < L1 then
  begin
    L1 := L1 xor L2; L2 := L1 xor L2; L1 := L1 xor L2;
  end;
  C1 := FAnchorCell; C2 := FCell;
  if C2 < C1 then
  begin
    C1 := C1 xor C2; C2 := C1 xor C2; C1 := C1 xor C2;
  end;
end;

procedure TTveEditor.SelectAll;
begin
  SetCursor(0, 0, False);
  StartSelection(skStream);
  SetCursor(FDoc.Buffer.LineCount - 1, CellsOf(FDoc.Buffer.LineCount - 1), False);
end;

procedure TTveEditor.SelectLine;
begin
  StartSelection(skLine);
end;

procedure TTveEditor.SelectWord;
var
  Off, A, B, Len: Int64;
  Buf: AnsiString;
  CP: LongWord;
  Used: Integer;

  function CpAt(O: Int64): LongWord;
  begin
    Buf := FDoc.Buffer.Copy(O, 4);
    if Buf = '' then Exit(0);
    if Utf8Enabled and (Byte(Buf[1]) >= $80) and Utf8Decode(@Buf[1], Length(Buf), CP, Used) and (Used > 1) then
      Result := CP
    else
      Result := Byte(Buf[1]);
  end;

  function PrevStart(O: Int64): Int64;
  begin
    Result := O - 1;
    if Utf8Enabled then
      while (Result > 0) and ((FDoc.Buffer.ByteAt(Result) and $C0) = $80) do
        Dec(Result);
  end;

  function NextEnd(O: Int64): Int64;
  begin
    Buf := FDoc.Buffer.Copy(O, 4);
    if (Buf <> '') and Utf8Enabled and (Byte(Buf[1]) >= $80) and Utf8Decode(@Buf[1], Length(Buf), CP, Used) and (Used > 1) then
      Result := O + Used
    else
      Result := O + 1;
  end;

begin
  Off := CursorOffset;
  Len := FDoc.Buffer.Length;
  if (Off >= Len) or not IsWordCp(CpAt(Off)) then
    Exit;
  A := Off;
  while (A > 0) and IsWordCp(CpAt(PrevStart(A))) do
    A := PrevStart(A);
  B := Off;
  while (B < Len) and IsWordCp(CpAt(B)) do
    B := NextEnd(B);
  PlaceAtOffset(A);
  StartSelection(skStream);
  PlaceAtOffset(B);
end;

function TTveEditor.SelectionText(out Column: Boolean): AnsiString;
var
  A, B, L1, L2: Int64;
  L: LongInt;
  C1, C2: Integer;
  S: AnsiString;
  I1, I2: Integer;
begin
  Result := '';
  Column := False;
  if not HasSelection then
    Exit;
  if FSelKind = skColumn then
  begin
    Column := True;
    ColumnRect(L1, L2, C1, C2);
    for L := L1 to L2 do
    begin
      S := GetLineText(L);
      I1 := LayoutCellToIndex(S, C1, Opt.TabSize);
      I2 := LayoutCellToIndex(S, C2, Opt.TabSize);
      S := LayoutSlice(S, C1, C2, Opt.TabSize);
      Result := Result + S;
      if L < L2 then
        Result := Result + #10;
    end;
    Exit;
  end;
  SelectionRange(A, B);
  Result := FDoc.Buffer.Copy(A, B - A);
end;

{ --- editing --- }

procedure TTveEditor.BeforeEdit;
begin
  FDoc.NoteCursor(CursorOffset);
end;

procedure TTveEditor.AfterEdit;
begin
  FDoc.NoteCursorAfter(CursorOffset);
end;

function TTveEditor.IndentOf(const S: AnsiString): AnsiString;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) do
    Inc(I);
  Result := Copy(S, 1, I - 1);
end;

{ The blanks that take the cursor from one cell to another: tabs where the option says so }
function TTveEditor.FillCells(FromCell, ToCell: Integer): AnsiString;
var
  Stop: Integer;
begin
  Result := '';
  if ToCell <= FromCell then
    Exit;
  if Opt.UseTabChars and (Opt.TabSize > 0) then
    while True do
    begin
      Stop := FromCell - (FromCell mod Opt.TabSize) + Opt.TabSize;
      if Stop > ToCell then
        Break;
      Result := Result + #9;
      FromCell := Stop;
    end;
  Result := Result + StringOfChar(' ', ToCell - FromCell);
end;

function TTveEditor.DeleteSelection: Boolean;
var
  A, B, L1, L2: Int64;
  L: LongInt;
  C1, C2: Integer;
  S: AnsiString;
  I1, I2: Integer;
begin
  Result := False;
  if FDoc.ReadOnly or not HasSelection then
    Exit;
  BeforeEdit;
  if FSelKind = skColumn then
  begin
    ColumnRect(L1, L2, C1, C2);
    FDoc.BeginGroup;
    for L := L2 downto L1 do
    begin
      S := GetLineText(L);
      if LayoutCells(S, Opt.TabSize) <= C1 then
        Continue;
      I1 := LayoutCellToIndex(S, C1, Opt.TabSize);
      I2 := LayoutCellToIndex(S, C2, Opt.TabSize);
      FDoc.Delete(FDoc.Buffer.LineStart(L) + I1 - 1, I2 - I1);
    end;
    FDoc.EndGroup;
    ClearSelection;
    SetCursor(L1, C1, False);
    AfterEdit;
    Exit(True);
  end;
  SelectionRange(A, B);
  FDoc.Delete(A, B - A);
  ClearSelection;
  PlaceAtOffset(A);
  AfterEdit;
  Result := True;
end;

procedure TTveEditor.WrapAtCursor;
var
  LineS, Ins: AnsiString;
  CurIdx, I, BP, BE, IndentLen: Integer;
  LS, CurOff, NewCur: Int64;
begin
  LineS := GetLineText(FLine);
  if LayoutCells(LineS, Opt.TabSize) <= Opt.WrapColumn then
    Exit;
  CurIdx := LayoutCellToIndex(LineS, FCell, Opt.TabSize);
  if CurIdx <= Length(LineS) then
    Exit;                                   // only at the end of the line
  IndentLen := Length(IndentOf(LineS));
  BP := 0;
  for I := Length(LineS) downto IndentLen + 1 do
    if (LineS[I] in [' ', #9]) and (LayoutIndexToCell(LineS, I, Opt.TabSize) <= Opt.WrapColumn) then
    begin
      BP := I;
      Break;
    end;
  if BP = 0 then
    Exit;
  while (BP > IndentLen + 1) and (LineS[BP - 1] in [' ', #9]) do
    Dec(BP);
  BE := BP;
  while (BE <= Length(LineS)) and (LineS[BE] in [' ', #9]) do
    Inc(BE);
  if BE > Length(LineS) then
    Exit;
  if Opt.AutoIndent then
    Ins := #10 + IndentOf(LineS)
  else
    Ins := #10;
  LS := FDoc.Buffer.LineStart(FLine);
  CurOff := CursorOffset;
  FDoc.Replace(LS + BP - 1, BE - BP, Ins);
  NewCur := CurOff - (BE - BP) + Length(Ins);
  PlaceAtOffset(NewCur);
end;

function TTveEditor.TypeText(const S: AnsiString): Boolean;
var
  Off: Int64;
  Pad: Integer;
  Ins: AnsiString;
  Closer, Opener: Char;
  K: Integer;
  Info: TTveCharInfo;
  LineS: AnsiString;
  Grouped: Boolean;
begin
  Result := False;
  if FDoc.ReadOnly or (S = '') then
    Exit;
  if (S = #10) or (S = #13) then
    Exit(NewLine);
  Grouped := HasSelection and Opt.OverwriteBlocks;
  if Grouped then
    FDoc.BeginGroup;
  try
    if Grouped then
      DeleteSelection
    else if not Opt.PersistentBlocks then
      ClearSelection;
    BeforeEdit;
    LineS := GetLineText(FLine);
    { a closing bracket that is already there is skipped }
    if Opt.AutoBrackets and (Length(S) = 1) then
    begin
      K := Pos(S, Opt.BracketPairs);
      if (K > 0) and (K mod 2 = 0) and (CharAtCursor = S) then
      begin
        MoveRight;
        AfterEdit;
        Exit(True);
      end;
    end;
    Off := OffsetAt(FLine, FCell, Pad);
    Ins := S;
    if Pad > 0 then
      Ins := FillCells(CellsOf(FLine), FCell) + Ins;
    if (not Opt.InsertMode) and (Pad = 0) then
    begin
      LayoutAtCell(LineS, FCell, Opt.TabSize, Info);
      if (Info.Bytes > 0) then
        FDoc.Replace(Off, Info.Bytes, Ins)
      else
        FDoc.Insert(Off, Ins);
    end
    else
      FDoc.Insert(Off, Ins);
    PlaceAtOffset(Off + Length(Ins));
    if (Opt.WrapColumn > 0) and (Length(S) = 1) and not (S[1] in [' ', #9]) then
      WrapAtCursor;
    if Opt.AutoBrackets and (Length(S) = 1) then
    begin
      K := Pos(S, Opt.BracketPairs);
      if (K > 0) and (K mod 2 = 1) then
      begin
        Closer := Opt.BracketPairs[K + 1];
        Opener := S[1];
        if Opener <> Closer then
        begin
          FDoc.Insert(Off + Length(Ins), Closer);
          PlaceAtOffset(Off + Length(Ins));
        end;
      end;
    end;
    AfterEdit;
  finally
    if Grouped then
      FDoc.EndGroup;
  end;
  Result := True;
end;

function TTveEditor.NewLine: Boolean;
var
  Off: Int64;
  Pad: Integer;
  LineS, Indent, Ins: AnsiString;
  Idx: Integer;
  Grouped: Boolean;
begin
  Result := False;
  if FDoc.ReadOnly then
    Exit;
  Grouped := HasSelection and Opt.OverwriteBlocks;
  if Grouped then
    FDoc.BeginGroup;
  try
    if Grouped then
      DeleteSelection;
    BeforeEdit;
    LineS := GetLineText(FLine);
    Off := OffsetAt(FLine, FCell, Pad);
    Indent := '';
    if Opt.AutoIndent then
    begin
      Indent := IndentOf(LineS);
      { only the part of the indent that is before the cursor }
      Idx := LayoutCellToIndex(LineS, FCell, Opt.TabSize);
      if Length(Indent) >= Idx then
        Indent := Copy(Indent, 1, Idx - 1);
    end;
    Ins := #10 + Indent;
    FDoc.Insert(Off, Ins);
    PlaceAtOffset(Off + Length(Ins));
    AfterEdit;
  finally
    if Grouped then
      FDoc.EndGroup;
  end;
  Result := True;
end;

{ The cell of the first non-blank of the nearest line above that is less than Cell (the stop of "unindent") }
function TTveEditor.PrevIndentCell(L: Int64; Cell: Integer): Integer;
var
  K: Int64;
  S: AnsiString;
  I, Cells: Integer;
  C: TTveCharInfo;
begin
  Result := 0;
  K := L - 1;
  while K >= 0 do
  begin
    S := GetLineText(K);
    I := 1;
    Cells := 0;
    while I <= Length(S) do
    begin
      LayoutChar(S, I, Cells, Opt.TabSize, C);
      if (S[I] <> ' ') and (S[I] <> #9) then
        Break;
      Inc(Cells, C.Cells);
      Inc(I, C.Bytes);
    end;
    if (I <= Length(S)) and (Cells < Cell) then
      Exit(Cells);
    Dec(K);
  end;
end;

function TTveEditor.Tab: Boolean;
var
  Stop, Target, Cells: Integer;
  Off: Int64;
  Pad: Integer;
  LineS, Above: AnsiString;
  K: Int64;
  C: TTveCharInfo;
  I: Integer;
  Ins: AnsiString;
  Grouped: Boolean;
begin
  Result := False;
  if FDoc.ReadOnly then
    Exit;
  if Opt.TabSize < 1 then
    Opt.TabSize := 8;
  Stop := FCell - (FCell mod Opt.TabSize) + Opt.TabSize;
  Target := Stop;
  if Opt.SmartTab and (FLine > 0) then
  begin
    { the next word start of the nearest line above that has text beyond the cursor }
    K := FLine - 1;
    while K >= 0 do
    begin
      Above := GetLineText(K);
      if Trim(Above) <> '' then
      begin
        I := 1;
        Cells := 0;
        while I <= Length(Above) do
        begin
          LayoutChar(Above, I, Cells, Opt.TabSize, C);
          if (Cells > FCell) and (I > 1) and ((Above[I - 1] = ' ') or (Above[I - 1] = #9)) and (Above[I] <> ' ') and (Above[I] <> #9) then
          begin
            Target := Cells;
            Break;
          end;
          Inc(Cells, C.Cells);
          Inc(I, C.Bytes);
        end;
        Break;
      end;
      Dec(K);
    end;
  end;
  Grouped := HasSelection and Opt.OverwriteBlocks;
  if Grouped then
    FDoc.BeginGroup;
  try
    if Grouped then
      DeleteSelection;
    BeforeEdit;
    LineS := GetLineText(FLine);
    Off := OffsetAt(FLine, FCell, Pad);
    if (Target = Stop) and Opt.UseTabChars and (Pad = 0) then
      Ins := #9
    else
    begin
      Ins := '';
      if Pad > 0 then
        Ins := FillCells(CellsOf(FLine), FCell);
      Ins := Ins + FillCells(FCell, Target);
    end;
    FDoc.Insert(Off, Ins);
    PlaceAtOffset(Off + Length(Ins));
    AfterEdit;
  finally
    if Grouped then
      FDoc.EndGroup;
  end;
  Result := True;
end;

function TTveEditor.Backspace: Boolean;
var
  Off: Int64;
  Pad: Integer;
  LineS: AnsiString;
  Info: TTveCharInfo;
  Target, I: Integer;
  OnlyBlank: Boolean;
  A, B: Int64;
begin
  Result := False;
  if FDoc.ReadOnly then
    Exit;
  if HasSelection and Opt.OverwriteBlocks then
    Exit(DeleteSelection);
  LineS := GetLineText(FLine);
  if FCell > CellsOf(FLine) then
  begin
    SetCursor(FLine, FCell - 1, False);          { in the free space: only the cursor moves }
    Exit(True);
  end;
  if FCell = 0 then
  begin
    if FLine = 0 then
      Exit;
    BeforeEdit;
    Off := FDoc.Buffer.LineStart(FLine) - 1;     { the line end before }
    FDoc.Delete(Off, 1);
    PlaceAtOffset(Off);
    AfterEdit;
    Exit(True);
  end;
  BeforeEdit;
  if Opt.BackspaceUnindent then
  begin
    OnlyBlank := True;
    I := LayoutCellToIndex(LineS, FCell, Opt.TabSize) - 1;
    while I >= 1 do
    begin
      if (LineS[I] <> ' ') and (LineS[I] <> #9) then
      begin
        OnlyBlank := False;
        Break;
      end;
      Dec(I);
    end;
    if OnlyBlank then
    begin
      Target := PrevIndentCell(FLine, FCell);
      A := OffsetAt(FLine, Target, I);
      B := OffsetAt(FLine, FCell, I);
      if B > A then
      begin
        FDoc.Delete(A, B - A);
        PlaceAtOffset(A);
        AfterEdit;
        Exit(True);
      end;
    end;
  end;
  LayoutAtCell(LineS, FCell - 1, Opt.TabSize, Info);
  Off := FDoc.Buffer.LineStart(FLine) + Info.Index - 1;
  FDoc.Delete(Off, Info.Bytes);
  PlaceAtOffset(Off);
  AfterEdit;
  Result := True;
end;

function TTveEditor.DeleteChar: Boolean;
var
  Off: Int64;
  Pad: Integer;
  LineS: AnsiString;
  Info: TTveCharInfo;
begin
  Result := False;
  if FDoc.ReadOnly then
    Exit;
  if HasSelection and Opt.OverwriteBlocks then
    Exit(DeleteSelection);
  LineS := GetLineText(FLine);
  Off := OffsetAt(FLine, FCell, Pad);
  if Pad > 0 then
    Exit;
  BeforeEdit;
  LayoutAtCell(LineS, FCell, Opt.TabSize, Info);
  if Info.Bytes = 0 then
  begin
    if FLine >= FDoc.Buffer.LineCount - 1 then
      Exit;
    FDoc.Delete(Off, 1);                         { the line end: join the next line }
  end
  else
    FDoc.Delete(Off, Info.Bytes);
  PlaceAtOffset(Off);
  AfterEdit;
  Result := True;
end;

function TTveEditor.DeleteLine: Boolean;
var
  A, B: Int64;
begin
  Result := False;
  if FDoc.ReadOnly then
    Exit;
  BeforeEdit;
  A := FDoc.Buffer.LineStart(FLine);
  if FLine + 1 < FDoc.Buffer.LineCount then
    B := FDoc.Buffer.LineStart(FLine + 1)
  else
  begin
    B := FDoc.Buffer.Length;
    if A > 0 then
      Dec(A);                                    { the last line: take the line end before it }
  end;
  if B = A then
    Exit;
  FDoc.Delete(A, B - A);
  ClearSelection;
  SetCursor(FLine, FWant, True);
  AfterEdit;
  Result := True;
end;

function TTveEditor.DeleteToEol: Boolean;
var
  A, B: Int64;
  Pad: Integer;
begin
  Result := False;
  if FDoc.ReadOnly then
    Exit;
  BeforeEdit;
  A := OffsetAt(FLine, FCell, Pad);
  B := FDoc.Buffer.LineEnd(FLine);
  if (Pad > 0) or (B <= A) then
    Exit;
  FDoc.Delete(A, B - A);
  PlaceAtOffset(A);
  AfterEdit;
  Result := True;
end;

function TTveEditor.DeleteToBol: Boolean;
var
  A, B: Int64;
  Pad: Integer;
begin
  Result := False;
  if FDoc.ReadOnly then
    Exit;
  BeforeEdit;
  A := FDoc.Buffer.LineStart(FLine);
  B := OffsetAt(FLine, FCell, Pad);
  if B <= A then
    Exit;
  FDoc.Delete(A, B - A);
  PlaceAtOffset(A);
  AfterEdit;
  Result := True;
end;

function TTveEditor.DeleteWordRight: Boolean;
var
  A, B: Int64;
  SaveSel: TTveSelKind;
begin
  Result := False;
  if FDoc.ReadOnly then
    Exit;
  SaveSel := FSelKind;
  ClearSelection;
  A := CursorOffset;
  MoveWordRight;
  B := CursorOffset;
  PlaceAtOffset(A);
  if B <= A then
    Exit;
  BeforeEdit;
  FDoc.Delete(A, B - A);
  PlaceAtOffset(A);
  AfterEdit;
  Result := True;
end;

function TTveEditor.DeleteWordLeft: Boolean;
var
  A, B: Int64;
begin
  Result := False;
  if FDoc.ReadOnly then
    Exit;
  ClearSelection;
  B := CursorOffset;
  MoveWordLeft;
  A := CursorOffset;
  if B <= A then
    Exit;
  PlaceAtOffset(B);
  BeforeEdit;
  FDoc.Delete(A, B - A);
  PlaceAtOffset(A);
  AfterEdit;
  Result := True;
end;

function TTveEditor.Undo: Boolean;
var
  C: Int64;
begin
  BeforeEdit;
  Result := FDoc.Undo(C);
  if Result then
  begin
    ClearSelection;
    PlaceAtOffset(C);
  end;
end;

function TTveEditor.Redo: Boolean;
var
  C: Int64;
begin
  BeforeEdit;
  Result := FDoc.Redo(C);
  if Result then
  begin
    ClearSelection;
    PlaceAtOffset(C);
  end;
end;

{ --- the clipboard --- }

function TTveEditor.CopyBlock: Boolean;
var
  Col: Boolean;
  T: AnsiString;
begin
  T := SelectionText(Col);
  Result := T <> '';
  if Result and Assigned(FOnClipSet) then
    FOnClipSet(T, Col);
end;

function TTveEditor.CutBlock: Boolean;
begin
  Result := CopyBlock;
  if Result then
    DeleteSelection;
end;

function TTveEditor.PasteText(const Text: AnsiString; Column: Boolean): Boolean;
var
  Off: Int64;
  Pad: Integer;
  Ins: AnsiString;
  Lines: array of AnsiString;
  N, I, P, Start: Integer;
  L: Int64;
  C: Integer;
  S: AnsiString;
  W: Integer;
begin
  Result := False;
  if FDoc.ReadOnly or (Text = '') then
    Exit;
  FDoc.BeginGroup;
  try
    if HasSelection and Opt.OverwriteBlocks then
      DeleteSelection;
    BeforeEdit;
    if not Column then
    begin
      Off := OffsetAt(FLine, FCell, Pad);
      Ins := Text;
      if Pad > 0 then
        Ins := FillCells(CellsOf(FLine), FCell) + Ins;
      FDoc.Insert(Off, Ins);
      PlaceAtOffset(Off + Length(Ins));
    end
    else
    begin
      { the lines of the block go to the same cells of the lines from the cursor down; a short line is padded, a missing line is made }
      N := 0;
      Start := 1;
      for P := 1 to Length(Text) + 1 do
        if (P = Length(Text) + 1) or (Text[P] = #10) then
        begin
          SetLength(Lines, N + 1);
          Lines[N] := Copy(Text, Start, P - Start);
          Inc(N);
          Start := P + 1;
        end;
      L := FLine;
      C := FCell;
      for I := 0 to N - 1 do
      begin
        if L + I >= FDoc.Buffer.LineCount then
          FDoc.Insert(FDoc.Buffer.Length, #10);
        S := GetLineText(L + I);
        W := LayoutCells(S, Opt.TabSize);
        Off := OffsetAt(L + I, C, Pad);
        Ins := Lines[I];
        if Pad > 0 then
          Ins := StringOfChar(' ', Pad) + Ins;
        if Ins <> '' then
          FDoc.Insert(Off, Ins);
      end;
      SetCursor(L + N - 1, C + LayoutCells(Lines[N - 1], Opt.TabSize), False);
    end;
    AfterEdit;
  finally
    FDoc.EndGroup;
  end;
  Result := True;
end;

function TTveEditor.Paste: Boolean;
var
  T: AnsiString;
  Col: Boolean;
begin
  Result := False;
  if not Assigned(FOnClipGet) then
    Exit;
  if not FOnClipGet(T, Col) then
    Exit;
  Result := PasteText(T, Col);
end;

end.
