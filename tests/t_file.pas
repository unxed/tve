program t_file;
{ TveFile: reading and writing with encodings, line ends, BOM, backup, links, change detection. }
{$mode objfpc}{$H+}
uses SysUtils, {$IFDEF UNIX}BaseUnix,{$ENDIF} TvCharset, TveDoc, TveFile;
{$I testlib.inc}

var
  Dir: AnsiString;
  Opt: TTveFileOptions;
  Text, Err: AnsiString;
  Info: TTveFileInfo;
  Lost: Integer;
  D: TTveDoc;
  SR: TSearchRec;

procedure Put(const Name, Data: AnsiString);
var
  F: file;
begin
  AssignFile(F, Dir + Name);
  Rewrite(F, 1);
  if Length(Data) > 0 then
    BlockWrite(F, Data[1], Length(Data));
  CloseFile(F);
end;

function Get(const Name: AnsiString): AnsiString;
var
  F: file;
begin
  Result := '';
  if not FileExists(Dir + Name) then Exit;
  AssignFile(F, Dir + Name);
  Reset(F, 1);
  SetLength(Result, FileSize(F));
  if Length(Result) > 0 then
    BlockRead(F, Result[1], Length(Result));
  CloseFile(F);
end;

const
  Privet_utf8 = #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;
  Sent_utf8 = #$D0#$AD#$D1#$82#$D0#$BE#$20#$D0#$BF#$D1#$80#$D0#$B8#$D0#$BC#$D0#$B5#$D1#$80#$20#$D1#$80#$D1#$83#$D1#$81#$D1#$81#$D0#$BA#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D1#$82#$D0#$B5#$D0#$BA#$D1#$81#$D1#$82#$D0#$B0;

