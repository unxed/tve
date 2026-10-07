{ TveDoc: a document of the editor: the text (TveBuf), the undo and redo, the anchors, and what is known about the file.

  MIT.

  Undo is a stack of groups; a group is the edits (TTveEdit of TveBuf) that one command made, and the cursor before and after. Typing a run of letters, or
  a run of Backspace, or a run of Delete, is one group (consecutive edits that touch each other merge); everything else is a group of its own, unless the caller
  opens one (BeginGroup .. EndGroup: paste, replace all, a block operation). A new edit throws the redo stack away. The save point is the number of groups when
  the file was saved: the document is modified when it is not at that number (or when the save point was lost by throwing the redo stack away). The cursor is not
  kept here (a document can have several views): the view tells the document where its cursor is (NoteCursor) and gets the position back from Undo and Redo.

  Anchors are offsets that follow the edits: the bookmarks, the folds, the markers of the debugger. An anchor in a removed run moves to the start of the run; an
  anchor at the place of an insertion stays before the inserted text (Sticky anchors go after it).

  The observers (views, highlighters) are told about every change, also by undo and redo, with the offset and the lengths removed and inserted. }
unit TveDoc;

{$I tvdefs.inc}

interface

uses
  TveBuf;

type
  { How the lines end in the file (the text itself has LF only) }
  TTveEol = (eolLF, eolCRLF, eolCR);

  { What is known of the file the document came from (filled by TveFile) }
  TTveFileInfo = record
    Charset: LongInt;               { the id of TvCharset the file is written in (65001 UTF-8, 1200 UTF-16LE ...) }
    Bom: Boolean;                   { the file starts with a byte order mark }
    Eol: TTveEol;
    MixedEol: Boolean;              { the file had more than one kind of line ends }
    DiskSize: Int64;                { as of the last read or write }
    DiskAge: LongInt;
    Known: Boolean;                 { DiskSize and DiskAge are valid }
  end;

  TTveUndoKind = (ukOther, ukTyping, ukBackspace, ukDeleteKey);

  TTveUndoGroup = record
    Edits: array of TTveEdit;
    Kind: TTveUndoKind;
    CursorBefore, CursorAfter: Int64;
    Sealed: Boolean;                { nothing more is merged into it }
  end;

  TTveAnchor = record
    Pos: Int64;
    Sticky: Boolean;                { stays after text that is inserted at its place }
    Alive: Boolean;
  end;

  TTveDoc = class;
  TTveDocObserver = procedure(Doc: TTveDoc; Offset, Removed, Inserted: Int64) of object;

  TTveDoc = class
  private
    FBuf: TTveBuffer;
    FUndo: array of TTveUndoGroup;
    FUndoCount: Integer;            { the groups 0 .. FUndoCount - 1 can be undone; the ones after it are the redo stack }
    FRedoCount: Integer;
    FSaveIndex: Integer;            { the number of groups at the last save; -1: lost }
    FGroupDepth: Integer;
    FGroupOpen: Boolean;
    FCursor: Int64;
    FAnchors: array of TTveAnchor;
    FObservers: array of TTveDocObserver;
    FEol: TTveEol;
    FInfo: TTveFileInfo;
    FReadOnly: Boolean;
    FUndoLimit: Integer;
    FFileName: AnsiString;
    FDirtyEpoch: LongWord;
    procedure BufferChange(Sender: TTveBuffer; Offset, Removed, Inserted: Int64);
    procedure MoveAnchors(Offset, Removed, Inserted: Int64);
    procedure Notify(Offset, Removed, Inserted: Int64);
    procedure NewGroup(Kind: TTveUndoKind);
    function CanMerge(Kind: TTveUndoKind; Offset, Removed, Inserted: Int64): Boolean;
    procedure TrimUndo;
    function GetModified: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    property Buffer: TTveBuffer read FBuf;
    property FileName: AnsiString read FFileName write FFileName;
    property Eol: TTveEol read FEol write FEol;
    property Info: TTveFileInfo read FInfo write FInfo;
    property ReadOnly: Boolean read FReadOnly write FReadOnly;
    property Modified: Boolean read GetModified;
    property UndoLimit: Integer read FUndoLimit write FUndoLimit;

    { Replaces the text by S (LF line ends), forgets the undo and marks the document as saved. }
    procedure LoadText(const S: AnsiString);
    { The text was written to the file: the document is not modified now. }
    procedure MarkSaved;

    { Editing. All of them return False for a read-only document and do nothing then. Offsets are cut to the text. }
    function Replace(Offset, DelCount: Int64; const Ins: AnsiString): Boolean;
    function Insert(Offset: Int64; const S: AnsiString): Boolean;
    function Delete(Offset, Count: Int64): Boolean;

    { Groups: the edits between BeginGroup and EndGroup are one undo step (they nest). }
    procedure BeginGroup;
    procedure EndGroup;
    { The next edit starts a new group even if it touches the last one (the cursor jumped, the command changed). }
    procedure BreakUndo;
    { The view says where its cursor is: it is stored with the groups. }
    procedure NoteCursor(Pos: Int64);
    { Where the cursor is after the edit that was just made: stored with its group (redo puts the cursor there). }
    procedure NoteCursorAfter(Pos: Int64);
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    { The cursor to restore (the offset), False if there was nothing to do. }
    function Undo(out Cursor: Int64): Boolean;
    function Redo(out Cursor: Int64): Boolean;
    function UndoCount: Integer;

    { Anchors: an id (>= 0) to ask for the position later. A removed anchor is not counted. }
    function AddAnchor(Pos: Int64; Sticky: Boolean = False): Integer;
    function AnchorPos(Id: Integer): Int64;
    function AnchorAlive(Id: Integer): Boolean;
    procedure SetAnchor(Id: Integer; Pos: Int64);
    procedure RemoveAnchor(Id: Integer);

    procedure AddObserver(Obs: TTveDocObserver);
    procedure RemoveObserver(Obs: TTveDocObserver);
  end;

