{ Tests of TveWrap. }
program t_wrap;

{$mode objfpc}{$H+}

uses
  SysUtils, TveBuf, TveFold, TveDoc, TveWrap;

var
  Fails: Integer = 0;
  Count: Integer = 0;

procedure Check(Ok: Boolean; const What: string);
begin
  Inc(Count);
  if Ok then
    WriteLn('PASS ', What)
  else
  begin
    WriteLn('FAIL ', What);
    Inc(Fails);
  end;
end;

function Join(const A: TTveIntArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(A) do
  begin
    if I > 0 then Result := Result + ',';
    Result := Result + IntToStr(A[I]);
  end;
end;

var
  Doc: TTveDoc;
  M: TTveWrapMap;
  Seg: Integer;
  A, B: Integer;
begin
  Check(Join(WrapSegments('short', 10, 8)) = '0', 'a short line is one segment');
  Check(Join(WrapSegments('', 10, 8)) = '0', 'an empty line is one segment');
  Check(Join(WrapSegments('abcdefghij', 5, 8)) = '0,5', 'a word longer than the row is cut where it does not fit');
  Check(Join(WrapSegments('abcdefghijk', 5, 8)) = '0,5,10', 'and again');
  Check(Join(WrapSegments('aaa bbb ccc', 8, 8)) = '0,8', 'a break after the blank: "aaa bbb " and "ccc"');
  Check(Join(WrapSegments('aaa bbbbbbbbb', 8, 8)) = '0,4,12', 'a long word goes to the next row and is cut where it must be');
  Check(Join(WrapSegments('aa'#9'bb', 4, 4)) = '0,4', 'a tab that does not fit starts the next row');
  Check(Join(WrapSegments('привет мир', 7, 8)) = '0,7', 'UTF-8 text: the cells count characters');
  Check(Join(WrapSegments('abcdef', 0, 8)) = '0', 'width 0: no wrap');
  Check(Join(WrapSegments('a-b-c-d', 4, 8)) = '0,4', 'a hyphen is a place to break');

  Doc := TTveDoc.Create;
  Doc.LoadText('aaa bbb ccc'#10'x'#10'0123456789abcdef');
  M := TTveWrapMap.Create(Doc.Buffer);
  M.Build(8, 8, nil);
  Check(M.TotalRows = 5, 'rows of three lines: 2 + 1 + 2');
  Check(M.FirstRow(1) = 2, 'the second line starts at row 2');
  Check(M.RowToLine(0, Seg) = 0, 'row 0 is line 0');
  Check((M.RowToLine(1, Seg) = 0) and (Seg = 1), 'row 1 is line 0, segment 1');
  Check((M.RowToLine(2, Seg) = 1) and (Seg = 0), 'row 2 is line 1');
  Check((M.RowToLine(4, Seg) = 2) and (Seg = 1), 'row 4 is line 2, segment 1');
  M.SegBounds(0, 1, A, B);
  Check((A = 8) and (B = 12), 'the last segment ends one cell past the line');
  Check(M.RowOf(0, 9) = 1, 'a cell in the second segment is in row 1');
  Check(M.Valid(8, 8, nil), 'the map is valid');
  Doc.Insert(0, 'z');
  Check(not M.Valid(8, 8, nil), 'a change of the text makes it stale');
  Check(not M.Valid(9, 8, nil), 'so does the width');
  M.Free;
  Doc.Free;
  WriteLn;
  if Fails = 0 then
    WriteLn('ALL OK (', Count, ' checks)')
  else
    WriteLn(Fails, ' FAILED');
end.
