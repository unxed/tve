program t_templ;
{ TveTemplates: variables, indentation, the cursor marker, sets of templates, shortcut expansion. }
{$mode objfpc}{$H+}
uses SysUtils, TveBuf, TveDoc, TveEditor, TveTemplates;
{$I testlib.inc}

type
  TAsk = class
    Last: AnsiString;
    function Ask(const Q: AnsiString; out V: AnsiString): Boolean;
  end;

function TAsk.Ask(const Q: AnsiString; out V: AnsiString): Boolean;
begin
  Last := Q;
  V := '<' + Q + '>';
  Result := Q <> 'cancel';
end;

var
  A: TAsk;
  T: AnsiString;
  C: Integer;
  Tp: TTveTemplates;
  D: TTveDoc;
  E: TTveEditor;
begin
  A := TAsk.Create;
  Check(TveExpandTemplate('a $PROMPT(''name'') b', '', @A.Ask, T, C) and (T = 'a <name> b') and (C = -1), 'prompt ' + T);
  Check(TveExpandTemplate('x $$ y $FOO', '', nil, T, C) and (T = 'x $ y $FOO'), 'dollar signs ' + T);
  Check(TveExpandTemplate('if (|$CURSOR) then' + #10 + 'end', '  ', nil, T, C) and (T = 'if (|) then' + #10 + '  end') and (C = 5), 'cursor and indent ' + T);
  Check(TveExpandTemplate('$DATE(''yyyy'')', '', nil, T, C) and (T = FormatDateTime('yyyy', Now)), 'date format');
  Check(not TveExpandTemplate('$PROMPT(cancel)', '', @A.Ask, T, C), 'cancel');
  Tp := TTveTemplates.Create;
  Check(Tp.LoadText('ignored' + #10 + '[ifb] if block' + #10 + 'if $CURSOR then' + #10 + '  x' + #10 + 'end' + #10 + '[[not a header' + #10 + '[for] loop' + #10 + 'for $PROMPT(var) do' + #10) = 2, 'two templates');
  Check((Tp.Name(0) = 'ifb') and (Tp.Description(0) = 'if block') and (Tp.IndexOf('FOR') = 1), 'names');
  Check(Tp.Body(0) = 'if $CURSOR then' + #10 + '  x' + #10 + 'end' + #10 + '[not a header', 'body ' + Tp.Body(0));
  D := TTveDoc.Create;
  D.LoadText('  ifb');
  E := TTveEditor.Create(D);
  E.GotoLineCell(0, 5);
  Check(TveExpandShortcut(E, Tp, nil), 'shortcut expands');
  Check(D.Buffer.AsString = '  if  then' + #10 + '    x' + #10 + '  end' + #10 + '  [not a header', 'result ' + D.Buffer.AsString);
  Check((E.Line = 0) and (E.Cell = 5), 'cursor at the marker');
  Check(D.UndoCount = 1, 'one undo step');
  E.Undo;
  Check(D.Buffer.AsString = '  ifb', 'undone');
  E.GotoLineCell(0, 2);
  Check(not TveExpandShortcut(E, Tp, nil), 'no word before the cursor');
  E.Free;
  D.Free;
  Tp.Free;
  A.Free;
  Finish;
end.
