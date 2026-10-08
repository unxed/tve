{ TveState: what is remembered of a file between sessions: the cursor, the first visible line, the selection, the bookmarks, the folds, the mode of insertion.

  MIT.

  The state of every file is a section of an INI file (TvIni) named by the full name of the file; the host decides where the INI file is. A selection, which is
  offsets, is restored only when the file has the same length as then. A saved section moves to the end of the INI file; when there are more than
  TveStateMaxFiles files, the ones saved longest ago are dropped. }
unit TveState;

{$I tvdefs.inc}
{$H+}

interface

uses
  TvIni, TveView;

const
  TveStateMaxFiles = 200;

procedure TveStateSave(Ini: TIniFile; const FileName: AnsiString; V: TTveView);
// False when there is nothing remembered about the file.
function TveStateLoad(Ini: TIniFile; const FileName: AnsiString; V: TTveView): Boolean;

implementation

uses
  SysUtils, TvPath, TveEditor, TveFold;

function SectionOf(const FileName: AnsiString): AnsiString;
begin
  Result := 'file:' + PathExpand(FileName);
end;

{ Removes the first file sections until at most Keep are left. }
procedure DropOldest(Ini: TIniFile; Keep: Integer);
var
  I, N: Integer;
begin
  N := 0;
  for I := 0 to Ini.SectionCount - 1 do
    if Copy(Ini.SectionAt(I).GetName, 1, 5) = 'file:' then
      Inc(N);
  I := 0;
  while (N > Keep) and (I < Ini.SectionCount) do
    if Copy(Ini.SectionAt(I).GetName, 1, 5) = 'file:' then
    begin
      Ini.DeleteSection(Ini.SectionAt(I).GetName);
      Dec(N);
    end
    else
      Inc(I);
end;

procedure TveStateSave(Ini: TIniFile; const FileName: AnsiString; V: TTveView);
var
  Sec: AnsiString;
  E: TTveEditor;
  I: Integer;
  A, B: Int64;
  Marks: AnsiString;
  Fl: AnsiString;
begin
  if FileName = '' then
    Exit;
  Sec := SectionOf(FileName);
  E := V.Editor;
  Ini.DeleteSection(Sec);
  DropOldest(Ini, TveStateMaxFiles - 1);
  Ini.SetEntry(Sec, 'line', IntToStr(E.Line));
  Ini.SetEntry(Sec, 'cell', IntToStr(E.Cell));
  Ini.SetEntry(Sec, 'top', IntToStr(V.Delta.Y));
  Ini.SetEntry(Sec, 'left', IntToStr(V.Delta.X));
  Ini.SetEntry(Sec, 'length', IntToStr(V.Doc.Buffer.Length));
  Ini.SetEntry(Sec, 'insert', IntToStr(Ord(E.Opt.InsertMode)));
  if E.HasSelection and E.SelectionRange(A, B) then
    Ini.SetEntry(Sec, 'selection', IntToStr(A) + ',' + IntToStr(B) + ',' + IntToStr(Ord(E.SelKind)))
  else
    Ini.DeleteEntry(Sec, 'selection');
  Marks := '';
  for I := 0 to 9 do
    if E.BookmarkLine(I) >= 0 then
    begin
      if Marks <> '' then
        Marks := Marks + ';';
      Marks := Marks + IntToStr(I) + ',' + IntToStr(E.BookmarkLine(I));
    end;
  if Marks <> '' then
    Ini.SetEntry(Sec, 'marks', Marks)
  else
    Ini.DeleteEntry(Sec, 'marks');
  Fl := V.Folds.SaveText;
  if Fl <> '' then
    Ini.SetEntry(Sec, 'folds', Fl)
  else
    Ini.DeleteEntry(Sec, 'folds');
end;

function TveStateLoad(Ini: TIniFile; const FileName: AnsiString; V: TTveView): Boolean;
var
  Sec, S: AnsiString;
  E: TTveEditor;
  L, Top: Int64;
  C, K, P, Q: Integer;
  Len, A, B, Kind: Int64;
  Item: AnsiString;
begin
  Result := False;
  if (FileName = '') or (Ini.SearchSection(SectionOf(FileName)) = nil) then
    Exit;
  Sec := SectionOf(FileName);
  E := V.Editor;
  Result := True;
  Len := Ini.GetIntEntry(Sec, 'length', -1);
  S := Ini.GetEntry(Sec, 'folds', '');
  if (S <> '') and (Len = V.Doc.Buffer.Length) then
    V.Folds.LoadText(S);
  S := Ini.GetEntry(Sec, 'marks', '');
  P := 1;
  while P <= Length(S) do
  begin
    Q := P;
    while (Q <= Length(S)) and (S[Q] <> ';') do
      Inc(Q);
    Item := Copy(S, P, Q - P);
    P := Q + 1;
    K := Pos(',', Item);
    if K > 0 then
    begin
      C := StrToIntDef(Copy(Item, 1, K - 1), -1);
      L := StrToInt64Def(Copy(Item, K + 1, MaxInt), -1);
      if (C >= 0) and (C <= 9) and (L >= 0) and (L < V.Doc.Buffer.LineCount) then
      begin
        E.GotoLineCell(L, 0);
        E.SetBookmark(C);
      end;
    end;
  end;
  L := Ini.GetIntEntry(Sec, 'line', 0);
  C := Ini.GetIntEntry(Sec, 'cell', 0);
  if L >= V.Doc.Buffer.LineCount then
    L := V.Doc.Buffer.LineCount - 1;
  if L < 0 then L := 0;
  E.GotoLineCell(L, C);
  S := Ini.GetEntry(Sec, 'selection', '');
  if (S <> '') and (Len = V.Doc.Buffer.Length) then
  begin
    K := Pos(',', S);
    if K > 0 then
    begin
      A := StrToInt64Def(Copy(S, 1, K - 1), -1);
      Item := Copy(S, K + 1, MaxInt);
      K := Pos(',', Item);
      if K > 0 then
      begin
        B := StrToInt64Def(Copy(Item, 1, K - 1), -1);
        Kind := StrToInt64Def(Copy(Item, K + 1, MaxInt), 1);
        if (A >= 0) and (B >= A) and (B <= V.Doc.Buffer.Length) then
        begin
          E.SetSelection(TTveSelKind(Kind), A);
          E.GotoOffset(B);
        end;
      end;
    end;
  end;
  E.Opt.InsertMode := Ini.GetIntEntry(Sec, 'insert', 1) <> 0;
  Top := Ini.GetIntEntry(Sec, 'top', 0);
  V.Refresh;
  V.ScrollTo(Ini.GetIntEntry(Sec, 'left', 0), Top);
end;

end.
