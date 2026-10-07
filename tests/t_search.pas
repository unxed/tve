program t_search;
{ TveSearch: plain and regular expression search, direction, scope, whole words, replace all. }
{$mode objfpc}{$H+}
uses SysUtils, TvUtf8, TveBuf, TveDoc, TveRegex, TveSearch;
{$I testlib.inc}

var
  D: TTveDoc;
  S: TTveSearcher;
  O: TTveSearchOptions;
  M: TTveMatch;

procedure Setup(const T: AnsiString);
begin
  D.LoadText(T);
  O := TveDefaultSearch;
end;

function F(const Pat: AnsiString; From: Int64; Backward: Boolean = False): Int64;
begin
  O.Pattern := Pat;
  O.Backward := Backward;
  if S.Find(O, From, M) = fsFound then
    Result := M.Start
  else
    Result := -1;
end;

const
  Privet = #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;
  privet_l = #$D0#$BF#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;

begin
  Utf8Enabled := True;
  D := TTveDoc.Create;
  S := TTveSearcher.Create(D.Buffer);

  Setup('one two'#10'three two'#10'four');
  Check(F('two', 0) = 4, 'find forward');
  Check((F('two', 5) = 14) and (M.Stop = 17), 'find the next one, on the next line');
  Check(F('two', 15) = -1, 'no more');
  Check(F('TWO', 0) = 4, 'case is ignored by default');
  O.CaseSensitive := True;
  Check(F('TWO', 0) = -1, 'case sensitive');
  O.CaseSensitive := False;
  Check(F('nope', 0) = -1, 'not found');
  Check(F('two', 17, True) = 14, 'backward: the last match that ends at or before the position');
  Check(F('two', 14, True) = 4, 'backward again');
  Check(F('two', 4, True) = -1, 'backward: nothing before the first');
  Check(F('o', 100, True) = 19, 'backward from the end');

  { whole words }
  Setup('foo food foo_bar foo');
  O.WholeWord := True;
  Check(F('foo', 0) = 0, 'whole word: the first');
  Check(F('foo', 1) = 17, 'whole word: skips food and foo_bar');
  Check(F('fo', 0) = -1, 'whole word: a part of a word is not a match');
  O.WholeWord := False;

  { regular expressions }
  Setup('a1 b22 c333');
  O.UseRegex := True;
  Check((F('\d+', 0) = 1) and (M.Stop = 2), 'regex');
  Check((F('\d+', 3) = 4) and (M.Stop = 6), 'regex: the next');
  Check(F('\d+', 11, True) = 8, 'regex backward');
  Check(F('(', 0) = -1, 'a bad pattern finds nothing');
  Check(S.Find(O, 0, M) = fsBadPattern, 'and is reported as a bad pattern');
  O.Pattern := '';
  Check(S.Find(O, 0, M) = fsBadPattern, 'an empty pattern is a bad one');
  O.UseRegex := False;

  { multi-line }
  Setup('ab'#10'cd'#10'ef');
  Check((F('b'#10'c', 0) = 1) and (M.Stop = 4), 'a plain text with a line end');
  O.UseRegex := True;
  Check((F('b\s+c', 0) = 1) and (M.Stop = 4), 'a regex with \s crosses lines');
  Check((F('d\nef', 0) = 4), 'a regex with \n');
  Check(F('^cd$', 0) = 3, '^ and $ in the multi-line mode');
  O.UseRegex := False;

  { scope }
  Setup('x x x x x');
  O.ScopeFrom := 2; O.ScopeTo := 7;
  Check(F('x', 0) = 2, 'scope: the first match inside');
  Check(F('x', 7) = -1, 'scope: none after the end of it');
  Check(F('x', 100, True) = 6, 'scope: backward stays inside');
  Check(S.Count(O) = 3, 'scope: the count');
  O := TveDefaultSearch;

  { UTF-8 }
  Setup(Privet + ' ' + Privet);
  Check(F(privet_l, 0) = 0, 'case-insensitive Cyrillic');
  Check(F(privet_l, 1) = 13, 'and the next one');
  O.CaseSensitive := True;
  Check(F(privet_l, 0) = -1, 'case-sensitive Cyrillic');
  O.CaseSensitive := False;
  O.WholeWord := True;
  Check(F(Copy(Privet, 1, 4), 0) = -1, 'a part of a Cyrillic word is no whole word');
  Check(F(Privet, 0) = 0, 'a Cyrillic word is a whole word');
  O.WholeWord := False;

  { replace }
  Setup('cat dog cat bird cat');
  O.Pattern := 'cat';
  Check(S.ReplaceAll(D, O, 'fox') = 3, 'replace all: the count');
  Check(D.Buffer.AsString = 'fox dog fox bird fox', 'replace all: the text');
  D.NoteCursor(0);
  Check(D.UndoCount >= 1, 'replace all is undoable');
  Setup('cat dog cat');
  O.Pattern := 'cat';
  S.ReplaceAll(D, O, 'fox');
  D.Undo(M.Start);
  Check(D.Buffer.AsString = 'cat dog cat', 'one undo takes all the replacements back');
  Setup('a1 b22 c333');
  O.UseRegex := True;
  O.Pattern := '([a-z])(\d+)';
  Check(S.ReplaceAll(D, O, '\2\1') = 3, 'regex replace all');
  Check(D.Buffer.AsString = '1a 22b 333c', 'regex replace with groups');
  Setup('abc');
  O.UseRegex := True;
  O.Pattern := 'x*';
  Check(S.ReplaceAll(D, O, '-') = 4, 'empty matches are counted once at each place');
  Check(D.Buffer.AsString = '-a-b-c-', 'and replaced there');
  Setup('one'#10'two');
  O.UseRegex := False;
  O.Pattern := 'e'#10't';
  S.ReplaceAll(D, O, ' ');
  Check(D.Buffer.AsString = 'on wo', 'replace across a line end');
  Setup('aaa');
  O.Pattern := 'a';
  O.ScopeFrom := 1; O.ScopeTo := 3;
  Check((S.ReplaceAll(D, O, 'b') = 2) and (D.Buffer.AsString = 'abb'), 'replace in a scope');
  O := TveDefaultSearch;
  O.Pattern := 'a';
  D.ReadOnly := True;
  Check(S.ReplaceAll(D, O, 'b') = 0, 'a read-only document is not changed');
  D.ReadOnly := False;

  { a big text }
  Setup('');
  M.Subject := '';
  D.Insert(0, StringOfChar('x', 100) + #10);
  D.BeginGroup;
  D.EndGroup;
  Setup(StringOfChar('x', 50000) + 'NEEDLE' + StringOfChar('y', 50000));
  O.Pattern := 'NEEDLE';
  Check(F('NEEDLE', 0) = 50000, 'a long line');
  S.Free;
  D.Free;
  Finish;
end.
