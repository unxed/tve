program t_doc;
{ TveDoc: undo and redo with grouping, the save point, anchors, observers. }
{$mode objfpc}{$H+}
uses SysUtils, TveBuf, TveDoc;
{$I testlib.inc}

type
  TObs = class
    Count: Integer;
    LastOff, LastRem, LastIns: Int64;
    procedure Hit(Doc: TTveDoc; Offset, Removed, Inserted: Int64);
  end;

procedure TObs.Hit(Doc: TTveDoc; Offset, Removed, Inserted: Int64);
begin
  Inc(Count);
  LastOff := Offset; LastRem := Removed; LastIns := Inserted;
end;

var
  D: TTveDoc;
  O: TObs;
  C: Int64;
  I, A, B2: Integer;
  S: AnsiString;

procedure Type_(const Text: AnsiString);
var
  K: Integer;
begin
  for K := 1 to Length(Text) do
  begin
    D.NoteCursor(D.Buffer.Length);
    D.Insert(D.Buffer.Length, Text[K]);
  end;
end;

begin
  D := TTveDoc.Create;
  O := TObs.Create;
  D.AddObserver(@O.Hit);
  D.LoadText('hello');
  Check((D.Buffer.AsString = 'hello') and not D.Modified and not D.CanUndo, 'LoadText: not modified, no undo');
  Check(O.Count = 1, 'LoadText tells the observers');

  { typing merges into one group }
  Type_(' world');
  Check((D.Buffer.AsString = 'hello world') and D.Modified, 'typing');
  Check(D.UndoCount = 1, 'a run of typing is one undo step (' + IntToStr(D.UndoCount) + ')');
  Check(D.Undo(C) and (D.Buffer.AsString = 'hello') and not D.Modified, 'undo of the run; modified is off again (the save point)');
  Check(D.CanRedo and D.Redo(C) and (D.Buffer.AsString = 'hello world') and D.Modified, 'redo');

  { Backspace merges }
  D.NoteCursor(11); D.Delete(10, 1);
  D.NoteCursor(10); D.Delete(9, 1);
  D.NoteCursor(9); D.Delete(8, 1);
  Check(D.Buffer.AsString = 'hello wo', 'three Backspace');
  Check(D.UndoCount = 2, 'a run of Backspace is one step');
  D.Undo(C);
  Check(D.Buffer.AsString = 'hello world', 'undo of the run of Backspace');
  { a Delete run merges }
  D.NoteCursor(0); D.Delete(0, 1);
  D.NoteCursor(0); D.Delete(0, 1);
  Check((D.Buffer.AsString = 'llo world') and (D.UndoCount = 2), 'a run of Delete is one step');
  { a new edit throws the redo stack away }
  D.Undo(C);
  Check(D.CanRedo, 'redo is there');
  D.NoteCursor(0); D.Insert(0, '>');
  Check(not D.CanRedo, 'a new edit throws the redo stack away');

  { the cursor of the groups }
  D.LoadText('abc');
  D.NoteCursor(1);
  D.Insert(1, 'X');
  D.NoteCursorAfter(2);
  D.Undo(C);
  Check(C = 1, 'undo gives the cursor from before the edit');
  D.Redo(C);
  Check(C = 2, 'redo gives the cursor after');

  { explicit groups }
  D.LoadText('0123456789');
  D.NoteCursor(0);
  D.BeginGroup;
  D.Replace(0, 1, 'a');
  D.Replace(5, 1, 'b');
  D.BeginGroup;
  D.Replace(9, 1, 'c');
  D.EndGroup;
  D.EndGroup;
  Check((D.Buffer.AsString = 'a1234b678c') and (D.UndoCount = 1), 'a group (nested) is one step');
  D.Undo(C);
  Check(D.Buffer.AsString = '0123456789', 'and one undo takes all of it back');
  D.Redo(C);
  Check(D.Buffer.AsString = 'a1234b678c', 'and one redo');
  D.BeginGroup; D.EndGroup;
  Check(D.UndoCount = 1, 'an empty group is nothing');

  { a newline and a long paste are steps of their own }
  D.LoadText('x');
  D.NoteCursor(1); D.Insert(1, 'a');
  D.NoteCursor(2); D.Insert(2, #10);
  D.NoteCursor(3); D.Insert(3, 'b');
  Check(D.UndoCount = 3, 'a newline is a step of its own');

  { BreakUndo }
  D.LoadText('');
  Type_('ab');
  D.BreakUndo;
  Type_('cd');
  Check(D.UndoCount = 2, 'BreakUndo: typing goes on in a new group');

  { the save point }
  D.LoadText('save');
  Type_('1');
  D.MarkSaved;
  Check(not D.Modified, 'MarkSaved');
  Type_('2');
  Check(D.Modified and (D.UndoCount = 2), 'typing after a save is a new group (the saved state stays reachable)');
  D.Undo(C);
  Check(not D.Modified, 'undo to the save point: not modified');
  D.Undo(C);
  Check(D.Modified, 'undo past the save point: modified');
  D.Redo(C);
  Check(not D.Modified, 'redo to the save point: not modified');
  D.Undo(C); D.Undo(C);
  D.NoteCursor(0); D.Insert(0, 'new');
  Check(D.Modified, 'a new edit in the past throws the saved state away');
  D.Undo(C);
  Check(D.Modified, 'and the save point is lost, not just moved');

  { anchors }
  D.LoadText('0123456789');
  A := D.AddAnchor(5);
  B2 := D.AddAnchor(5, True);
  D.Insert(0, 'xx');
  Check(D.AnchorPos(A) = 7, 'an anchor moves with an insertion before it');
  D.Insert(7, 'yy');
  Check((D.AnchorPos(A) = 7) and (D.AnchorPos(B2) = 9), 'at the place of an insertion: stays before, a sticky one goes after');
  D.Delete(4, 6);
  Check((D.AnchorPos(A) = 4) and (D.AnchorPos(B2) = 4), 'inside a removed run: at its start');
  D.Undo(C);
  Check(D.Buffer.Length = 14, 'undo of the delete');
  D.RemoveAnchor(A);
  Check((D.AnchorPos(A) = -1) and not D.AnchorAlive(A), 'a removed anchor');
  Check(D.AddAnchor(1) = A, 'an id is reused');

  { observers }
  D.LoadText('abc');
  O.Count := 0;
  D.Insert(1, 'XY');
  Check((O.Count = 1) and (O.LastOff = 1) and (O.LastRem = 0) and (O.LastIns = 2), 'an edit is told to the observer');
  D.Undo(C);
  Check((O.Count = 2) and (O.LastOff = 1) and (O.LastRem = 2) and (O.LastIns = 0), 'undo is told as the opposite edit');
  D.RemoveObserver(@O.Hit);
  D.Insert(0, 'q');
  Check(O.Count = 2, 'a removed observer is not told');

  { read-only }
  D.LoadText('ro');
  D.ReadOnly := True;
  Check(not D.Insert(0, 'x') and (D.Buffer.AsString = 'ro'), 'a read-only document refuses edits');
  D.ReadOnly := False;

  { the limit }
  D.LoadText('');
  D.UndoLimit := 5;
  for I := 1 to 20 do
  begin
    D.BreakUndo;
    D.NoteCursor(D.Buffer.Length);
    D.Insert(D.Buffer.Length, 'a');
  end;
  Check(D.UndoCount = 5, 'the undo limit');
  S := '';
  while D.Undo(C) do S := S + 'u';
  Check((Length(S) = 5) and (D.Buffer.Length = 15), 'only the last steps can be undone');

  D.Free;
  O.Free;
  Finish;
end.
