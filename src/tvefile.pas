{ TveFile: reading and writing the files of the editor.

  MIT.

  Reading: the bytes of the file become UTF-8 text with LF as the only line end (that is what TveDoc holds); what was converted is remembered in the info of the
  document, so that writing gives the file back as it was (or as the user changed it).
    The character set: a byte order mark decides (UTF-8, UTF-16 LE and BE); else a file that is valid UTF-8 is UTF-8; else it is a single-byte text of one of the
    candidate sets (the one that reads it as the most likely text, see TvCharset), or of the default set when Detect is off.
    The line ends: CR LF, LF and CR are counted; the kind that is more than half is the kind of the file; a file with more than one kind is marked as mixed
    and gets the majority kind when written.
  Writing is done through a temporary file and a rename, so a crash does not leave half of a file; the old file may be kept as a backup (name.bak); a link is
  followed (the target is written, the link stays); the mode bits are kept on Unix. A text that the character set cannot hold is written with '?' and the
  number of such characters is returned, so that the caller can ask the user before it. The names go through TvDosNames, so that a DOS with UTF-8 names works. }
unit TveFile;

{$I tvdefs.inc}

interface

uses
  TveDoc;

type
  TTveFileOptions = record
    Detect: Boolean;                { guess the single-byte set among Candidates }
    DefaultCharset: LongInt;        { the set of a single-byte file when Detect is off, and the set of a new file }
    Candidates: array of LongInt;
    DefaultEol: TTveEol;            { the line ends of a new file }
    StripTrailing: Boolean;         { remove the spaces at the ends of lines when reading }
    Backup: Boolean;
    BackupExt: AnsiString;          { '.bak' by default }
  end;

function TveDefaultOptions: TTveFileOptions;

{ Reads the file. False (and Err) if it cannot be read. Text is UTF-8 with LF. }
function TveReadFile(const Name: AnsiString; const Opt: TTveFileOptions; out Text: AnsiString; out Info: TTveFileInfo; out Err: AnsiString): Boolean;
{ Writes the text (UTF-8 with LF) as the info says. Lost = the characters that the set lacks. }
function TveWriteFile(const Name: AnsiString; const Text: AnsiString; var Info: TTveFileInfo; const Opt: TTveFileOptions; out Lost: Integer; out Err: AnsiString): Boolean;

{ The document from a file / the file from a document (the info of the document is kept up to date, the document is marked as saved). }
function TveLoadDoc(Doc: TTveDoc; const Name: AnsiString; const Opt: TTveFileOptions; out Err: AnsiString): Boolean;
function TveSaveDoc(Doc: TTveDoc; const Name: AnsiString; const Opt: TTveFileOptions; out Lost: Integer; out Err: AnsiString): Boolean;

{ Did the file change on the disk since it was read or written (the size or the time; a file that is gone counts as changed)? }
function TveDiskChanged(const Name: AnsiString; const Info: TTveFileInfo): Boolean;

{ The line ends of a text (LF) as another kind, and back. }
function TveEolToText(const Text: AnsiString; Eol: TTveEol): AnsiString;

implementation

uses
  SysUtils,
{$IFDEF UNIX}
  BaseUnix,
{$ENDIF}
  TvCharset, TvDosNames;

function TveDefaultOptions: TTveFileOptions;
begin
  Result.Detect := True;
  Result.DefaultCharset := csCp1252;
  SetLength(Result.Candidates, 3);
  Result.Candidates[0] := csCp1252;
  Result.Candidates[1] := csCp1251;
  Result.Candidates[2] := csCp866;
  Result.DefaultEol := {$IFDEF UNIX}eolLF{$ELSE}eolCRLF{$ENDIF};
  Result.StripTrailing := False;
  Result.Backup := False;
  Result.BackupExt := '.bak';
end;

function OsName(const Name: AnsiString): AnsiString;
begin
  Result := NameToDos(Name);
end;

{$IFDEF UNIX}
{ Follows links, so that the target is written and the link stays. }
function ResolveLink(const Name: AnsiString): AnsiString;
var
  Cur, Target: AnsiString;
  N: Integer;
  St: Stat;
