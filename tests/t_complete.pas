program t_complete;
{ TveComplete: keywords and words of the text. }
{$mode objfpc}{$H+}
uses SysUtils, TveBuf, TveDoc, TveEditor, TveComplete;
{$I testlib.inc}
var
  D: TTveDoc;
  E: TTveEditor;
  C: TTveCompletion;
  F: AnsiString;
  S: Int64;
  Items: TTveWords;
begin
  D := TTveDoc.Create;
  D.LoadText('procedure Foo; begin fooBar := 1; FooBaz := 2; pro');
  E := TTveEditor.Create(D);
  C := TTveCompletion.Create;
  C.SetKeywords('procedure program property');
  E.GotoOffset(D.Buffer.Length);
  Check(C.Candidates(E, F, S, Items), 'candidates');
  Check((F = 'pro') and (S = D.Buffer.Length - 3), 'fragment ' + F);
  Check((Length(Items) = 3) and (Items[0] = 'procedure') and (Items[1] = 'program') and (Items[2] = 'property'), 'keywords first, no duplicates: ' + IntToStr(Length(Items)));
  E.GotoOffset(D.Buffer.Length - 3);
  Check(not C.Candidates(E, F, S, Items), 'no fragment before the cursor');
  D.LoadText('fooBar fooBaz foo');
  E.GotoOffset(D.Buffer.Length);
  Check(C.Candidates(E, F, S, Items) and (Length(Items) = 2) and (Items[0] = 'fooBar') and (Items[1] = 'fooBaz'), 'words of the text');
  C.CaseSensitive := True;
  D.LoadText('FooX fooY foo');
  E.GotoOffset(D.Buffer.Length);
  Check(C.Candidates(E, F, S, Items) and (Length(Items) = 1) and (Items[0] = 'fooY'), 'case sensitive');
  C.Free;
  E.Free;
  D.Free;
  Finish;
end.
