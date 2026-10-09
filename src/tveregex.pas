{ TveRegex: regular expressions on UTF-8 text.

  MIT; a backtracking machine of the usual kind, with an explicit stack (so a long line does not use the stack of the program) and a limit
  of steps (so a pattern that backtracks without end gives up, Aborted tells it).

  Syntax: literals and \ escapes (\n \t \r \f \v \e \xHH \x[H..] \uHHHH and any sign after a backslash is itself); . (any character except the line end); classes [abc] [a-z]
  [^...] with \d \w \s \D \W \S and [:alpha:] [:digit:] [:alnum:] [:upper:] [:lower:] [:space:] [:punct:] [:word:]; anchors ^ $ (of a line) \A \z \b \B; groups (...) (?:...);
  alternation |; quantifiers * + ? [n] [n,] [n,m] and the lazy ones (*? +? ?? [n,m]?); back references \1 .. \9; the flag (?i) at the start of the pattern.
  Characters are code points of UTF-8 (a stray byte is itself). \d is 0-9, \w is a word character of TveLayout.IsWordCp, \s is a blank, a line end or U+00A0.

  Exec looks for the first match that starts at or after an index; Caps[0..1] are the start and the end (exclusive) byte indexes (1-based, the end is the index after the
  match) of the whole match, Caps[2k..2k+1] those of the group k; -1 where the group did not take part. }
unit TveRegex;

{$I tvdefs.inc}

interface

const
  MaxGroups = 9;

type
  TByteSet = array[0..255] of Boolean;
  TCaps = array[0..2 * (MaxGroups + 1) - 1] of Integer;

  TRange = record
    Lo, Hi: LongWord;
  end;

  TCharClass = record
    Ranges: array of TRange;
    Negate: Boolean;
    Word, NotWord, Space, NotSpace, Digit, NotDigit: Boolean;      { the shorthands that are in the class }
  end;

  TOp = (opChar, opAny, opClass, opSplit, opJmp, opSave, opBol, opEol, opWordB, opNotWordB, opBegin, opEnd, opBackRef, opMark, opProgress, opMatch);

  TInst = record
    Op: TOp;
    X, Y: Integer;                  { char / class index / targets / slot }
  end;

  { The tree of a pattern }
  TNodeKind = (nkEmpty, nkChar, nkAny, nkClass, nkSeq, nkAlt, nkGroup, nkRepeat, nkBol, nkEol, nkBegin, nkEnd, nkWordB, nkNotWordB, nkBackRef);

  TNode = record
    Kind: TNodeKind;
    Value: Integer;                 { a code point, a class index, a group number (-1: none), a back reference }
    Min, Max: Integer;             { of a repeat; Max = -1: no limit }
    Greedy: Boolean;
    Kids: array of Integer;
  end;

  TTveRegex = class
  private
    FProg: array of TInst;
    FCount: Integer;
    FNodes: array of TNode;
    FClasses: array of TCharClass;
    FGroups: Integer;
    FMarks: Integer;
    FIgnoreCase: Boolean;
    FError: AnsiString;
    FAborted: Boolean;
    FPat: AnsiString;
    FPos: Integer;
    FSteps: Int64;
    FLiteral: AnsiString;           { the pattern is a plain text (first-character shortcut) }
    FRoot: Integer;
    function FirstOf(N: Integer; var B: TByteSet): Boolean;
    function Emit(Op: TOp; X: Integer = 0; Y: Integer = 0): Integer;
    function NewNode(K: TNodeKind; Value: Integer = 0): Integer;
    function ParseAlt: Integer;
    function ParseSeq: Integer;
    function ParseAtom: Integer;
    function ParseClass: Integer;
    function ReadEscape(out CP: LongWord; out Shorthand: Char): Boolean;
    function CanBeEmpty(N: Integer): Boolean;
    procedure Compile(N: Integer);
    procedure SetError(const Msg: AnsiString);
    function MatchesClass(const C: TCharClass; CP: LongWord): Boolean;
    function RunAt(const S: AnsiString; Start: Integer; var Caps: TCaps): Boolean;
  public
    constructor Create(const Pattern: AnsiString; IgnoreCase: Boolean = False);
    property Error: AnsiString read FError;
    property Groups: Integer read FGroups;
    property Aborted: Boolean read FAborted;
    { The first match at or after StartIdx (1-based). }
    { The bytes that a match can start with; False when any byte can (or the pattern can match the empty text). }
    function FirstBytes(out B: TByteSet): Boolean;
    function Exec(const S: AnsiString; StartIdx: Integer; out Caps: TCaps): Boolean;
    { A match that starts exactly at StartIdx. }
    function ExecAt(const S: AnsiString; StartIdx: Integer; out Caps: TCaps): Boolean;
    { The replacement text with \0..\9, $0..$9, $&, \n \t \\ \$ expanded }
    function Expand(const Repl, S: AnsiString; const Caps: TCaps): AnsiString;
  end;