begin
  Cur := Name;
  for N := 1 to 16 do
  begin
    if (fpLStat(PChar(Cur), St) <> 0) or not fpS_ISLNK(St.st_mode) then
      Exit(Cur);
    Target := fpReadLink(Cur);
    if Target = '' then
      Exit(Cur);
    if Target[1] <> '/' then
      Target := ExtractFilePath(Cur) + Target;
    Cur := Target;
  end;
  Result := Cur;
end;
{$ENDIF}

function ReadAll(const Name: AnsiString; out Data: AnsiString; out Size: Int64; out Age: LongInt; out Err: AnsiString): Boolean;
var
  H: THandle;
  Got, Total, Want: LongInt;
begin
  Result := False;
  Data := '';
  Size := 0;
  Age := 0;
  H := FileOpen(OsName(Name), fmOpenRead or fmShareDenyNone);
  if H = THandle(-1) then
  begin
    Err := 'cannot open ' + Name;
    Exit;
  end;
  try
    Size := FileSeek(H, 0, 2);
    FileSeek(H, 0, 0);
    SetLength(Data, Size);
    Total := 0;
    while Total < Size do
    begin
      Want := Size - Total;
      if Want > 1 shl 20 then
        Want := 1 shl 20;
      Got := FileRead(H, Data[Total + 1], Want);
      if Got <= 0 then
        Break;
      Inc(Total, Got);
    end;
    if Total < Size then
    begin
      Err := 'cannot read ' + Name;
      Exit;
    end;
    Age := FileGetDate(H);
  finally
    FileClose(H);
  end;
  Result := True;
end;

{ Counts the line ends and makes the text LF-only }
procedure NormalizeEol(var S: AnsiString; out Eol: TTveEol; out Mixed: Boolean);
var
  I, J, N, CRLF, LF, CR: Integer;
  R: AnsiString;