begin
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'tve_t_file_' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Dir);
  Opt := TveDefaultOptions;

  { UTF-8, LF }
  Put('a.txt', 'one'#10 + Privet_utf8 + #10'three');
  Check(TveReadFile(Dir + 'a.txt', Opt, Text, Info, Err), 'read a UTF-8 file');
  Check((Text = 'one'#10 + Privet_utf8 + #10'three') and (Info.Charset = csUtf8) and not Info.Bom and (Info.Eol = eolLF) and not Info.MixedEol, 'UTF-8, LF, no BOM');
  Check(Info.Known and (Info.DiskSize = Length(Text)), 'the disk info');
  Check(not TveReadFile(Dir + 'none.txt', Opt, Text, Info, Err) and (Err <> ''), 'a missing file: False and a message');

  { CRLF and the way back }
  Put('crlf.txt', 'a'#13#10'b'#13#10'c'#13#10);
  TveReadFile(Dir + 'crlf.txt', Opt, Text, Info, Err);
  Check((Text = 'a'#10'b'#10'c'#10) and (Info.Eol = eolCRLF) and not Info.MixedEol, 'CRLF is converted to LF and remembered');
  Check(TveWriteFile(Dir + 'crlf2.txt', Text, Info, Opt, Lost, Err) and (Get('crlf2.txt') = 'a'#13#10'b'#13#10'c'#13#10), 'and written back as it was');

  { CR (classic Mac) }
  Put('cr.txt', 'a'#13'b'#13'c');
  TveReadFile(Dir + 'cr.txt', Opt, Text, Info, Err);
  Check((Text = 'a'#10'b'#10'c') and (Info.Eol = eolCR), 'CR files');
  TveWriteFile(Dir + 'cr2.txt', Text, Info, Opt, Lost, Err);
  Check(Get('cr2.txt') = 'a'#13'b'#13'c', 'CR written back');

  { mixed: the majority wins and the file is marked }
  Put('mix.txt', 'a'#13#10'b'#13#10'c'#10'd');
  TveReadFile(Dir + 'mix.txt', Opt, Text, Info, Err);
  Check((Text = 'a'#10'b'#10'c'#10'd') and (Info.Eol = eolCRLF) and Info.MixedEol, 'mixed line ends: CRLF by majority, marked mixed');
  Put('lone.txt', 'a'#13'b'#10'c'#10);
  TveReadFile(Dir + 'lone.txt', Opt, Text, Info, Err);
  Check((Info.Eol = eolLF) and (Pos(#13, Text) > 0), 'a lone CR in an LF file stays a character');

  { BOMs }
  Put('bom8.txt', #$EF#$BB#$BF'bom'#10);
  TveReadFile(Dir + 'bom8.txt', Opt, Text, Info, Err);
  Check((Text = 'bom'#10) and Info.Bom and (Info.Charset = csUtf8), 'UTF-8 BOM is dropped and remembered');
  TveWriteFile(Dir + 'bom8b.txt', Text, Info, Opt, Lost, Err);
  Check(Get('bom8b.txt') = #$EF#$BB#$BF'bom'#10, 'and written back');
  Put('u16.txt', #$FF#$FE'h'#0'i'#0#10#0);
  TveReadFile(Dir + 'u16.txt', Opt, Text, Info, Err);
  Check((Text = 'hi'#10) and (Info.Charset = csUtf16LE) and Info.Bom, 'UTF-16LE with a BOM');
  TveWriteFile(Dir + 'u16b.txt', Text, Info, Opt, Lost, Err);
  Check(Get('u16b.txt') = #$FF#$FE'h'#0'i'#0#10#0, 'UTF-16LE written back');
  Put('u16be.txt', #$FE#$FF#0'h'#0'i');
  TveReadFile(Dir + 'u16be.txt', Opt, Text, Info, Err);
  Check((Text = 'hi') and (Info.Charset = csUtf16BE), 'UTF-16BE with a BOM');

  { legacy sets }
  Put('w1251.txt', CharsetFromUtf8(1251, Sent_utf8 + #10, Lost));
  Opt.Candidates[0] := csCp1252; Opt.Candidates[1] := csCp1251; Opt.Candidates[2] := csCp866;
  TveReadFile(Dir + 'w1251.txt', Opt, Text, Info, Err);
  Check((Info.Charset = 1251) and (Text = Sent_utf8 + #10), 'cp1251 is guessed and converted');
  TveWriteFile(Dir + 'w1251b.txt', Text, Info, Opt, Lost, Err);
  Check((Get('w1251b.txt') = Get('w1251.txt')) and (Lost = 0), 'cp1251 written back byte by byte');
  Put('d866.txt', CharsetFromUtf8(866, Sent_utf8, Lost));
  TveReadFile(Dir + 'd866.txt', Opt, Text, Info, Err);
  Check((Info.Charset = 866) and (Text = Sent_utf8), 'cp866 is guessed');
  Opt.Detect := False;
  Opt.DefaultCharset := 866;
  Put('d866b.txt', CharsetFromUtf8(866, Privet_utf8, Lost));
  TveReadFile(Dir + 'd866b.txt', Opt, Text, Info, Err);
  Check((Info.Charset = 866) and (Text = Privet_utf8), 'with Detect off the default set is used');
  Opt.Detect := True;

  { characters the set lacks }
  Info.Charset := csLatin1;
  Info.Bom := False;
  TveWriteFile(Dir + 'lost.txt', Privet_utf8 + 'x', Info, Opt, Lost, Err);
  Check((Lost = 6) and (Get('lost.txt') = '??????x'), 'characters that the set lacks: ? and the count');

  { trailing spaces }
  Put('trail.txt', 'a  '#10'b'#9#10'  '#10'c');
  Opt.StripTrailing := True;
  TveReadFile(Dir + 'trail.txt', Opt, Text, Info, Err);
  Check(Text = 'a'#10'b'#10#10'c', 'trailing spaces and tabs are stripped on request');
  Opt.StripTrailing := False;

  { a file without line ends takes the default of new files }
  Put('one.txt', 'single');
  Opt.DefaultEol := eolCRLF;
  TveReadFile(Dir + 'one.txt', Opt, Text, Info, Err);
  Check(Info.Eol = eolCRLF, 'no line end in the file: the default kind');
  Opt.DefaultEol := eolLF;

  { backup }
  Put('bk.txt', 'old');
  Opt.Backup := True;
  Info.Charset := csUtf8; Info.Bom := False; Info.Eol := eolLF;
  Check(TveWriteFile(Dir + 'bk.txt', 'new', Info, Opt, Lost, Err), 'write over an existing file with a backup');
  Check((Get('bk.txt') = 'new') and (Get('bk.bak') = 'old'), 'the new file and the backup');
  Put('bk.bak', 'older');
  TveWriteFile(Dir + 'bk.txt', 'newer', Info, Opt, Lost, Err);
  Check((Get('bk.txt') = 'newer') and (Get('bk.bak') = 'new'), 'the old backup is replaced');
  Opt.Backup := False;
  Check(not FileExists(Dir + 'bk.$ve'), 'no temporary file is left');

  { a link is followed }
{$IFDEF UNIX}
  Put('target.txt', 'target');
  fpSymlink(PChar('target.txt'), PChar(Dir + 'link.txt'));
  TveWriteFile(Dir + 'link.txt', 'via link', Info, Opt, Lost, Err);
  Check((Get('target.txt') = 'via link') and (fpReadLink(Dir + 'link.txt') = 'target.txt'), 'a link stays a link and the target is written');
  { the mode bits are kept }
  fpChmod(PChar(Dir + 'target.txt'), &751);
  TveWriteFile(Dir + 'target.txt', 'mode', Info, Opt, Lost, Err);
  Check(FileGetAttr(Dir + 'target.txt') >= 0, 'the file is there');
  Check(FpAccess(PChar(Dir + 'target.txt'), X_OK) = 0, 'the execute bit is kept');
  { a backslash is a character of a name on Unix: the link 'l\k.txt' is in Dir, and so is its relative target }
  Put('target2.txt', 'two');
  fpSymlink(PChar('target2.txt'), PChar(Dir + 'l\k.txt'));
  TveWriteFile(Dir + 'l\k.txt', 'via l\k', Info, Opt, Lost, Err);
  Check((Get('target2.txt') = 'via l\k') and (fpReadLink(Dir + 'l\k.txt') = 'target2.txt'), 'a link with a backslash in its name');
  DeleteFile(Dir + 'l\k.txt');
  DeleteFile(Dir + 'target2.txt');
{$ENDIF}

  { the backup of a name that starts with a dot keeps the whole name }
  Put('.cfg', 'old');
  Opt.Backup := True;
  TveWriteFile(Dir + '.cfg', 'new', Info, Opt, Lost, Err);
  Check((Get('.cfg') = 'new') and (Get('.cfg.bak') = 'old'), 'the backup of a dot name');
  Opt.Backup := False;
  DeleteFile(Dir + '.cfg');
  DeleteFile(Dir + '.cfg.bak');

  { change detection }
  Put('chg.txt', 'x');
  TveReadFile(Dir + 'chg.txt', Opt, Text, Info, Err);
  Check(not TveDiskChanged(Dir + 'chg.txt', Info), 'unchanged on the disk');
  Put('chg.txt', 'xyz');
  Check(TveDiskChanged(Dir + 'chg.txt', Info), 'a changed size is a change');
  DeleteFile(Dir + 'chg.txt');
  Check(TveDiskChanged(Dir + 'chg.txt', Info), 'a file that is gone is a change');

  { documents }
  D := TTveDoc.Create;
  Check(TveLoadDoc(D, Dir + 'crlf.txt', Opt, Err) and (D.Buffer.AsString = 'a'#10'b'#10'c'#10) and (D.Eol = eolCRLF) and not D.Modified and (D.FileName = Dir + 'crlf.txt'), 'TveLoadDoc');
  D.Insert(0, 'Z');
  Check(D.Modified, 'edited');
  Check(TveSaveDoc(D, Dir + 'crlf3.txt', Opt, Lost, Err) and (Get('crlf3.txt') = 'Za'#13#10'b'#13#10'c'#13#10) and not D.Modified, 'TveSaveDoc: the kind of line ends and the saved mark');
  D.Eol := eolLF;
  TveSaveDoc(D, Dir + 'crlf4.txt', Opt, Lost, Err);
  Check(Get('crlf4.txt') = 'Za'#10'b'#10'c'#10, 'switching the line ends of a document');
  D.Free;

  { clean up the files of the test }
  if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
        DeleteFile(Dir + SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  RemoveDir(Dir);
  Finish;
end.
