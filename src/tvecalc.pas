{ TveCalc: arithmetic on a text, for "calculate the block" and the like.

  MIT.

  Numbers: 12, 3.5, .5, 1e-3, 0x1F, $1F, 0b101. Operators: + - * / % (remainder) ^ and ** (power, right to left), unary + -, parentheses, and the names pi and e.
  Functions: sqrt abs sin cos tan asin acos atan ln log (base 10) exp floor ceil round trunc sign min max (any number of arguments) hypot.
  Text that is not part of an expression is an error; a thousands separator or a unit is not understood. }
unit TveCalc;

{$I tvdefs.inc}

interface

{ False (and a message) if the text is no expression. }
function CalcExpression(const S: AnsiString; out Value: Double; out Err: AnsiString): Boolean;
{ A number as text: whole numbers without a dot, others with up to 12 significant digits and no trailing zeros. }
function CalcFormat(V: Double): AnsiString;
{ The numbers in the lines of a text added up: every line is an expression; empty lines are skipped. }
function CalcSum(const S: AnsiString; out Value: Double; out Err: AnsiString): Boolean;

implementation

uses
  SysUtils, Math;

type
  TParser = record
    S: AnsiString;
    P: Integer;
    Err: AnsiString;
  end;

procedure SkipBlanks(var R: TParser);
begin
  while (R.P <= Length(R.S)) and (R.S[R.P] in [' ', #9, #13, #10]) do
    Inc(R.P);
end;

function ParseExpr(var R: TParser): Double; forward;

function ParseNumber(var R: TParser): Double;
var
  Start, Base: Integer;
  V: Double;
  Digit: Integer;
  Txt: AnsiString;
  C: Char;
begin
  Start := R.P;
  Result := 0;
  if (R.P + 1 <= Length(R.S)) and (R.S[R.P] = '0') and (R.S[R.P + 1] in ['x', 'X', 'b', 'B']) then
  begin
    if R.S[R.P + 1] in ['x', 'X'] then Base := 16 else Base := 2;
    Inc(R.P, 2);
  end
  else if R.S[R.P] = '$' then
  begin
    Base := 16;
    Inc(R.P);
  end
  else
    Base := 10;
  if Base <> 10 then
  begin
    V := 0;
    Start := R.P;
    while R.P <= Length(R.S) do
    begin
      C := R.S[R.P];
      case C of
        '0'..'9': Digit := Ord(C) - 48;
        'a'..'f': Digit := Ord(C) - 87;
        'A'..'F': Digit := Ord(C) - 55;
      else
        Break;
      end;
      if Digit >= Base then
        Break;
      V := V * Base + Digit;
      Inc(R.P);
    end;
    if R.P = Start then
      R.Err := 'a number is expected';
    Exit(V);
  end;
  while (R.P <= Length(R.S)) and (R.S[R.P] in ['0'..'9']) do
    Inc(R.P);
  if (R.P <= Length(R.S)) and (R.S[R.P] = '.') then
  begin
    Inc(R.P);
    while (R.P <= Length(R.S)) and (R.S[R.P] in ['0'..'9']) do
      Inc(R.P);
  end;
  if (R.P <= Length(R.S)) and (R.S[R.P] in ['e', 'E']) and (R.P < Length(R.S)) and
     ((R.S[R.P + 1] in ['0'..'9']) or ((R.S[R.P + 1] in ['+', '-']) and (R.P + 1 < Length(R.S)) and (R.S[R.P + 2] in ['0'..'9']))) then
  begin
    Inc(R.P, 2);
    while (R.P <= Length(R.S)) and (R.S[R.P] in ['0'..'9']) do
      Inc(R.P);
  end;
  Txt := Copy(R.S, Start, R.P - Start);
  if (Txt = '') or (Txt = '.') then
  begin
    R.Err := 'a number is expected';
    Exit(0);
  end;
  if not TryStrToFloat(Txt, Result, DefaultFormatSettings) then
  begin
    if (Pos('.', Txt) > 0) then
    begin
      DefaultFormatSettings.DecimalSeparator := '.';
    end;
    R.Err := 'bad number ' + Txt;
  end;
end;

function ParsePrimary(var R: TParser): Double;
var
  Name: AnsiString;
  Args: array of Double;
  N: Integer;
  A: Double;
begin
  SkipBlanks(R);
  Result := 0;
  if R.P > Length(R.S) then
  begin
    R.Err := 'the expression ends too early';
    Exit;
  end;
  case R.S[R.P] of
    '(':
      begin
        Inc(R.P);
        Result := ParseExpr(R);
        SkipBlanks(R);
        if (R.Err = '') and ((R.P > Length(R.S)) or (R.S[R.P] <> ')')) then
          R.Err := 'a ) is missing'
        else
          Inc(R.P);
      end;
    '0'..'9', '.', '$':
      Result := ParseNumber(R);
    'a'..'z', 'A'..'Z', '_':
      begin
        Name := '';
        while (R.P <= Length(R.S)) and (R.S[R.P] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
        begin
          Name := Name + LowerCase(R.S[R.P]);
          Inc(R.P);
        end;
        SkipBlanks(R);
        if (R.P <= Length(R.S)) and (R.S[R.P] = '(') then
        begin
          Inc(R.P);
          Args := nil;
          SkipBlanks(R);
          if (R.P <= Length(R.S)) and (R.S[R.P] = ')') then
            Inc(R.P)
          else
            while R.Err = '' do
            begin
              SetLength(Args, Length(Args) + 1);
              Args[High(Args)] := ParseExpr(R);
              SkipBlanks(R);
              if (R.P <= Length(R.S)) and (R.S[R.P] = ',') then
                Inc(R.P)
              else if (R.P <= Length(R.S)) and (R.S[R.P] = ')') then
              begin
                Inc(R.P);
                Break;
              end
              else
                R.Err := 'a ) is missing';
            end;
          if R.Err <> '' then Exit(0);
          N := Length(Args);
          if (Name = 'min') or (Name = 'max') or (Name = 'hypot') then
          begin
            if N < 1 then begin R.Err := Name + ' needs arguments'; Exit(0); end;
            Result := Args[0];
            if Name = 'hypot' then
            begin
              Result := 0;
              for A in Args do Result := Result + A * A;
              Exit(Sqrt(Result));
            end;
            for A in Args do
              if Name = 'min' then begin if A < Result then Result := A; end
              else if A > Result then Result := A;
            Exit;
          end;
          if N <> 1 then
          begin
            R.Err := Name + ' takes one argument';
            Exit(0);
          end;
          A := Args[0];
          if Name = 'sqrt' then begin if A < 0 then R.Err := 'sqrt of a negative number' else Result := Sqrt(A); end
          else if Name = 'abs' then Result := Abs(A)
          else if Name = 'sin' then Result := Sin(A)
          else if Name = 'cos' then Result := Cos(A)
          else if Name = 'tan' then Result := Tan(A)
          else if Name = 'asin' then Result := ArcSin(A)
          else if Name = 'acos' then Result := ArcCos(A)
          else if Name = 'atan' then Result := ArcTan(A)
          else if Name = 'ln' then begin if A <= 0 then R.Err := 'ln of a non-positive number' else Result := Ln(A); end
          else if Name = 'log' then begin if A <= 0 then R.Err := 'log of a non-positive number' else Result := Ln(A) / Ln(10); end
          else if Name = 'exp' then Result := Exp(A)
          else if Name = 'floor' then Result := Floor(A)
          else if Name = 'ceil' then Result := Ceil(A)
          else if Name = 'round' then begin if A >= 0 then Result := Floor(A + 0.5) else Result := Ceil(A - 0.5); end
          else if Name = 'trunc' then Result := Trunc(A)
          else if Name = 'sign' then Result := Sign(A)
          else R.Err := 'unknown function ' + Name;
        end
        else if Name = 'pi' then Result := Pi
        else if Name = 'e' then Result := Exp(1)
        else R.Err := 'unknown name ' + Name;
      end;
  else
    R.Err := 'unexpected ' + R.S[R.P];
  end;
end;

function ParsePower(var R: TParser): Double; forward;

{ Power binds tighter than a minus before it: -3^2 is -9; an exponent can have a sign: 2^-1 }
function ParseUnary(var R: TParser): Double;
begin
  SkipBlanks(R);
  if (R.P <= Length(R.S)) and (R.S[R.P] = '-') then
  begin
    Inc(R.P);
    Exit(-ParseUnary(R));
  end;
  if (R.P <= Length(R.S)) and (R.S[R.P] = '+') then
  begin
    Inc(R.P);
    Exit(ParseUnary(R));
  end;
  Result := ParsePower(R);
end;

function ParsePower(var R: TParser): Double;
var
  Exp_: Double;
begin
  Result := ParsePrimary(R);
  SkipBlanks(R);
  if R.P > Length(R.S) then Exit;
  if (R.S[R.P] = '^') or ((R.S[R.P] = '*') and (R.P < Length(R.S)) and (R.S[R.P + 1] = '*')) then
  begin
    if R.S[R.P] = '^' then Inc(R.P) else Inc(R.P, 2);
    Exp_ := ParseUnary(R);                        { right to left }
    if R.Err = '' then
      Result := Power(Result, Exp_);
  end;
end;

function ParseTerm(var R: TParser): Double;
var
  Op: Char;
  B: Double;
begin
  Result := ParseUnary(R);
  while R.Err = '' do
  begin
    SkipBlanks(R);
    if R.P > Length(R.S) then Break;
    Op := R.S[R.P];
    if (Op = '*') and (R.P < Length(R.S)) and (R.S[R.P + 1] = '*') then
      Break;
    if not (Op in ['*', '/', '%']) then Break;
    Inc(R.P);
    B := ParseUnary(R);
    if R.Err <> '' then Break;
    case Op of
      '*': Result := Result * B;
      '/': if B = 0 then R.Err := 'division by zero' else Result := Result / B;
      '%': if B = 0 then R.Err := 'division by zero' else Result := Result - B * Int(Result / B);
    end;
  end;
end;

function ParseExpr(var R: TParser): Double;
var
  Op: Char;
  B: Double;
begin
  Result := ParseTerm(R);
  while R.Err = '' do
  begin
    SkipBlanks(R);
    if R.P > Length(R.S) then Break;
    Op := R.S[R.P];
    if not (Op in ['+', '-']) then Break;
    Inc(R.P);
    B := ParseTerm(R);
    if R.Err <> '' then Break;
    if Op = '+' then Result := Result + B else Result := Result - B;
  end;
end;

function CalcExpression(const S: AnsiString; out Value: Double; out Err: AnsiString): Boolean;
var
  R: TParser;
begin
  R.S := S;
  R.P := 1;
  R.Err := '';
  Value := 0;
  SkipBlanks(R);
  if R.P > Length(R.S) then
  begin
    Err := 'empty expression';
    Exit(False);
  end;
  Value := ParseExpr(R);
  SkipBlanks(R);
  if (R.Err = '') and (R.P <= Length(R.S)) then
    R.Err := 'unexpected ' + R.S[R.P];
  Err := R.Err;
  Result := R.Err = '';
end;

function CalcFormat(V: Double): AnsiString;
begin
  if IsNan(V) or IsInfinite(V) then
    Exit('NaN');
  if (Abs(V) < 1e15) and (Frac(V) = 0) then
    Exit(IntToStr(Round(V)));
  Result := FloatToStrF(V, ffGeneral, 12, 0, DefaultFormatSettings);
end;

function CalcSum(const S: AnsiString; out Value: Double; out Err: AnsiString): Boolean;
var
  I, Start: Integer;
  Line: AnsiString;
  V: Double;
begin
  Value := 0;
  Err := '';
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = #10) then
    begin
      Line := Trim(Copy(S, Start, I - Start));
      Start := I + 1;
      if Line = '' then
        Continue;
      if not CalcExpression(Line, V, Err) then
        Exit(False);
      Value := Value + V;
    end;
  Result := True;
end;

end.
