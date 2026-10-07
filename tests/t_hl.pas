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
  D.Free;
  Finish;
end.
