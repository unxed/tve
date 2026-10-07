program t_regex;
{ TveRegex: the syntax, the groups, the repeats, the classes, the flags, UTF-8, the limit. }
{$mode objfpc}{$H+}
uses SysUtils, TvUtf8, TveRegex;
{$I testlib.inc}

var
  Last: AnsiString;

{ finds Pat in Subj; returns the matched text ('' + Last='nomatch' when there is none) }
function M(const Pat, Subj: AnsiString; IgnoreCase: Boolean = False): AnsiString;
var
  R: TTveRegex;
  C: TCaps;
begin
  R := TTveRegex.Create(Pat, IgnoreCase);
  try
    if R.Error <> '' then
    begin
      Last := 'error: ' + R.Error;
      Exit('');
    end;
    if R.Exec(Subj, 1, C) then
    begin
      Last := 'match';
      Result := Copy(Subj, C[0], C[1] - C[0]);
    end
    else
    begin
      Last := 'nomatch';
      Result := '';
    end;
  finally
    R.Free;
  end;
end;

function G(const Pat, Subj: AnsiString; N: Integer): AnsiString;
var
  R: TTveRegex;
  C: TCaps;
begin
  Result := '<none>';
  R := TTveRegex.Create(Pat, False);
  if R.Exec(Subj, 1, C) and (C[2 * N] >= 0) then
    Result := Copy(Subj, C[2 * N], C[2 * N + 1] - C[2 * N]);
  R.Free;
end;

function Sub(const Pat, Subj, Repl: AnsiString): AnsiString;
var
  R: TTveRegex;
  C: TCaps;
begin
  R := TTveRegex.Create(Pat, False);
  if R.Exec(Subj, 1, C) then
    Result := Copy(Subj, 1, C[0] - 1) + R.Expand(Repl, Subj, C) + Copy(Subj, C[1], MaxInt)
  else
    Result := Subj;
  R.Free;
end;

const
  Privet = #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;
  privet_l = #$D0#$BF#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;

