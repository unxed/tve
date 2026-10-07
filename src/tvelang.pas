{ TveLang: the built-in languages (the grammars are in langs/, TveHl tells the format) and the choice of the language for a file name.

  MIT. }
unit TveLang;

{$I tvdefs.inc}
{$H+}

interface

uses
  TveHl;

{$I tvelangdata.inc}

{ The grammar text of built-in language I (0..TveLangCount-1). }
function TveLangText(I: Integer): AnsiString;
{ A new language object for the file name (nil if no language has a mask for it); the caller frees it. }
function TveLangForFile(const FileName: AnsiString): TTveLanguage;
{ By name (case does not matter; a part of the name is enough: "smarty"). }
function TveLangByName(const Name: AnsiString): TTveLanguage;
{ A language from the text of a grammar; nil and Err when it is wrong. }
function TveLangFromText(const Text: AnsiString; out Err: AnsiString): TTveLanguage;

implementation

uses
  SysUtils;

function TveLangText(I: Integer): AnsiString;
begin
  if (I >= 0) and (I < TveLangCount) then
    Result := TveLangTexts[I]
  else
    Result := '';
end;

function TveLangFromText(const Text: AnsiString; out Err: AnsiString): TTveLanguage;
begin
  Result := TTveLanguage.Create;
  if not Result.Load(Text, Err) then
    FreeAndNil(Result);
end;

function Make(I: Integer): TTveLanguage;
var
  Err: AnsiString;
begin
  Result := TveLangFromText(TveLangText(I), Err);
end;

function TveLangForFile(const FileName: AnsiString): TTveLanguage;
var
  I: Integer;
begin
  for I := 0 to TveLangCount - 1 do
  begin
    Result := Make(I);
    if (Result <> nil) and Result.MatchesFile(FileName) then
      Exit;
    FreeAndNil(Result);
  end;
  Result := nil;
end;

function TveLangByName(const Name: AnsiString): TTveLanguage;
var
  I: Integer;
begin
  for I := 0 to TveLangCount - 1 do
  begin
    Result := Make(I);
    if (Result <> nil) and (Pos(LowerCase(Name), LowerCase(Result.Name)) = 1) then
      Exit;
    FreeAndNil(Result);
  end;
  Result := nil;
end;

end.
