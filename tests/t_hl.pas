program t_hl;
{ TveHl, TveLang: classes of the bytes, states across lines, cache after edits. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, TveBuf, TveDoc, TveHl, TveLang;
{$I testlib.inc}

const
  Letters = '.cs0ktbpoeTaEvdfPSVAx';

var
  D: TTveDoc;
  L: TTveLanguage;
  H: TTveHighlighter;
  F: TStringList;
  I, J, Bad: Integer;

function Cl(Line: Int64): AnsiString;
var
  C: TByteClasses;
  I: Integer;
begin
  H.ClassifyLine(Line, C);
  Result := '';
  for I := 0 to High(C) do
    Result := Result + Letters[C[I] + 1];
end;

begin
  D := TTveDoc.Create;
  L := TveLangByName('pascal');
  Check(L <> nil, 'pascal exists');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('begin x := 12; // hi' + #10 + '(* a' + #10 + 'b *) s := ''it''''s'';' + #10 + '{$IFDEF X}');
  Check(Cl(0) = 'kkkkk...oo.00..ccccc', 'line0 ' + Cl(0));
  Check(Cl(1) = 'cccc', 'block start ' + Cl(1));
  Check(Cl(2)[1] = 'c', 'block continues ' + Cl(2));
  Check(Cl(2)[6] = '.', 'block ended ' + Cl(2));
  Check(Cl(2)[11] = 's', 'string with doubled quote ' + Cl(2));
  Check(Cl(3)[1] = 'p', 'directive ' + Cl(3));
  D.Replace(D.Buffer.LineStart(1), 2, 'xx');
  Check(Cl(2)[1] = '.', 'comment removed, state recomputed ' + Cl(2));
  L.Free;
  H.Free;
  L := TveLangForFile('main.go');
  Check((L <> nil) and (L.Name = 'Go'), 'go by mask');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('x := `a' + #10 + 'b` + "q\n" // c');
  Check(Cl(0)[6] = 's', 'raw string open ' + Cl(0));
  Check(Cl(1)[1] = 's', 'raw string goes on ' + Cl(1));
  Check(Cl(1)[6] = 's', 'string ' + Cl(1));
  Check(Cl(1)[8] = 'e', 'escape ' + Cl(1));
  Check(Cl(1)[12] = 'c', 'comment ' + Cl(1));
  H.Free;
  L.Free;
  Check(TveLangForFile('a.unknown') = nil, 'no language');
  { the test file of nested languages: HTML with CSS, JavaScript and Smarty in every place }
  L := TveLangForFile('appeals.tpl');
  Check((L <> nil) and (Pos('Smarty', L.Name) = 1), 'tpl is Smarty');
  F := TStringList.Create;
  F.LoadFromFile('data/appeals.tpl');
  D.LoadText(F.Text);
  H := TTveHighlighter.Create(D, L);
  Check(Copy(Cl(0), 1, 8) = 'dkkkkkkk', 'include tag ' + Cl(0));
  Bad := 0;
  for I := 0 to F.Count - 1 do
    if (Pos('{*', F[I]) = 0) and (Pos('*}', F[I]) = 0) then
      for J := 1 to Length(F[I]) - 1 do
        if (F[I][J] = '{') and (F[I][J + 1] in ['$', '/', 'i', 'e', 'f']) and (Cl(I)[J] <> 'd') then
          Inc(Bad);
  Check(Bad = 0, 'every smarty brace of the file is a delimiter: ' + IntToStr(Bad));
  Check(Cl(8)[9] = 'P', 'css property in the file');
  H.Free;
  L.Free;
  F.Free;
  { languages inside languages }
  L := TveLangByName('smarty');
  Check(L <> nil, 'smarty exists');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('<a href={$u}&x=1 {if $a}on{/if}>t</a>' + #10 +
    '<style>p { left: {$l}px; }</style>' + #10 +
    '<script>f({$p}); {* c *} g("{$q}");</script>' + #10 +
    '{literal}<b>{x}</b>{/literal}{$z}' + #10 +
    '<p style="color: {$c}; top: 1px" onclick="go({$n})">');
  Check(Cl(0) = 'dT.aaaaodvvdVVVV.dkk.vvdaadkkkdd.ddTd', 'smarty in unquoted attribute ' + Cl(0));
  Check(Cl(1) = 'dTTTTTdT...PPPPoVdvvdVV...ddTTTTTd', 'smarty in css value ' + Cl(1));
    Check(Cl(2) = 'dTTTTTTd..dvvd...ccccccc...sdvvds..ddTTTTTTd', 'smarty in js, a smarty comment, smarty in a js string ' + Cl(2));
      Check(Cl(3) = 'dkkkkkkkddTd...ddTdddkkkkkkkddvvd', 'literal: html stays, smarty is text, then smarty again ' + Cl(3));
      Check(Cl(4) = 'dT.aaaaaosPPPPPoVdvvd..PPPoV000s.aaaaaaaos...dvvd.sd', 'smarty in style and onclick attributes ' + Cl(4));
  H.Free;
  L.Free;
  L := TveLangByName('php');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('<p class="<?= $c ?>"><?php if ($x) { echo "a$b"; } // z' + #10 + '?></p>');
  Check(Copy(Cl(0), 10, 11) = 'sppp.vv.pps', 'php in attribute ' + Cl(0));
  Check(Copy(Cl(0), 28, 2) = 'kk', 'php keyword ' + Cl(0));
  Check(Cl(0)[Length(Cl(0))] = 'c', 'php comment to the end of the line ' + Cl(0));
  Check(Copy(Cl(1), 1, 2) = 'pp', 'php closes on the next line ' + Cl(1));
  H.Free;
  L.Free;
  L := TveLangByName('markdown');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('# T' + #10 + '```go' + #10 + 'func f() {} // c' + #10 + '```' + #10 + 'text `x`');
  Check(Cl(0) = 'dkk', 'md heading ' + Cl(0));
  Check(Copy(Cl(2), 1, 4) = 'kkkk', 'go in markdown ' + Cl(2));
  Check(Cl(2)[Length(Cl(2))] = 'c', 'go comment in markdown ' + Cl(2));
  Check(Cl(4) = '.....sss', 'back to markdown ' + Cl(4));
  H.Free;
  L.Free;
  L := TveLangByName('pascal');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('asm' + #10 + '  mov eax, 1 // z' + #10 + 'end;' + #10 + 'x := 1;');
  Check(Cl(1)[3] = 'A', 'asm block ' + Cl(1));
  Check(Cl(2) = 'kkk.', 'end of asm ' + Cl(2));
  Check(Cl(3)[6] = '0', 'pascal after asm ' + Cl(3));
  H.Free;
  L.Free;
  { YAML, INI/TOML, diff, Makefile }
  L := TveLangForFile('a/docker-compose.yml');
  Check((L <> nil) and (L.Name = 'YAML'), 'yaml by the file name');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('# c'#10'a:'#10'  b: "x\n" # t'#10'  - c: 1'#10'  - &r yes');
  Check(Cl(0) = 'ccc', 'yaml comment ' + Cl(0));
  Check(Cl(1) = 'Pd', 'yaml key ' + Cl(1));
  Check((Cl(2)[3] = 'P') and (Cl(2)[4] = 'd') and (Cl(2)[6] = 's') and (Cl(2)[11] = 'c'), 'yaml quoted value and a comment ' + Cl(2));
  Check((Cl(3)[3] = 'd') and (Cl(3)[5] = 'P') and (Cl(3)[8] = '0'), 'yaml list item with a key ' + Cl(3));
  Check((Cl(4)[5] = 'v') and (Cl(4)[9] = 'k'), 'yaml anchor and word ' + Cl(4));
  { block scalars: the lines indented more than the key are text, up to a line that is not }
  D.LoadText('run: |'#10'  echo: 1 # x'#10#10'  - b'#10'next: 2'#10'jobs:'#10'  - step: >-'#10'      a: b'#10'    name: x'#10'  k: |2'#10'   t'#10'z: 1');
  Check(Cl(0) = 'PPPddo', 'block key ' + Cl(0));
  Check(Cl(1) = 'sssssssssssss', 'block text ' + Cl(1));
  Check(Cl(3) = 'sssss', 'after an empty line ' + Cl(3));
  Check((Cl(4)[1] = 'P') and (Cl(4)[7] = '0'), 'the block ends at a key as indented ' + Cl(4));
  Check(Cl(6)[5] = 'P', 'a key in a list item ' + Cl(6));
  Check(Cl(7) = 'ssssssssss', 'its text ' + Cl(7));
  Check(Cl(8)[5] = 'P', 'ends at the next key of the item ' + Cl(8));
  Check(Cl(10) = 'ssss', 'indicator with an indentation ' + Cl(10));
  Check(Cl(11)[1] = 'P', 'and the end ' + Cl(11));
  H.Free;
  L.Free;
  { Markdown fences of these languages }
  L := TveLangForFile('r.md');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('```yaml'#10'a: 1'#10'```'#10'```diff'#10'+x'#10'```'#10'```toml'#10'[s]'#10'```'#10'```make'#10'all: x'#10'```'#10'text');
  Check((Cl(1)[1] = 'P') and (Cl(4)[1] = 't') and (Cl(7) = 'TTT') and (Cl(10)[1] = 'f'), 'fences: yaml, diff, toml, make');
  Check((Cl(2) = 'ddd') and (Cl(11) = 'ddd') and (Cl(12)[1] = '.'), 'the fences close');
  H.Free;
  L.Free;
  L := TveLangForFile('x.toml');
  Check((L <> nil) and (L.Name = 'INI/TOML'), 'toml by the file name');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('; c'#10'[sec]'#10'k = "v" '#10'n=12');
  Check((Cl(0) = 'ccc') and (Cl(1) = 'TTTTT'), 'ini comment and section ' + Cl(1));
  Check((Cl(2)[1] = 'P') and (Cl(2)[3] = 'o') and (Cl(2)[5] = 's'), 'ini key and string ' + Cl(2));
  Check((Cl(3)[2] = 'o') and (Cl(3)[3] = '0'), 'ini number ' + Cl(3));
  H.Free;
  L.Free;
  L := TveLangForFile('fix.patch');
  Check((L <> nil) and (L.Name = 'Diff'), 'diff by the file name');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('--- a/f'#10'@@ -1 +1 @@'#10' same'#10'-old'#10'+new');
  Check((Cl(0)[1] = 'k') and (Cl(1)[1] = 'x') and (Cl(2)[2] = '.') and (Cl(3)[1] = 'p') and (Cl(4)[1] = 't'), 'diff lines');
  H.Free;
  L.Free;
  L := TveLangForFile('Makefile');
  Check((L <> nil) and (L.Name = 'Makefile'), 'makefile by the file name');
  H := TTveHighlighter.Create(D, L);
  D.LoadText('CC := gcc'#10'all: $(OBJ)'#10#9'$(CC) $@'#10'# c');
  Check((Cl(0)[1] = 'v') and (Cl(0)[4] = 'o'), 'make variable ' + Cl(0));
  Check((Cl(1)[1] = 'f') and (Cl(1)[4] = 'd') and (Cl(1)[6] = 'v'), 'make target ' + Cl(1));
  Check((Cl(2)[2] = 'v') and (Cl(2)[8] = 'v'), 'make recipe ' + Cl(2));
  Check(Cl(3) = 'ccc', 'make comment');
  H.Free;
  L.Free;
  D.Free;
  Finish;
end.
