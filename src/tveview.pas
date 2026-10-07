{ TveView: the editor as a Turbo Vision view.

  MIT.

  A TTveView shows a TTveDoc through a TTveEditor: the text with the syntax colours, the selection, the current line, the bookmarks in a gutter, a cursor that is a cell.
  It turns keys (by a key map of TveCmds, including chords of two keys), the mouse (click, drag, double and triple click, the wheel) and commands into calls of the
  editor. What needs the user (a search dialog, a file name, a line number) is the host's: the view calls OnHostCommand first for every command and does the command itself
  only when the host says it did not. A host that wants lines coloured (breakpoints, the line of an error, the line where the debugger stopped) sets OnLineAttr.

  The palette is the one of TScroller: 1 normal text, 2 selected text. The syntax colours are derived from the normal text (the background stays); a host can set
  its own with SetClassAttr. }
unit TveView;

{$I tvdefs.inc}
{$H+}

interface

uses
  TvGeom, TvObjs, TvColors, TvKeys, TvEvents, TvDrawBuf, TvViews, TvWindow,
  TveBuf, TveDoc, TveEditor, TveSearch, TveHl, TveCmds, TveFold, TveTemplates, TveComplete, TveDraw;

const
  cmTveStatus = $7A00;           { broadcast: the view changed its cursor or text }

