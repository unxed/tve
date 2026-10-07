// TveHl: syntax highlighting, driven by data.
//
// MIT.
//
// A language is a description (an INI text, see TveLang for the built-in ones) of its comments, strings, numbers, keywords. The highlighter colours one line at a time: it is given
// the state at the start of the line (inside a block comment? inside a string that goes on?) and gives the class of every byte of the line and the state at its end. The states
// of the line starts are cached; an edit in line N throws away the cache from N on, and the lines are coloured again only when someone asks for them.
//
// The description (all the keys are optional):
// [language]    name=Go   masks=*.go *.mod
// [syntax]      case=sensitive|insensitive
// line_comments=// #                 (separated by blanks)
// block_comments=/* */ (* *)         (pairs: start end start end ...)
// directive_blocks={$ }              (block comments that are compiler directives)
// nested_comments=0|1
// strings=" '                        (delimiters of strings that end at the end of the line, unless the line ends with the escape)
// raw_strings=`                      (no escapes; the string goes on over lines)
// escape=\                           (the escape character; none by default)
// doubled_quote_escape=0|1           (Pascal: '' is a quote inside a string)
// numbers=c|pascal|basic|none        (what a number looks like)
// preprocessor=#                     (a line that starts with this, after blanks, is a directive)
// identifier_chars=_$                (besides letters and digits)
// operators=+-*/<>=!&|^~%?:          (drawn as operators)
// hash_chars=1                       (Pascal #13 is a character)
// [keywords]    class1=words ...   class2=words ...   class3=words ...
// The classes of the keywords are drawn by the colours of "keyword", "type" and "builtin".
unit TveHl;

{$I tvdefs.inc}

interface

uses
  TveBuf, TveDoc;

const
  { the classes of the bytes of a line }
  hcNormal = 0;
  hcComment = 1;
  hcString = 2;
  hcNumber = 3;
  hcKeyword = 4;
  hcType = 5;
  hcBuiltin = 6;
  hcPreproc = 7;
  hcOperator = 8;
  hcEscape = 9;
  hcClassCount = 10;

type
  TByteClasses = array of Byte;
  TWordArray = array of AnsiString;

  TTveLanguage = class
  private
    FName: AnsiString;
    FMasks: AnsiString;
    FIgnoreCase: Boolean;
    FLineComments: array of AnsiString;
    FBlockStart, FBlockEnd: array of AnsiString;
    FBlockDirective: array of Boolean;
    FNested: Boolean;
    FStrings: AnsiString;
    FRawStrings: AnsiString;
    FEscape: Char;
    FDoubledQuote: Boolean;
    FNumbers: AnsiString;
    FPreprocessor: AnsiString;
    FIdentChars: AnsiString;
    FOperators: AnsiString;
    FHashChars: Boolean;
    FWords: array[1..3] of array of AnsiString;      { sorted, lower case when the language ignores case }
    function Lookup(const Word_: AnsiString): Integer;
  public
    constructor Create;
    { Fills the language from the text of a description; False (and Err) if it has no name or a bad part }
    function Load(const IniText: AnsiString; out Err: AnsiString): Boolean;
    function MatchesFile(const FileName: AnsiString): Boolean;
    property Name: AnsiString read FName;
    property Masks: AnsiString read FMasks;
  end;

  TTveHighlighter = class
  private
    FLang: TTveLanguage;
    FDoc: TTveDoc;
    FStates: array of LongInt;       { the state at the start of line I (valid for I <= FValid) }
    FValid: Int64;
    function StateAt(L: Int64): LongInt;
    procedure DocChange(Doc: TTveDoc; Offset, Removed, Inserted: Int64);
  public
    constructor Create(ADoc: TTveDoc; ALang: TTveLanguage);
    destructor Destroy; override;
    property Language: TTveLanguage read FLang;
    { The classes of the bytes of line L (0-based). }
    procedure ClassifyLine(L: Int64; out Cls: TByteClasses);
    { The classes of any text, with a start state; EndState is the state after it. For the tests and for text that is not in the document. }
    procedure Classify(const Text: AnsiString; StartState: LongInt; out Cls: TByteClasses; out EndState: LongInt);
    procedure Invalidate;
  end;

