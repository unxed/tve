program t_semantic;
{ Semantic colouring: the names of types and routines that the outline finds are coloured where the text uses them. }
{$mode objfpc}{$H+}
uses SysUtils, TvGeom, TveDoc, TveHl, TveLang, TveSymbols, TveView;
{$I testlib.inc}

const
  Letters = '.cs0ktbpoeTaEvdfPSVAx';

var
  D: TTveDoc;
  L: TTveLanguage;
  H: TTveHighlighter;
  V: TTveView;
  Rc: TRect;
  Names: TWordArr;
  Classes: TTveByteArray;
  I: Integer;
  S: AnsiString;

function Cl(Line: Int64): AnsiString;
var
  C: TByteClasses;
  K: Integer;
begin
  H.ClassifyLine(Line, C);
  Result := '';
  for K := 0 to High(C) do
    Result := Result + Letters[C[K] + 1];
end;

begin
  D := TTveDoc.Create;
  D.LoadText('type'#10'  TFoo = class'#10'  end;'#10'procedure TFoo.Run;'#10'begin'#10'  x := TFOO(y); run; s := ''Run''; // Run'#10'  xrun := 1;'#10'end;'#10);
  L := TveLangByName('Pascal');
  TveSemanticNames(D, L, Names, Classes);
  S := '';
  for I := 0 to High(Names) do
    S := S + Names[I] + ':' + IntToStr(Classes[I]) + ' ';
  Check(S = 'TFoo:' + IntToStr(hcType) + ' Run:' + IntToStr(hcFunction) + ' ', 'names: ' + S);
  H := TTveHighlighter.Create(D, L);
  Check(Cl(5) = '....oo.................oo.sssss..cccccc', 'before: ' + Cl(5));
  H.SetNames(Names, Classes);
  { the language ignores case; strings, comments and parts of other words are left alone }
  Check(Cl(5) = '....oo.tttt.....fff....oo.sssss..cccccc', 'coloured: ' + Cl(5));
  Check(Pos('f', Cl(6)) = 0, 'not inside another word: ' + Cl(6));
  H.Free;
  { off: a grammar without "semantic" }
  TveSemanticNames(D, TveLangByName('SQL'), Names, Classes);
  Check(Length(Names) = 0, 'no names without the directive');
  { C: the last part of a qualified name; case matters }
  D.LoadText('struct P {'#10'};'#10'void P::run() {'#10'}'#10'int main() { P p; p.run(); RUN(); }'#10);
  L := TveLangByName('C/C++');
  TveSemanticNames(D, L, Names, Classes);
  H := TTveHighlighter.Create(D, L);
  H.SetNames(Names, Classes);
  S := Cl(4);
  Check((S[14] = 't') and (S[21] = 'f') and (S[23] = 'f') and (S[29] <> 'f'), 'C: ' + S);
  H.Free;
  { the view finds the names before drawing when the text changed }
  D.LoadText('def go():'#10'    pass'#10'go()'#10);
  Rc.Assign(0, 0, 40, 10);
  V := TTveView.Create(Rc, nil, nil, D);
  V.SetLanguage(TveLangByName('Python'));
  V.SemanticNames := True;
  V.Draw;
  H := V.Highlighter;
  Check(Copy(Cl(2), 1, 2) = 'ff', 'view: a use of a routine ' + Cl(2));
  D.Insert(D.Buffer.LineStart(2), 'class K: pass'#10'K()'#10);
  V.Draw;
  Check(Copy(Cl(3), 1, 1) = 't', 'view: names found again after an edit ' + Cl(3));
  V.SemanticNames := False;
  Check(Copy(Cl(4), 1, 2) = '..', 'off again ' + Cl(4));
  V.Free;
  D.Free;
  Finish;
end.