type
  TTveHostCommand = function(Sender: TObject; Cmd: Integer): Boolean of object;
  TTveLineAttr = function(Sender: TObject; Line: Int64; var Attr: TColorAttr): Boolean of object;

  TTveView = class(TScroller)
  private
    FEditor: TTveEditor;
    FOwnDoc: Boolean;
    FHl: TTveHighlighter;
    FKeymap: TTveKeymap;
    FPrefix: TKey;
    FHavePrefix: Boolean;
    FClassAttr: array[0..hcClassCount - 1] of TColorAttr;
    FClassSet: array[0..hcClassCount - 1] of Boolean;
    FSearch: TTveSearchOptions;
    FSearcher: TTveSearcher;
    FOnHost: TTveHostCommand;
    FOnLineAttr: TTveLineAttr;
    FGutter: Boolean;
    FShowCurrentLine: Boolean;
    FRecording: Boolean;
    FMacro: array of Integer;
    FHistory: array of Int64;
    FWheelStep: Integer;
    FLastVersion: LongWord;
    FMarkA, FMarkB: Int64;
    FFolds: TTveFolds;
    FTemplates: TTveTemplates;
    FCompletion: TTveCompletion;
    FOnPrompt: TTvePrompt;
    FComplItems: TTveWords;
    FComplIdx: Integer;
    FComplStart: Int64;
    FComplEnd: Int64;
    FComplActive: Boolean;
    FComplFragment: AnsiString;
    FDrawMode: Integer;               // 0 off, 1 single lines, 2 double
    FKeysEnabled: Boolean;
    FMultiClick: Boolean;
    FHlA, FHlB: Int64;                // a highlighted range of the text (the match of a search), -1: none
    FHighlightColumn: Boolean;
    FMessage: AnsiString;
    function GetDoc: TTveDoc;
    function GetFolds: TTveFolds;
    procedure MoveVertical(Down: Boolean; Pages: Boolean);
    function GutterWidth: Integer;
    function TextWidth: Integer;
    procedure DocChanged(Doc: TTveDoc; Offset, Removed, Inserted: Int64);
    procedure KeepCursorVisible;
    procedure Sync;
    function Hit(Where: TPoint; out L: Int64; out C: Integer): Boolean;
    procedure DoMouse(var Event: TEvent);
    procedure Remember;
    procedure Complete;
    procedure Setup(ADoc: TTveDoc; OwnDoc: Boolean);
  protected
    // The colour of a class of the highlighter. A host that has its own palette overrides it.
    function ClassAttr(C: Integer): TColorAttr; virtual;
    // Called at the end of every change of the cursor, the selection or the text (after the view is redrawn): the place for a host to update its own state.
    procedure Changed; virtual;
    // The colours of the message row and of the highlighted range (the selection colours reversed by default).
    function NormalAttr: TColorAttr; virtual;
    function SelectedAttr: TColorAttr; virtual;
    function MessageAttr: TColorAttr; virtual;
    function HighlightAttr: TColorAttr; virtual;
  public
    constructor Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar; ADoc: TTveDoc; OwnDoc: Boolean = False);
    // From a stream (the scroll bars and the scrolling of TScroller); the document is the host's.
    constructor Load(S: TStream; ADoc: TTveDoc; OwnDoc: Boolean = False);
    destructor Destroy; override;
    property Editor: TTveEditor read FEditor;
    property Doc: TTveDoc read GetDoc;
    property Highlighter: TTveHighlighter read FHl;
    { Folds are created on first use. }
    property Folds: TTveFolds read GetFolds;
    property Templates: TTveTemplates read FTemplates write FTemplates;
    property Completion: TTveCompletion read FCompletion write FCompletion;
    property DrawMode: Integer read FDrawMode write FDrawMode;
    // False: the view does not handle keys by its key map (a host that has its own key handling uses the commands of the view and the mouse of it).
    property KeysEnabled: Boolean read FKeysEnabled write FKeysEnabled;
    // True (the default): a double click selects a word and a triple click a line.
    property MultiClick: Boolean read FMultiClick write FMultiClick;
    property HighlightColumn: Boolean read FHighlightColumn write FHighlightColumn;
    // A message in the first or last row of the view, whichever is farther from the cursor (an error of the compiler); '' for none.
    property MessageText: AnsiString read FMessage write FMessage;
    // The highlighted range (offsets), drawn in the colour 3 of the palette of the view (or as a selection); A = B clears it.
    procedure SetHighlightRange(A, B: Int64);
    procedure GetHighlightRange(out A, B: Int64);
    property OnPrompt: TTvePrompt read FOnPrompt write FOnPrompt;
    property Keymap: TTveKeymap read FKeymap write FKeymap;
    property OnHostCommand: TTveHostCommand read FOnHost write FOnHost;
    property OnLineAttr: TTveLineAttr read FOnLineAttr write FOnLineAttr;
    property Gutter: Boolean read FGutter write FGutter;
    property ShowCurrentLine: Boolean read FShowCurrentLine write FShowCurrentLine;
    property WheelStep: Integer read FWheelStep write FWheelStep;
    property SearchOptions: TTveSearchOptions read FSearch write FSearch;
    property Recording: Boolean read FRecording;

    procedure SetLanguage(ALang: TTveLanguage);
    procedure SetClassAttr(C: Integer; const Attr: TColorAttr);

    procedure SetState(AState: Word; Enable: Boolean); override;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ChangeBounds(const Bounds: TRect); override;

    { Runs a command (the host's first). True if something was done. }
    function Execute(Cmd: Integer): Boolean;
    function FindNext(Backward: Boolean = False): TTveFindStatus;
    { Finds the next match and replaces it (the new text is selected); the number of replacements (0 or 1). }
    function ReplaceNext(const Repl: AnsiString): Integer;
    function ReplaceAll(const Repl: AnsiString): Integer;
    { The text of the status line: "line:column  offset  INS  modified". }
    function StatusText: AnsiString;
    // Line numbers and the numbers of the rows (the lines that are not hidden by a fold), 0-based.
    function ViewToLine(V: Int64): Int64;
    function LineToView(L: Int64): Int64;
    procedure JumpToLine(L: Int64);
    procedure ScrollLines(N: Integer);
    { After the host changed the cursor or the text: scroll to the cursor, redraw, tell the owner. }
    procedure Refresh;
  end;

implementation

uses
  SysUtils, TvUtf8, TveLayout, TveBlocks, TveExtras;

const
  CursorHistoryMax = 64;

constructor TTveView.Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar; ADoc: TTveDoc; OwnDoc: Boolean);
begin
  inherited Create(Bounds, AHScrollBar, AVScrollBar);
  Setup(ADoc, OwnDoc);
end;

constructor TTveView.Load(S: TStream; ADoc: TTveDoc; OwnDoc: Boolean);
begin
  inherited Load(S);
  Setup(ADoc, OwnDoc);
end;

procedure TTveView.Setup(ADoc: TTveDoc; OwnDoc: Boolean);
begin
  GrowMode := gfGrowHiX or gfGrowHiY;
  Options := Options or ofFirstClick;
  EventMask := EventMask or evMouseWheel or evBroadcast;
  FEditor := TTveEditor.Create(ADoc);
  FOwnDoc := OwnDoc;
  FKeymap := TveKeymapA;
  FSearch := TveDefaultSearch;
  FSearcher := TTveSearcher.Create(ADoc.Buffer);
  FShowCurrentLine := False;
  FWheelStep := 3;
  FMarkA := -1;
  FMarkB := -1;
  FKeysEnabled := True;
  FMultiClick := True;
  FHlA := -1;
  FHlB := -1;
  FEditor.Rows := Size.Y;
  FLastVersion := ADoc.Buffer.Version;
  ADoc.AddObserver(@DocChanged);
  ShowCursor;
end;

destructor TTveView.Destroy;
var
  D: TTveDoc;
begin
  D := FEditor.Doc;
  D.RemoveObserver(@DocChanged);
  FHl.Free;
  FFolds.Free;
  FSearcher.Free;
  FEditor.Free;
  if FOwnDoc then
    D.Free;
  inherited Destroy;
end;

function TTveView.GetFolds: TTveFolds;
begin
  if FFolds = nil then
    FFolds := TTveFolds.Create(FEditor.Doc);
  Result := FFolds;
end;

function TTveView.ViewToLine(V: Int64): Int64;
begin
  if FFolds = nil then
    Result := V
  else
    Result := FFolds.ViewToLine(V);
end;

function TTveView.LineToView(L: Int64): Int64;
begin
  if FFolds = nil then
    Result := L
  else
    Result := FFolds.LineToView(L);
end;

function TTveView.GetDoc: TTveDoc;
begin
  Result := FEditor.Doc;
end;

procedure TTveView.SetLanguage(ALang: TTveLanguage);
begin
  FreeAndNil(FHl);
  if ALang <> nil then
    FHl := TTveHighlighter.Create(FEditor.Doc, ALang);
  DrawView;
end;

procedure TTveView.SetClassAttr(C: Integer; const Attr: TColorAttr);
begin
  if (C >= 0) and (C < hcClassCount) then
  begin
    FClassAttr[C] := Attr;
    FClassSet[C] := True;
  end;
end;

function TTveView.ClassAttr(C: Integer): TColorAttr;
var
  Fg: TColor;
begin
  Result := NormalAttr;
  if (C <= 0) or (C >= hcClassCount) then
    Exit;
  if FClassSet[C] then
    Exit(FClassAttr[C]);
  case C of
    hcComment: Fg := ColorBIOS($08);
    hcString: Fg := ColorBIOS($0B);
    hcNumber: Fg := ColorBIOS($0D);
    hcKeyword: Fg := ColorBIOS($0F);
    hcType: Fg := ColorBIOS($0A);
    hcBuiltin: Fg := ColorBIOS($0E);
    hcPreproc: Fg := ColorBIOS($0C);
    hcOperator: Fg := ColorBIOS($07);
    hcEscape: Fg := ColorBIOS($0D);
    hcTag: Fg := ColorBIOS($0A);
    hcAttr: Fg := ColorBIOS($0E);
    hcEntity: Fg := ColorBIOS($0D);
    hcVariable: Fg := ColorBIOS($0B);
    hcDelimiter: Fg := ColorBIOS($0F);
    hcFunction: Fg := ColorBIOS($0E);
    hcProperty: Fg := ColorBIOS($0B);
    hcSelector: Fg := ColorBIOS($0A);
    hcValue: Fg := ColorBIOS($0B);
    hcAsm: Fg := ColorBIOS($0C);
    hcSpecial: Fg := ColorBIOS($0D);
  else
    Fg := AttrFg(Result);
  end;
  AttrSetFg(Result, Fg);
end;

function TTveView.GutterWidth: Integer;
begin
  if FGutter then
    Result := 1
  else
    Result := 0;
end;

function TTveView.TextWidth: Integer;
begin
  Result := Size.X - GutterWidth;
  if Result < 1 then
    Result := 1;
end;

procedure TTveView.DocChanged(Doc: TTveDoc; Offset, Removed, Inserted: Int64);
begin
  DrawView;
end;

procedure TTveView.Sync;
var
  W: Int64;
begin
  FEditor.Rows := Size.Y;
  if FFolds <> nil then
    FFolds.Reveal(FEditor.Line);
  KeepCursorVisible;
  W := Size.X;
  if FEditor.Cell + 2 > W then
    W := FEditor.Cell + 2;
  if Delta.X + Size.X > W then
    W := Delta.X + Size.X;
  if FFolds <> nil then
    SetLimit(W, FFolds.VisibleCount)
  else
    SetLimit(W, FEditor.Doc.Buffer.LineCount);
  DrawView;
  Message(Owner, evBroadcast, cmTveStatus, Self);
  Changed;
end;

procedure TTveView.Changed;
begin
end;

function TTveView.NormalAttr: TColorAttr;
begin
  Result := GetColor(1).Lo;
end;

function TTveView.SelectedAttr: TColorAttr;
begin
  Result := GetColor(2).Lo;
end;

function TTveView.MessageAttr: TColorAttr;
begin
  Result := AttrReversed(NormalAttr);
end;

function TTveView.HighlightAttr: TColorAttr;
begin
  Result := AttrReversed(SelectedAttr);
end;

procedure TTveView.SetHighlightRange(A, B: Int64);
begin
  if B <= A then
  begin
    A := -1;
    B := -1;
  end;
  if (A <> FHlA) or (B <> FHlB) then
  begin
    FHlA := A;
    FHlB := B;
    DrawView;
  end;
end;

procedure TTveView.GetHighlightRange(out A, B: Int64);
begin
  A := FHlA;
  B := FHlB;
end;

procedure TTveView.KeepCursorVisible;
var
  X, Y, TX: Integer;
  CV: Int64;
begin
  TX := TextWidth;
  X := Delta.X;
  Y := Delta.Y;
  CV := LineToView(FEditor.Line);
  if CV < Y then
    Y := CV
  else if CV >= Y + Size.Y then
    Y := CV - Size.Y + 1;
  if FEditor.Cell < X then
    X := FEditor.Cell
  else if FEditor.Cell >= X + TX then
    X := FEditor.Cell - TX + 1;
  if X < 0 then X := 0;
  if Y < 0 then Y := 0;
  if (X <> Delta.X) or (Y <> Delta.Y) then
    ScrollTo(X, Y);
end;

procedure TTveView.ChangeBounds(const Bounds: TRect);
begin
  inherited ChangeBounds(Bounds);
  FEditor.Rows := Size.Y;
  KeepCursorVisible;
end;

procedure TTveView.SetState(AState: Word; Enable: Boolean);
begin
  inherited;
  if (AState and sfFocused) <> 0 then
    Message(Owner, evBroadcast, cmTveStatus, Self);
end;

{ --- drawing --- }

procedure TTveView.Draw;
var
  B: TDrawBuffer;
  Y, X0, TX, Cells, SelA, SelB, ColC1, ColC2: Integer;
  L: Int64;
  Text: AnsiString;
  Cls: TByteClasses;
  Normal, SelAttr, Attr, LineAttr: TColorAttr;
  SelLo, SelHi: Int64;
  HasSel, IsCol: Boolean;
  CL1, CL2: Int64;
  LS, LE: Int64;
  Idx, Cell, ScreenX, Grp, GrpCells, K: Integer;
  Info, NextInfo: TTveCharInfo;
  Selected, Custom, CursorLine: Boolean;
  Mark: Boolean;
  N, MsgRow: Integer;
  HlAttr: TColorAttr;
  COff: Int64;

  procedure LineSelection(Line: Int64; out A, Bc: Integer);
  var
    Ofs: Int64;
  begin
    A := 0;
    Bc := 0;
    if not HasSel then
      Exit;
    if IsCol then
    begin
      if (Line >= CL1) and (Line <= CL2) then
      begin
        A := ColC1;
        Bc := ColC2;
      end;
      Exit;
    end;
    if (Line < FEditor.Doc.Buffer.LineOfOffset(SelLo)) or (Line > FEditor.Doc.Buffer.LineOfOffset(SelHi)) then
      Exit;
    LS := FEditor.Doc.Buffer.LineStart(Line);
    LE := LS + Length(Text);
    if SelLo <= LS then
      A := 0
    else
      A := LayoutIndexToCell(Text, SelLo - LS + 1, FEditor.Opt.TabSize);
    if SelHi > LE then
      Bc := MaxInt
    else
    begin
      Ofs := SelHi - LS;
      Bc := LayoutIndexToCell(Text, Ofs + 1, FEditor.Opt.TabSize);
    end;
    if (Bc = A) and (SelHi <= LS) then
      Bc := A;
  end;

begin
  Normal := NormalAttr;
  SelAttr := SelectedAttr;
  HlAttr := HighlightAttr;
  TX := TextWidth;
  X0 := Delta.X;
  HasSel := FEditor.HasSelection;
  IsCol := False;
  SelLo := 0; SelHi := 0; CL1 := 0; CL2 := -1; ColC1 := 0; ColC2 := 0;
  if HasSel then
  begin
    if FEditor.SelKind = skColumn then
    begin
      IsCol := FEditor.ColumnRect(CL1, CL2, ColC1, ColC2);
      if not IsCol then HasSel := False;
    end
    else if not FEditor.SelectionRange(SelLo, SelHi) then
      HasSel := False;
  end;
  MsgRow := -1;
  if FMessage <> '' then
  begin
    if LineToView(FEditor.Line) - Delta.Y < Size.Y div 2 then
      MsgRow := Size.Y - 1
    else
      MsgRow := 0;
  end;
  B := TDrawBuffer.Create(Size.X);
  try
    for Y := 0 to Size.Y - 1 do
    begin
      if Y = MsgRow then
      begin
        B.MoveChar(0, Ord(' '), MessageAttr, Size.X);
        B.MoveStr(0, @FMessage[1], Length(FMessage), MessageAttr, Size.X);
        WriteLineD(0, Y, Size.X, 1, B);
        Continue;
      end;
      L := ViewToLine(Delta.Y + Y);
      B.MoveChar(0, Ord(' '), Normal, Size.X);
      if L < FEditor.Doc.Buffer.LineCount then
      begin
        Text := FEditor.Doc.Buffer.LineText(L);
        CursorLine := FShowCurrentLine and (L = FEditor.Line);
        LineAttr := Normal;
        Custom := (FOnLineAttr <> nil) and FOnLineAttr(Self, L, LineAttr);
        if Custom or CursorLine then
        begin
          if CursorLine and not Custom then
            AttrSetBg(LineAttr, AttrFg(SelAttr));
          B.MoveChar(0, Ord(' '), LineAttr, Size.X);
        end;
        Cls := nil;
        if FHl <> nil then
          FHl.ClassifyLine(L, Cls);
        LineSelection(L, SelA, SelB);
        if GutterWidth > 0 then
        begin
          Mark := False;
          for K := 0 to 9 do
            if FEditor.BookmarkLine(K) = L then
            begin
              B.PutChar(0, Ord('0') + K);
              B.PutAttribute(0, Normal);
              Mark := True;
              Break;
            end;
          if not Mark then
            B.PutChar(0, Ord(' '));
        end;
        { the text, character by character, from the first one that is visible }
        Idx := LayoutCellToIndex(Text, X0, FEditor.Opt.TabSize);
        if Idx > 1 then
          LayoutChar(Text, Idx - 1, 0, FEditor.Opt.TabSize, Info)
        else
          Info.CellStart := 0;
        Cell := LayoutIndexToCell(Text, Idx, FEditor.Opt.TabSize);
        while (Idx <= Length(Text)) and (Cell < X0 + TX) do
        begin
          LayoutChar(Text, Idx, Cell, FEditor.Opt.TabSize, Info);
          Grp := Info.Bytes;
          GrpCells := Info.Cells;
          { a base character takes the combining marks that follow }
          while Idx + Grp <= Length(Text) do
          begin
            LayoutChar(Text, Idx + Grp, Cell + GrpCells, FEditor.Opt.TabSize, NextInfo);
            if (NextInfo.Cells <> 0) or (NextInfo.Bytes = 0) then
              Break;
            Inc(Grp, NextInfo.Bytes);
          end;
          Attr := LineAttr;
          if (Idx - 1 <= High(Cls)) and (Cls <> nil) and (Cls[Idx - 1] <> hcNormal) then
          begin
            Attr := ClassAttr(Cls[Idx - 1]);
            if Custom or CursorLine then
              AttrSetBg(Attr, AttrBg(LineAttr));
          end;
          Selected := HasSel and (Cell >= SelA) and (Cell < SelB);
          if Selected then
            Attr := SelAttr;
          if FHlA >= 0 then
          begin
            COff := FEditor.Doc.Buffer.LineStart(L) + Idx - 1;
            if (COff >= FHlA) and (COff < FHlB) then
              Attr := HlAttr;
          end
          else if FHighlightColumn and (Cell = FEditor.Cell) then
            AttrSetBg(Attr, AttrBg(SelAttr));
          ScreenX := GutterWidth + Cell - X0;
          if (GrpCells > 0) and (ScreenX >= GutterWidth) then
          begin
            if Text[Idx] = #9 then
              B.MoveChar(ScreenX, Ord(' '), Attr, GrpCells)
            else if (Byte(Text[Idx]) < 32) then
              B.MoveChar(ScreenX, Ord('.'), Attr, 1)
            else
              B.MoveStr(ScreenX, @Text[Idx], Grp, Attr, Size.X - ScreenX);
          end
          else if (GrpCells > 0) and (ScreenX + GrpCells > GutterWidth) then
            B.MoveChar(GutterWidth, Ord(' '), Attr, ScreenX + GrpCells - GutterWidth);
          Inc(Cell, GrpCells);
          Inc(Idx, Grp);
        end;
        if FFolds <> nil then
        begin
          N := FFolds.FoldAt(L, True);
          if (N >= 0) and FFolds.Collapsed(N) then
          begin
            Cells := LayoutCells(Text, FEditor.Opt.TabSize) + 1 - X0;
            if Cells < 0 then Cells := 0;
            if GutterWidth + Cells < Size.X then
              B.MoveStrS(GutterWidth + Cells, '[+' + IntToStr(FFolds.EndLine(N) - L) + ' lines]', ClassAttr(hcComment), Size.X - GutterWidth - Cells);
          end;
        end;
        { selected blanks past the end of the line (the line end itself, or the column block) }
        if HasSel then
        begin
          Cells := LayoutCells(Text, FEditor.Opt.TabSize);
          if SelB = MaxInt then
          begin
            if (Cells >= X0) and (Cells < X0 + TX) and (SelA <= Cells) then
              B.MoveChar(GutterWidth + Cells - X0, Ord(' '), SelAttr, 1);
          end
          else
            for N := Cells to SelB - 1 do
              if (N >= SelA) and (N >= X0) and (N < X0 + TX) then
                B.MoveChar(GutterWidth + N - X0, Ord(' '), SelAttr, 1);
        end;
      end;
      WriteLineD(0, Y, Size.X, 1, B);
    end;
  finally
    B.Free;
  end;
  if ((State and sfFocused) <> 0) then
  begin
    if FEditor.Opt.InsertMode then
      NormalCursor
    else
      BlockCursor;
    SetCursor(GutterWidth + FEditor.Cell - Delta.X, LineToView(FEditor.Line) - Delta.Y);
    ShowCursor;
  end;
end;

{ --- commands --- }

procedure TTveView.Remember;
begin
  if (Length(FHistory) = 0) or (FHistory[High(FHistory)] <> FEditor.Offset) then
  begin
    if Length(FHistory) >= CursorHistoryMax then
      Move(FHistory[1], FHistory[0], (Length(FHistory) - 1) * SizeOf(Int64))
    else
      SetLength(FHistory, Length(FHistory) + 1);
    FHistory[High(FHistory)] := FEditor.Offset;
  end;
end;

procedure TTveView.Complete;
var
  Fragment: AnsiString;
  FragStart: Int64;
  Items: TTveWords;
begin
  if FCompletion = nil then
    Exit;
  if FComplActive and (FEditor.Offset = FComplEnd) then
  begin
    FComplIdx := (FComplIdx + 1) mod (Length(FComplItems) + 1);
  end
  else
  begin
    if not FCompletion.Candidates(FEditor, Fragment, FragStart, Items) then
      Exit;
    FComplItems := Items;
    FComplStart := FragStart;
    FComplIdx := 0;
    FComplActive := True;
    FComplEnd := FEditor.Offset;
    SetLength(Fragment, Length(Fragment));
    SetLength(FComplItems, Length(Items) + 0);
    FComplFragment := Fragment;
  end;
  // the candidate number FComplIdx (the last one is the fragment typed by the user, to get back to it)
  if FComplIdx < Length(FComplItems) then
    Fragment := FComplItems[FComplIdx]
  else
    Fragment := FComplFragment;
  FEditor.Doc.Replace(FComplStart, FComplEnd - FComplStart, Fragment);
  FComplEnd := FComplStart + Length(Fragment);
  FEditor.GotoOffset(FComplEnd);
end;

procedure TTveView.JumpToLine(L: Int64);
begin
  Remember;
  if L < 0 then L := 0;
  if L >= FEditor.Doc.Buffer.LineCount then
    L := FEditor.Doc.Buffer.LineCount - 1;
  FEditor.GotoLineCell(L, 0);
  Sync;
end;

procedure TTveView.Refresh;
begin
  Sync;
end;

procedure TTveView.ScrollLines(N: Integer);
var
  Y, Total, CV: Int64;
begin
  if FFolds <> nil then
    Total := FFolds.VisibleCount
  else
    Total := FEditor.Doc.Buffer.LineCount;
  Y := Delta.Y + N;
  if Y > Total - 1 then Y := Total - 1;
  if Y < 0 then Y := 0;
  ScrollTo(Delta.X, Y);
  { the cursor follows when it left the window }
  CV := LineToView(FEditor.Line);
  if CV < Y then
    FEditor.GotoLineCell(ViewToLine(Y), FEditor.Cell)
  else if CV >= Y + Size.Y then
    FEditor.GotoLineCell(ViewToLine(Y + Size.Y - 1), FEditor.Cell);
  DrawView;
end;

procedure TTveView.MoveVertical(Down: Boolean; Pages: Boolean);
var
  L: Int64;
  I, Count: Integer;
begin
  L := FEditor.Line;
  if Pages then
    Count := Size.Y - 1
  else
    Count := 1;
  for I := 1 to Count do
    L := FFolds.NextVisible(L, Down);
  FEditor.GotoLineCell(L, FEditor.Cell);
end;

function TTveView.FindNext(Backward: Boolean): TTveFindStatus;
var
  O: TTveSearchOptions;
  M: TTveMatch;
  From: Int64;
  A, B2: Int64;
begin
  O := FSearch;
  if Backward then
    O.Backward := not O.Backward;
  From := FEditor.Offset;
  if FEditor.HasSelection and FEditor.SelectionRange(A, B2) then
  begin
    if O.Backward then From := A else From := B2;
  end;
  Result := FSearcher.Find(O, From, M);
  if Result = fsFound then
  begin
    Remember;
    FEditor.SetSelection(skStream, M.Start);
    FEditor.GotoOffset(M.Stop);
    FEditor.SetSelection(skStream, M.Start);
    FEditor.GotoOffset(M.Stop);
    Sync;
  end;
end;

function TTveView.ReplaceNext(const Repl: AnsiString): Integer;
var
  O: TTveSearchOptions;
  M: TTveMatch;
  New_: AnsiString;
begin
  Result := 0;
  O := FSearch;
  O.Backward := False;
  if FSearcher.Find(O, FEditor.Offset, M) <> fsFound then
    Exit;
  New_ := FSearcher.ReplacementFor(M, Repl);
  FEditor.Doc.Replace(M.Start, M.Stop - M.Start, New_);
  FEditor.SetSelection(skStream, M.Start);
  FEditor.GotoOffset(M.Start + Length(New_));
  Result := 1;
  Sync;
end;

function TTveView.ReplaceAll(const Repl: AnsiString): Integer;
begin
  Result := FSearcher.ReplaceAll(FEditor.Doc, FSearch, Repl);
  Sync;
end;

function TTveView.Execute(Cmd: Integer): Boolean;
var
  E: TTveEditor;
  Back, Fwd: Int64;
begin
  Result := True;
  if (FOnHost <> nil) and FOnHost(Self, Cmd) then
    Exit;
  E := FEditor;
  if Cmd <> tcCompletion then
    FComplActive := False;
  if FRecording and (Cmd <> tcMacroRecord) and (Cmd <> tcMacroPlay) then
  begin
    SetLength(FMacro, Length(FMacro) + 1);
    FMacro[High(FMacro)] := Cmd;
  end;
  if (FDrawMode > 0) and (Cmd >= tcLeft) and (Cmd <= tcDown) then
  begin
    case Cmd of
      tcLeft: TveDrawStep(E, dirLeft, TTveDrawStyle(FDrawMode - 1));
      tcRight: TveDrawStep(E, dirRight, TTveDrawStyle(FDrawMode - 1));
      tcUp: TveDrawStep(E, dirUp, TTveDrawStyle(FDrawMode - 1));
      tcDown: TveDrawStep(E, dirDown, TTveDrawStyle(FDrawMode - 1));
    end;
    Sync;
    Exit;
  end;
  case Cmd of
    tcDrawMode: FDrawMode := (FDrawMode + 1) mod 3;
    tcLeft: E.MoveLeft;
    tcRight: E.MoveRight;
    tcUp: if (FFolds <> nil) and (FFolds.Count > 0) then MoveVertical(False, False) else E.MoveUp;
    tcDown: if (FFolds <> nil) and (FFolds.Count > 0) then MoveVertical(True, False) else E.MoveDown;
    tcPageUp: if (FFolds <> nil) and (FFolds.Count > 0) then MoveVertical(False, True) else E.MovePageUp;
    tcPageDown: if (FFolds <> nil) and (FFolds.Count > 0) then MoveVertical(True, True) else E.MovePageDown;
    tcHome: E.MoveHome;
    tcEnd: E.MoveEnd;
    tcWordLeft: E.MoveWordLeft;
    tcWordRight: E.MoveWordRight;
    tcTextStart: begin Remember; E.MoveTextStart; end;
    tcTextEnd: begin Remember; E.MoveTextEnd; end;
    tcWindowTop: E.GotoLineCell(Delta.Y, E.Cell);
    tcWindowBottom: E.GotoLineCell(Delta.Y + Size.Y - 1, E.Cell);
    tcScrollUp: begin ScrollLines(-1); Exit; end;
    tcScrollDown: begin ScrollLines(1); Exit; end;
    tcSelLeft: E.MoveLeft(True);
    tcSelRight: E.MoveRight(True);
    tcSelUp: E.MoveUp(True);
    tcSelDown: E.MoveDown(True);
    tcSelPageUp: E.MovePageUp(True);
    tcSelPageDown: E.MovePageDown(True);
    tcSelHome: E.MoveHome(True);
    tcSelEnd: E.MoveEnd(True);
    tcSelWordLeft: E.MoveWordLeft(True);
    tcSelWordRight: E.MoveWordRight(True);
    tcSelTextStart: E.MoveTextStart(True);
    tcSelTextEnd: E.MoveTextEnd(True);
    tcNewLine: E.NewLine;
    tcTab: E.Tab;
    tcBackspace: E.Backspace;
    tcDelete: E.DeleteChar;
    tcDeleteLine: E.DeleteLine;
    tcDeleteToEol: E.DeleteToEol;
    tcDeleteToBol: E.DeleteToBol;
    tcDeleteWordRight: E.DeleteWordRight;
    tcDeleteWordLeft: E.DeleteWordLeft;
    tcInsertLineBelow: InsertLineBelow(E);
    tcInsertLineAbove: InsertLineAbove(E);
    tcDuplicateLine: DuplicateLine(E);
    tcBreakLineStay: BreakLineStay(E);
    tcJoinLine: JoinLine(E);
    tcToggleInsert: E.Opt.InsertMode := not E.Opt.InsertMode;
    tcUndo: E.Undo;
    tcRedo: E.Redo;
    tcCopy: E.CopyBlock;
    tcCut: E.CutBlock;
    tcPaste: E.Paste;
    tcDeleteBlock: E.DeleteSelection;
    tcBlockBegin: begin FMarkA := E.Offset; if (FMarkB > FMarkA) then E.SetBlockMarks(FMarkA, FMarkB); end;
    tcBlockEnd: begin FMarkB := E.Offset; if (FMarkA >= 0) and (FMarkB > FMarkA) then E.SetBlockMarks(FMarkA, FMarkB); end;
    tcSelectAll: E.SelectAll;
    tcSelectLine: E.SelectLine;
    tcSelectWord: E.SelectWord;
    tcHideBlock: E.ClearSelection;
    tcColumnBlock: E.StartSelection(skColumn);
    tcLineBlock: E.StartSelection(skLine);
    tcStreamBlock: E.StartSelection(skStream);
    tcGotoBlockBegin: if E.SelectionRange(Back, Fwd) then E.GotoOffset(Back);
    tcGotoBlockEnd: if E.SelectionRange(Back, Fwd) then E.GotoOffset(Fwd);
    tcCopyBlockHere: CopyBlockHere(E);
    tcMoveBlockHere: MoveBlockHere(E);
    tcIndent: BlockIndent(E);
    tcUnindent: BlockUnindent(E);
    tcUpperCase: if E.HasSelection then ChangeCase(E, caseUpper);
    tcLowerCase: if E.HasSelection then ChangeCase(E, caseLower);
    tcTitleCase: if E.HasSelection then ChangeCase(E, caseTitle);
    tcToggleCase: if E.HasSelection then ChangeCase(E, caseToggle);
    tcSortAsc: SortLines(E, False);
    tcSortDesc: SortLines(E, True);
    tcTrimTrailing: TrimTrailing(E);
    tcExpandTabs: ExpandTabs(E);
    tcTabify: TabifyIndent(E);
    tcTemplate: if FTemplates <> nil then TveExpandShortcut(E, FTemplates, FOnPrompt);
    tcCompletion: Complete;
    tcFoldToggle: Folds.Toggle(E.Line);
    tcFoldCollapse: Folds.CollapseAt(E.Line);
    tcFoldExpand: Folds.ExpandAt(E.Line);
    tcFoldFromBlock:
      if E.AffectedLines(Back, Fwd) and (Fwd > Back) then
      begin
        Folds.Add(Back, Fwd, False);
        E.ClearSelection;
      end;
    tcFindNext: FindNext(False);
    tcFindPrev: FindNext(True);
    tcMatchBracket: E.GotoMatchingBracket;
    tcSetMark0..tcSetMark0 + 9: E.SetBookmark(Cmd - tcSetMark0);
    tcGotoMark0..tcGotoMark0 + 9: begin Remember; E.GotoBookmark(Cmd - tcGotoMark0); end;
    tcClearMarks: for Back := 0 to 9 do E.ClearBookmark(Back);
    tcInsertDate: InsertDateTime(E, 'yyyy-mm-dd');
    tcInsertTime: InsertDateTime(E, 'hh:nn:ss');
    tcCursorBack:
      if Length(FHistory) > 0 then
      begin
        E.GotoOffset(FHistory[High(FHistory)]);
        SetLength(FHistory, Length(FHistory) - 1);
      end;
    tcMacroRecord:
      begin
        FRecording := not FRecording;
        if FRecording then
          FMacro := nil;
      end;
    tcMacroPlay:
      begin
        for Back := 0 to High(FMacro) do
          if (FMacro[Back] <> tcMacroPlay) then
            Execute(FMacro[Back]);
      end;
  else
    Result := False;
  end;
  if Result then
    Sync;
end;

function TTveView.StatusText: AnsiString;
begin
  Result := IntToStr(FEditor.Line + 1) + ':' + IntToStr(FEditor.Cell + 1);
  if FEditor.Doc.Modified then
    Result := Result + ' *';
  if not FEditor.Opt.InsertMode then
    Result := Result + ' OVR';
  if FRecording then
    Result := Result + ' REC';
  if FDrawMode > 0 then
    Result := Result + ' DRAW';
end;

{ --- the mouse --- }

function TTveView.Hit(Where: TPoint; out L: Int64; out C: Integer): Boolean;
var
  P: TPoint;
begin
  P := MakeLocal(Where);
  L := ViewToLine(Delta.Y + P.Y);
  C := Delta.X + P.X - GutterWidth;
  if L < 0 then L := 0;
  if L >= FEditor.Doc.Buffer.LineCount then
    L := FEditor.Doc.Buffer.LineCount - 1;
  if C < 0 then C := 0;
  Result := True;
end;

procedure TTveView.DoMouse(var Event: TEvent);
var
  L: Int64;
  C: Integer;
  Extend: Boolean;
begin
  Extend := (Event.ControlKeyState and kbShift) <> 0;
  Hit(Event.Where, L, C);
  if FMultiClick and ((Event.EventFlags and meTripleClick) <> 0) then
  begin
    FEditor.GotoLineCell(L, C);
    FEditor.SelectLine;
    Sync;
    Exit;
  end;
  if FMultiClick and ((Event.EventFlags and meDoubleClick) <> 0) then
  begin
    FEditor.GotoLineCell(L, C);
    FEditor.SelectWord;
    Sync;
    Exit;
  end;
  if not Extend then
  begin
    FEditor.ClearSelection;
    FEditor.GotoLineCell(L, C);
    if (Event.ControlKeyState and kbAltShift) <> 0 then
      FEditor.StartSelection(skColumn)
    else
      FEditor.StartSelection(skStream);
  end
  else
  begin
    if not FEditor.HasSelection then
      FEditor.StartSelection(skStream);
    FEditor.GotoLineCell(L, C);
  end;
  Sync;
  while MouseEvent(Event, evMouseMove or evMouseAuto) do
  begin
    Hit(Event.Where, L, C);
    FEditor.GotoLineCell(L, C);
    Sync;
  end;
end;

procedure TTveView.HandleEvent(var Event: TEvent);
var
  K: TKey;
  Cmd: Integer;
  T: AnsiString;
  I: Integer;
begin
  inherited HandleEvent(Event);
  case Event.What of
    evMouseDown:
      if (Event.Buttons and mbLeftButton) <> 0 then
      begin
        if (State and sfFocused) = 0 then
          Select;
        DoMouse(Event);
        ClearEvent(Event);
      end;
    evMouseWheel:
      begin
        if Event.Wheel = mwUp then
          ScrollLines(-FWheelStep)
        else if Event.Wheel = mwDown then
          ScrollLines(FWheelStep);
        ClearEvent(Event);
      end;
    evKeyDown:
      if FKeysEnabled then
      begin
        K := KeyMake(Event.KeyCode, Event.ControlKeyState);
        if FHavePrefix then
        begin
          FHavePrefix := False;
          if Event.KeyCode = kbEsc then
          begin
            ClearEvent(Event);
            Exit;
          end;
          Cmd := FKeymap.LookupChord(FPrefix, K);
          if Cmd > 0 then
          begin
            Execute(Cmd);
            ClearEvent(Event);
          end
          else
            ClearEvent(Event);
          Exit;
        end;
        Cmd := FKeymap.Lookup(K);
        if Cmd = -2 then
        begin
          FPrefix := K;
          FHavePrefix := True;
          ClearEvent(Event);
        end
        else if (Cmd > 0) and Execute(Cmd) then
          ClearEvent(Event)
        else if (Event.TextLength > 0) and ((Event.ControlKeyState and (kbCtrlShift or kbAltShift)) = 0) and (Byte(Event.Text[0]) >= 32) then
        begin
          SetLength(T, Event.TextLength);
          for I := 0 to Event.TextLength - 1 do
            T[I + 1] := Event.Text[I];
          if FEditor.TypeText(T) then
            Sync;
          ClearEvent(Event);
        end;
      end;
  end;
end;

end.
