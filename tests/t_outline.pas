program t_outline;
{ TveOutline: the symbols of a text by the rules of the grammars. }
{$mode objfpc}{$H+}
uses SysUtils, TveDoc, TveHl, TveLang, TveSymbols;
{$I testlib.inc}

function Run(const Lang, Text: AnsiString): AnsiString;
var
  D: TTveDoc;
  L: TTveLanguage;
  O: TTveOutline;
  I: Integer;
begin
  Result := '';
  L := TveLangByName(Lang);
  if L = nil then
    Exit('NO LANGUAGE ' + Lang);
  D := TTveDoc.Create;
  D.LoadText(Text);
  O := TveOutline(D, L);
  for I := 0 to High(O) do
    Result := Result + IntToStr(O[I].Line) + ':' + IntToStr(O[I].Level) + ':' + O[I].Title + ' ';
  D.Free;
  L.Free;
end;

var
  O: TTveOutline;
  Err_: AnsiString;
  T: AnsiString;
  D: TTveDoc;
  L: TTveLanguage;
begin
  Check(Run('Pascal',
    'unit U;'#10'interface'#10'type'#10'  TFoo = class(TObject)'#10'    procedure Bar;'#10'  end;'#10'  TRec = record'#10'    A: Integer;'#10'  end;'#10 +
    '  TRef = class of TFoo;'#10'  TFwd = class;'#10'implementation'#10'procedure TFoo.Bar;'#10'begin'#10'end;'#10'{ procedure Hidden; }'#10 +
    'function Plain(X: Integer): Integer;'#10'begin end;'#10'end.'#10) =
    '3:1:TFoo 6:1:TRec 12:2:TFoo.Bar 16:2:Plain ', 'Pascal: ' + Run('Pascal', 'x'));
  Check(Run('Markdown', '# Title'#10'text'#10'## Part one ##'#10'```sh'#10'# not a heading'#10'```'#10'### Deep'#10'#nospace'#10) =
    '0:1:Title 2:2:Part one 6:3:Deep ', 'Markdown: ' + Run('Markdown', '# Title'#10'text'#10'## Part one ##'#10'```sh'#10'# not a heading'#10'```'#10'### Deep'#10));
  Check(Run('Python', 'import os'#10'class A:'#10'    def f(self):'#10'        pass'#10'    class B: pass'#10'def g():'#10'    return 1'#10'async def h(): pass'#10) =
    '1:1:A 2:2:f 4:2:B 5:1:g 7:1:h ', 'Python: ' + Run('Python', 'class A:'#10'    def f(self):'#10));
  Check(Run('Go', 'package m'#10'type S struct {'#10'}'#10'func (s *S) Do(x int) {'#10'}'#10'func Main() {'#10'}'#10) =
    '1:1:S 3:2:Do 5:2:Main ', 'Go');
  Check(Run('C/C++', '#include <x.h>'#10'struct P {'#10'  int a;'#10'};'#10'static int add(int a, int b)'#10'{'#10'  return a;'#10'}'#10'void P::run() {'#10'}'#10'struct Q;'#10'int x;'#10) =
    '1:1:P 4:1:add 8:1:P::run ', 'C: ' + Run('C/C++', 'struct P {'#10'static int add(int a, int b)'#10));
  Check(Run('JavaScript', 'export class K {'#10'}'#10'function f() {}'#10'const g = (a) => a;'#10'const n = 5;'#10'// function nope() {}'#10'async function* h() {}'#10) =
    '0:1:K 2:1:f 3:1:g 6:1:h ', 'JS: ' + Run('JavaScript', 'export class K {'#10'}'#10'function f() {}'#10'const g = (a) => a;'#10));
  Check(Run('Shell', 'f() {'#10'  echo'#10'}'#10'function g {'#10'}'#10'# h() {}'#10'echo "x"'#10) = '0:1:f 3:1:g ', 'Shell: ' + Run('Shell', 'f() {'#10'function g {'#10'# h() {}'#10));
  Check(Run('HTML', '<html>'#10'<h1 class="a">Head</h1>'#10'<h2>Sub</h2>'#10'<!--'#10'<h2>Old</h2>'#10'-->'#10) = '1:1:Head 2:2:Sub ', 'HTML: ' + Run('HTML', '<h1 class="a">Head</h1>'#10'<h2>Sub</h2>'#10'<!--'#10'<h2>Old</h2>'#10'-->'#10));
  Check(Run('PHP', '<?php'#10'class A {'#10'  public static function f() {}'#10'}'#10'function g() {}'#10) = '1:1:A 2:2:f 4:2:g ', 'PHP: ' + Run('PHP', '<?php'#10'class A {'#10'  public static function f() {}'#10'}'#10'function g() {}'#10));
  Check(Run('SQL', 'create table if not exists t (a int);'#10'CREATE OR REPLACE VIEW v AS select 1;'#10'select 1;'#10) = '0:1:t 1:1:v ', 'SQL: ' + Run('SQL', 'create table if not exists t (a int);'#10));
  Check(Run('YAML', '# c'#10'a: 1'#10'b:'#10'  c: 2'#10'    d: 3'#10'  - e: 1'#10) = '1:1:a 2:1:b 3:2:c ', 'YAML');
  Check(Run('INI', '; c'#10'[core]'#10'a = 1'#10'[[x.y]]'#10) = '1:1:core 3:1:x.y ', 'INI');
  Check(Run('Makefile', '# c'#10'CC := gcc'#10'all: x'#10#9'echo'#10'.PHONY: all'#10'clean:'#10) = '2:1:all 5:1:clean ', 'Makefile');
  Check(Run('Diff', 'diff --git a/x.c b/x.c'#10'+a'#10'diff --git a/q b/q'#10) = '0:1:x.c 2:1:q ', 'Diff');
  { nesting by indentation, by braces; the routines of a Pascal unit from its implementation part only }
  T := 'class A:'#10'    class B:'#10'        def f(self):'#10'            pass'#10'        """'#10'x"""'#10 +
    '    def g(self): pass'#10'if x:'#10'    def h(): pass'#10'def k():'#10'    # c'#10'    def inner(): pass'#10;
  Check(Run('Python', T) = '0:1:A 1:2:B 2:3:f 6:2:g 8:1:h 9:1:k 11:2:inner ', 'Python nesting: ' + Run('Python', T));
  T := 'namespace N'#10'{'#10'class C {'#10'  int a; // }'#10'};'#10'int f(int x)'#10'{'#10'  return x;'#10'}'#10'}'#10'int g(void) {'#10'}'#10;
  Check(Run('C/C++', T) = '0:1:N 2:2:C 5:2:f 10:1:g ', 'C nesting: ' + Run('C/C++', T));
  T := 'function outer() {'#10'  const s = "{";'#10'  function inner() {'#10'  }'#10'}'#10'function next() {}'#10;
  Check(Run('JavaScript', T) = '0:1:outer 2:2:inner 5:1:next ', 'JS nesting: ' + Run('JavaScript', T));
  T := 'unit U;'#10'interface'#10'procedure Free1;'#10'function Two: Integer;'#10'implementation'#10'procedure Free1;'#10'begin end;'#10 +
    'function Two: Integer;'#10'begin end;'#10'end.'#10;
  Check(Run('Pascal', T) = '5:2:Free1 7:2:Two ', 'Pascal: a routine once: ' + Run('Pascal', T));
  Check(Run('Pascal', 'program P;'#10'procedure A;'#10'begin end;'#10'begin end.'#10) = '1:2:A ', 'Pascal program: no implementation part');
  Check(Run('JSON', '{"a": 1}') = '', 'a language without rules has an empty outline');
  { the empty cases and the lookup }
  Check(Length(TveOutline(nil, nil)) = 0, 'nil');
  L := TveLangByName('Python');
  D := TTveDoc.Create;
  D.LoadText('def a(): pass'#10#10'x = 1'#10'def b(): pass'#10);
  O := TveOutline(D, L);
  Check((TveOutlineAt(O, 0) = 0) and (TveOutlineAt(O, 2) = 0) and (TveOutlineAt(O, 3) = 1), 'outline at a line');
  Check(TveOutlineLabel(O[0]) = 'a', 'label');
  O[0].Level := 3;
  Check(TveOutlineLabel(O[0]) = '    a', 'label is indented by the level');
  D.LoadText('x = 1'#10);
  Check(TveOutlineAt(TveOutline(D, L), 0) = -1, 'before the first entry');
  D.Free;
  L.Free;
  { the grammar of a user: a symbol rule that is wrong is reported }
  L := TTveLanguage.Create;
  Check(not L.Load('language X'#10'symbol 0 /a/'#10, Err_), 'level 0');
  Check(not L.Load('language X'#10'symbol 1 /(a/'#10, Err_), 'bad regex: ' + Err_);
  Check(not L.Load('language X'#10'outline sideways'#10, Err_), 'bad outline: ' + Err_);
  Check(not L.Load('language X'#10'outline from 0 /a/'#10, Err_), 'outline from level 0');
  Check(L.Load('language X'#10'outline braces'#10'outline from 2 /^impl/'#10'start m'#10'context m'#10, Err_) and (L.OutlineNest = 2) and
    (L.OutlineFromLevel = 2) and (L.OutlineFrom <> nil), 'outline directives: ' + Err_);
  Check(L.Load('language X'#10'symbol 2 /^(\w+):/'#10'start m'#10'context m'#10'  match /x/ => keyword'#10, Err_) and (L.SymbolCount = 1) and (L.SymbolLevel(0) = 2), 'good rule: ' + Err_);
  L.Free;
  Finish;
end.