implementation

constructor TTveDoc.Create;
begin
  inherited Create;
  FBuf := TTveBuffer.Create;
  FBuf.OnChange := @BufferChange;
  FEol := eolLF;
  FInfo.Charset := 65001;
  FUndoLimit := 100000;
end;

destructor TTveDoc.Destroy;
begin
  FBuf.Free;
  inherited Destroy;
end;

procedure TTveDoc.LoadText(const S: AnsiString);
begin
  FBuf.SetText(S);
  FUndo := nil;
  FUndoCount := 0;
  FRedoCount := 0;
  FSaveIndex := 0;
  FGroupDepth := 0;
  FGroupOpen := False;
  FAnchors := nil;
  Notify(0, 0, FBuf.Length);
end;

procedure TTveDoc.MarkSaved;
begin
  FSaveIndex := FUndoCount;
  if FUndoCount > 0 then
    FUndo[FUndoCount - 1].Sealed := True;       { the saved state must stay reachable: nothing merges into its last group }
  Inc(FDirtyEpoch);
end;

function TTveDoc.GetModified: Boolean;
begin
  Result := (FSaveIndex < 0) or (FSaveIndex <> FUndoCount);
end;

{ --- the observers and the anchors --- }

procedure TTveDoc.AddObserver(Obs: TTveDocObserver);
begin
  SetLength(FObservers, Length(FObservers) + 1);
  FObservers[High(FObservers)] := Obs;
end;

procedure TTveDoc.RemoveObserver(Obs: TTveDocObserver);
var
  I, J: Integer;
begin
  for I := 0 to High(FObservers) do
    if (TMethod(FObservers[I]).Code = TMethod(Obs).Code) and (TMethod(FObservers[I]).Data = TMethod(Obs).Data) then
    begin
      for J := I to High(FObservers) - 1 do
        FObservers[J] := FObservers[J + 1];
      SetLength(FObservers, Length(FObservers) - 1);
      Exit;
    end;
end;

procedure TTveDoc.Notify(Offset, Removed, Inserted: Int64);
var
  I: Integer;
begin
  for I := 0 to High(FObservers) do
    FObservers[I](Self, Offset, Removed, Inserted);
end;

procedure TTveDoc.MoveAnchors(Offset, Removed, Inserted: Int64);
var
  I: Integer;
begin
  for I := 0 to High(FAnchors) do
    with FAnchors[I] do
      if Alive then
      begin
        if Pos > Offset + Removed then
          Inc(Pos, Inserted - Removed)
        else if Pos > Offset then
          Pos := Offset                         { inside the removed run: at its start }
        else if (Pos = Offset) and Sticky and (Removed = 0) then
          Inc(Pos, Inserted);
      end;
end;

procedure TTveDoc.BufferChange(Sender: TTveBuffer; Offset, Removed, Inserted: Int64);
begin
  MoveAnchors(Offset, Removed, Inserted);
  Notify(Offset, Removed, Inserted);