implementation

uses
  SysUtils, TvIni, TvWild, TvUStr;

constructor TTveLanguage.Create;
begin
  inherited Create;
  FEscape := #0;
  FNumbers := 'c';
end;

function SplitWords(const S: AnsiString): TWordArray;
var
  I, Start: Integer;
begin
  Result := nil;
  I := 1;
  while I <= Length(S) do
  begin
    while (I <= Length(S)) and (S[I] in [' ', #9]) do
      Inc(I);
    if I > Length(S) then
      Break;
    Start := I;
    while (I <= Length(S)) and not (S[I] in [' ', #9]) do
      Inc(I);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Copy(S, Start, I - Start);
  end;
end;

procedure SortStrings(var A: array of AnsiString);
var
  I, J: Integer;
  T: AnsiString;
begin
  for I := 1 to High(A) do
  begin
    T := A[I];
    J := I - 1;
    while (J >= 0) and (CompareStr(A[J], T) > 0) do
    begin
      A[J + 1] := A[J];
      Dec(J);
    end;
    A[J + 1] := T;
  end;
end;

function TTveLanguage.Load(const IniText: AnsiString; out Err: AnsiString): Boolean;
var
  Ini: TIniFile;
  W: TWordArray;
  I, K: Integer;
  S: AnsiString;
  Hex: Boolean;
begin
  Result := False;
  Err := '';
  Ini := TIniFile.Create('');
  try
    Ini.InlineComments := False;
    Ini.LoadFromText(IniText);
    FName := Ini.GetEntry('language', 'name', '');
    if FName = '' then
    begin
      Err := 'a language needs a name';
      Exit;
    end;
    FMasks := Ini.GetEntry('language', 'masks', '');
    FIgnoreCase := LowerCase(Ini.GetEntry('syntax', 'case', 'sensitive')) = 'insensitive';
    W := SplitWords(Ini.GetEntry('syntax', 'line_comments', ''));
    SetLength(FLineComments, Length(W));
    for I := 0 to High(W) do
      FLineComments[I] := W[I];
    S := Ini.GetEntry('syntax', 'block_comments', '');
    W := SplitWords(S);
    if Odd(Length(W)) then
    begin
      Err := 'block_comments needs pairs';
      Exit;
    end;
    SetLength(FBlockStart, Length(W) div 2);
    SetLength(FBlockEnd, Length(W) div 2);
    SetLength(FBlockDirective, Length(W) div 2);
    for I := 0 to Length(W) div 2 - 1 do
    begin
      FBlockStart[I] := W[2 * I];
      FBlockEnd[I] := W[2 * I + 1];
    end;
    W := SplitWords(Ini.GetEntry('syntax', 'directive_blocks', ''));
    for I := 0 to Length(W) div 2 - 1 do
    begin
      K := Length(FBlockStart);
      SetLength(FBlockStart, K + 1);
      SetLength(FBlockEnd, K + 1);
      SetLength(FBlockDirective, K + 1);
      FBlockStart[K] := W[2 * I];
      FBlockEnd[K] := W[2 * I + 1];
      FBlockDirective[K] := True;
    end;
    // the longer start first, so that the directive start is tried before the plain one
    for I := 1 to High(FBlockStart) do
      for K := I downto 1 do
        if Length(FBlockStart[K]) > Length(FBlockStart[K - 1]) then
        begin
          S := FBlockStart[K]; FBlockStart[K] := FBlockStart[K - 1]; FBlockStart[K - 1] := S;
          S := FBlockEnd[K]; FBlockEnd[K] := FBlockEnd[K - 1]; FBlockEnd[K - 1] := S;
          Hex := FBlockDirective[K]; FBlockDirective[K] := FBlockDirective[K - 1]; FBlockDirective[K - 1] := Hex;
        end;
    FNested := Ini.GetEntry('syntax', 'nested_comments', '0') = '1';
    FStrings := Ini.GetEntry('syntax', 'strings', '');
    FRawStrings := Ini.GetEntry('syntax', 'raw_strings', '');
    S := Ini.GetEntry('syntax', 'escape', '');
    if S <> '' then FEscape := S[1];
    FDoubledQuote := Ini.GetEntry('syntax', 'doubled_quote_escape', '0') = '1';
    FNumbers := LowerCase(Ini.GetEntry('syntax', 'numbers', 'c'));
    FPreprocessor := Ini.GetEntry('syntax', 'preprocessor', '');
    FIdentChars := Ini.GetEntry('syntax', 'identifier_chars', '_');
    FOperators := Ini.GetEntry('syntax', 'operators', '');
    FHashChars := Ini.GetEntry('syntax', 'hash_chars', '0') = '1';
    for I := 1 to 3 do
    begin
      W := SplitWords(Ini.GetEntry('keywords', 'class' + IntToStr(I), ''));
      SetLength(FWords[I], Length(W));
      for K := 0 to High(W) do
        if FIgnoreCase then
          FWords[I][K] := LowerCase(W[K])
        else
          FWords[I][K] := W[K];
      SortStrings(FWords[I]);
    end;
  finally
    Ini.Free;
  end;
  Result := True;
end;

function TTveLanguage.Lookup(const Word_: AnsiString): Integer;
var
  K, Lo, Hi, Mid, C: Integer;
  Key: AnsiString;
begin
  Result := 0;
  if FIgnoreCase then
    Key := LowerCase(Word_)
  else
    Key := Word_;
  for K := 1 to 3 do
  begin
    Lo := 0;
    Hi := High(FWords[K]);
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) shr 1;
      C := CompareStr(FWords[K][Mid], Key);
      if C = 0 then
        Exit(K)
      else if C < 0 then
        Lo := Mid + 1
      else
        Hi := Mid - 1;
    end;
  end;
end;

function TTveLanguage.MatchesFile(const FileName: AnsiString): Boolean;
begin
  Result := (FMasks <> '') and WildMatchList(ExtractFileName(FileName), StringReplace(Trim(FMasks), ' ', ';', [rfReplaceAll]));
end;

// --- the states ---
//   0 normal; 1 + K inside the block comment K (nesting depth in bits 16..); -K inside the raw string K

constructor TTveHighlighter.Create(ADoc: TTveDoc; ALang: TTveLanguage);
begin
  inherited Create;
  FDoc := ADoc;
  FLang := ALang;
  FValid := 0;
  SetLength(FStates, 1);
  FStates[0] := 0;
  if FDoc <> nil then
    FDoc.AddObserver(@DocChange);
end;

destructor TTveHighlighter.Destroy;
begin
  if FDoc <> nil then
    FDoc.RemoveObserver(@DocChange);
  inherited Destroy;
end;

procedure TTveHighlighter.Invalidate;
begin
  FValid := 0;
end;

procedure TTveHighlighter.DocChange(Doc: TTveDoc; Offset, Removed, Inserted: Int64);
var
  L: Int64;
begin
  L := Doc.Buffer.LineOfOffset(Offset);
  if L < FValid then
    FValid := L;
end;

function StartsAt(const S: AnsiString; I: Integer; const Pat: AnsiString): Boolean;
begin
  Result := (Pat <> '') and (I + Length(Pat) - 1 <= Length(S)) and (CompareByte(S[I], Pat[1], Length(Pat)) = 0);
end;

function IsIdentStart(C: Char; const Extra: AnsiString): Boolean;
begin
  Result := (C in ['a'..'z', 'A'..'Z']) or (Byte(C) >= $80) or (Pos(C, Extra) > 0);
end;

function IsIdentChar(C: Char; const Extra: AnsiString): Boolean;
begin
  Result := (C in ['a'..'z', 'A'..'Z', '0'..'9']) or (Byte(C) >= $80) or (Pos(C, Extra) > 0);
end;

procedure TTveHighlighter.Classify(const Text: AnsiString; StartState: LongInt; out Cls: TByteClasses; out EndState: LongInt);
var
  I, N, K, J, Depth, Which: Integer;
  State: LongInt;
  Q: Char;
  Word_: AnsiString;
  Hex, Found: Boolean;
  Lang: TTveLanguage;
  AtLineStart: Boolean;

  procedure Fill(From, To_: Integer; C: Byte);
  var
    X: Integer;
  begin
    for X := From to To_ do
      if (X >= 1) and (X <= N) then
        Cls[X - 1] := C;
  end;

begin
  Lang := FLang;
  N := Length(Text);
  SetLength(Cls, N);
  if N > 0 then
    FillChar(Cls[0], N, hcNormal);
  State := StartState;
  I := 1;
  AtLineStart := True;
  while I <= N do
  begin
    { inside a block comment }
    if State > 0 then
    begin
      Which := (State and $FFFF) - 1;
      Depth := State shr 16;
      J := I;
      Found := False;
      while J <= N do
      begin
        if StartsAt(Text, J, Lang.FBlockEnd[Which]) then
        begin
          Inc(J, Length(Lang.FBlockEnd[Which]));
          Dec(Depth);
          if (Depth <= 0) or not Lang.FNested then
          begin
            Found := True;
            Break;
          end;
          Continue;
        end;
        if Lang.FNested and StartsAt(Text, J, Lang.FBlockStart[Which]) then
        begin
          Inc(Depth);
          Inc(J, Length(Lang.FBlockStart[Which]));
          Continue;
        end;
        Inc(J);
      end;
      if Lang.FBlockDirective[Which] then
        Fill(I, J - 1, hcPreproc)
      else
        Fill(I, J - 1, hcComment);
      I := J;
      if Found then
        State := 0
      else
        State := (Which + 1) or (Depth shl 16);
      Continue;
    end;
    { inside a raw string }
    if State < 0 then
    begin
      Q := Lang.FRawStrings[-State];
      J := I;
      while (J <= N) and (Text[J] <> Q) do
        Inc(J);
      if J <= N then
      begin
        Fill(I, J, hcString);
        I := J + 1;
        State := 0;
      end
      else
      begin
        Fill(I, N, hcString);
        I := N + 1;
      end;
      Continue;
    end;
    { blanks }
    if Text[I] in [' ', #9] then
    begin
      Inc(I);
      Continue;
    end;
    { a directive line }
    if AtLineStart and (Lang.FPreprocessor <> '') and StartsAt(Text, I, Lang.FPreprocessor) then
    begin
      Fill(I, N, hcPreproc);
      I := N + 1;
      Break;
    end;
    AtLineStart := False;
    { a line comment }
    Found := False;
    for K := 0 to High(Lang.FLineComments) do
      if StartsAt(Text, I, Lang.FLineComments[K]) then
      begin
        Fill(I, N, hcComment);
        I := N + 1;
        Found := True;
        Break;
      end;
    if Found then
      Break;
    { a block comment starts }
    for K := 0 to High(Lang.FBlockStart) do
      if StartsAt(Text, I, Lang.FBlockStart[K]) then
      begin
        State := (K + 1) or (1 shl 16);
        Found := True;
        if Lang.FBlockDirective[K] then
          Fill(I, I + Length(Lang.FBlockStart[K]) - 1, hcPreproc)
        else
          Fill(I, I + Length(Lang.FBlockStart[K]) - 1, hcComment);
        Inc(I, Length(Lang.FBlockStart[K]));
        Break;
      end;
    if Found then
      Continue;
    { a raw string }
    K := Pos(Text[I], Lang.FRawStrings);
    if K > 0 then
    begin
      Fill(I, I, hcString);
      Inc(I);
      State := -K;
      Continue;
    end;
    { a string }
    if (Pos(Text[I], Lang.FStrings) > 0) then
    begin
      Q := Text[I];
      J := I + 1;
      while J <= N do
      begin
        if (Lang.FEscape <> #0) and (Text[J] = Lang.FEscape) and (J < N) then
        begin
          Fill(J, J + 1, hcEscape);
          Inc(J, 2);
          Continue;
        end;
        if Text[J] = Q then
        begin
          if Lang.FDoubledQuote and (J < N) and (Text[J + 1] = Q) then
          begin
            Inc(J, 2);
            Continue;
          end;
          Break;
        end;
        Inc(J);
      end;
      { the characters that are escapes keep their class: fill the rest }
      K := I;
      while K <= J do
      begin
        if (K <= N) and (Cls[K - 1] <> hcEscape) then
          Cls[K - 1] := hcString;
        Inc(K);
      end;
      I := J + 1;
      Continue;
    end;
    { a Pascal character #13 }
    if Lang.FHashChars and (Text[I] = '#') then
    begin
      J := I + 1;
      if (J <= N) and (Text[J] = '$') then
        Inc(J);
      while (J <= N) and (Text[J] in ['0'..'9', 'a'..'f', 'A'..'F']) do
        Inc(J);
      Fill(I, J - 1, hcString);
      I := J;
      Continue;
    end;
    { a number }
    if (Lang.FNumbers <> 'none') and ((Text[I] in ['0'..'9']) or ((Text[I] = '.') and (I < N) and (Text[I + 1] in ['0'..'9']) and (Lang.FNumbers <> 'pascal')) or
       ((Lang.FNumbers = 'pascal') and (Text[I] = '$') and (I < N) and (Text[I + 1] in ['0'..'9', 'a'..'f', 'A'..'F']))) and
       ((I = 1) or not IsIdentChar(Text[I - 1], Lang.FIdentChars)) then
    begin
      J := I;
      Hex := False;
      if Text[J] = '$' then
      begin
        Hex := True;
        Inc(J);
      end
      else if (Text[J] = '0') and (J < N) and (Text[J + 1] in ['x', 'X', 'b', 'B', 'o', 'O']) and (Lang.FNumbers <> 'pascal') then
      begin
        Hex := True;
        Inc(J, 2);
      end;
      while (J <= N) and (Text[J] in ['0'..'9', 'a'..'f', 'A'..'F', '_']) and (Hex or (Text[J] in ['0'..'9', '_'])) do
        Inc(J);
      if not Hex then
      begin
        if (J <= N) and (Text[J] = '.') and (J < N) and (Text[J + 1] in ['0'..'9']) then
        begin
          Inc(J);
          while (J <= N) and (Text[J] in ['0'..'9', '_']) do
            Inc(J);
        end;
        if (J <= N) and (Text[J] in ['e', 'E']) and (J < N) and ((Text[J + 1] in ['0'..'9']) or ((Text[J + 1] in ['+', '-']) and (J + 1 < N) and (Text[J + 2] in ['0'..'9']))) then
        begin
          Inc(J, 2);
          while (J <= N) and (Text[J] in ['0'..'9']) do
            Inc(J);
        end;
        { suffixes of C: 10u 10L 1.5f }
        while (J <= N) and (Lang.FNumbers = 'c') and (Text[J] in ['u', 'U', 'l', 'L', 'f', 'F']) do
          Inc(J);
      end;
      Fill(I, J - 1, hcNumber);
      I := J;
      Continue;
    end;
    { a word }
    if IsIdentStart(Text[I], Lang.FIdentChars) then
    begin
      J := I;
      while (J <= N) and IsIdentChar(Text[J], Lang.FIdentChars) do
        Inc(J);
      Word_ := Copy(Text, I, J - I);
      case Lang.Lookup(Word_) of
        1: Fill(I, J - 1, hcKeyword);
        2: Fill(I, J - 1, hcType);
        3: Fill(I, J - 1, hcBuiltin);
      end;
      I := J;
      Continue;
    end;
    { an operator }
    if Pos(Text[I], Lang.FOperators) > 0 then
      Cls[I - 1] := hcOperator;
    Inc(I);
  end;
  EndState := State;
end;

function TTveHighlighter.StateAt(L: Int64): LongInt;
var
  K: Int64;
  Cls: TByteClasses;
  St: LongInt;
begin
  if L < 0 then L := 0;
  if L >= Length(FStates) then
    SetLength(FStates, L + 1024);
  if L > FValid then
  begin
    K := FValid;
    St := FStates[K];
    while K < L do
    begin
      Classify(FDoc.Buffer.LineText(K), St, Cls, St);
      Inc(K);
      if K >= Length(FStates) then
        SetLength(FStates, K + 1024);
      FStates[K] := St;
    end;
    FValid := L;
  end;
  Result := FStates[L];
end;

procedure TTveHighlighter.ClassifyLine(L: Int64; out Cls: TByteClasses);
var
  Dummy: LongInt;
begin
  Classify(FDoc.Buffer.LineText(L), StateAt(L), Cls, Dummy);
end;

end.
