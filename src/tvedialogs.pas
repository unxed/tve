{ TveDialogs: the dialogs of the editor: find, replace, go to line. They are plain functions; the view does not call them itself, a host (or the tve program)
  connects them to the commands.

  MIT. }
unit TveDialogs;

{$I tvdefs.inc}
{$H+}

interface

uses
  TveSearch;

{ True when the user pressed OK; Opt gets the pattern and the options. }
function TveFindDialog(var Opt: TTveSearchOptions): Boolean;
{ Also the replacement text and "replace all". }
function TveReplaceDialog(var Opt: TTveSearchOptions; var Repl: AnsiString; var All: Boolean): Boolean;
{ A code point to insert: "U+263A", "0x263a", "263a" or "#9786" (see TveParseCodePoint in TveExtras). }
function TveCodePointDialog(var Text: AnsiString): Boolean;
{ A line number, "line:column" or "+offset" (the text is returned as typed; see TveParseGoto). }
function TveGotoDialog(var Text: AnsiString): Boolean;

{ A list to choose from (the outline of a document): Index is the item that is focused first and the chosen one when True is returned. Enter, OK or a double click choose. }
type
  TTveStringArray = array of AnsiString;
function TveListDialog(const Title: AnsiString; const Items: TTveStringArray; var Index: Integer): Boolean;

{ "12", "12:5", "+1000" (byte offset); False when the text is none of them. Line and column are 1-based in the text and 0-based in the result. }
function TveParseGoto(const Text: AnsiString; out Line: Int64; out Cell: Integer; out Offset: Int64; out IsOffset: Boolean): Boolean;

implementation

uses
  SysUtils, TvGeom, TvViews, TvApp, TvDialog, TvInput, TvCluster, TvHist, TvEvents, TvList, TvWindow;

const
  HistFind = 61;
  HistRepl = 62;
  HistGoto = 63;
  HistCode = 64;

type
  TFindRec = record
    Pattern: string[80];
    Flags: Word;
  end;
  TReplRec = record
    Pattern: string[80];
    Repl: string[80];
    Flags: Word;
  end;
  TGotoRec = record
    Text: string[40];
  end;

function Run(D: TDialog): Boolean;
begin
  Result := TProgram.DeskTop.ExecView(D) = cmOK;
end;

function MakeBoxes(D: TDialog; X, Y: Integer; Three: Boolean): TView;
var
  R: TRect;
begin
  R.Assign(X, Y, X + 36, Y + 6);
  Result := TCheckBoxes.Create(R,
    NewSItem('~C~ase sensitive',
    NewSItem('~W~hole words only',
    NewSItem('~R~egular expression',
    NewSItem('~B~ackward',
    NewSItem('He~x~ bytes',
    NewSItem('~A~ll code pages', nil)))))));
  D.Insert(Result);
end;

function FlagsOf(const O: TTveSearchOptions): Word;
begin
  Result := 0;
  if O.CaseSensitive then Result := Result or 1;
  if O.WholeWord then Result := Result or 2;
  if O.UseRegex then Result := Result or 4;
  if O.Backward then Result := Result or 8;
  if O.Hex then Result := Result or 16;
  if O.AllCodePages then Result := Result or 32;
end;

procedure FlagsTo(F: Word; var O: TTveSearchOptions);
begin
  O.CaseSensitive := (F and 1) <> 0;
  O.WholeWord := (F and 2) <> 0;
  O.UseRegex := (F and 4) <> 0;
  O.Backward := (F and 8) <> 0;
  O.Hex := (F and 16) <> 0;
  O.AllCodePages := (F and 32) <> 0;
end;

function TveFindDialog(var Opt: TTveSearchOptions): Boolean;
var
  D: TDialog;
  R: TRect;
  I: TInputLine;
  Rec: TFindRec;