{ A text as a pattern that matches it literally }
function RegexEscape(const S: AnsiString): AnsiString;

implementation

uses
  SysUtils, TvUtf8, TveLayout, TvUStr;

const
  StepLimit = 20000000;

function RegexEscape(const S: AnsiString): AnsiString;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    if S[I] in ['\', '.', '*', '+', '?', '(', ')', '[', ']', '{', '}', '|', '^', '$'] then
      Result := Result + '\';
    if S[I] = #10 then
      Result := Result + '\n'
    else if S[I] = #9 then
      Result := Result + '\t'
    else
      Result := Result + S[I];
  end;
end;

{ --- code points of the subject --- }

function NextCp(const S: AnsiString; Idx: Integer; out CP: LongWord): Integer; inline;
var
  Used: Integer;
begin
  if Idx > Length(S) then
  begin
    CP := 0;
    Exit(0);
  end;
  if Byte(S[Idx]) < $80 then
  begin
    CP := Byte(S[Idx]);
    Exit(1);
  end;
  if Utf8Decode(@S[Idx], Length(S) + 1 - Idx, CP, Used) and (Used >= 2) then
    Exit(Used);
  CP := Byte(S[Idx]);
  Result := 1;
end;

function PrevCp(const S: AnsiString; Idx: Integer; out CP: LongWord): Integer;
var
  K: Integer;
begin
  if Idx <= 1 then
  begin
    CP := 0;
    Exit(0);
  end;
  K := 1;
  while (K < 4) and (Idx - K > 1) and ((Byte(S[Idx - K]) and $C0) = $80) do
    Inc(K);
  if NextCp(S, Idx - K, CP) = K then
    Result := K
  else
  begin
    CP := Byte(S[Idx - 1]);
    Result := 1;
  end;
end;

function FoldCp(CP: LongWord): LongWord; inline;
begin
  Result := CpLower(CP);
end;

function IsSpaceCp(CP: LongWord): Boolean;
begin
  Result := (CP = 32) or ((CP >= 9) and (CP <= 13)) or (CP = $A0);
end;

function IsWordAt(const S: AnsiString; Idx: Integer; Before: Boolean): Boolean;
var
  CP: LongWord;
begin
  if Before then
  begin
    if PrevCp(S, Idx, CP) = 0 then Exit(False);
  end
  else if NextCp(S, Idx, CP) = 0 then
    Exit(False);
  Result := IsWordCp(CP);
end;

{ --- the parser: the pattern becomes a tree --- }

constructor TTveRegex.Create(const Pattern: AnsiString; IgnoreCase: Boolean);
var
  I, Root: Integer;
  Plain: Boolean;
begin
  inherited Create;
  FPat := Pattern;
  FIgnoreCase := IgnoreCase;
  FPos := 1;
  if Copy(FPat, 1, 4) = '(?i)' then
  begin
    FIgnoreCase := True;
    FPos := 5;
  end;
  Root := ParseAlt;
  FRoot := Root;
  if (FError = '') and (FPos <= Length(FPat)) then
    SetError('unmatched )');
  if FError = '' then
  begin
    Emit(opSave, 0);
    Compile(Root);
    Emit(opSave, 1);
    Emit(opMatch);
  end;
  Plain := FError = '';
  for I := 1 to Length(Pattern) do
    if Pattern[I] in ['\', '.', '*', '+', '?', '(', ')', '[', '{', '|', '^', '$'] then
      Plain := False;
  if Plain and not FIgnoreCase then
    FLiteral := Pattern;
end;

procedure TTveRegex.SetError(const Msg: AnsiString);
begin
  if FError = '' then
    FError := Msg;
end;

function TTveRegex.Emit(Op: TOp; X, Y: Integer): Integer;
begin
  if FCount = Length(FProg) then
    SetLength(FProg, FCount * 2 + 16);
  if FCount > 200000 then
  begin
    SetError('the pattern is too big');
    Exit(0);
  end;
  FProg[FCount].Op := Op;
  FProg[FCount].X := X;
  FProg[FCount].Y := Y;
  Result := FCount;
  Inc(FCount);
end;

function TTveRegex.NewNode(K: TNodeKind; Value: Integer): Integer;
begin
  SetLength(FNodes, Length(FNodes) + 1);
  Result := High(FNodes);
  FNodes[Result].Kind := K;
  FNodes[Result].Value := Value;
  FNodes[Result].Min := 1;
  FNodes[Result].Max := 1;
  FNodes[Result].Greedy := True;
  FNodes[Result].Kids := nil;
end;

function HexVal(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - 48;
    'a'..'f': Result := Ord(C) - 87;
    'A'..'F': Result := Ord(C) - 55;
  else
    Result := -1;
  end;
end;

{ After the backslash at FPos: a code point, or a shorthand letter (dDwWsS) }
function TTveRegex.ReadEscape(out CP: LongWord; out Shorthand: Char): Boolean;
var
  C: Char;
  V, K: Integer;
begin
  Shorthand := #0;
  CP := 0;
  Result := True;
  Inc(FPos);
  if FPos > Length(FPat) then
  begin
    SetError('a backslash at the end');
    Exit(False);
  end;
  C := FPat[FPos];
  Inc(FPos);
  case C of
    'n': CP := 10;
    't': CP := 9;
    'r': CP := 13;
    'f': CP := 12;
    'v': CP := 11;
    'e': CP := 27;
    'a': CP := 7;
    '0': CP := 0;
    'd', 'D', 'w', 'W', 's', 'S': Shorthand := C;
    'x':
      if (FPos <= Length(FPat)) and (FPat[FPos] = '{') then
      begin
        Inc(FPos);
        while (FPos <= Length(FPat)) and (FPat[FPos] <> '}') do
        begin
          V := HexVal(FPat[FPos]);
          if V < 0 then
          begin
            SetError('bad \x{}');
            Exit(False);
          end;
          CP := CP * 16 + LongWord(V);
          Inc(FPos);
        end;
        Inc(FPos);
      end
      else
        for K := 1 to 2 do
          if (FPos <= Length(FPat)) and (HexVal(FPat[FPos]) >= 0) then
          begin
            CP := CP * 16 + LongWord(HexVal(FPat[FPos]));
            Inc(FPos);
          end;
    'u':
      for K := 1 to 4 do
        if (FPos <= Length(FPat)) and (HexVal(FPat[FPos]) >= 0) then
        begin
          CP := CP * 16 + LongWord(HexVal(FPat[FPos]));
          Inc(FPos);
        end;
  else
    begin
      Dec(FPos);
      K := NextCp(FPat, FPos, CP);
      Inc(FPos, K);
    end;
  end;
end;

function TTveRegex.ParseClass: Integer;
var
  Cls: TCharClass;
  CP, Hi: LongWord;
  Sh: Char;
  First: Boolean;
  Name: AnsiString;
  E, K: Integer;

  procedure AddRange(Lo, High_: LongWord);
  begin
    SetLength(Cls.Ranges, Length(Cls.Ranges) + 1);
    Cls.Ranges[High(Cls.Ranges)].Lo := Lo;
    Cls.Ranges[High(Cls.Ranges)].Hi := High_;
  end;

  procedure AddShorthand(Ch: Char);
  begin
    case Ch of
      'd': Cls.Digit := True;
      'D': Cls.NotDigit := True;
      'w': Cls.Word := True;
      'W': Cls.NotWord := True;
      's': Cls.Space := True;
      'S': Cls.NotSpace := True;
    end;
  end;

begin
  Result := NewNode(nkEmpty);
  Cls.Negate := False;
  Cls.Ranges := nil;
  Cls.Word := False; Cls.NotWord := False; Cls.Space := False; Cls.NotSpace := False; Cls.Digit := False; Cls.NotDigit := False;
  Inc(FPos);                                 { the [ }
  if (FPos <= Length(FPat)) and (FPat[FPos] = '^') then
  begin
    Cls.Negate := True;
    Inc(FPos);
  end;
  First := True;
  while True do
  begin
    if FPos > Length(FPat) then
    begin
      SetError('missing ]');
      Exit;
    end;
    if (FPat[FPos] = ']') and not First then
    begin
      Inc(FPos);
      Break;
    end;
    First := False;
    if (FPat[FPos] = '[') and (FPos < Length(FPat)) and (FPat[FPos + 1] = ':') then
    begin
      E := Pos(':]', Copy(FPat, FPos, MaxInt));
      if E > 0 then
      begin
        Name := Copy(FPat, FPos + 2, E - 3);
        Inc(FPos, E + 1);
        if Name = 'alpha' then begin AddRange(97, 122); AddRange(65, 90); AddRange($C0, $24F); AddRange($370, $52F); end
        else if Name = 'digit' then AddRange(48, 57)
        else if Name = 'alnum' then begin AddRange(97, 122); AddRange(65, 90); AddRange(48, 57); AddRange($C0, $24F); AddRange($370, $52F); end
        else if Name = 'upper' then begin AddRange(65, 90); AddRange($C0, $DE); AddRange($410, $42F); end
        else if Name = 'lower' then begin AddRange(97, 122); AddRange($DF, $FF); AddRange($430, $45F); end
        else if Name = 'space' then Cls.Space := True
        else if Name = 'word' then Cls.Word := True
        else if Name = 'punct' then begin AddRange(33, 47); AddRange(58, 64); AddRange(91, 96); AddRange(123, 126); end
        else
        begin
          SetError('unknown class [:' + Name + ':]');
          Exit;
        end;
        Continue;
      end;
    end;
    if FPat[FPos] = '\' then
    begin
      if not ReadEscape(CP, Sh) then
        Exit;
      if Sh <> #0 then
      begin
        AddShorthand(Sh);
        Continue;
      end;
    end
    else
    begin
      K := NextCp(FPat, FPos, CP);
      Inc(FPos, K);
    end;
    Hi := CP;
    if (FPos + 1 <= Length(FPat)) and (FPat[FPos] = '-') and (FPat[FPos + 1] <> ']') then
    begin
      Inc(FPos);
      if FPat[FPos] = '\' then
      begin
        if not ReadEscape(Hi, Sh) then
          Exit;
      end
      else
      begin
        K := NextCp(FPat, FPos, Hi);
        Inc(FPos, K);
      end;
      if Hi < CP then
      begin
        SetError('a range is backwards');
        Exit;
      end;
    end;
    AddRange(CP, Hi);
  end;
  SetLength(FClasses, Length(FClasses) + 1);
  FClasses[High(FClasses)] := Cls;
  FNodes[Result].Kind := nkClass;
  FNodes[Result].Value := High(FClasses);
end;

function TTveRegex.ParseAtom: Integer;
var
  Ch: Char;
  CP: LongWord;
  Sh: Char;
  K, G: Integer;
  Cls: TCharClass;
  Inner: Integer;
begin
  Ch := FPat[FPos];
  case Ch of
    '.':
      begin
        Inc(FPos);
        Result := NewNode(nkAny);
      end;
    '^': begin Inc(FPos); Result := NewNode(nkBol); end;
    '$': begin Inc(FPos); Result := NewNode(nkEol); end;
    '(':
      begin
        Inc(FPos);
        if (FPos + 1 <= Length(FPat)) and (FPat[FPos] = '?') and (FPat[FPos + 1] = ':') then
        begin
          Inc(FPos, 2);
          G := -1;
        end
        else
        begin
          if FGroups >= MaxGroups then
          begin
            SetError('too many groups');
            Exit(NewNode(nkEmpty));
          end;
          Inc(FGroups);
          G := FGroups;
        end;
        Inner := ParseAlt;
        if (FError = '') and ((FPos > Length(FPat)) or (FPat[FPos] <> ')')) then
          SetError('missing )')
        else
          Inc(FPos);
        Result := NewNode(nkGroup, G);
        SetLength(FNodes[Result].Kids, 1);
        FNodes[Result].Kids[0] := Inner;
      end;
    '[':
      Result := ParseClass;
    '\':
      begin
        if (FPos < Length(FPat)) and (FPat[FPos + 1] in ['1'..'9']) then
        begin
          Result := NewNode(nkBackRef, Ord(FPat[FPos + 1]) - 48);
          Inc(FPos, 2);
        end
        else if (FPos < Length(FPat)) and (FPat[FPos + 1] = 'b') then
        begin
          Inc(FPos, 2);
          Result := NewNode(nkWordB);
        end
        else if (FPos < Length(FPat)) and (FPat[FPos + 1] = 'B') then
        begin
          Inc(FPos, 2);
          Result := NewNode(nkNotWordB);
        end
        else if (FPos < Length(FPat)) and (FPat[FPos + 1] = 'A') then
        begin
          Inc(FPos, 2);
          Result := NewNode(nkBegin);
        end
        else if (FPos < Length(FPat)) and (FPat[FPos + 1] = 'z') then
        begin
          Inc(FPos, 2);
          Result := NewNode(nkEnd);
        end
        else
        begin
          if not ReadEscape(CP, Sh) then
            Exit(NewNode(nkEmpty));
          if Sh <> #0 then
          begin
            Cls.Negate := False;
            Cls.Ranges := nil;
            Cls.Word := False; Cls.NotWord := False; Cls.Space := False; Cls.NotSpace := False; Cls.Digit := False; Cls.NotDigit := False;
            case Sh of
              'd': Cls.Digit := True;
              'D': Cls.NotDigit := True;
              'w': Cls.Word := True;
              'W': Cls.NotWord := True;
              's': Cls.Space := True;
              'S': Cls.NotSpace := True;
            end;
            SetLength(FClasses, Length(FClasses) + 1);
            FClasses[High(FClasses)] := Cls;
            Result := NewNode(nkClass, High(FClasses));
          end
          else
            Result := NewNode(nkChar, Integer(CP));
        end;
      end;
    '*', '+', '?':
      begin
        SetError('nothing to repeat');
        Result := NewNode(nkEmpty);
      end;
  else
    begin
      K := NextCp(FPat, FPos, CP);
      Inc(FPos, K);
      Result := NewNode(nkChar, Integer(CP));
    end;
  end;
end;

function TTveRegex.ParseSeq: Integer;
var
  Atom, Rep, Mn, Mx, K, Save: Integer;
  Quant, Greedy: Boolean;
  Items: array of Integer;
begin
  Items := nil;
  while (FError = '') and (FPos <= Length(FPat)) and (FPat[FPos] <> '|') and (FPat[FPos] <> ')') do
  begin
    Atom := ParseAtom;
    if FError <> '' then
      Break;
    Quant := False;
    Mn := 1; Mx := 1; Greedy := True;
    if FPos <= Length(FPat) then
      case FPat[FPos] of
        '*': begin Mn := 0; Mx := -1; Quant := True; Inc(FPos); end;
        '+': begin Mn := 1; Mx := -1; Quant := True; Inc(FPos); end;
        '?': begin Mn := 0; Mx := 1; Quant := True; Inc(FPos); end;
        '{':
          begin
            Save := FPos;
            Inc(FPos);
            Mn := 0;
            K := 0;
            while (FPos <= Length(FPat)) and (FPat[FPos] in ['0'..'9']) do
            begin
              Mn := Mn * 10 + Ord(FPat[FPos]) - 48;
              if Mn > 1000 then Mn := 1000;
              Inc(FPos);
              Inc(K);
            end;
            if K > 0 then
            begin
              Mx := Mn;
              if (FPos <= Length(FPat)) and (FPat[FPos] = ',') then
              begin
                Inc(FPos);
                Mx := 0;
                K := 0;
                while (FPos <= Length(FPat)) and (FPat[FPos] in ['0'..'9']) do
                begin
                  Mx := Mx * 10 + Ord(FPat[FPos]) - 48;
                  if Mx > 1000 then Mx := 1000;
                  Inc(FPos);
                  Inc(K);
                end;
                if K = 0 then
                  Mx := -1;
              end;
              if (FPos <= Length(FPat)) and (FPat[FPos] = '}') then
              begin
                Inc(FPos);
                Quant := True;
              end;
            end;
            if not Quant then
            begin
              FPos := Save;                     { the opening brace starts no quantifier: it is the next atom, a plain character }
              Mn := 1;
              Mx := 1;
            end;
          end;
      end;
    if Quant then
    begin
      if FNodes[Atom].Kind in [nkBol, nkEol, nkBegin, nkEnd, nkWordB, nkNotWordB] then
      begin
        SetError('nothing to repeat');
        Break;
      end;
      if (FPos <= Length(FPat)) and (FPat[FPos] = '?') then
      begin
        Greedy := False;
        Inc(FPos);
      end;
      if (Mx >= 0) and (Mx < Mn) then
      begin
        SetError('bad repeat counts');
        Break;
      end;
      Rep := NewNode(nkRepeat);
      FNodes[Rep].Min := Mn;
      FNodes[Rep].Max := Mx;
      FNodes[Rep].Greedy := Greedy;
      SetLength(FNodes[Rep].Kids, 1);
      FNodes[Rep].Kids[0] := Atom;
      Atom := Rep;
    end;
    SetLength(Items, Length(Items) + 1);
    Items[High(Items)] := Atom;
  end;
  if Length(Items) = 1 then
    Exit(Items[0]);
  Result := NewNode(nkSeq);
  FNodes[Result].Kids := Items;
end;

function TTveRegex.ParseAlt: Integer;
var
  Branches: array of Integer;
begin
  Branches := nil;
  repeat
    SetLength(Branches, Length(Branches) + 1);
    Branches[High(Branches)] := ParseSeq;
    if (FError = '') and (FPos <= Length(FPat)) and (FPat[FPos] = '|') then
      Inc(FPos)
    else
      Break;
  until False;
  if Length(Branches) = 1 then
    Exit(Branches[0]);
  Result := NewNode(nkAlt);
  FNodes[Result].Kids := Branches;
end;

{ --- the compiler: the tree becomes the program --- }

function TTveRegex.CanBeEmpty(N: Integer): Boolean;
var
  I: Integer;
begin
  with FNodes[N] do
    case Kind of
      nkChar, nkAny, nkClass: Result := False;
      nkSeq:
        begin
          Result := True;
          for I := 0 to High(Kids) do
            if not CanBeEmpty(Kids[I]) then
              Exit(False);
        end;
      nkAlt:
        begin
          Result := False;
          for I := 0 to High(Kids) do
            if CanBeEmpty(Kids[I]) then
              Exit(True);
        end;
      nkGroup: Result := CanBeEmpty(Kids[0]);
      nkRepeat: Result := (Min = 0) or CanBeEmpty(Kids[0]);
    else
      Result := True;
    end;
end;

procedure TTveRegex.Compile(N: Integer);
var
  I, K, Split, Loop, Mark: Integer;
  Splits, Jumps: array of Integer;
begin
  if FError <> '' then
    Exit;
  case FNodes[N].Kind of
    nkEmpty: ;
    nkChar: Emit(opChar, FNodes[N].Value);
    nkAny: Emit(opAny);
    nkClass: Emit(opClass, FNodes[N].Value);
    nkBol: Emit(opBol);
    nkEol: Emit(opEol);
    nkBegin: Emit(opBegin);
    nkEnd: Emit(opEnd);
    nkWordB: Emit(opWordB);
    nkNotWordB: Emit(opNotWordB);
    nkBackRef: Emit(opBackRef, FNodes[N].Value);
    nkSeq:
      for I := 0 to High(FNodes[N].Kids) do
        Compile(FNodes[N].Kids[I]);
    nkAlt:
      begin
        Jumps := nil;
        for I := 0 to High(FNodes[N].Kids) do
        begin
          if I < High(FNodes[N].Kids) then
          begin
            Split := Emit(opSplit, 0, 0);
            FProg[Split].X := FCount;
            Compile(FNodes[N].Kids[I]);
            SetLength(Jumps, Length(Jumps) + 1);
            Jumps[High(Jumps)] := Emit(opJmp, 0);
            FProg[Split].Y := FCount;
          end
          else
            Compile(FNodes[N].Kids[I]);
        end;
        for I := 0 to High(Jumps) do
          FProg[Jumps[I]].X := FCount;
      end;
    nkGroup:
      begin
        if FNodes[N].Value >= 0 then
          Emit(opSave, 2 * FNodes[N].Value);
        Compile(FNodes[N].Kids[0]);
        if FNodes[N].Value >= 0 then
          Emit(opSave, 2 * FNodes[N].Value + 1);
      end;
    nkRepeat:
      begin
        for K := 1 to FNodes[N].Min do
          Compile(FNodes[N].Kids[0]);
        if FNodes[N].Max = -1 then
        begin
          Loop := Emit(opSplit, 0, 0);
          Mark := -1;
          if CanBeEmpty(FNodes[N].Kids[0]) then
          begin
            Mark := FMarks;
            Inc(FMarks);
            Emit(opMark, Mark);
          end;
          Compile(FNodes[N].Kids[0]);
          if Mark >= 0 then
            Emit(opProgress, Mark);
          Emit(opJmp, Loop);
          if FNodes[N].Greedy then
          begin
            FProg[Loop].X := Loop + 1;
            FProg[Loop].Y := FCount;
          end
          else
          begin
            FProg[Loop].X := FCount;
            FProg[Loop].Y := Loop + 1;
          end;
        end
        else
        begin
          Splits := nil;
          for K := FNodes[N].Min + 1 to FNodes[N].Max do
          begin
            SetLength(Splits, Length(Splits) + 1);
            Splits[High(Splits)] := Emit(opSplit, 0, 0);
            Compile(FNodes[N].Kids[0]);
          end;
          for I := 0 to High(Splits) do
            if FNodes[N].Greedy then
            begin
              FProg[Splits[I]].X := Splits[I] + 1;
              FProg[Splits[I]].Y := FCount;
            end
            else
            begin
              FProg[Splits[I]].X := FCount;
              FProg[Splits[I]].Y := Splits[I] + 1;
            end;
        end;
      end;
  end;
end;

function TTveRegex.MatchesClass(const C: TCharClass; CP: LongWord): Boolean;
var
  I: Integer;
  Hit: Boolean;
  F: LongWord;
begin
  Hit := False;
  for I := 0 to High(C.Ranges) do
    if (CP >= C.Ranges[I].Lo) and (CP <= C.Ranges[I].Hi) then
    begin
      Hit := True;
      Break;
    end;
  if (not Hit) and FIgnoreCase then
  begin
    F := FoldCp(CP);
    for I := 0 to High(C.Ranges) do
      if ((F >= C.Ranges[I].Lo) and (F <= C.Ranges[I].Hi)) or ((CpUpper(CP) >= C.Ranges[I].Lo) and (CpUpper(CP) <= C.Ranges[I].Hi)) then
      begin
        Hit := True;
        Break;
      end;
  end;
  if not Hit then
    Hit := (C.Word and IsWordCp(CP)) or (C.NotWord and not IsWordCp(CP)) or (C.Space and IsSpaceCp(CP)) or (C.NotSpace and not IsSpaceCp(CP)) or
           (C.Digit and (CP >= 48) and (CP <= 57)) or (C.NotDigit and not ((CP >= 48) and (CP <= 57)));
  Result := Hit <> C.Negate;
end;

{ --- the machine --- }

type
  TFrame = record
    Kind: Byte;                     { 0 branch (pc, pos), 1 restore a capture slot, 2 restore a mark }
    A, B: Integer;
  end;

function TTveRegex.RunAt(const S: AnsiString; Start: Integer; var Caps: TCaps): Boolean;
var
  Stack: array of TFrame;
  SP: Integer;
  PC, Pos, I, K, L: Integer;
  CP: LongWord;
  Marks: array of Integer;
  Inst: TInst;
  Ok: Boolean;
  Used: Integer;

  procedure Push(Kind: Byte; A, B: Integer);
  begin
    if SP = Length(Stack) then
      SetLength(Stack, SP * 2 + 64);
    Stack[SP].Kind := Kind;
    Stack[SP].A := A;
    Stack[SP].B := B;
    Inc(SP);
  end;

  { backtrack: pops until a branch; False when nothing is left }
  function Backtrack: Boolean;
  begin
    while SP > 0 do
    begin
      Dec(SP);
      case Stack[SP].Kind of
        0:
          begin
            PC := Stack[SP].A;
            Pos := Stack[SP].B;
            Exit(True);
          end;
        1: Caps[Stack[SP].A] := Stack[SP].B;
        2: Marks[Stack[SP].A] := Stack[SP].B;
      end;
    end;
    Result := False;
  end;

begin
  Result := False;
  SP := 0;
  Stack := nil;
  Marks := nil;
  SetLength(Marks, FMarks + 1);
  for I := 0 to High(Caps) do
    Caps[I] := -1;
  PC := 0;
  Pos := Start;
  while True do
  begin
    Inc(FSteps);
    if FSteps > StepLimit then
    begin
      FAborted := True;
      Exit(False);
    end;
    Inst := FProg[PC];
    Ok := True;
    case Inst.Op of
      opChar:
        begin
          L := NextCp(S, Pos, CP);
          if L = 0 then
            Ok := False
          else if FIgnoreCase then
            Ok := (CP = LongWord(Inst.X)) or (FoldCp(CP) = FoldCp(LongWord(Inst.X)))
          else
            Ok := CP = LongWord(Inst.X);
          if Ok then
          begin
            Inc(Pos, L);
            Inc(PC);
          end;
        end;
      opAny:
        begin
          L := NextCp(S, Pos, CP);
          Ok := (L > 0) and (CP <> 10);
          if Ok then
          begin
            Inc(Pos, L);
            Inc(PC);
          end;
        end;
      opClass:
        begin
          L := NextCp(S, Pos, CP);
          Ok := (L > 0) and MatchesClass(FClasses[Inst.X], CP);
          if Ok then
          begin
            Inc(Pos, L);
            Inc(PC);
          end;
        end;
      opSplit:
        begin
          Push(0, Inst.Y, Pos);
          PC := Inst.X;
        end;
      opJmp:
        PC := Inst.X;
      opSave:
        begin
          Push(1, Inst.X, Caps[Inst.X]);
          Caps[Inst.X] := Pos;
          Inc(PC);
        end;
      opBol:
        begin
          Ok := (Pos = 1) or (S[Pos - 1] = #10);
          if Ok then Inc(PC);
        end;
      opEol:
        begin
          Ok := (Pos > Length(S)) or (S[Pos] = #10);
          if Ok then Inc(PC);
        end;
      opBegin:
        begin
          Ok := Pos = 1;
          if Ok then Inc(PC);
        end;
      opEnd:
        begin
          Ok := Pos > Length(S);
          if Ok then Inc(PC);
        end;
      opWordB, opNotWordB:
        begin
          Ok := (IsWordAt(S, Pos, True) <> IsWordAt(S, Pos, False)) = (Inst.Op = opWordB);
          if Ok then Inc(PC);
        end;
      opBackRef:
        begin
          K := Caps[2 * Inst.X];
          L := Caps[2 * Inst.X + 1];
          if (K < 0) or (L < 0) then
            Ok := False
          else
          begin
            Used := L - K;
            if Pos + Used - 1 > Length(S) then
              Ok := False
            else if FIgnoreCase then
              Ok := TveLower(Copy(S, K, Used)) = TveLower(Copy(S, Pos, Used))
            else
              Ok := Copy(S, K, Used) = Copy(S, Pos, Used);
            if Ok then
            begin
              Inc(Pos, Used);
              Inc(PC);
            end;
          end;
        end;
      opMark:
        begin
          Push(2, Inst.X, Marks[Inst.X]);
          Marks[Inst.X] := Pos;
          Inc(PC);
        end;
      opProgress:
        begin
          Ok := Pos <> Marks[Inst.X];
          if Ok then Inc(PC);
        end;
      opMatch:
        Exit(True);
    end;
    if not Ok then
      if not Backtrack then
        Exit(False);
  end;
end;

function TTveRegex.Exec(const S: AnsiString; StartIdx: Integer; out Caps: TCaps): Boolean;
var
  I, L: Integer;
  CP: LongWord;
begin
  Result := False;
  FAborted := False;
  FSteps := 0;
  if FError <> '' then
    Exit;
  I := StartIdx;
  if I < 1 then I := 1;
  while I <= Length(S) + 1 do
  begin
    if FLiteral <> '' then
    begin
      { a plain text: jump to the next place where it starts }
      L := Pos(FLiteral, Copy(S, I, MaxInt));
      if L = 0 then
        Exit(False);
      Inc(I, L - 1);
    end;
    if RunAt(S, I, Caps) then
      Exit(True);
    if FAborted then
      Exit(False);
    if I > Length(S) then
      Break;
    L := NextCp(S, I, CP);
    if L = 0 then L := 1;
    Inc(I, L);
  end;
end;

function TTveRegex.FirstOf(N: Integer; var B: TByteSet): Boolean;
var
  I: Integer;
  Nullable: Boolean;
  CP: LongWord;
  Nd: TNode;
begin
  { returns True when the node can match the empty text }
  Nd := FNodes[N];
  Result := False;
  case Nd.Kind of
    nkEmpty, nkBol, nkEol, nkBegin, nkEnd, nkWordB, nkNotWordB:
      Result := True;
    nkChar:
      begin
        CP := Nd.Value;
        if CP < 128 then
        begin
          B[CP] := True;
          if FIgnoreCase then
          begin
            if Chr(CP) in ['a'..'z'] then B[CP - 32] := True;
            if Chr(CP) in ['A'..'Z'] then B[CP + 32] := True;
          end;
        end
        else if CP < $800 then
        begin
          B[$C0 or (CP shr 6)] := True;
          if FIgnoreCase then
            for I := $C0 to $DF do B[I] := True;
        end
        else if CP < $10000 then
        begin
          B[$E0 or (CP shr 12)] := True;
          if FIgnoreCase then
            for I := $E0 to $EF do B[I] := True;
        end
        else
          for I := $F0 to $F7 do B[I] := True;
        if (CP >= 128) and FIgnoreCase then
          for I := 128 to 255 do B[I] := True;
      end;
    nkAny:
      for I := 0 to 255 do
        if I <> 10 then B[I] := True;
    nkClass:
      begin
        for I := 0 to 127 do
          if MatchesClass(FClasses[Nd.Value], I) then
            B[I] := True
          else if FIgnoreCase and (Chr(I) in ['a'..'z']) and MatchesClass(FClasses[Nd.Value], I - 32) then
            B[I] := True
          else if FIgnoreCase and (Chr(I) in ['A'..'Z']) and MatchesClass(FClasses[Nd.Value], I + 32) then
            B[I] := True;
        for I := 128 to 255 do
          B[I] := True;
      end;
    nkBackRef:
      begin
        for I := 0 to 255 do B[I] := True;
        Result := True;
      end;
    nkSeq:
      begin
        Result := True;
        for I := 0 to High(Nd.Kids) do
          if not FirstOf(Nd.Kids[I], B) then
          begin
            Result := False;
            Break;
          end;
      end;
    nkAlt:
      begin
        Nullable := False;
        for I := 0 to High(Nd.Kids) do
          if FirstOf(Nd.Kids[I], B) then
            Nullable := True;
        Result := Nullable;
      end;
    nkGroup:
      Result := (Length(Nd.Kids) = 0) or FirstOf(Nd.Kids[0], B);
    nkRepeat:
      begin
        Result := FirstOf(Nd.Kids[0], B);
        if Nd.Min = 0 then Result := True;
      end;
  end;
end;

function TTveRegex.FirstBytes(out B: TByteSet): Boolean;
begin
  FillChar(B, SizeOf(B), 0);
  Result := False;
  if (FError <> '') or (Length(FNodes) = 0) then
    Exit;
  if FirstOf(FRoot, B) then
    Exit;
  Result := True;
end;

function TTveRegex.ExecAt(const S: AnsiString; StartIdx: Integer; out Caps: TCaps): Boolean;
begin
  FAborted := False;
  FSteps := 0;
  Result := (FError = '') and RunAt(S, StartIdx, Caps);
end;

function TTveRegex.Expand(const Repl, S: AnsiString; const Caps: TCaps): AnsiString;
var
  I, G: Integer;
  C: Char;
begin
  Result := '';
  I := 1;
  while I <= Length(Repl) do
  begin
    C := Repl[I];
    if (C = '\') and (I < Length(Repl)) then
    begin
      Inc(I);
      case Repl[I] of
        'n': Result := Result + #10;
        't': Result := Result + #9;
        'r': Result := Result + #13;
        '0'..'9':
          begin
            G := Ord(Repl[I]) - 48;
            if (2 * G + 1 <= High(Caps)) and (Caps[2 * G] >= 0) and (Caps[2 * G + 1] >= 0) then
              Result := Result + Copy(S, Caps[2 * G], Caps[2 * G + 1] - Caps[2 * G]);
          end;
      else
        Result := Result + Repl[I];
      end;
    end
    else if (C = '$') and (I < Length(Repl)) and (Repl[I + 1] in ['0'..'9', '&']) then
    begin
      Inc(I);
      if Repl[I] = '&' then
        G := 0
      else
        G := Ord(Repl[I]) - 48;
      if (Caps[2 * G] >= 0) and (Caps[2 * G + 1] >= 0) then
        Result := Result + Copy(S, Caps[2 * G], Caps[2 * G + 1] - Caps[2 * G]);
    end
    else
      Result := Result + C;
    Inc(I);
  end;
end;

end.
