program t_lang;
{ TveLang: every built-in grammar loads. }
{$mode objfpc}{$H+}
uses SysUtils, TveHl, TveLang;
{$I testlib.inc}
var
  I: Integer;
  L: TTveLanguage;
  Err: AnsiString;
begin
  for I := 0 to TveLangCount - 1 do
  begin
    L := TveLangFromText(TveLangText(I), Err);
    Check(L <> nil, 'grammar ' + IntToStr(I) + ' loads: ' + Err);
    L.Free;
  end;
  Finish;
end.
