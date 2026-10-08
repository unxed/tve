program t_foldgram;
{ Folding by the grammar: TveFoldRegions (braces, pairs of words, indentation, outline) and the fold commands of the view on them. }
{$mode objfpc}{$H+}
uses SysUtils, TvGeom, TveDoc, TveHl, TveLang, TveSymbols, TveView, TveCmds;
{$I testlib.inc}

function Regions(const Lang, Text: AnsiString): AnsiString;
var
  D: TTveDoc;
  L: TTveLanguage;
  R: TTveFoldRegions;
  I: Integer;
begin
  Result := '';
  L := TveLangByName(Lang);
  if L = nil then
    Exit('NO LANGUAGE ' + Lang);
  D := TTveDoc.Create;
  D.LoadText(Text);
  R := TveFoldRegions(D, L);
  for I := 0 to High(R) do
    Result := Result + IntToStr(R[I].First) + '-' + IntToStr(R[I].Last) + ' ';
  D.Free;
  L.Free;
end;

var
  T, Err: AnsiString;
  D: TTveDoc;
  V: TTveView;
  L: TTveLanguage;
  Rc: TRect;
begin
  { braces: a brace alone on its line starts the region at the line above; braces in strings and comments do not count; a one-line pair is no region }
  T := 'int f(void)'#10'{'#10'  if (x) {'#10'    s = "}";'#10'  }'#10'  // {'#10'  g({1});'#10'}'#10;
  Check(Regions('C/C++', T) = '0-7 2-4 ', 'C: ' + Regions('C/C++', T));
  { words: begin .. end, a class declaration .. end; not a forward declaration }
  T := 'type'#10'  TA = class(TObject)'#10'    X: Integer;'#10'  end;'#10'  EB = class(Exception);'#10'procedure P;'#10'begin'#10'  if a then'#10'  begin'#10'    s := ''end'';'#10'  end;'#10'end;'#10;
  Check(Regions('Pascal', T) = '1-3 6-11 8-10 ', 'Pascal: ' + Regions('Pascal', T));
  { the case of a variant record is no block, a case statement is one }
  T := 'type'#10'  TR = record'#10'    case Tag: Integer of'#10'      0: (A: Integer);'#10'      1: (B: record C: Char; end);'#10'  end;'#10 +
    'procedure P;'#10'begin'#10'  case X of'#10'    1: ;'#10'  end;'#10'end;'#10;
  Check(Regions('Pascal', T) = '1-5 7-11 8-10 ', 'Pascal variant record: ' + Regions('Pascal', T));
  { shell: braces and the words of the blocks }
  T := 'f() {'#10'  if x; then'#10'    y'#10'  fi'#10'}'#10'for a in b; do'#10'  c'#10'done'#10;
  Check(Regions('Shell', T) = '0-4 1-3 5-7 ', 'Shell: ' + Regions('Shell', T));
  { indentation: up to the last line indented more; blank lines inside do not end it; a string at the start of a line does not end it }
  T := 'class A:'#10'    def f(self):'#10'        x = 1'#10#10'        y = """'#10'z"""'#10'    def g(self): pass'#10'b = 2'#10;
  Check(Regions('Python', T) = '0-6 1-5 ', 'Python: ' + Regions('Python', T));
  { the outline: an entry up to the next one of its level or above, without the blank lines at the end }
  T := '# A'#10'text'#10'## B'#10'more'#10#10'# C'#10'end'#10;
  Check(Regions('Markdown', T) = '0-3 2-3 5-6 ', 'Markdown: ' + Regions('Markdown', T));
  { markup: the tags (a tag that closes itself does not open), HTML by its container elements (not <p>, <li>, void elements), the template blocks }
  T := '<?xml version="1.0"?>'#10'<a x="1">'#10'  <b/>'#10'  <c>'#10'    <!-- <d> -->'#10'  </c>'#10'</a>'#10;
  Check(Regions('XML', T) = '1-6 3-5 ', 'XML: ' + Regions('XML', T));
  T := '<body>'#10'<p>a'#10'<br>'#10'<ul>'#10'<li>x'#10'</ul>'#10'</body>'#10;
  Check(Regions('HTML', T) = '0-6 3-5 ', 'HTML: ' + Regions('HTML', T));
  T := '{% block main %}'#10'<div>'#10'{% if x %}'#10'y'#10'{% endif %}'#10'</div>'#10'{% endblock %}'#10;
  Check(Regions('Jinja/Twig/Django (HTML, CSS, JavaScript)', T) = '0-6 1-5 2-4 ', 'Jinja: ' + Regions('Jinja/Twig/Django (HTML, CSS, JavaScript)', T));
  T := '{foreach $a as $b}'#10'{if $b}'#10'x'#10'{/if}'#10'{/foreach}'#10;
  Check(Regions('Smarty (HTML, CSS, JavaScript)', T) = '0-4 1-3 ', 'Smarty: ' + Regions('Smarty (HTML, CSS, JavaScript)', T));
  { tags over several lines: an XML tag that closes itself on a later line is a region of its own lines, an end tag split before its > closes }
  T := '<root>'#10'  <item a="1"'#10'        b="2"/>'#10'  <group'#10'     name="x">'#10'    <leaf/>'#10'  </group>'#10'</root>'#10;
  Check(Regions('XML', T) = '0-7 1-2 3-6 ', 'XML tags over lines: ' + Regions('XML', T));
  T := '<body>'#10'<div'#10'  class="a">'#10'<p>x</p>'#10'</div'#10'>'#10'</body>'#10;
  Check(Regions('HTML', T) = '0-6 1-4 ', 'HTML tags over lines: ' + Regions('HTML', T));
  { SQL: brackets over lines, the blocks of a routine (not BEGIN; of a transaction), END IF and END LOOP close their own words }
  T := 'CREATE TABLE IF NOT EXISTS t ('#10'  a int,'#10'  b text -- ('#10');'#10'BEGIN;'#10'CREATE FUNCTION f() RETURNS int AS $$'#10'BEGIN'#10 +
    '  IF x > 1 THEN'#10'    LOOP'#10'      EXIT;'#10'    END LOOP;'#10'  END IF;'#10'  RETURN CASE WHEN a THEN 1 ELSE 0 END;'#10'END;'#10 +
    '$$ LANGUAGE plpgsql;'#10'COMMIT;'#10'SELECT CASE'#10'  WHEN a THEN 1'#10'END FROM t;'#10;
  Check(Regions('SQL', T) = '0-3 6-13 7-11 8-10 16-18 ', 'SQL: ' + Regions('SQL', T));
  Check(Regions('SQL', 'begin'#10'x;'#10'end;'#10) = '0-2 ', 'SQL: a block of begin and end');
  { the directive }
  L := TTveLanguage.Create;
  Check(not L.Load('language X'#10'fold sideways'#10, Err), 'bad fold: ' + Err);
  Check(not L.Load('language X'#10'fold /a/'#10, Err), 'a pair needs two expressions');
  Check(not L.Load('language X'#10'fold /(a/ /b/'#10, Err), 'bad expression');
  Check(L.Load('language X'#10'fold braces'#10'fold indent'#10'fold outline'#10'fold /x\/y/ /z/'#10'start m'#10'context m'#10, Err) and L.FoldBraces and
    L.FoldIndent and L.FoldOutline and (L.FoldPairCount = 1), 'fold directives: ' + Err);
  L.Free;

  { the view: FoldToggle on a line where a region starts makes it a fold and collapses it; again expands it }
  D := TTveDoc.Create;
  D.LoadText('void f()'#10'{'#10'  a();'#10'  if (x) {'#10'    b();'#10'  }'#10'}'#10'int y;'#10);
  Rc.Assign(0, 0, 40, 10);
  V := TTveView.Create(Rc, nil, nil, D);
  V.SetLanguage(TveLangByName('C/C++'));
  V.Editor.GotoLineCell(0, 0);
  V.Execute(tcFoldToggle);
  Check((V.Folds.Count = 1) and V.Folds.Collapsed(0) and (V.Folds.EndLine(0) = 6), 'a region becomes a collapsed fold');
  Check(V.Folds.IsHidden(3) and not V.Folds.IsHidden(7), 'its lines are hidden');
  V.Execute(tcFoldToggle);
  Check((V.Folds.Count = 1) and not V.Folds.Collapsed(0), 'toggled back');
  { inside a region: the innermost one, the cursor goes to its first line }
  V.Editor.GotoLineCell(4, 2);
  V.Execute(tcFoldCollapse);
  Check((V.Folds.Count = 2) and V.Folds.IsHidden(4) and (V.Editor.Line = 3), 'collapse inside: cursor on the first line ' + IntToStr(V.Editor.Line));
  V.Execute(tcUnfoldAll);
  Check(not V.Folds.IsHidden(4) and not V.Folds.IsHidden(2), 'unfold all');
  V.Editor.GotoLineCell(4, 0);
  V.Execute(tcFoldAll);
  Check(V.Folds.IsHidden(2) and V.Folds.IsHidden(4) and (V.Folds.Count = 2), 'fold all');
  Check(V.Editor.Line = 0, 'the cursor is on a shown line: ' + IntToStr(V.Editor.Line));
  Check(TveCommandByName('FoldAll') = tcFoldAll, 'command names');
  V.Free;
  D.Free;
  Finish;
end.
