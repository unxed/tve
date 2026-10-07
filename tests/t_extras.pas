program t_extras;
{ TveCalc, TveExtras, bookmarks and brackets of TveEditor. }
{$mode objfpc}{$H+}
uses SysUtils, TvUtf8, TveBuf, TveDoc, TveEditor, TveCalc, TveExtras;
{$I testlib.inc}

var
  D: TTveDoc;
  E: TTveEditor;
  V: Double;
  Err: AnsiString;

function Calc(const S: AnsiString): AnsiString;
begin
  if CalcExpression(S, V, Err) then
    Result := CalcFormat(V)
  else
    Result := 'ERR ' + Err;
end;

procedure Setup(const Text: AnsiString);
begin
  if E <> nil then E.Free;
  D.LoadText(Text);
  E := TTveEditor.Create(D);
end;

const
  Privet = #$D0#$9F#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82;

begin
  Utf8Enabled := True;
  D := TTveDoc.Create;
  E := nil;
  Check(Calc('1+2*3') = '7', 'precedence');
  Check(Calc('(1+2)*3') = '9', 'parentheses');
  Check(Calc('10/4') = '2.5', 'division');
  Check(Calc('10 % 4') = '2', 'remainder');
  Check(Calc('2^10') = '1024', 'power');
  Check(Calc('2**3**2') = '512', 'power is right to left');
  Check(Calc('-3^2') = '-9', 'a minus before a power: -(3^2)');
  Check(Calc('2^-1') = '0.5', 'a signed exponent');
  Check(Calc('--4') = '4', 'double minus');
  Check(Calc('0x1F + $10 + 0b101') = '52', 'hex and binary');
  Check(Calc('1e3 + 2.5e-1') = '1000.25', 'exponents');
  Check(Calc('sqrt(16) + abs(-2)') = '6', 'functions');
  Check(Calc('max(1, 5, 3) - min(4, 2)') = '3', 'max and min');
  Check(Calc('pi') = '3.14159265359', 'pi');
  Check(Calc('floor(2.7) + ceil(2.1) + round(2.5) + trunc(-2.7)') = '6', 'rounding functions (2 + 3 + 3 - 2; round is half away from zero)');
  Check(Pos('ERR', Calc('1/0')) = 1, 'division by zero');
  Check(Pos('ERR', Calc('1+')) = 1, 'the expression ends too early');
  Check(Pos('ERR', Calc('(1+2')) = 1, 'missing )');
  Check(Pos('ERR', Calc('1 2')) = 1, 'unexpected text');
  Check(Pos('ERR', Calc('foo(1)')) = 1, 'unknown function');
  Check(Pos('ERR', Calc('')) = 1, 'empty');
  Check(CalcFormat(3) = '3', 'format a whole number');
  Check(CalcFormat(0.1 + 0.2) = '0.3', 'format without noise digits');
  Check(CalcSum('1'#10'2+3'#10#10'4', V, Err) and (V = 10), 'sum of lines');

  { calculate the block }
  Setup('2+2');
  Check(CalcBlock(E, Err) and (Err = '4'), 'calculate the current line');
  Setup('1'#10'2'#10'3');
  E.StartSelection(skColumn);
  E.GotoLineCell(2, 1);
  Check(CalcBlock(E, Err) and (Err = '6'), 'a column block is added up');
  Setup('2*3');
  E.StartSelection(skStream);
  E.MoveEnd(True);
  Check(CalcBlock(E, Err) and (Err = '6'), 'the selection is calculated');
  Setup('foo');
  Check(not CalcBlock(E, Err), 'not an expression');

  { the keyboard layout: 'ghbdtn' is "привет" typed on the Latin layout }
  Check(FixLayoutText('ghbdtn') = #$D0#$BF#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82, 'Latin letters to Russian');
  Check(FixLayoutText('Ghbdtn') = Privet, 'a capital stays a capital');
  Check(FixLayoutText(#$D1#$80#$D1#$83#$D0#$B4#$D0#$B4#$D1#$89) = 'hello', 'Russian letters to Latin');
  Check(FixLayoutText('123 ,') = '123 ,', 'digits are not changed');
  Setup('ghbdtn world');
  E.GotoLineCell(0, 2);
  Check(FixLayout(E) and (D.Buffer.AsString = #$D0#$BF#$D1#$80#$D0#$B8#$D0#$B2#$D0#$B5#$D1#$82' world'), 'fix the word at the cursor');
  Setup('abc def');
  FixLayout(E, True);
  Check(D.Buffer.Length > 7, 'fix a whole line');

  { date and a character }
  Setup('');
  Check(InsertDateTime(E, 'yyyy') and (Length(D.Buffer.AsString) = 4), 'insert the year');
  Setup('');
  InsertCodePoint(E, $20AC);
  Check(D.Buffer.AsString = #$E2#$82#$AC, 'insert a character by its code point');
  Check(not InsertCodePoint(E, $110000), 'a code point above U+10FFFF');

  { bookmarks follow the edits }
  Setup('zero'#10'one'#10'two'#10'three');
  E.GotoLineCell(2, 0);
  E.SetBookmark(3);
  E.GotoLineCell(0, 0);
  Check(E.GotoBookmark(3) and (E.Line = 2), 'goto a bookmark');
  E.GotoLineCell(0, 0);
  E.NewLine;
  Check(E.BookmarkLine(3) = 3, 'a bookmark moves down with an inserted line');
  E.GotoLineCell(0, 0);
  E.DeleteLine;
  Check(E.BookmarkLine(3) = 2, 'and up with a deleted one');
  Check(not E.GotoBookmark(5), 'a bookmark that is not set');
  E.ClearBookmark(3);
  Check(E.BookmarkLine(3) = -1, 'clear a bookmark');

  { brackets }
  Setup('f(a[1], (b))');
  E.GotoLineCell(0, 1);
  Check(E.GotoMatchingBracket and (E.Cell = 11), 'forward to the closing bracket, over nested ones');
  Check(E.GotoMatchingBracket and (E.Cell = 1), 'and back');
  E.GotoLineCell(0, 3);
  Check(E.GotoMatchingBracket and (E.Cell = 5), '[ ] pair');
  E.GotoLineCell(0, 0);
  Check(not E.GotoMatchingBracket, 'no bracket at the cursor');
  Setup('((');
  Check(not E.GotoMatchingBracket, 'an unmatched bracket');
  E.Free;
  D.Free;
  Finish;
end.