end;

function TTveDoc.AddAnchor(Pos: Int64; Sticky: Boolean): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FAnchors) do
    if not FAnchors[I].Alive then
    begin
      FAnchors[I].Pos := Pos;
      FAnchors[I].Sticky := Sticky;
      FAnchors[I].Alive := True;
      Exit(I);
    end;
  SetLength(FAnchors, Length(FAnchors) + 1);
  Result := High(FAnchors);
  FAnchors[Result].Pos := Pos;
  FAnchors[Result].Sticky := Sticky;
  FAnchors[Result].Alive := True;
end;

function TTveDoc.AnchorPos(Id: Integer): Int64;
begin
  if (Id < 0) or (Id > High(FAnchors)) or not FAnchors[Id].Alive then
    Exit(-1);
  Result := FAnchors[Id].Pos;
end;

function TTveDoc.AnchorAlive(Id: Integer): Boolean;
begin
  Result := (Id >= 0) and (Id <= High(FAnchors)) and FAnchors[Id].Alive;
end;

procedure TTveDoc.SetAnchor(Id: Integer; Pos: Int64);
begin
  if (Id >= 0) and (Id <= High(FAnchors)) and FAnchors[Id].Alive then
    FAnchors[Id].Pos := Pos;
end;

procedure TTveDoc.RemoveAnchor(Id: Integer);
begin
  if (Id >= 0) and (Id <= High(FAnchors)) then
    FAnchors[Id].Alive := False;
end;

{ --- undo --- }

procedure TTveDoc.NoteCursor(Pos: Int64);
begin
  FCursor := Pos;
end;

procedure TTveDoc.NoteCursorAfter(Pos: Int64);
begin
  FCursor := Pos;
  if (FUndoCount > 0) and (FRedoCount = 0) then
    FUndo[FUndoCount - 1].CursorAfter := Pos;
end;

procedure TTveDoc.BreakUndo;
begin
  if (FUndoCount > 0) and (FGroupDepth = 0) then
    FUndo[FUndoCount - 1].Sealed := True;
end;

procedure TTveDoc.TrimUndo;
var
  Cut, I: Integer;
begin
  if (FUndoLimit <= 0) or (FUndoCount <= FUndoLimit) then
    Exit;
  Cut := FUndoCount - FUndoLimit;
  for I := Cut to FUndoCount - 1 do
    FUndo[I - Cut] := FUndo[I];
  Dec(FUndoCount, Cut);
  if FSaveIndex >= 0 then
  begin
    Dec(FSaveIndex, Cut);
    if FSaveIndex < 0 then
      FSaveIndex := -1;                          { the saved state fell out of the history }
  end;
end;

procedure TTveDoc.NewGroup(Kind: TTveUndoKind);
begin
  { a new edit throws the redo stack away; if the save point was in it, it is lost }
  if FRedoCount > 0 then
  begin
    if FSaveIndex > FUndoCount then
      FSaveIndex := -1;
    FRedoCount := 0;
  end;
  if FUndoCount = Length(FUndo) then
    SetLength(FUndo, FUndoCount * 2 + 16);
  FUndo[FUndoCount].Edits := nil;
  FUndo[FUndoCount].Kind := Kind;
  FUndo[FUndoCount].CursorBefore := FCursor;
  FUndo[FUndoCount].CursorAfter := FCursor;
  FUndo[FUndoCount].Sealed := False;
  Inc(FUndoCount);
  TrimUndo;
end;

{ Do the edit and the last group belong together? Typing continues where the last typing ended; Backspace goes back; Delete stays. }
function TTveDoc.CanMerge(Kind: TTveUndoKind; Offset, Removed, Inserted: Int64): Boolean;
var
  G: ^TTveUndoGroup;
  L: TTveEdit;
begin
  Result := False;
  if (Kind = ukOther) or (FUndoCount = 0) or (FRedoCount > 0) or (FGroupDepth > 0) then
    Exit;
  G := @FUndo[FUndoCount - 1];
  if (G^.Sealed) or (G^.Kind <> Kind) or (Length(G^.Edits) = 0) then
    Exit;
  L := G^.Edits[High(G^.Edits)];
  case Kind of
    ukTyping:
      Result := (Removed = 0) and (Offset = L.Offset + L.Inserted);
    ukBackspace:
      Result := (Inserted = 0) and (Offset + Removed = L.Offset);
    ukDeleteKey:
      Result := (Inserted = 0) and (Offset = L.Offset);
  end;
