program t_hl;
{ TveHl, TveLang: classes of the bytes, states across lines, cache after edits. }
{$mode objfpc}{$H+}
uses SysUtils, TveBuf, TveDoc, TveHl, TveLang;
{$I testlib.inc}

var
  D: TTveDoc;
  L: TTveLanguage;
  H: TTveHighlighter;

function Cl(Line: Int64): AnsiString;
var
  C: TByteClasses;
  I: Integer;
begin
  H.ClassifyLine(Line, C);
  Result := '';
  for I := 0 to High(C) do
    Result := Result + Chr(Ord('0') + C[I]);
end;

begin
  D := TTveDoc.Create;
  L := TveLangByName('pascal');
  Check(L <> nil, 'pascal exists');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('begin x := 12; // hi' + #10 + '(* a' + #10 + 'b *) s := ''it''''s'';' + #10 + '{$IFDEF X}');
  Check(Cl(0) = '44444000880338011111', 'line0 ' + Cl(0));
  Check(Cl(1) = '111' + '1', 'block start ' + Cl(1));
  Check(Cl(2)[1] = '1', 'block continues ' + Cl(2));
  Check(Cl(2)[6] = '0', 'block ended ' + Cl(2));
  Check(Cl(2)[11] = '2', 'string with doubled quote ' + Cl(2));
  Check(Cl(3)[1] = '7', 'directive ' + Cl(3));
  D.Replace(D.Buffer.LineStart(1), 2, 'xx');
  Check(Cl(2)[1] = '0', 'comment removed, state recomputed ' + Cl(2));
  L.Free;
  H.Free;
  L := TveLangForFile('main.go');
  Check((L <> nil) and (L.Name = 'Go'), 'go by mask');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('x := `a' + #10 + 'b` + "q\n" // c');
  Check(Cl(0)[6] = '2', 'raw string open ' + Cl(0));
  Check(Cl(1)[1] = '2', 'raw string goes on ' + Cl(1));
  Check(Cl(1)[6] = '2', 'string ' + Cl(1));
  Check(Cl(1)[8] = '9', 'escape ' + Cl(1));
  Check(Cl(1)[12] = '1', 'comment ' + Cl(1));
  H.Free;
  L.Free;
  Check(TveLangForFile('a.unknown') = nil, 'no language');
  D.Free;
  Finish;
end.