begin
  R.Assign(0, 0, 52, 15);
  D := TDialog.Create(R, 'Find');
  D.Options := D.Options or ofCentered;
  R.Assign(3, 3, 46, 4);
  I := TInputLine.Create(R, 80);
  D.Insert(I);
  R.Assign(2, 2, 20, 3);
  D.Insert(TLabel.Create(R, '~T~ext to find', I));
  R.Assign(46, 3, 49, 4);
  D.Insert(THistory.Create(R, I, HistFind));
  MakeBoxes(D, 3, 5, False);
  R.Assign(14, 12, 24, 14);
  D.Insert(TButton.Create(R, 'O~K~', cmOK, bfDefault));
  R.Assign(26, 12, 36, 14);
  D.Insert(TButton.Create(R, 'Cancel', cmCancel, bfNormal));
  D.SelectNext(False);
  Rec.Pattern := Copy(Opt.Pattern, 1, 80);
  Rec.Flags := FlagsOf(Opt);
  D.SetData(Rec);
  Result := Run(D);
  if Result then
  begin
    D.GetData(Rec);
    Opt.Pattern := Rec.Pattern;
    FlagsTo(Rec.Flags, Opt);
  end;
  D.Free;
end;

function TveReplaceDialog(var Opt: TTveSearchOptions; var Repl: AnsiString; var All: Boolean): Boolean;
var
  D: TDialog;
  R: TRect;
  I, J: TInputLine;
  Rec: TReplRec;
  Boxes: TView;
  K: Word;
begin
  R.Assign(0, 0, 52, 18);
  D := TDialog.Create(R, 'Replace');
  D.Options := D.Options or ofCentered;
  R.Assign(3, 3, 46, 4);
  I := TInputLine.Create(R, 80);
  D.Insert(I);
  R.Assign(2, 2, 20, 3);
  D.Insert(TLabel.Create(R, '~T~ext to find', I));
  R.Assign(46, 3, 49, 4);
  D.Insert(THistory.Create(R, I, HistFind));
  R.Assign(3, 6, 46, 7);
  J := TInputLine.Create(R, 80);
  D.Insert(J);
  R.Assign(2, 5, 20, 6);
  D.Insert(TLabel.Create(R, '~N~ew text', J));
  R.Assign(46, 6, 49, 7);
  D.Insert(THistory.Create(R, J, HistRepl));
  Boxes := MakeBoxes(D, 3, 8, False);
  R.Assign(4, 15, 20, 17);
  D.Insert(TButton.Create(R, '~R~eplace', cmOK, bfDefault));
  R.Assign(21, 15, 35, 17);
  D.Insert(TButton.Create(R, 'Replace ~a~ll', cmYes, bfNormal));
  R.Assign(36, 15, 48, 17);
  D.Insert(TButton.Create(R, 'Cancel', cmCancel, bfNormal));
  D.SelectNext(False);
  Rec.Pattern := Copy(Opt.Pattern, 1, 80);
  Rec.Repl := Copy(Repl, 1, 80);
  Rec.Flags := FlagsOf(Opt);
  D.SetData(Rec);
  K := TProgram.DeskTop.ExecView(D);
  All := K = cmYes;
  Result := (K = cmOK) or (K = cmYes);
  if Result then
  begin
    D.GetData(Rec);
    Opt.Pattern := Rec.Pattern;
    Repl := Rec.Repl;
    FlagsTo(Rec.Flags, Opt);
  end;
  D.Free;
end;

function TveCodePointDialog(var Text: AnsiString): Boolean;
var
  D: TDialog;
  R: TRect;
  I: TInputLine;
  Rec: TGotoRec;
begin
  R.Assign(0, 0, 44, 8);
  D := TDialog.Create(R, 'Insert character');
  D.Options := D.Options or ofCentered;
  R.Assign(3, 3, 37, 4);
  I := TInputLine.Create(R, 40);
  D.Insert(I);
  R.Assign(2, 2, 40, 3);
  D.Insert(TLabel.Create(R, '~C~ode point (U+263A, 263A or #9786)', I));
  R.Assign(37, 3, 40, 4);
  D.Insert(THistory.Create(R, I, HistCode));
  R.Assign(10, 5, 20, 7);
  D.Insert(TButton.Create(R, 'O~K~', cmOK, bfDefault));
  R.Assign(22, 5, 32, 7);
  D.Insert(TButton.Create(R, 'Cancel', cmCancel, bfNormal));
  D.SelectNext(False);
  Rec.Text := Copy(Text, 1, 40);
  D.SetData(Rec);
  Result := Run(D);
  if Result then
  begin
    D.GetData(Rec);
    Text := Rec.Text;
  end;
  D.Free;