end;

procedure TTveDoc.BeginGroup;
begin
  if FGroupDepth = 0 then
  begin
    NewGroup(ukOther);
    FGroupOpen := True;
  end;
  Inc(FGroupDepth);
end;

procedure TTveDoc.EndGroup;
begin
  if FGroupDepth = 0 then
    Exit;
  Dec(FGroupDepth);
  if FGroupDepth = 0 then
  begin
    FGroupOpen := False;
    FUndo[FUndoCount - 1].CursorAfter := FCursor;
    FUndo[FUndoCount - 1].Sealed := True;
    { a group without edits is nothing }
    if Length(FUndo[FUndoCount - 1].Edits) = 0 then
      Dec(FUndoCount);
  end;
end;

function TTveDoc.Replace(Offset, DelCount: Int64; const Ins: AnsiString): Boolean;
var
  Kind: TTveUndoKind;
  E: TTveEdit;
  G: Integer;
begin
  Result := False;
  if FReadOnly then
    Exit;
  if Offset < 0 then Offset := 0;
  if Offset > FBuf.Length then Offset := FBuf.Length;
  if DelCount < 0 then DelCount := 0;
  if Offset + DelCount > FBuf.Length then DelCount := FBuf.Length - Offset;
  if (DelCount = 0) and (Ins = '') then
    Exit(True);
  { the kind of the edit, to find out whether it merges with the last group }
  Kind := ukOther;
  if (DelCount = 0) and (Length(Ins) = 1) and (Ins <> #10) then
    Kind := ukTyping
  else if (Ins = '') and (FBuf.Length > 0) then
  begin
    { one character deleted: Backspace if the cursor was at its end, Delete if at its start }
    if (DelCount <= 4) and (FCursor = Offset + DelCount) and (FCursor <> Offset) then
      Kind := ukBackspace
    else if (DelCount <= 4) and (FCursor = Offset) then
      Kind := ukDeleteKey;
  end;
  if FGroupDepth = 0 then
  begin
    if CanMerge(Kind, Offset, DelCount, Length(Ins)) then
      G := FUndoCount - 1
    else
    begin
      NewGroup(Kind);
      G := FUndoCount - 1;
    end;
  end
  else
    G := FUndoCount - 1;
  E := FBuf.Replace(Offset, DelCount, Ins);
  SetLength(FUndo[G].Edits, Length(FUndo[G].Edits) + 1);
  FUndo[G].Edits[High(FUndo[G].Edits)] := E;
  FUndo[G].CursorAfter := FCursor;
  Inc(FDirtyEpoch);
  Result := True;
end;

function TTveDoc.Insert(Offset: Int64; const S: AnsiString): Boolean;
begin
  Result := Replace(Offset, 0, S);
end;

function TTveDoc.Delete(Offset, Count: Int64): Boolean;
begin
  Result := Replace(Offset, Count, '');
end;

function TTveDoc.CanUndo: Boolean;
begin
  Result := FUndoCount > 0;
end;

function TTveDoc.CanRedo: Boolean;
begin
  Result := FRedoCount > 0;
end;

function TTveDoc.UndoCount: Integer;
begin
  Result := FUndoCount;
end;

function TTveDoc.Undo(out Cursor: Int64): Boolean;
var
  I: Integer;
begin
  Result := False;
  Cursor := FCursor;
  if (FUndoCount = 0) or (FGroupDepth > 0) then
    Exit;
  Dec(FUndoCount);
  Inc(FRedoCount);
  { the groups after FUndoCount are kept in place: the redo stack is the same array, above the count }
  for I := High(FUndo[FUndoCount].Edits) downto 0 do
    FBuf.Apply(FUndo[FUndoCount].Edits[I], True);
  FUndo[FUndoCount].Sealed := True;
  Cursor := FUndo[FUndoCount].CursorBefore;
  Result := True;
end;

function TTveDoc.Redo(out Cursor: Int64): Boolean;
var
  I: Integer;
begin
  Result := False;
  Cursor := FCursor;
  if (FRedoCount = 0) or (FGroupDepth > 0) then
    Exit;
  for I := 0 to High(FUndo[FUndoCount].Edits) do
    FBuf.Apply(FUndo[FUndoCount].Edits[I], False);
  Cursor := FUndo[FUndoCount].CursorAfter;
  Inc(FUndoCount);
  Dec(FRedoCount);
  Result := True;
end;

end.
