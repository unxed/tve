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
  TveBuf, TveDoc, TveEditor, TveSearch, TveHl, TveCmds, TveFold, TveTemplates, TveComplete, TveDraw, TveWrap, TveMacro, TveSymbols, TvXlat;

const
  cmTveStatus = $7A00;           { broadcast: the view changed its cursor or text }
  TveSemanticAutoLimit = 128 * 1024;    { see TTveView.SemanticNames }

type
  // The sender of a callback (a host that has a rule against the name of the root class can use this one).
  TTveSender = TObject;
  TTveHostCommand = function(Sender: TTveSender; Cmd: Integer): Boolean of object;
  TTveLineAttr = function(Sender: TTveSender; Line: Int64; var Attr: TColorAttr): Boolean of object;

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
    FMarkWord: Boolean;
    FRecording: Boolean;
    FMacro: TTveMacro;                // the current macro, one of FMacros
    FMacros: TTveMacroList;
    FMacroName: AnsiString;
    FMacroStop: Boolean;              // a stop step was played
    FMacroDepth: Integer;             // play steps inside play steps
    FPlaying: Boolean;
    FExecuting: Integer;
    FStepFailed: Boolean;             // the last command of Execute could not be done (a search found nothing)              // inside the commands of Execute: a search is recorded as the command, not as a find step
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
    FDragDrop: Boolean;
    FHlA, FHlB: Int64;                // a highlighted range of the text (the match of a search), -1: none
    FSemantic: Boolean;
    FProjNames: TWordArr;
    FProjClasses: array of Byte;
    FSemValid: Boolean;
    FSemVersion: LongWord;
    FDropShown: Boolean;              // a drag of text is over the view: the cell where it would go is marked
    FDropL: Int64;
    FDropC: Integer;
    FHighlightColumn: Boolean;
    FMessage: AnsiString;
    FWrap: Boolean;
    FWrapMap: TTveWrapMap;
    procedure SetWrap(V: Boolean);
    procedure SetSemantic(V: Boolean);
    procedure FindNames;
    procedure EnsureWrap;
    function CursorRow: Int64;
    function RowPlace(Row: Int64; out L: Int64; out A, B: Integer; out Last: Boolean): Boolean;
    procedure MoveToRow(Row: Int64; Extend: Boolean);
    function WrapMove(Cmd: Integer): Boolean;
    function TotalRows: Int64;
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
    function InSelection(L: Int64; C: Integer): Boolean;
    procedure DragSelection(var Event: TEvent);
    procedure ShowDrop(L: Int64; C: Integer);
    procedure HideDrop;
    procedure DropInto(Target: TTveView; const Where: TPoint; Copying: Boolean);
    function EditorAt(const Where: TPoint): TTveView;
    procedure DragScroll(var P: TPoint);
    procedure Remember;
    procedure Complete;
    function RunCommand(Cmd: Integer): Boolean;
    procedure FoldAtCursor(Toggle: Boolean);
    procedure RecordSearch(Kind: Integer; const Repl: AnsiString);
    function PlayStep(const St: TTveMacroStep): Boolean;
    function MacroCondition(const St: TTveMacroStep): Boolean;
    function RunMacro(M: TTveMacro; Times: Integer): Boolean;
    function PlayGoto(const Place: AnsiString): Boolean;
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
    { the cell where dragged text would be dropped (the highlight colour by default) }
    function DropAttr: TColorAttr; virtual;
    { the other occurrences of the word under the cursor }
    function OccurrenceAttr: TColorAttr; virtual;
  public
    constructor Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar; ADoc: TTveDoc; OwnDoc: Boolean = False);
    // From a stream (the scroll bars and the scrolling of TScroller); the document is the host's.
    constructor LoadWith(S: TStream; ADoc: TTveDoc; OwnDoc: Boolean = False);
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
    // True (the default): a press on the selected text and a drag moves the text to where the button is released (Ctrl: copies it). One undo step.
    property DragDrop: Boolean read FDragDrop write FDragDrop;
    // True while dragged text is over the view (the drop place is marked at DropLine, DropCell).
    property DropShown: Boolean read FDropShown;
    property DropLine: Int64 read FDropL;
    property DropCell: Integer read FDropC;
    property HighlightColumn: Boolean read FHighlightColumn write FHighlightColumn;
    // The names of types and routines that the outline finds are coloured where the text uses them (a grammar with "semantic"). They are found again
    // when the text changed, before drawing, for a text up to TveSemanticAutoLimit bytes; a longer one keeps the names until UpdateNames.
    property SemanticNames: Boolean read FSemantic write SetSemantic;
    procedure UpdateNames;
    // Names that the host gives besides those of the text itself, as those that TveSemanticNames finds in the other open files of the same project
    // (tve reads no files by itself): they are coloured as the names of the text are (with SemanticNames, in a grammar with "semantic"); a name of the
    // text wins over the same name given here. Set replaces them, Add adds to them, AddNamesOf adds the names of another document by its language.
    procedure SetProjectNames(const Names: TWordArr; const Classes: array of Byte);
    procedure AddProjectNames(const Names: TWordArr; const Classes: array of Byte);
    procedure AddNamesOf(ADoc: TTveDoc; ALang: TTveLanguage);
    procedure ClearProjectNames;
    function ProjectNameCount: Integer;
    // Soft wrap: a long line is shown as several rows (no horizontal scrolling); the text is not changed.
    property Wrap: Boolean read FWrap write SetWrap;
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
    { shade every whole-word occurrence of the word under the cursor (when nothing is selected) }
    property MarkOccurrences: Boolean read FMarkWord write FMarkWord;
    property WheelStep: Integer read FWheelStep write FWheelStep;
    property SearchOptions: TTveSearchOptions read FSearch write FSearch;
    property Recording: Boolean read FRecording;
    { The current macro (commands and typed text), the one that MacroRecord records and MacroPlay plays; it can be loaded and saved as text, see TveMacro. }
    property RecordedMacro: TTveMacro read FMacro;
    { All the macros of the view by their names; the current one is MacroName ('' at first). }
    property Macros: TTveMacroList read FMacros;
    property MacroName: AnsiString read FMacroName;
    { Makes the macro of a name the current one (a new empty one when there is none); a recording stops. }
    procedure SelectMacro(const AName: AnsiString);
    { Plays the macro of a name as PlayMacro does; False when there is none or a step failed. }
    function PlayMacroNamed(const AName: AnsiString; Times: Integer = 1): Boolean;
    { The outline of the text by the symbol rules of the language of the view (empty without a language); see TveSymbols. }
    function Outline: TTveOutline;
    { The regions that the grammar of the view can fold (see TveFoldRegions). }
    function FoldRegions: TTveFoldRegions;
    { Every region of the grammar becomes a collapsed fold (the folds there are kept and collapsed too). }
    procedure FoldAll;
    { Plays the current macro Times times; Times <= 0: again and again until a step fails, a stop step is played or a round changes neither the text nor
      the cursor. A step fails when a search finds nothing, a prompt is cancelled or a cursor movement cannot move; that ends the playing. An "if" step
      skips the step after it when its condition does not hold. False when a step failed. }
    function PlayMacro(Times: Integer = 1): Boolean;
    { For a host (a dialog of its own): moves the cursor (0-based line and cell, or a byte offset) or types text as the user does; while a macro is being
      recorded, they are steps of it. }
    procedure GotoPlace(Line: Int64; Cell: Integer);
    procedure GotoOffsetPlace(Offset: Int64);
    procedure TypeText(const S: AnsiString);
    { All the macros (TTveMacroList.LoadFile, SaveFile); the current one keeps its name. }
    function LoadMacroFile(const FileName: AnsiString; out Err: AnsiString): Boolean;
    function SaveMacroFile(const FileName: AnsiString): Boolean;

    procedure SetLanguage(ALang: TTveLanguage);
    procedure SetClassAttr(C: Integer; const Attr: TColorAttr);

    procedure SetState(AState: Word; Enable: Boolean); override;
    procedure Draw; override;
    procedure HandleEvent(var Event: TEvent); override;
    procedure ChangeBounds(const Bounds: TRect); override;

    { Runs a command (the host's first). True if something was done. }
    function Execute(Cmd: Integer): Boolean; reintroduce;
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
  SysUtils, TvUtf8, TveLayout, TveBlocks, TveExtras, TveRegex;

const
  CursorHistoryMax = 64;

constructor TTveView.Create(const Bounds: TRect; AHScrollBar, AVScrollBar: TScrollBar; ADoc: TTveDoc; OwnDoc: Boolean);
begin
  inherited Create(Bounds, AHScrollBar, AVScrollBar);
  Setup(ADoc, OwnDoc);
end;

constructor TTveView.LoadWith(S: TStream; ADoc: TTveDoc; OwnDoc: Boolean);
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
  FMacros := TTveMacroList.Create;
  FMacro := FMacros.Get('');
  FSearch := TveDefaultSearch;
  FSearcher := TTveSearcher.Create(ADoc.Buffer);
  FWrapMap := TTveWrapMap.Create(ADoc.Buffer);
  FShowCurrentLine := False;
  FWheelStep := 3;
  FMarkA := -1;
  FMarkB := -1;
  FKeysEnabled := True;
  FMultiClick := True;
  FDragDrop := True;
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
  FMacros.Free;
  FFolds.Free;
  FSearcher.Free;
  FWrapMap.Free;
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
  FSemValid := False;
  DrawView;
end;

procedure TTveView.SetSemantic(V: Boolean);
var
  None: TWordArr;
begin
  FSemantic := V;
  FSemValid := False;
  if not V and (FHl <> nil) then
  begin
    None := nil;
    FHl.SetNames(None, []);
  end;
  DrawView;
end;

procedure TTveView.FindNames;
var
  Names: TWordArr;
  Classes: TTveByteArray;
  I, N: Integer;
begin
  TveSemanticNames(FEditor.Doc, FHl.Language, Names, Classes);
  if (Length(FProjNames) > 0) and FHl.Language.Semantic then
  begin
    { the names of the text first: the highlighter keeps the first of equal names }
    N := Length(Names);
    SetLength(Names, N + Length(FProjNames));
    SetLength(Classes, N + Length(FProjNames));
    for I := 0 to High(FProjNames) do
    begin
      Names[N + I] := FProjNames[I];
      Classes[N + I] := FProjClasses[I];
    end;
  end;
  FHl.SetNames(Names, Classes);
  FSemValid := True;
  FSemVersion := FEditor.Doc.Buffer.Version;
end;

procedure TTveView.UpdateNames;
begin
  if FHl = nil then
    Exit;
  FindNames;
  DrawView;
end;

procedure TTveView.SetProjectNames(const Names: TWordArr; const Classes: array of Byte);
begin
  FProjNames := nil;
  FProjClasses := nil;
  AddProjectNames(Names, Classes);
end;

procedure TTveView.AddProjectNames(const Names: TWordArr; const Classes: array of Byte);
var
  I, N: Integer;
begin
  N := Length(FProjNames);
  SetLength(FProjNames, N + Length(Names));
  SetLength(FProjClasses, N + Length(Names));
  for I := 0 to High(Names) do
  begin
    FProjNames[N + I] := Names[I];
    if I <= High(Classes) then
      FProjClasses[N + I] := Classes[I]
    else
      FProjClasses[N + I] := hcType;
  end;
  FSemValid := False;
  DrawView;
end;

procedure TTveView.AddNamesOf(ADoc: TTveDoc; ALang: TTveLanguage);
var
  Names: TWordArr;
  Classes: TTveByteArray;
begin
  TveSemanticNames(ADoc, ALang, Names, Classes);
  AddProjectNames(Names, Classes);
end;

procedure TTveView.ClearProjectNames;
begin
  FProjNames := nil;
  FProjClasses := nil;
  FSemValid := False;
  DrawView;
end;

function TTveView.ProjectNameCount: Integer;
begin
  Result := Length(FProjNames);
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

procedure TTveView.SetWrap(V: Boolean);
begin
  if V = FWrap then
    Exit;
  FWrap := V;
  if V then
    ScrollTo(0, Delta.Y);
  Sync;
end;

procedure TTveView.EnsureWrap;
begin
  if FWrap and not FWrapMap.Valid(TextWidth, FEditor.Opt.TabSize, FFolds) then
    FWrapMap.Build(TextWidth, FEditor.Opt.TabSize, FFolds);
end;

function TTveView.TotalRows: Int64;
begin
  if FWrap then
  begin
    EnsureWrap;
    Result := FWrapMap.TotalRows;
  end
  else if FFolds <> nil then
    Result := FFolds.VisibleCount
  else
    Result := FEditor.Doc.Buffer.LineCount;
end;

function TTveView.CursorRow: Int64;
begin
  if FWrap then
  begin
    EnsureWrap;
    Result := FWrapMap.RowOf(FEditor.Line, FEditor.Cell);
  end
  else
    Result := LineToView(FEditor.Line);
end;

{ The line, and the cells of the segment, that a row shows (wrap on). False for a row past the end. }
function TTveView.RowPlace(Row: Int64; out L: Int64; out A, B: Integer; out Last: Boolean): Boolean;
var
  Seg: Integer;
begin
  EnsureWrap;
  Result := (Row >= 0) and (Row < FWrapMap.TotalRows);
  L := FWrapMap.RowToLine(Row, Seg);
  FWrapMap.SegBounds(L, Seg, A, B);
  Last := Seg = FWrapMap.RowsOf(L) - 1;
end;

procedure TTveView.MoveToRow(Row: Int64; Extend: Boolean);
var
  L, CL: Int64;
  A, B, CA, CB, Off: Integer;
  Last: Boolean;
begin
  EnsureWrap;
  RowPlace(CursorRow, CL, CA, CB, Last);
  Off := FEditor.Cell - CA;
  if Row < 0 then Row := 0;
  if Row >= FWrapMap.TotalRows then Row := FWrapMap.TotalRows - 1;
  RowPlace(Row, L, A, B, Last);
  if A + Off >= B then
    Off := B - A - 1;
  if Extend then
  begin
    if not FEditor.HasSelection then
      FEditor.StartSelection(skStream);
  end
  else if not FEditor.Opt.PersistentBlocks then
    FEditor.ClearSelection;
  FEditor.GotoLineCell(L, A + Off);
end;

{ The commands that move by rows when the lines are wrapped. }
function TTveView.WrapMove(Cmd: Integer): Boolean;
var
  L: Int64;
  A, B: Integer;
  Last: Boolean;
  Ext: Boolean;
begin
  Result := True;
  Ext := (Cmd = tcSelUp) or (Cmd = tcSelDown) or (Cmd = tcSelPageUp) or (Cmd = tcSelPageDown) or (Cmd = tcSelHome) or (Cmd = tcSelEnd);
  case Cmd of
    tcUp, tcSelUp: MoveToRow(CursorRow - 1, Ext);
    tcDown, tcSelDown: MoveToRow(CursorRow + 1, Ext);
    tcPageUp, tcSelPageUp: MoveToRow(CursorRow - (Size.Y - 1), Ext);
    tcPageDown, tcSelPageDown: MoveToRow(CursorRow + (Size.Y - 1), Ext);
    tcHome, tcSelHome:
    begin
      RowPlace(CursorRow, L, A, B, Last);
      if Ext then
      begin
        if not FEditor.HasSelection then FEditor.StartSelection(skStream);
      end
      else if not FEditor.Opt.PersistentBlocks then
        FEditor.ClearSelection;
      FEditor.GotoLineCell(L, A);
    end;
    tcEnd, tcSelEnd:
    begin
      RowPlace(CursorRow, L, A, B, Last);
      if Ext then
      begin
        if not FEditor.HasSelection then FEditor.StartSelection(skStream);
      end
      else if not FEditor.Opt.PersistentBlocks then
        FEditor.ClearSelection;
      if Last then
        FEditor.GotoLineCell(L, B - 1)
      else
        FEditor.GotoLineCell(L, B - 1);
    end;
  else
    Result := False;
  end;
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
  if FWrap then
    SetLimit(Size.X, TotalRows)
  else if FFolds <> nil then
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

function TTveView.DropAttr: TColorAttr;
begin
  Result := HighlightAttr;
end;

function TTveView.OccurrenceAttr: TColorAttr;
begin
  Result := NormalAttr;
  AttrSetBg(Result, AttrBg(SelectedAttr));
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
  CV := CursorRow;
  if CV < Y then
    Y := CV
  else if CV >= Y + Size.Y then
    Y := CV - Size.Y + 1;
  if FWrap then
    X := 0
  else if FEditor.Cell < X then
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
  SegEnd: Integer;
  CL: Int64;
  IsLast, InText: Boolean;
  TX0: Integer;
  OccWord, OccText: AnsiString;
  OccNext, OccA, OccB: Integer;
  OccAttr: TColorAttr;

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
  if FSemantic and (FHl <> nil) and (not FSemValid or ((FSemVersion <> FEditor.Doc.Buffer.Version) and
    (FEditor.Doc.Buffer.Length <= TveSemanticAutoLimit))) then
  begin
    FindNames;
  end;
  Normal := NormalAttr;
  SelAttr := SelectedAttr;
  HlAttr := HighlightAttr;
  TX := TextWidth;
  TX0 := TX;
  X0 := Delta.X;
  IsLast := True;
  if FWrap then
    EnsureWrap;
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
  OccWord := '';
  if FMarkWord and not HasSel and (FEditor.Line < FEditor.Doc.Buffer.LineCount) then
  begin
    OccText := FEditor.Doc.Buffer.LineText(FEditor.Line);
    if TveWordAt(OccText, LayoutCellToIndex(OccText, FEditor.Cell, FEditor.Opt.TabSize), OccA, OccB) then
      OccWord := Copy(OccText, OccA, OccB - OccA);
  end;
  OccAttr := OccurrenceAttr;
  MsgRow := -1;
  if FMessage <> '' then
  begin
    if CursorRow - Delta.Y < Size.Y div 2 then
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
      if FWrap then
      begin
        InText := RowPlace(Delta.Y + Y, L, X0, SegEnd, IsLast);
        TX := SegEnd - X0;
        if not InText then
          L := FEditor.Doc.Buffer.LineCount;
      end
      else
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
        OccNext := 0;
        if OccWord <> '' then
          OccNext := TveFindWord(Text, OccWord, 1);
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
          while (OccNext > 0) and (Idx >= OccNext + Length(OccWord)) do
            OccNext := TveFindWord(Text, OccWord, OccNext + Length(OccWord));
          if (OccNext > 0) and (Idx >= OccNext) then
          begin
            Attr := OccAttr;
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
        if (FFolds <> nil) and IsLast then
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
        { the place where dragged text would go }
        if FDropShown and (L = FDropL) and (FDropC >= X0) and ((FDropC < X0 + TX) or (IsLast and (FDropC = X0 + TX))) and
          (GutterWidth + FDropC - X0 < Size.X) then
          B.PutAttribute(GutterWidth + FDropC - X0, DropAttr);
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
    if FWrap then
    begin
      RowPlace(CursorRow, CL, X0, SegEnd, IsLast);
      SetCursor(GutterWidth + FEditor.Cell - X0, CursorRow - Delta.Y);
    end
    else
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
  Total := TotalRows;
  Y := Delta.Y + N;
  if Y > Total - 1 then Y := Total - 1;
  if Y < 0 then Y := 0;
  ScrollTo(Delta.X, Y);
  { the cursor follows when it left the window }
  CV := CursorRow;
  if FWrap then
  begin
    if CV < Y then
      MoveToRow(Y, False)
    else if CV >= Y + Size.Y then
      MoveToRow(Y + Size.Y - 1, False);
  end
  else if CV < Y then
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
  if not Backward then
    RecordSearch(msFind, '');
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
  RecordSearch(msReplace, Repl);
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
  RecordSearch(msReplaceAll, Repl);
  Result := FSearcher.ReplaceAll(FEditor.Doc, FSearch, Repl);
  Sync;
end;

function TTveView.Outline: TTveOutline;
begin
  if FHl = nil then
    Result := nil
  else
    Result := TveOutline(FEditor.Doc, FHl.Language);
end;

function TTveView.FoldRegions: TTveFoldRegions;
begin
  if FHl = nil then
    Result := nil
  else
    Result := TveFoldRegions(FEditor.Doc, FHl.Language);
end;

{ the fold from L1 to L2; -1 if there is none }
function FindFold(F: TTveFolds; L1, L2: Int64): Integer;
var
  I: Integer;
begin
  for I := 0 to F.Count - 1 do
    if (F.StartLine(I) = L1) and (F.EndLine(I) = L2) then
      Exit(I);
  Result := -1;
end;

procedure TTveView.FoldAll;
var
  R: TTveFoldRegions;
  I: Integer;
begin
  R := FoldRegions;
  for I := 0 to High(R) do
    if FindFold(Folds, R[I].First, R[I].Last) < 0 then
      Folds.Add(R[I].First, R[I].Last, False);
  for I := 0 to Folds.Count - 1 do
    Folds.SetCollapsed(I, True);
  { the cursor goes to a line that is still shown }
  FEditor.GotoLineCell(Folds.ViewToLine(Folds.LineToView(FEditor.Line)), 0);
end;

{ Toggles (or collapses) the fold at the cursor: a fold that starts at its line, else a region of the grammar that starts there, else the innermost fold or
  region that holds the line. A region becomes a fold. The cursor goes to the first line of a fold that it collapses. }
procedure TTveView.FoldAtCursor(Toggle: Boolean);
var
  L, Best1, Best2: Int64;
  K: Integer;
  R: TTveFoldRegions;

  function Pick(Starts: Boolean): Boolean;
  var
    J: Integer;
  begin
    Best1 := -1;
    Best2 := -1;
    for J := 0 to High(R) do
      if ((R[J].First = L) or (not Starts and (R[J].First < L) and (L <= R[J].Last))) and
        ((Best1 < 0) or (R[J].Last - R[J].First < Best2 - Best1)) then
      begin
        Best1 := R[J].First;
        Best2 := R[J].Last;
      end;
    Result := Best1 >= 0;
  end;

begin
  L := FEditor.Line;
  K := Folds.FoldAt(L, True);
  if K < 0 then
  begin
    R := FoldRegions;
    if Pick(True) then
      K := Folds.Add(Best1, Best2, False)
    else
    begin
      { the innermost of the folds and the regions that hold the line }
      K := Folds.FoldAt(L);
      if Pick(False) and ((K < 0) or (Best2 - Best1 < Folds.EndLine(K) - Folds.StartLine(K))) then
      begin
        K := FindFold(Folds, Best1, Best2);
        if K < 0 then
          K := Folds.Add(Best1, Best2, False);
      end;
    end;
  end;
  if K < 0 then
    Exit;
  if Toggle and Folds.Collapsed(K) then
    Folds.SetCollapsed(K, False)
  else
  begin
    Folds.SetCollapsed(K, True);
    if L > Folds.StartLine(K) then
      FEditor.GotoLineCell(Folds.StartLine(K), 0);
  end;
end;

const
  MacroRoundsMax = 1000000;

function SearchFlags(const O: TTveSearchOptions): Integer;
begin
  Result := 0;
  if O.CaseSensitive then Result := Result or mfCase;
  if O.WholeWord then Result := Result or mfWord;
  if O.UseRegex then Result := Result or mfRegex;
  if O.Backward then Result := Result or mfBack;
  if O.Hex then Result := Result or mfHex;
end;

procedure TTveView.RecordSearch(Kind: Integer; const Repl: AnsiString);
begin
  if FRecording and not FPlaying and (FExecuting = 0) then
    FMacro.AddSearch(Kind, FSearch.Pattern, Repl, SearchFlags(FSearch));
end;

procedure TTveView.GotoPlace(Line: Int64; Cell: Integer);
begin
  if FRecording and not FPlaying then
    FMacro.AddSearch(msGoto, IntToStr(Line + 1) + ':' + IntToStr(Cell + 1), '', 0);
  Remember;
  FEditor.GotoLineCell(Line, Cell);
  Sync;
end;

procedure TTveView.GotoOffsetPlace(Offset: Int64);
begin
  if FRecording and not FPlaying then
    FMacro.AddSearch(msGoto, '+' + IntToStr(Offset), '', 0);
  Remember;
  FEditor.GotoOffset(Offset);
  Sync;
end;

procedure TTveView.TypeText(const S: AnsiString);
begin
  if FRecording and not FPlaying then
    FMacro.AddText(S);
  if FEditor.TypeText(S) then
    Sync;
end;

{ a goto step: False when the place is not in the text }
function TTveView.PlayGoto(const Place: AnsiString): Boolean;
var
  K: Integer;
  L, C, Ofs: Int64;
begin
  if (Place <> '') and (Place[1] = '+') then
  begin
    Ofs := StrToInt64Def(Copy(Place, 2, MaxInt), -1);
    Result := (Ofs >= 0) and (Ofs <= FEditor.Doc.Buffer.Length);
    if Result then
      GotoOffsetPlace(Ofs);
    Exit;
  end;
  K := Pos(':', Place);
  if K = 0 then
  begin
    L := StrToInt64Def(Place, 0);
    C := 1;
  end
  else
  begin
    L := StrToInt64Def(Copy(Place, 1, K - 1), 0);
    C := StrToInt64Def(Copy(Place, K + 1, MaxInt), 0);
  end;
  Result := (L >= 1) and (L <= FEditor.Doc.Buffer.LineCount) and (C >= 1) and (C <= MaxInt);
  if Result then
    GotoPlace(L - 1, C - 1);
end;

function TTveView.MacroCondition(const St: TTveMacroStep): Boolean;
var
  Ofs, LS: Int64;
  T: AnsiString;
  Re: TTveRegex;
  Caps: TCaps;
begin
  Ofs := FEditor.Offset;
  LS := FEditor.Doc.Buffer.LineStart(FEditor.Line);
  T := FEditor.Doc.Buffer.LineText(FEditor.Line);
  if (T <> '') and (T[Length(T)] = #13) then
    SetLength(T, Length(T) - 1);
  if St.Text = 'eof' then
    Result := Ofs >= FEditor.Doc.Buffer.Length
  else if St.Text = 'bof' then
    Result := Ofs = 0
  else if St.Text = 'eol' then
    Result := Ofs >= LS + Length(T)
  else if St.Text = 'bol' then
    Result := Ofs = LS
  else if St.Text = 'blank' then
    Result := Trim(T) = ''
  else if St.Text = 'selection' then
    Result := FEditor.HasSelection
  else if St.Text = 'at' then
    Result := FEditor.Doc.Buffer.Copy(Ofs, Length(St.Repl)) = St.Repl
  else if St.Text = 'match' then
  begin
    Re := TTveRegex.Create(St.Repl);
    try
      Result := (Re.Error = '') and Re.Exec(T, 1, Caps);
    finally
      Re.Free;
    end;
  end
  else
    Result := False;
  if St.Flags and mfNot <> 0 then
    Result := not Result;
end;

function TTveView.PlayStep(const St: TTveMacroStep): Boolean;
var
  Value: AnsiString;
  P: Int64;
  M: TTveMacro;
begin
  Result := True;
  if St.Cmd = msGoto then
    Exit(PlayGoto(St.Text));
  if St.Cmd = msStop then
  begin
    FMacroStop := True;
    Exit;
  end;
  if St.Cmd = msPlay then
  begin
    M := FMacros.Find(St.Text);
    if (M = nil) or (FMacroDepth >= 8) then
      Exit(False);
    Inc(FMacroDepth);
    try
      Result := RunMacro(M, 1);
    finally
      Dec(FMacroDepth);
    end;
    Exit;
  end;
  if St.Cmd = msIf then
    Exit;
  if St.Cmd < msText then
  begin
    if St.Cmd = msPrompt then
    begin
      Result := (FOnPrompt <> nil) and FOnPrompt(St.Text, Value);
      if Result and FEditor.TypeText(Value) then
        Sync;
      Exit;
    end;
    FSearch.Pattern := St.Text;
    FSearch.CaseSensitive := St.Flags and mfCase <> 0;
    FSearch.WholeWord := St.Flags and mfWord <> 0;
    FSearch.UseRegex := St.Flags and mfRegex <> 0;
    FSearch.Backward := St.Flags and mfBack <> 0;
    FSearch.Hex := St.Flags and mfHex <> 0;
    FSearch.AllCodePages := False;
    case St.Cmd of
      msFind: Result := FindNext = fsFound;
      msReplace: Result := ReplaceNext(St.Repl) > 0;
      msReplaceAll: ReplaceAll(St.Repl);
    end;
  end
  else if St.Cmd = msText then
  begin
    if FEditor.TypeText(St.Text) then
      Sync;
  end
  else
  begin
    P := FEditor.Offset;
    FStepFailed := False;
    Execute(St.Cmd);
    { a step of the cursor that cannot move fails (at an end of the text); Home, End and the like are where they go already }
    Result := not FStepFailed and not ((St.Cmd in [tcLeft, tcRight, tcUp, tcDown, tcPageUp, tcPageDown, tcWordLeft, tcWordRight, tcNavWordLeft,
      tcNavWordRight, tcSelLeft, tcSelRight, tcSelUp, tcSelDown, tcSelPageUp, tcSelPageDown, tcSelWordLeft, tcSelWordRight, tcSelNavWordLeft,
      tcSelNavWordRight]) and (FEditor.Offset = P));
  end;
end;

{ the rounds of a macro; a stop step ends them (and those of the macros that play it) }
function TTveView.RunMacro(M: TTveMacro; Times: Integer): Boolean;
var
  I, Round: Integer;
  Before: Int64;
  Ver: LongWord;
  St: TTveMacroStep;
begin
  Result := True;
  Round := 0;
  while Result and not FMacroStop and (((Times <= 0) and (Round < MacroRoundsMax)) or (Round < Times)) do
  begin
    Before := FEditor.Offset;
    Ver := FEditor.Doc.Buffer.Version;
    I := 0;
    while I < M.Count do
    begin
      St := M.Step(I);
      Inc(I);
      if St.Cmd = msIf then
      begin
        if not MacroCondition(St) then
          Inc(I);
        Continue;
      end;
      if not PlayStep(St) then
      begin
        Result := False;
        Break;
      end;
      if FMacroStop then
        Break;
    end;
    Inc(Round);
    if (Times <= 0) and (FEditor.Offset = Before) and (FEditor.Doc.Buffer.Version = Ver) then
      Break;
  end;
end;

function TTveView.PlayMacro(Times: Integer): Boolean;
begin
  Result := True;
  if FPlaying or (FMacro.Count = 0) then
    Exit;
  FPlaying := True;
  FMacroStop := False;
  FMacroDepth := 0;
  try
    Result := RunMacro(FMacro, Times);
  finally
    FPlaying := False;
    FMacroStop := False;
  end;
  Sync;
end;

function TTveView.PlayMacroNamed(const AName: AnsiString; Times: Integer): Boolean;
var
  Old: TTveMacro;
begin
  Old := FMacro;
  FMacro := FMacros.Find(AName);
  if FMacro = nil then
  begin
    FMacro := Old;
    Exit(False);
  end;
  try
    Result := PlayMacro(Times);
  finally
    FMacro := Old;
  end;
end;

procedure TTveView.SelectMacro(const AName: AnsiString);
begin
  FRecording := False;
  FMacro := FMacros.Get(AName);
  FMacroName := AName;
end;

function TTveView.LoadMacroFile(const FileName: AnsiString; out Err: AnsiString): Boolean;
begin
  Result := FMacros.LoadFile(FileName, Err);
  FMacro := FMacros.Get(FMacroName);
end;

function TTveView.SaveMacroFile(const FileName: AnsiString): Boolean;
begin
  Result := FMacros.SaveFile(FileName);
end;

function TTveView.Execute(Cmd: Integer): Boolean;
begin
  Result := True;
  if (FOnHost <> nil) and FOnHost(Self, Cmd) then
    Exit;
  if Cmd <> tcCompletion then
    FComplActive := False;
  if FRecording and not FPlaying and (Cmd <> tcMacroRecord) and (Cmd <> tcMacroPlay) and (Cmd <> tcMacroPlayAll) then
    FMacro.AddCommand(Cmd);
  Inc(FExecuting);
  try
    Result := RunCommand(Cmd);
  finally
    Dec(FExecuting);
  end;
end;

function TTveView.RunCommand(Cmd: Integer): Boolean;
var
  E: TTveEditor;
  Fwd: Int64;
  Back: Int64;
  MIdx: LongInt;
begin
  Result := True;
  E := FEditor;
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
  if FWrap and WrapMove(Cmd) then
  begin
    Sync;
    Exit;
  end;
  case Cmd of
    tcWrap: begin SetWrap(not FWrap); Exit; end;
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
    tcNavWordLeft: E.MoveNavWordLeft;
    tcNavWordRight: E.MoveNavWordRight;
    tcTextStart: begin Remember; E.MoveTextStart; end;
    tcTextEnd: begin Remember; E.MoveTextEnd; end;
    tcWindowTop: if FWrap then MoveToRow(Delta.Y, False) else E.GotoLineCell(ViewToLine(Delta.Y), E.Cell);
    tcWindowBottom: if FWrap then MoveToRow(Delta.Y + Size.Y - 1, False) else E.GotoLineCell(ViewToLine(Delta.Y + Size.Y - 1), E.Cell);
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
    tcSelNavWordLeft: E.MoveNavWordLeft(True);
    tcSelNavWordRight: E.MoveNavWordRight(True);
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
    tcFoldToggle, tcFoldCollapse: FoldAtCursor(Cmd = tcFoldToggle);
    tcFoldExpand: Folds.ExpandAt(E.Line);
    tcFoldAll: FoldAll;
    tcUnfoldAll: for MIdx := 0 to Folds.Count - 1 do Folds.SetCollapsed(MIdx, False);
    tcFoldFromBlock:
      if E.AffectedLines(Back, Fwd) and (Fwd > Back) then
      begin
        Folds.Add(Back, Fwd, False);
        E.ClearSelection;
      end;
    tcFindNext: FStepFailed := FindNext(False) <> fsFound;
    tcFindPrev: FStepFailed := FindNext(True) <> fsFound;
    tcMatchBracket: E.GotoMatchingBracket;
    tcSetMark0..tcSetMark0 + 9: E.SetBookmark(Cmd - tcSetMark0);
    tcGotoMark0..tcGotoMark0 + 9: begin Remember; E.GotoBookmark(Cmd - tcGotoMark0); end;
    tcClearMarks: for MIdx := 0 to 9 do E.ClearBookmark(MIdx);
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
          FMacro.Clear;
      end;
    tcMacroPlay:
      PlayMacro;
    tcMacroPlayAll:
      PlayMacro(0);
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
  A, B2: Integer;
  Last: Boolean;
begin
  P := MakeLocal(Where);
  if FWrap then
  begin
    RowPlace(Delta.Y + P.Y, L, A, B2, Last);
    C := A + P.X - GutterWidth;
    if C >= B2 then C := B2 - 1;
  end
  else
  begin
    L := ViewToLine(Delta.Y + P.Y);
    C := Delta.X + P.X - GutterWidth;
  end;
  if L < 0 then L := 0;
  if L >= FEditor.Doc.Buffer.LineCount then
    L := FEditor.Doc.Buffer.LineCount - 1;
  if C < 0 then C := 0;
  Result := True;
end;

// True when the cell is inside the stream or line selection (a column selection is not dragged).
function TTveView.InSelection(L: Int64; C: Integer): Boolean;
var
  A, B, Off: Int64;
begin
  Result := False;
  if not FEditor.HasSelection or (FEditor.SelKind = skColumn) then
    Exit;
  if not FEditor.SelectionRange(A, B) then
    Exit;
  Off := FEditor.LineCellToOffset(L, C);
  Result := (Off >= A) and (Off < B);
end;

// The button went down on the selected text: a click puts the cursor there, a drag moves the text (Ctrl: copies it) to where the button goes up.
{ A pointer above or below the view while a button is held scrolls by as many rows as it is away from the view (at most a page) and stands at the edge row. }
procedure TTveView.DragScroll(var P: TPoint);
var
  N: Integer;
begin
  if P.Y < 0 then
  begin
    N := -P.Y;
    P.Y := 0;
  end
  else if P.Y >= Size.Y then
  begin
    N := P.Y - Size.Y + 1;
    P.Y := Size.Y - 1;
  end
  else
    Exit;
  if N > Size.Y then
    N := Size.Y;
  if P.Y = 0 then
    ScrollLines(-N)
  else
    ScrollLines(N);
end;

procedure TTveView.ShowDrop(L: Int64; C: Integer);
begin
  if FDropShown and (FDropL = L) and (FDropC = C) then
    Exit;
  FDropShown := True;
  FDropL := L;
  FDropC := C;
  DrawView;
end;

procedure TTveView.HideDrop;
begin
  if not FDropShown then
    Exit;
  FDropShown := False;
  DrawView;
end;

{ The topmost visible view at a point of the screen, inside groups. }
function ViewAtPoint(G: TGroup; const Where: TPoint): TView;
var
  V: TView;
begin
  Result := nil;
  V := G.Last;
  if V = nil then
    Exit;
  repeat
    V := V.Next;
    if ((V.State and sfVisible) <> 0) and V.MouseInView(Where) then
    begin
      Result := V;
      if V is TGroup then
      begin
        V := ViewAtPoint(TGroup(V), Where);
        if V <> nil then
          Result := V;
      end;
      Exit;
    end;
  until V = G.Last;
end;

function TTveView.EditorAt(const Where: TPoint): TTveView;
var
  G: TGroup;
  V: TView;
begin
  Result := nil;
  G := Owner;
  if G = nil then
    Exit;
  while G.Owner <> nil do
    G := G.Owner;
  V := ViewAtPoint(G, Where);
  if (V <> Self) and (V is TTveView) then
    Result := TTveView(V);
end;

{ The selected text goes to another view: into its document at the place under the pointer (moved, or copied with Ctrl). One undo step on each side. }
procedure TTveView.DropInto(Target: TTveView; const Where: TPoint; Copying: Boolean);
var
  A, B, Ofs: Int64;
  L: Int64;
  C: Integer;
  S: AnsiString;
begin
  if (FEditor.SelKind = skColumn) or not FEditor.SelectionRange(A, B) or (B <= A) then
    Exit;
  Target.Hit(Where, L, C);
  if Target.Doc = Doc then
  begin
    { two views of one document: as a drag inside it }
    DragBlock(FEditor, FEditor.LineCellToOffset(L, C), Copying);
    Sync;
    Target.Refresh;
    Exit;
  end;
  S := Doc.Buffer.Copy(A, B - A);
  Target.Editor.GotoLineCell(L, C);
  Ofs := Target.Editor.Offset;
  if not Target.Doc.Insert(Ofs, S) then
    Exit;
  Target.Editor.SetSelection(skStream, Ofs);
  Target.Editor.GotoOffset(Ofs + Length(S));
  if not Copying then
    FEditor.DeleteSelection;
  Sync;
  { the window of the other editor comes to the front with it }
  if Target.Owner <> nil then
    Target.Owner.Focus;
  Target.Select;
  Target.Refresh;
end;

procedure TTveView.DragSelection(var Event: TEvent);
var
  L: Int64;
  C: Integer;
  Start: TPoint;
  Moved, Copying: Boolean;
  P: TPoint;
  OldL: Int64;
  OldC: Integer;
  Target, Over: TTveView;
begin
  Start := Event.Where;
  Moved := False;
  Copying := (Event.ControlKeyState and kbCtrlShift) <> 0;
  OldL := FEditor.Line;
  OldC := FEditor.Cell;
  Target := nil;
  FEditor.FreezeSelection;        // the selection stays while the cursor shows where the text would go
  while MouseEvent(Event, evMouseMove or evMouseAuto) do
  begin
    if (Event.Where.X <> Start.X) or (Event.Where.Y <> Start.Y) then
      Moved := True;
    if not Moved then
      Continue;
    Copying := (Event.ControlKeyState and kbCtrlShift) <> 0;
    { over another editor: that one shows where the text would go }
    Over := nil;
    if not MouseInView(Event.Where) then
      Over := EditorAt(Event.Where);
    if Over <> Target then
    begin
      if Target <> nil then
        Target.HideDrop;
      Target := Over;
    end;
    if Target <> nil then
    begin
      Target.Hit(Event.Where, L, C);
      Target.ShowDrop(L, C);
      HideDrop;
      Continue;
    end;
    P := MakeLocal(Event.Where);
    DragScroll(P);
    Hit(MakeGlobal(P), L, C);
    FEditor.GotoLineCell(L, C);
    FDropShown := True;
    FDropL := FEditor.Line;
    FDropC := FEditor.Cell;
    Sync;
  end;
  FDropShown := False;
  if (Event.ControlKeyState and kbCtrlShift) <> 0 then
    Copying := True;
  if Target <> nil then
  begin
    Target.HideDrop;
    FEditor.GotoLineCell(OldL, OldC);
    DropInto(Target, Event.Where, Copying);
    Sync;
    Exit;
  end;
  P := MakeLocal(Event.Where);
  if P.Y < 0 then P.Y := 0;
  if P.Y >= Size.Y then P.Y := Size.Y - 1;
  Hit(MakeGlobal(P), L, C);
  if not Moved then
  begin
    FEditor.ClearSelection;
    FEditor.GotoLineCell(L, C);
  end
  else if not DragBlock(FEditor, FEditor.LineCellToOffset(L, C), Copying) then
    FEditor.GotoLineCell(OldL, OldC);
  Sync;
end;

procedure TTveView.DoMouse(var Event: TEvent);
var
  L: Int64;
  C: Integer;
  Extend: Boolean;
  P: TPoint;
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
  if not Extend and FDragDrop and InSelection(L, C) then
  begin
    DragSelection(Event);
    Exit;
  end;
  if not Extend then
  begin
    FEditor.ClearSelection;
    FEditor.GotoLineCell(L, C);
    if ((Event.ControlKeyState and kbAltShift) <> 0) or FEditor.Opt.ColumnBlocks then
      FEditor.StartSelection(skColumn)
    else
      FEditor.StartSelection(skStream);
  end
  else
  begin
    if not FEditor.HasSelection then
    begin
      if FEditor.Opt.ColumnBlocks then
        FEditor.StartSelection(skColumn)
      else
        FEditor.StartSelection(skStream);
    end;
    FEditor.GotoLineCell(L, C);
  end;
  Sync;
  while MouseEvent(Event, evMouseMove or evMouseAuto) do
  begin
    P := MakeLocal(Event.Where);
    DragScroll(P);
    Hit(MakeGlobal(P), L, C);
    FEditor.GotoLineCell(L, C);
    Sync;
  end;
end;

procedure TTveView.HandleEvent(var Event: TEvent);
var
  E2: TEvent;
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
          if (Cmd <= 0) and ((K.Code and $FF) > 32) and ((K.Code and $FF) < 127) and ((K.Code <> (K.Code and $FF)) or ((K.Mods and kbShift) <> 0)) then
            { a second key of a chord that is a character: also without Shift and from the keypad (Ctrl+K + is Ctrl+K Shift+= on many keyboards) }
            Cmd := FKeymap.LookupChord(FPrefix, KeyMake(K.Code and $FF, K.Mods and not kbShift));
          if Cmd <= 0 then
          begin
            { the second key typed in another layout: the Latin key of the same place }
            E2 := Event;
            if XlatPlain(E2) then
              Cmd := FKeymap.LookupChord(FPrefix, KeyMake(E2.KeyCode, E2.ControlKeyState));
          end;
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
          begin
            if FRecording then
              FMacro.AddText(T);
            Sync;
          end;
          ClearEvent(Event);
        end;
      end;
  end;
end;

end.