end;

function TveGotoDialog(var Text: AnsiString): Boolean;
var
  D: TDialog;
  R: TRect;
  I: TInputLine;
  Rec: TGotoRec;
begin
  R.Assign(0, 0, 44, 8);
  D := TDialog.Create(R, 'Go to');
  D.Options := D.Options or ofCentered;
  R.Assign(3, 3, 37, 4);
  I := TInputLine.Create(R, 40);
  D.Insert(I);
  R.Assign(2, 2, 40, 3);
  D.Insert(TLabel.Create(R, '~L~ine, line:column or +offset', I));
  R.Assign(37, 3, 40, 4);
  D.Insert(THistory.Create(R, I, HistGoto));
  R.Assign(10, 5, 20, 7);
  D.Insert(TButton.Create(R, 'O~K~', cmOK, bfDefault));
  R.Assign(22, 5, 32, 7);
  D.Insert(TButton.Create(R, 'Cancel', cmCancel, bfNormal));
  D.SelectNext(False);
  Rec.Text := Copy(Text, 1, 40);
  D.SetData(Rec);
  Result := Run(D);
  if Result then
  begin
    D.GetData(Rec);
    Text := Rec.Text;
  end;
  D.Free;
end;

type
  TStrListViewer = class(TListViewer)
    Items: TTveStringArray;
    function GetText(Item, MaxLen: Integer): ShortString; override;
    procedure SelectItem(Item: Integer); override;
  end;

function TStrListViewer.GetText(Item, MaxLen: Integer): ShortString;
begin
  if (Item >= 0) and (Item < Length(Items)) then
    Result := Copy(Items[Item], 1, MaxLen)
  else
    Result := '';
end;

procedure TStrListViewer.SelectItem(Item: Integer);
begin
  Message(TopView, evCommand, cmOK, Self);
end;

function TveListDialog(const Title: AnsiString; const Items: TTveStringArray; var Index: Integer): Boolean;
var
  D: TDialog;
  R: TRect;
  V: TStrListViewer;
  Bar: TScrollBar;
begin
  Result := False;
  if Length(Items) = 0 then
    Exit;
  R.Assign(0, 0, 60, 20);
  D := TDialog.Create(R, Title);
  D.Options := D.Options or ofCentered;
  R.Assign(57, 2, 58, 15);
  Bar := TScrollBar.Create(R);
  D.Insert(Bar);
  R.Assign(2, 2, 57, 15);
  V := TStrListViewer.Create(R, 1, nil, Bar);
  V.Items := Items;
  V.SetRange(Length(Items));
  D.Insert(V);
  R.Assign(14, 16, 24, 18);
  D.Insert(TButton.Create(R, 'O~K~', cmOK, bfDefault));
  R.Assign(34, 16, 44, 18);
  D.Insert(TButton.Create(R, 'Cancel', cmCancel, bfNormal));
  if (Index >= 0) and (Index < Length(Items)) then
    V.FocusItem(Index);
  V.Select;
  Result := Run(D);
  if Result then
    Index := V.Focused;
  D.Free;
end;

function TveParseGoto(const Text: AnsiString; out Line: Int64; out Cell: Integer; out Offset: Int64; out IsOffset: Boolean): Boolean;
var
  S: AnsiString;
  P: Integer;
  V: Int64;
begin
  Result := False;
  Line := 0;
  Cell := 0;
  Offset := 0;
  IsOffset := False;
  S := Trim(Text);
  if S = '' then
    Exit;
  if S[1] = '+' then
  begin
    if not TryStrToInt64(Copy(S, 2, MaxInt), V) or (V < 0) then
      Exit;
    IsOffset := True;
    Offset := V;
    Exit(True);
  end;
  P := Pos(':', S);
  if P > 0 then
  begin
    if not TryStrToInt64(Trim(Copy(S, 1, P - 1)), V) or (V < 1) then
      Exit;
    Line := V - 1;
    if not TryStrToInt64(Trim(Copy(S, P + 1, MaxInt)), V) or (V < 1) then
      Exit;
    Cell := V - 1;
    Exit(True);
  end;
  if not TryStrToInt64(S, V) or (V < 1) then
    Exit;
  Line := V - 1;
  Result := True;
end;

end.