begin
  CRLF := 0; LF := 0; CR := 0;
  N := Length(S);
  I := 1;
  while I <= N do
  begin
    case S[I] of
      #13:
        if (I < N) and (S[I + 1] = #10) then
        begin
          Inc(CRLF);
          Inc(I);
        end
        else
          Inc(CR);
      #10: Inc(LF);
    end;
    Inc(I);
  end;
  Eol := eolLF;
  if (CRLF >= LF) and (CRLF >= CR) and (CRLF > 0) then
    Eol := eolCRLF
  else if (CR > LF) and (CR > CRLF) then
    Eol := eolCR;
  Mixed := (Ord(CRLF > 0) + Ord(LF > 0) + Ord(CR > 0)) > 1;
  if (CRLF = 0) and ((CR = 0) or (Eol <> eolCR)) then
    Exit;                                   { nothing to change }
  SetLength(R, N);
  J := 0;
  I := 1;
  while I <= N do
  begin
    if (S[I] = #13) and (I < N) and (S[I + 1] = #10) then
      Inc(I)                                { the CR of CR LF is dropped, the LF stays }
    else if (S[I] = #13) and (Eol = eolCR) then
    begin
      Inc(J);
      R[J] := #10;
      Inc(I);
      Continue;
    end;
    Inc(J);
    R[J] := S[I];
    Inc(I);
  end;
  SetLength(R, J);
  S := R;
end;

procedure StripTrailingSpaces(var S: AnsiString);
var
  I, J, N, LineStart, E: Integer;
  R: AnsiString;
begin
  N := Length(S);
  SetLength(R, N);
  J := 0;
  LineStart := 1;
  I := 1;
  while I <= N + 1 do
  begin
    if (I = N + 1) or (S[I] = #10) then
    begin
      E := I - 1;
      while (E >= LineStart) and ((S[E] = ' ') or (S[E] = #9)) do
        Dec(E);
      if E >= LineStart then
      begin
        Move(S[LineStart], R[J + 1], E - LineStart + 1);
        Inc(J, E - LineStart + 1);
      end;
      if I <= N then
      begin
        Inc(J);
        R[J] := #10;
      end;
      LineStart := I + 1;
    end;
    Inc(I);
  end;
  SetLength(R, J);
  S := R;
end;

function TveReadFile(const Name: AnsiString; const Opt: TTveFileOptions; out Text: AnsiString; out Info: TTveFileInfo; out Err: AnsiString): Boolean;
var
  Raw: AnsiString;
begin
  Err := '';
  Text := '';
  FillChar(Info, SizeOf(Info), 0);
  Info.Charset := csUtf8;
  Info.Eol := Opt.DefaultEol;
  Result := ReadAll(Name, Raw, Info.DiskSize, Info.DiskAge, Err);
  if not Result then
    Exit;
  Info.Known := True;
  if (Length(Raw) >= 3) and (Byte(Raw[1]) = $EF) and (Byte(Raw[2]) = $BB) and (Byte(Raw[3]) = $BF) then
  begin
    Info.Bom := True;
    Info.Charset := csUtf8;
    Delete(Raw, 1, 3);
    Text := Raw;
  end
  else if (Length(Raw) >= 2) and (Byte(Raw[1]) = $FF) and (Byte(Raw[2]) = $FE) then
  begin
    Info.Bom := True;
    Info.Charset := csUtf16LE;
    Text := CharsetToUtf8(csUtf16LE, Copy(Raw, 3, MaxInt));
  end
  else if (Length(Raw) >= 2) and (Byte(Raw[1]) = $FE) and (Byte(Raw[2]) = $FF) then
  begin
    Info.Bom := True;
    Info.Charset := csUtf16BE;
    Text := CharsetToUtf8(csUtf16BE, Copy(Raw, 3, MaxInt));
  end
  else if Utf8Valid(Raw) then
  begin
    Info.Charset := csUtf8;
    Text := Raw;
  end
  else
  begin
    if Opt.Detect and (Length(Opt.Candidates) > 0) then
      Info.Charset := CharsetGuess(Raw, Opt.Candidates)
    else
      Info.Charset := Opt.DefaultCharset;
    Text := CharsetToUtf8(Info.Charset, Raw);
  end;
  NormalizeEol(Text, Info.Eol, Info.MixedEol);
  if (Pos(#10, Text) = 0) and (Pos(#13, Raw) = 0) then
    Info.Eol := Opt.DefaultEol;               { a file without line ends: the default of new files }
  if Opt.StripTrailing then
    StripTrailingSpaces(Text);
end;

function TveEolToText(const Text: AnsiString; Eol: TTveEol): AnsiString;
var
  I, J, N, Cnt: Integer;
begin
  if Eol = eolLF then
    Exit(Text);
  Cnt := 0;
  for I := 1 to Length(Text) do
    if Text[I] = #10 then
      Inc(Cnt);
  if Cnt = 0 then
    Exit(Text);
  if Eol = eolCR then
  begin
    Result := Text;
    for I := 1 to Length(Result) do
      if Result[I] = #10 then
        Result[I] := #13;
    Exit;
  end;
  N := Length(Text);
  SetLength(Result, N + Cnt);
  J := 0;
  for I := 1 to N do
  begin
    if Text[I] = #10 then
    begin
      Inc(J);
      Result[J] := #13;
    end;
    Inc(J);
    Result[J] := Text[I];
  end;
end;

function WriteAll(const Name: AnsiString; const Data: AnsiString): Boolean;
var
  H: THandle;
  Total, Put: LongInt;
begin
  Result := False;
  H := FileCreate(OsName(Name));
  if H = THandle(-1) then
    Exit;
  try
    Total := 0;
    while Total < Length(Data) do
    begin
      Put := Length(Data) - Total;
      if Put > 1 shl 20 then
        Put := 1 shl 20;
      Put := FileWrite(H, Data[Total + 1], Put);
      if Put <= 0 then
        Exit;
      Inc(Total, Put);
    end;
    Result := True;
  finally
    FileClose(H);
  end;
end;

function TveWriteFile(const Name: AnsiString; const Text: AnsiString; var Info: TTveFileInfo; const Opt: TTveFileOptions; out Lost: Integer; out Err: AnsiString): Boolean;
var
  Data, Real, Tmp, Bak: AnsiString;
  HadFile: Boolean;
  H: THandle;
{$IFDEF UNIX}
  St: Stat;
  HaveMode: Boolean;
{$ENDIF}
begin
  Result := False;
  Err := '';
  Lost := 0;
  Data := CharsetFromUtf8(Info.Charset, TveEolToText(Text, Info.Eol), Lost);
  if Info.Bom then
    case Info.Charset of
      csUtf8: Data := Chr($EF) + Chr($BB) + Chr($BF) + Data;
      csUtf16LE: Data := Chr($FF) + Chr($FE) + Data;
      csUtf16BE: Data := Chr($FE) + Chr($FF) + Data;
    end;
  Real := Name;
{$IFDEF UNIX}
  Real := ResolveLink(Name);
  HaveMode := fpStat(PChar(Real), St) = 0;
{$ENDIF}
  Tmp := ChangeFileExt(Real, '.$ve');
  if not WriteAll(Tmp, Data) then
  begin
    Err := 'cannot write ' + Tmp;
    DeleteFile(OsName(Tmp));
    Exit;
  end;
{$IFDEF UNIX}
  if HaveMode then
    fpChmod(PChar(Tmp), St.st_mode and &7777);
{$ENDIF}
  HadFile := FileExists(OsName(Real));
  Bak := '';
  if HadFile and Opt.Backup then
  begin
    Bak := ChangeFileExt(Real, Opt.BackupExt);
    if FileExists(OsName(Bak)) then
      DeleteFile(OsName(Bak));
    if not RenameFile(OsName(Real), OsName(Bak)) then
      Bak := '';
  end
  else if HadFile then
    DeleteFile(OsName(Real));
  if not RenameFile(OsName(Tmp), OsName(Real)) then
  begin
    Err := 'cannot replace ' + Name;
    if Bak <> '' then
      RenameFile(OsName(Bak), OsName(Real));      { the old file is back }
    DeleteFile(OsName(Tmp));
    Exit;
  end;
  H := FileOpen(OsName(Real), fmOpenRead or fmShareDenyNone);
  if H <> THandle(-1) then
  begin
    Info.DiskSize := FileSeek(H, 0, 2);
    Info.DiskAge := FileGetDate(H);
    Info.Known := True;
    FileClose(H);
  end;
  Result := True;
end;

function TveLoadDoc(Doc: TTveDoc; const Name: AnsiString; const Opt: TTveFileOptions; out Err: AnsiString): Boolean;
var
  Text: AnsiString;
  Info: TTveFileInfo;
begin
  Result := TveReadFile(Name, Opt, Text, Info, Err);
  if not Result then
    Exit;
  Doc.LoadText(Text);
  Doc.FileName := Name;
  Doc.Info := Info;
  Doc.Eol := Info.Eol;
end;

function TveSaveDoc(Doc: TTveDoc; const Name: AnsiString; const Opt: TTveFileOptions; out Lost: Integer; out Err: AnsiString): Boolean;
var
  Info: TTveFileInfo;
begin
  Info := Doc.Info;
  Info.Eol := Doc.Eol;
  Result := TveWriteFile(Name, Doc.Buffer.AsString, Info, Opt, Lost, Err);
  if not Result then
    Exit;
  Doc.Info := Info;
  Doc.FileName := Name;
  Doc.MarkSaved;
end;

function TveDiskChanged(const Name: AnsiString; const Info: TTveFileInfo): Boolean;
var
  H: THandle;
  Size: Int64;
  Age: LongInt;
begin
  if not Info.Known then
    Exit(False);
  H := FileOpen(OsName(Name), fmOpenRead or fmShareDenyNone);
  if H = THandle(-1) then
    Exit(True);
  Size := FileSeek(H, 0, 2);
  Age := FileGetDate(H);
  FileClose(H);
  Result := (Size <> Info.DiskSize) or (Age <> Info.DiskAge);
end;

end.
