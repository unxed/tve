{ TveLang: the built-in language descriptions (the format is in TveHl) and the choice of the language for a file name.

  MIT. }
unit TveLang;

{$I tvdefs.inc}

interface

uses
  TveHl;

const
  TveLangCount = 5;

{ The description text of built-in language I (0..TveLangCount-1). }
function TveLangText(I: Integer): AnsiString;
{ A new language object for the file name (nil if no language has a mask for it); the caller frees it. }
function TveLangForFile(const FileName: AnsiString): TTveLanguage;
function TveLangByName(const Name: AnsiString): TTveLanguage;

implementation

uses
  SysUtils;

const
  LF = #10;

function TveLangText(I: Integer): AnsiString;
begin
  case I of
    0: Result :=
      '[language]' + LF + 'name=Pascal' + LF + 'masks=*.pas *.pp *.inc *.lpr *.dpr' + LF +
      '[syntax]' + LF + 'case=insensitive' + LF + 'line_comments=//' + LF + 'block_comments=(* *)' + LF + 'directive_blocks={$ }' + LF +
      'strings=''' + LF + 'doubled_quote_escape=1' + LF + 'numbers=pascal' + LF + 'hash_chars=1' + LF + 'operators=+-*/<>=:^@.,;' + LF +
      '[keywords]' + LF +
      'class1=and array as asm begin case class const constructor destructor div do downto else end except exports file finally for function goto if implementation in inherited initialization inline interface is label library mod nil not object of on or out packed procedure program property raise record repeat set shl shr string then threadvar to try type unit until uses var while with xor private protected public published strict override virtual abstract overload reintroduce static cdecl stdcall' + LF +
      'class2=boolean byte char integer longint longword int64 qword pointer real double single extended shortint smallint word widechar ansistring unicodestring pchar string comp currency cardinal' + LF +
      'class3=writeln write readln read new dispose inc dec length setlength copy pos ord chr sizeof high low true false assigned exit break continue halt' + LF;
    1: Result :=
      '[language]' + LF + 'name=Go' + LF + 'masks=*.go go.mod' + LF +
      '[syntax]' + LF + 'case=sensitive' + LF + 'line_comments=//' + LF + 'block_comments=/* */' + LF + 'strings="''' + LF + 'raw_strings=`' + LF + 'escape=\' + LF +
      'numbers=c' + LF + 'operators=+-*/<>=!&|^%:.,;' + LF +
      '[keywords]' + LF +
      'class1=break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var' + LF +
      'class2=bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any comparable' + LF +
      'class3=append cap clear close copy delete imag len make max min new panic print println real recover true false nil iota' + LF;
    2: Result :=
      '[language]' + LF + 'name=C' + LF + 'masks=*.c *.h *.cpp *.hpp *.cc *.cxx' + LF +
      '[syntax]' + LF + 'case=sensitive' + LF + 'line_comments=//' + LF + 'block_comments=/* */' + LF + 'strings="''' + LF + 'escape=\' + LF +
      'numbers=c' + LF + 'preprocessor=#' + LF + 'operators=+-*/<>=!&|^~%?:.,;' + LF +
      '[keywords]' + LF +
      'class1=auto break case const continue default do else enum extern for goto if inline register return sizeof static struct switch typedef union volatile while class namespace new delete template this throw try catch public private protected virtual' + LF +
      'class2=char double float int long short signed unsigned void bool size_t' + LF +
      'class3=NULL true false nullptr' + LF;
    3: Result :=
      '[language]' + LF + 'name=Shell' + LF + 'masks=*.sh *.bash' + LF +
      '[syntax]' + LF + 'case=sensitive' + LF + 'line_comments=#' + LF + 'strings="''' + LF + 'escape=\' + LF + 'numbers=c' + LF + 'identifier_chars=_' + LF + 'operators=|&;<>=' + LF +
      '[keywords]' + LF +
      'class1=if then else elif fi for while until do done case esac in function select time' + LF +
      'class3=echo cd exit export local read return set shift test unset eval exec source' + LF;
    4: Result :=
      '[language]' + LF + 'name=Python' + LF + 'masks=*.py' + LF +
      '[syntax]' + LF + 'case=sensitive' + LF + 'line_comments=#' + LF + 'strings="''' + LF + 'escape=\' + LF + 'numbers=c' + LF + 'operators=+-*/<>=!&|^~%:.,;' + LF +
      '[keywords]' + LF +
      'class1=and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield' + LF +
      'class2=int str float bool list dict set tuple bytes object' + LF +
      'class3=print len range True False None self' + LF;
  else
    Result := '';
  end;
end;

function Make(I: Integer): TTveLanguage;
var
  Err: AnsiString;
begin
  Result := TTveLanguage.Create;
  if not Result.Load(TveLangText(I), Err) then
    FreeAndNil(Result);
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
    if (Result <> nil) and (LowerCase(Result.Name) = LowerCase(Name)) then
      Exit;
    FreeAndNil(Result);
  end;
  Result := nil;
end;

end.