begin
  Utf8Enabled := True;
  Check(M('abc', 'xxabcxx') = 'abc', 'literal');
  Check(M('abc', 'xxabxx') = '', 'literal: no match');
  Check(M('a.c', 'abc') = 'abc', 'dot');
  Check(M('a.c', 'a'#10'c') = '', 'dot does not match the line end');
  Check(M('^abc', 'abc') = 'abc', 'bol');
  Check(M('^abc', 'xabc') = '', 'bol: not at the start');
  Check(M('abc$', 'xabc') = 'abc', 'eol');
  Check(M('^b', 'a'#10'b') = 'b', '^ matches after a line end');
  Check(M('a$', 'a'#10'b') = 'a', '$ matches before a line end');
  Check(M('ab*c', 'ac') = 'ac', 'star: zero');
  Check(M('ab*c', 'abbbc') = 'abbbc', 'star: many');
  Check(M('ab+c', 'ac') = '', 'plus: needs one');
  Check(M('ab+c', 'abbc') = 'abbc', 'plus');
  Check(M('ab?c', 'abc') = 'abc', 'question');
  Check(M('ab?c', 'ac') = 'ac', 'question: zero');
  Check(M('a{3}', 'aaaa') = 'aaa', '{n}');
  Check(M('a{2,3}', 'aaaa') = 'aaa', '{n,m} is greedy');
  Check(M('a{2,}', 'aaaa') = 'aaaa', '{n,}');
  Check(M('a{2,3}?', 'aaaa') = 'aa', 'lazy {n,m}?');
  Check(M('a*?b', 'aaab') = 'aaab', 'lazy star still has to reach b');
  Check(M('<.*>', '<a><b>') = '<a><b>', 'greedy');
  Check(M('<.*?>', '<a><b>') = '<a>', 'lazy');
  Check(M('cat|dog', 'hotdog') = 'dog', 'alternation');
  Check(M('cat|dog|bird', 'a bird') = 'bird', 'alternation of three');
  Check(M('a(b|c)d', 'acd') = 'acd', 'group with alternation');
  Check(M('(ab)+', 'ababab') = 'ababab', 'repeated group');
  Check(M('(?:ab)+c', 'ababc') = 'ababc', 'non-capturing group');
  Check(M('[abc]+', 'xxbcaxx') = 'bca', 'class');
  Check(M('[a-c]+', 'xxbcaxx') = 'bca', 'range');
  Check(M('[^a-c]+', 'abxyc') = 'xy', 'negated class');
  Check(M('[]a]+', 'a]a') = 'a]a', 'a ] first in a class is a character');
  Check(M('\d+', 'ab123c') = '123', '\d');
  Check(M('\D+', '12ab3') = 'ab', '\D');
  Check(M('\w+', '  foo_1 ') = 'foo_1', '\w');
  Check(M('\s+', 'a  b') = '  ', '\s');
  Check(M('[\d.]+', 'v1.25x') = '1.25', 'shorthand in a class');
  Check(M('[[:alpha:]]+', '12abc34') = 'abc', '[:alpha:]');
  Check(M('[[:digit:]]+', 'ab12') = '12', '[:digit:]');
  Check(M('\bfoo\b', 'a foo b') = 'foo', 'word boundary');
  Check(M('\bfoo\b', 'afoob') = '', 'word boundary: inside a word');
  Check(M('\Boo\B', 'foob') = 'oo', 'not a word boundary');
  Check(M('\Aab', 'ab') = 'ab', '\A');
  Check(M('b\z', 'ab') = 'b', '\z');
  Check(M('a\.b', 'a.b') = 'a.b', 'escaped dot');
  Check(M('a\.b', 'axb') = '', 'escaped dot is not any');
  Check(M('\x41', 'A') = 'A', '\xHH');
  Check(M('\x{41}', 'A') = 'A', '\x{H}');
  Check(M('Ж', #$D0#$96) = #$D0#$96, '\uHHHH');
  Check(M('a\tb', 'a'#9'b') = 'a'#9'b', '\t');
  Check(M('a\nb', 'a'#10'b') = 'a'#10'b', '\n matches a line end');

  { groups and back references }
  Check(G('(a)(b)(c)', 'abc', 2) = 'b', 'group 2');
  Check(G('(a)|(b)', 'b', 1) = '<none>', 'a group that did not take part');
  Check(G('(a)|(b)', 'b', 2) = 'b', 'the other group');
  Check(G('(\w+)@(\w+)', 'me@host', 2) = 'host', 'groups of a pattern');
  Check(M('(a+)\1', 'aaaa') = 'aaaa', 'back reference');
  Check(M('(a+)\1', 'aaa') = 'aa', 'back reference: the longest that fits');
  Check(M('(\w)\1', 'hello') = 'll', 'doubled letter');
  Check(Sub('(\w+) (\w+)', 'hello world', '\2 \1') = 'world hello', 'replacement with \2 \1');
  Check(Sub('(\w+) (\w+)', 'hello world', '$2-$1') = 'world-hello', 'replacement with $2 $1');
  Check(Sub('b', 'abc', '[$&]') = 'a[b]c', 'replacement with $&');
  Check(Sub('b', 'abc', 'x\ny') = 'ax'#10'yc', 'replacement with \n');
  Check(Sub('b', 'abc', '\\') = 'a\c', 'replacement with \\');

  { flags }
  Check(M('abc', 'xABCx', True) = 'ABC', 'ignore case');
  Check(M('(?i)abc', 'xABCx') = 'ABC', '(?i)');
  Check(M('[a-c]+', 'ABC', True) = 'ABC', 'ignore case in a class');
  Check(M('(a)\1', 'aA', True) = 'aA', 'ignore case in a back reference');

  { UTF-8 }
  Check(M('.', Privet) = #$D0#$9F, 'dot takes a whole character');
  Check(M('^.{6}$', Privet) = Privet, 'counts are in characters');
  Check(M(privet_l, Privet, True) = Privet, 'ignore case for Cyrillic');
  Check(M('[а-я]+', Privet) = Copy(Privet, 3, MaxInt), 'a class of Cyrillic lowercase does not match the capital letter, only the lowercase after it');
  Check(M('[а-я]+', Privet, True) = Privet, 'ignore case in a Cyrillic class');
  Check(M('\w+', Privet) = Privet, '\w for Cyrillic');
  Check(M('Привет|мир', 'мир') = 'мир', 'alternation of UTF-8 words');
  Check(M('a'#$80'b', 'xa'#$80'bx') = 'a'#$80'b', 'a stray byte matches itself');

  { errors }
  M('(abc', 'x'); Check(Pos('error', Last) = 1, 'missing )');
  M('abc)', 'x'); Check(Pos('error', Last) = 1, 'unmatched )');
  M('[abc', 'x'); Check(Pos('error', Last) = 1, 'missing ]');
  M('*a', 'x'); Check(Pos('error', Last) = 1, 'nothing to repeat');
  M('a{3,2}', 'x'); Check(Pos('error', Last) = 1, 'bad counts');
  M('[c-a]', 'x'); Check(Pos('error', Last) = 1, 'a range backwards');
  M('a\', 'x'); Check(Pos('error', Last) = 1, 'a backslash at the end');

  { odd but valid }
  Check(M('a{', 'a{') = 'a{', 'a { that starts no quantifier is a character');
  Check(M('a{x}', 'a{x}') = 'a{x}', '{x} is text');
  Check(M('', 'abc') = '', 'the empty pattern matches the empty text');
  Check(M('(a*)*b', 'aaab') = 'aaab', 'a repeat of something that can be empty ends');
  Check(M('(a|b)*c', 'ababc') = 'ababc', 'a repeated alternation');
  Check(M('(a?)*b', 'aab') = 'aab', 'a repeat of an optional group');

  { the limit of steps }
  Check(M('(a+)+$', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!') = '', 'a catastrophic pattern gives up');
  Check(Last = 'nomatch', 'and says no match (Aborted)');

  { a long line does not use the stack }
  Check(Length(M('a*b', StringOfChar('a', 2000000) + 'b')) = 2000001, 'a million characters with a star');

  Finish;
end.
