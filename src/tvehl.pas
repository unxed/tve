// TveHl: syntax highlighting, driven by data, with languages inside languages.
//
// MIT.
//
// A language is a grammar: named contexts (modes), each a list of rules. A rule matches at the current position (a literal text or a regular expression) and says
// what the matched text is (a class, or one class for every group of the expression), and what happens to the stack of contexts: push a context, pop the top one,
// or switch the top one for another. The stack is what makes a language live inside another one: <script> pushes the JavaScript context, </script> pops it; a
// template language is an "inject" context whose rules are tried first in every context, so {$name} is found in HTML text, in a tag, in an attribute value, in
// CSS and in JavaScript alike.
//
// The state of the highlighter at the start of a line is the stack (and the "literal" flag); the states are numbered, the number of a line start is cached, an edit
// throws away the numbers from its line on, and the lines are coloured again only when someone asks for them.
//
// The text of a grammar, one directive per line ("#" at the start of a line: a comment):
//   language NAME
//   masks *.tpl *.html            (the file names that choose the language)
//   case sensitive | insensitive  (the default of the contexts that follow, for their words and literals; a regular expression has the flag i: /text/i)
//   start CONTEXT                 (the context at the start of the text)
//   inject CONTEXT ...            (the contexts whose rules are tried first everywhere, except in a context declared noinject)
//   ident CHARS                   (besides letters, digits and the bytes of non-ASCII characters, what an identifier is made of)
//   context NAME [noinject] [default CLASS] [eolpop] [nocase|case]
//     include CONTEXT             (the rules, words and so on of another context, here)
//     match PATTERN => CLASS... [push CTX] [pop] [switch CTX] [literal on|off] [always]
//     words CLASS WORD ...        (identifiers; the class of a word that no rule took)
//     number c | pascal           (what a number looks like)
//     ops CHARS                   (characters drawn as operators)
//   PATTERN is 'literal', "literal" (no escapes inside) or /regular expression/i. A regular expression can end with a look-ahead (?=...) or (?!...).
//   With one class the whole match has it; with a regular expression that has groups, the classes are those of the groups 1, 2, ... in turn (the text outside the
//   groups is normal). "eolpop": the context ends at the end of the line. "always": the rule of an inject context works in literal mode too.
unit TveHl;

{$I tvdefs.inc}
{$H+}

interface

uses
  TveBuf, TveDoc, TveRegex;

const
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
  hcTag = 10;
  hcAttr = 11;
  hcEntity = 12;
  hcVariable = 13;
  hcDelimiter = 14;
  hcFunction = 15;
  hcProperty = 16;
  hcSelector = 17;
  hcValue = 18;
  hcAsm = 19;
  hcSpecial = 20;
  hcClassCount = 21;

type
  TByteClasses = array of Byte;
  TWordArr = array of AnsiString;

  TRule = record
    Lit: AnsiString;                  // a literal (when Re = nil)
    Re, Look: TTveRegex;
    LookNeg: Boolean;
    NoCase: Boolean;
    Classes: array of Byte;
    PushName, SwitchName: AnsiString;
    Push, Switch: Integer;            // -1: none
    Pop: Boolean;
    LiteralSet: Integer;              // -1: none, 0: off, 1: on
    Always: Boolean;
    Injected: Boolean;
    IncludeName: AnsiString;          // a rule that only stands for the rules of a context
    First: TByteSet;
    AnyFirst: Boolean;
  end;
  TRuleList = array of TRule;

  TWordList = record
    Cls: Byte;
    NoCase: Boolean;
    Words: array of AnsiString;       // sorted
  end;
  TWordLists = array of TWordList;

  TContext = record
    Name: AnsiString;
    NoInject, EolPop, NoCase: Boolean;
    DefaultClass: Byte;
    Rules: TRuleList;                 // the own rules, with the includes still in them
    Words: TWordLists;
    NumStyle: AnsiString;
    Ops: AnsiString;
    // after linking
    All: TRuleList;                   // inject rules, then the own ones, includes expanded
    Cand: array[0..255] of array of Integer;
    AllWords: TWordLists;
    AllNum: AnsiString;
    AllOps: AnsiString;
  end;

  TTveLanguage = class
  private
    FName: AnsiString;
    FMasks: AnsiString;
    FIgnoreCase: Boolean;
    FIdent: AnsiString;
    FStart: Integer;
    FInject: array of Integer;
    FCtx: array of TContext;
    FStacks: array of AnsiString;      // the numbered states: a byte per context, and the literal flag at the end
    function CtxIndex(const Name: AnsiString): Integer;
    function AddCtx(const Name: AnsiString): Integer;
    function ParseRule(const Line: AnsiString; LineNo: Integer; CtxNoCase: Boolean; var R: TRule; out Err: AnsiString): Boolean;
    procedure Link(out Err: AnsiString);
    procedure Gather(CI, Depth: Integer; Inj: Boolean; var Rules: TRuleList; var W: TWordLists; var Num, Ops: AnsiString; var Err: AnsiString);
    procedure Clear;
    function WordClass(const C: TContext; const Word_: AnsiString): Integer;
    function Intern(const Key: AnsiString): LongInt;
  public
    constructor Create;
    destructor Destroy; override;
    // Fills the language from the text of a grammar; False (and Err) if it is wrong.
    function Load(const Text: AnsiString; out Err: AnsiString): Boolean;
    function MatchesFile(const FileName: AnsiString): Boolean;
    // The classes of the bytes of Text, from a state; EndState is the state after it. State 0 is the start of a text.
    procedure Classify(const Text: AnsiString; StartState: LongInt; out Cls: TByteClasses; out EndState: LongInt);
    property Name: AnsiString read FName;
    property Masks: AnsiString read FMasks;
  end;

  TTveHighlighter = class
  private
    FLang: TTveLanguage;
    FDoc: TTveDoc;
    FStates: array of LongInt;       // the state at the start of line I (valid for I <= FValid)
    FValid: Int64;
    function StateAt(L: Int64): LongInt;
    procedure DocChange(Doc: TTveDoc; Offset, Removed, Inserted: Int64);
  public
    constructor Create(ADoc: TTveDoc; ALang: TTveLanguage);
    destructor Destroy; override;
    property Language: TTveLanguage read FLang;
    // The classes of the bytes of line L (0-based).
    procedure ClassifyLine(L: Int64; out Cls: TByteClasses);
    procedure Classify(const Text: AnsiString; StartState: LongInt; out Cls: TByteClasses; out EndState: LongInt);
    procedure Invalidate;
  end;

function HlClassByName(const Name: AnsiString): Integer;     // -1: unknown
function HlClassName(C: Integer): AnsiString;

implementation

uses
  SysUtils, TvWild;

const
  ClassNames: array[0..hcClassCount - 1] of AnsiString = (
    'normal', 'comment', 'string', 'number', 'keyword', 'type', 'builtin', 'preproc', 'operator', 'escape', 'tag', 'attr',
    'entity', 'variable', 'delimiter', 'function', 'property', 'selector', 'value', 'asm', 'special');
  MaxDepth = 24;

function HlClassByName(const Name: AnsiString): Integer;
var
  I: Integer;
begin
  for I := 0 to hcClassCount - 1 do
    if SameText(ClassNames[I], Name) then
      Exit(I);
  Result := -1;
end;

function HlClassName(C: Integer): AnsiString;
begin
  if (C >= 0) and (C < hcClassCount) then
    Result := ClassNames[C]
  else
    Result := '';
end;

constructor TTveLanguage.Create;
begin
  inherited Create;
  FStart := 0;
  FIdent := '_';
end;

destructor TTveLanguage.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TTveLanguage.Clear;
var
  I, J: Integer;
begin
  for I := 0 to High(FCtx) do
  begin
    for J := 0 to High(FCtx[I].Rules) do
    begin
      FCtx[I].Rules[J].Re.Free;
      FCtx[I].Rules[J].Look.Free;
    end;
    FCtx[I].Rules := nil;
    FCtx[I].All := nil;
  end;
  FCtx := nil;
  FStacks := nil;
end;

function TTveLanguage.CtxIndex(const Name: AnsiString): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FCtx) do
    if SameText(FCtx[I].Name, Name) then
      Exit(I);
  Result := -1;
end;

function TTveLanguage.AddCtx(const Name: AnsiString): Integer;
begin
  Result := Length(FCtx);
  SetLength(FCtx, Result + 1);
  FCtx[Result].Name := Name;
  FCtx[Result].DefaultClass := hcNormal;
  FCtx[Result].NoCase := FIgnoreCase;
end;

function SplitWords(const S: AnsiString): TWordArr;
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

procedure SortWords(var A: array of AnsiString);
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

// Reads a pattern at P: 'text', "text" or /regex/flags. Kind: 'l' literal, 'r' regex.
function ReadPattern(const S: AnsiString; var P: Integer; out Kind: Char; out Pat: AnsiString; out NoCase: Boolean): Boolean;
var
  Q: Char;
  E: Integer;
begin
  Result := False;
  NoCase := False;
  Kind := 'l';
  Pat := '';
  while (P <= Length(S)) and (S[P] = ' ') do
    Inc(P);
  if P > Length(S) then
    Exit;
  Q := S[P];
  if Q in ['''', '"'] then
  begin
    E := P + 1;
    while (E <= Length(S)) and (S[E] <> Q) do
      Inc(E);
    if E > Length(S) then
      Exit;
    Kind := 'l';
    Pat := Copy(S, P + 1, E - P - 1);
    P := E + 1;
    Exit(True);
  end;
  if Q = '/' then
  begin
    E := P + 1;
    while (E <= Length(S)) and (S[E] <> '/') do
    begin
      if S[E] = '\' then
        Inc(E);
      Inc(E);
    end;
    if E > Length(S) then
      Exit;
    Kind := 'r';
    Pat := Copy(S, P + 1, E - P - 1);
    P := E + 1;
    while (P <= Length(S)) and (S[P] = 'i') do
    begin
      NoCase := True;
      Inc(P);
    end;
    Exit(True);
  end;
end;

// "... (?=X)" at the end of a regular expression: the look-ahead is cut off.
function SplitLook(var Pat: AnsiString; out Look: AnsiString; out Neg: Boolean): Boolean;
var
  I, Depth: Integer;
begin
  Result := False;
  Look := '';
  Neg := False;
  if (Length(Pat) < 5) or (Pat[Length(Pat)] <> ')') or ((Length(Pat) > 1) and (Pat[Length(Pat) - 1] = '\')) then
    Exit;
  Depth := 0;
  for I := Length(Pat) downto 1 do
  begin
    if (Pat[I] = ')') and ((I = 1) or (Pat[I - 1] <> '\')) then
      Inc(Depth)
    else if (Pat[I] = '(') and ((I = 1) or (Pat[I - 1] <> '\')) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        if (I + 2 <= Length(Pat)) and (Pat[I + 1] = '?') and (Pat[I + 2] in ['=', '!']) then
        begin
          Neg := Pat[I + 2] = '!';
          Look := Copy(Pat, I + 3, Length(Pat) - I - 3);
          Pat := Copy(Pat, 1, I - 1);
          Exit(True);
        end;
        Exit(False);
      end;
    end;
  end;
end;

function TTveLanguage.ParseRule(const Line: AnsiString; LineNo: Integer; CtxNoCase: Boolean; var R: TRule; out Err: AnsiString): Boolean;
var
  P, Arrow: Integer;
  Kind: Char;
  Pat, LookPat, Rest: AnsiString;
  NoCase, Neg: Boolean;
  T: TWordArr;
  I, C: Integer;
  Cls: array of Byte;
begin
  Result := False;
  Err := '';
  FillChar(R, SizeOf(R), 0);
  R.Push := -1;
  R.Switch := -1;
  R.LiteralSet := -1;
  P := 1;
  if not ReadPattern(Line, P, Kind, Pat, NoCase) then
  begin
    Err := 'line ' + IntToStr(LineNo) + ': a pattern was expected';
    Exit;
  end;
  Arrow := Pos('=>', Copy(Line, P, MaxInt));
  if Arrow = 0 then
    Rest := ''
  else
    Rest := Copy(Line, P + Arrow + 1, MaxInt);
  R.NoCase := NoCase or (CtxNoCase and (Kind = 'l'));
  if Kind = 'l' then
  begin
    if Pat = '' then
    begin
      Err := 'line ' + IntToStr(LineNo) + ': an empty literal';
      Exit;
    end;
    R.Lit := Pat;
    if R.NoCase then
      R.Lit := LowerCase(Pat);
    FillChar(R.First, SizeOf(R.First), 0);
    R.First[Byte(R.Lit[1])] := True;
    if R.NoCase then
      R.First[Byte(UpCase(R.Lit[1]))] := True;
  end
  else
  begin
    LookPat := '';
    Neg := False;
    if SplitLook(Pat, LookPat, Neg) then
    begin
      R.Look := TTveRegex.Create(LookPat, NoCase);
      R.LookNeg := Neg;
      if R.Look.Error <> '' then
      begin
        Err := 'line ' + IntToStr(LineNo) + ': ' + R.Look.Error;
        Exit;
      end;
    end;
    if Pat = '' then
      R.Re := TTveRegex.Create('(?:)', NoCase)
    else
      R.Re := TTveRegex.Create(Pat, NoCase);
    if R.Re.Error <> '' then
    begin
      Err := 'line ' + IntToStr(LineNo) + ': ' + R.Re.Error;
      Exit;
    end;
    R.AnyFirst := (Pat = '') or not R.Re.FirstBytes(R.First);
  end;
  T := SplitWords(Rest);
  Cls := nil;
  I := 0;
  while I < Length(T) do
  begin
    if SameText(T[I], 'pop') then
      R.Pop := True
    else if SameText(T[I], 'always') then
      R.Always := True
    else if SameText(T[I], 'push') and (I + 1 < Length(T)) then
    begin
      Inc(I);
      R.PushName := T[I];
    end
    else if SameText(T[I], 'switch') and (I + 1 < Length(T)) then
    begin
      Inc(I);
      R.SwitchName := T[I];
    end
    else if SameText(T[I], 'literal') and (I + 1 < Length(T)) then
    begin
      Inc(I);
      if SameText(T[I], 'on') then
        R.LiteralSet := 1
      else
        R.LiteralSet := 0;
    end
    else
    begin
      C := HlClassByName(T[I]);
      if C < 0 then
      begin
        Err := 'line ' + IntToStr(LineNo) + ': unknown word "' + T[I] + '"';
        Exit;
      end;
      SetLength(Cls, Length(Cls) + 1);
      Cls[High(Cls)] := C;
    end;
    Inc(I);
  end;
  SetLength(R.Classes, Length(Cls));
  for I := 0 to High(Cls) do
    R.Classes[I] := Cls[I];
  Result := True;
end;

function TTveLanguage.Load(const Text: AnsiString; out Err: AnsiString): Boolean;
var
  P, E, LineNo, Cur, I, Sp: Integer;
  Line, Key, Arg: AnsiString;
  T, InjNames: TWordArr;
  R: TRule;
  StartName: AnsiString;
  WL: TWordList;
  C: Integer;
begin
  Clear;
  Result := False;
  Err := '';
  FName := '';
  FMasks := '';
  FIgnoreCase := False;
  FIdent := '_';
  StartName := '';
  InjNames := nil;
  Cur := -1;
  LineNo := 0;
  P := 1;
  while P <= Length(Text) do
  begin
    E := P;
    while (E <= Length(Text)) and (Text[E] <> #10) do
      Inc(E);
    Line := Copy(Text, P, E - P);
    P := E + 1;
    Inc(LineNo);
    while (Line <> '') and (Line[Length(Line)] in [#13, ' ', #9]) do
      SetLength(Line, Length(Line) - 1);
    Line := TrimLeft(Line);
    if (Line = '') or (Line[1] = '#') then
      Continue;
    Sp := Pos(' ', Line);
    if Sp = 0 then
    begin
      Key := Line;
      Arg := '';
    end
    else
    begin
      Key := Copy(Line, 1, Sp - 1);
      Arg := TrimLeft(Copy(Line, Sp + 1, MaxInt));
    end;
    Key := LowerCase(Key);
    if Key = 'language' then
      FName := Arg
    else if Key = 'masks' then
      FMasks := Arg
    else if Key = 'case' then
      FIgnoreCase := SameText(Arg, 'insensitive')
    else if Key = 'start' then
      StartName := Arg
    else if Key = 'inject' then
      InjNames := SplitWords(Arg)
    else if Key = 'ident' then
      FIdent := Arg
    else if Key = 'context' then
    begin
      T := SplitWords(Arg);
      if Length(T) = 0 then
      begin
        Err := 'line ' + IntToStr(LineNo) + ': a context needs a name';
        Exit;
      end;
      Cur := AddCtx(T[0]);
      I := 1;
      while I < Length(T) do
      begin
        if SameText(T[I], 'noinject') then
          FCtx[Cur].NoInject := True
        else if SameText(T[I], 'nocase') then
          FCtx[Cur].NoCase := True
        else if SameText(T[I], 'case') then
          FCtx[Cur].NoCase := False
        else if SameText(T[I], 'eolpop') then
          FCtx[Cur].EolPop := True
        else if SameText(T[I], 'default') and (I + 1 < Length(T)) then
        begin
          Inc(I);
          C := HlClassByName(T[I]);
          if C < 0 then
          begin
            Err := 'line ' + IntToStr(LineNo) + ': unknown class "' + T[I] + '"';
            Exit;
          end;
          FCtx[Cur].DefaultClass := C;
        end
        else
        begin
          Err := 'line ' + IntToStr(LineNo) + ': unknown word "' + T[I] + '"';
          Exit;
        end;
        Inc(I);
      end;
    end
    else if Cur < 0 then
    begin
      Err := 'line ' + IntToStr(LineNo) + ': "' + Key + '" is outside of a context';
      Exit;
    end
    else if Key = 'include' then
    begin
      FillChar(R, SizeOf(R), 0);
      R.IncludeName := Arg;
      R.Push := -1;
      R.Switch := -1;
      R.LiteralSet := -1;
      SetLength(FCtx[Cur].Rules, Length(FCtx[Cur].Rules) + 1);
      FCtx[Cur].Rules[High(FCtx[Cur].Rules)] := R;
    end
    else if Key = 'match' then
    begin
      if not ParseRule(Arg, LineNo, FCtx[Cur].NoCase, R, Err) then
        Exit;
      SetLength(FCtx[Cur].Rules, Length(FCtx[Cur].Rules) + 1);
      FCtx[Cur].Rules[High(FCtx[Cur].Rules)] := R;
    end
    else if Key = 'words' then
    begin
      T := SplitWords(Arg);
      if Length(T) < 1 then
        Continue;
      C := HlClassByName(T[0]);
      if C < 0 then
      begin
        Err := 'line ' + IntToStr(LineNo) + ': unknown class "' + T[0] + '"';
        Exit;
      end;
      WL.Cls := C;
      WL.NoCase := FCtx[Cur].NoCase;
      SetLength(WL.Words, Length(T) - 1);
      for I := 1 to High(T) do
        if WL.NoCase then
          WL.Words[I - 1] := LowerCase(T[I])
        else
          WL.Words[I - 1] := T[I];
      SortWords(WL.Words);
      SetLength(FCtx[Cur].Words, Length(FCtx[Cur].Words) + 1);
      FCtx[Cur].Words[High(FCtx[Cur].Words)] := WL;
    end
    else if Key = 'number' then
      FCtx[Cur].NumStyle := LowerCase(Arg)
    else if Key = 'ops' then
      FCtx[Cur].Ops := Arg
    else
    begin
      Err := 'line ' + IntToStr(LineNo) + ': unknown directive "' + Key + '"';
      Exit;
    end;
  end;
  if FName = '' then
  begin
    Err := 'a language needs a name';
    Exit;
  end;
  if Length(FCtx) = 0 then
  begin
    Err := 'a language needs a context';
    Exit;
  end;
  if StartName = '' then
    FStart := 0
  else
  begin
    FStart := CtxIndex(StartName);
    if FStart < 0 then
    begin
      Err := 'the start context "' + StartName + '" does not exist';
      Exit;
    end;
  end;
  SetLength(FInject, 0);
  for I := 0 to High(InjNames) do
  begin
    C := CtxIndex(InjNames[I]);
    if C < 0 then
    begin
      Err := 'the inject context "' + InjNames[I] + '" does not exist';
      Exit;
    end;
    SetLength(FInject, Length(FInject) + 1);
    FInject[High(FInject)] := C;
  end;
  Link(Err);
  if Err <> '' then
    Exit;
  SetLength(FStacks, 1);
  FStacks[0] := Chr(FStart) + #0;
  Result := True;
end;

procedure TTveLanguage.Gather(CI, Depth: Integer; Inj: Boolean; var Rules: TRuleList; var W: TWordLists; var Num, Ops: AnsiString; var Err: AnsiString);
var
  J, K, Inc_: Integer;
  R: TRule;
begin
  if Depth > 8 then
  begin
    Err := 'includes are nested too deep (a cycle?) at "' + FCtx[CI].Name + '"';
    Exit;
  end;
  for J := 0 to High(FCtx[CI].Rules) do
  begin
    R := FCtx[CI].Rules[J];
    if R.IncludeName <> '' then
    begin
      Inc_ := CtxIndex(R.IncludeName);
      if Inc_ < 0 then
      begin
        Err := 'the included context "' + R.IncludeName + '" does not exist';
        Exit;
      end;
      Gather(Inc_, Depth + 1, Inj, Rules, W, Num, Ops, Err);
      if Err <> '' then
        Exit;
    end
    else
    begin
      R.Injected := Inj;
      SetLength(Rules, Length(Rules) + 1);
      Rules[High(Rules)] := R;
    end;
  end;
  for J := 0 to High(FCtx[CI].Words) do
  begin
    K := Length(W);
    SetLength(W, K + 1);
    W[K] := FCtx[CI].Words[J];
  end;
  if FCtx[CI].NumStyle <> '' then
    Num := FCtx[CI].NumStyle;
  Ops := Ops + FCtx[CI].Ops;
end;

procedure TTveLanguage.Link(out Err: AnsiString);
var
  I, J, B: Integer;
  Rules: TRuleList;
  W: TWordLists;
  Num, Ops: AnsiString;
begin
  Err := '';
  for I := 0 to High(FCtx) do
    for J := 0 to High(FCtx[I].Rules) do
    begin
      if FCtx[I].Rules[J].PushName <> '' then
      begin
        FCtx[I].Rules[J].Push := CtxIndex(FCtx[I].Rules[J].PushName);
        if FCtx[I].Rules[J].Push < 0 then
        begin
          Err := 'the context "' + FCtx[I].Rules[J].PushName + '" does not exist';
          Exit;
        end;
      end;
      if FCtx[I].Rules[J].SwitchName <> '' then
      begin
        FCtx[I].Rules[J].Switch := CtxIndex(FCtx[I].Rules[J].SwitchName);
        if FCtx[I].Rules[J].Switch < 0 then
        begin
          Err := 'the context "' + FCtx[I].Rules[J].SwitchName + '" does not exist';
          Exit;
        end;
      end;
    end;
  for I := 0 to High(FCtx) do
  begin
    Rules := nil;
    W := nil;
    Num := '';
    Ops := '';
    if not FCtx[I].NoInject then
      for J := 0 to High(FInject) do
        if FInject[J] <> I then
          Gather(FInject[J], 0, True, Rules, W, Num, Ops, Err);
    if Err <> '' then
      Exit;
    // the words, numbers and operators of the injected contexts do not count
    W := nil;
    Num := '';
    Ops := '';
    Gather(I, 0, False, Rules, W, Num, Ops, Err);
    if Err <> '' then
      Exit;
    FCtx[I].All := Rules;
    FCtx[I].AllWords := W;
    FCtx[I].AllNum := Num;
    FCtx[I].AllOps := Ops;
    for B := 0 to 255 do
      FCtx[I].Cand[B] := nil;
    for J := 0 to High(Rules) do
      for B := 0 to 255 do
        if ((Rules[J].Re <> nil) and Rules[J].AnyFirst) or Rules[J].First[B] then
        begin
          SetLength(FCtx[I].Cand[B], Length(FCtx[I].Cand[B]) + 1);
          FCtx[I].Cand[B][High(FCtx[I].Cand[B])] := J;
        end;
  end;
end;

function TTveLanguage.MatchesFile(const FileName: AnsiString): Boolean;
begin
  Result := (FMasks <> '') and WildMatchList(ExtractFileName(FileName), StringReplace(Trim(FMasks), ' ', ';', [rfReplaceAll]));
end;

function TTveLanguage.Intern(const Key: AnsiString): LongInt;
var
  I: Integer;
begin
  for I := 0 to High(FStacks) do
    if FStacks[I] = Key then
      Exit(I);
  Result := Length(FStacks);
  SetLength(FStacks, Result + 1);
  FStacks[Result] := Key;
end;

function IsIdStart(C: Char; const Extra: AnsiString): Boolean;
begin
  Result := (C in ['a'..'z', 'A'..'Z']) or (Byte(C) >= $80) or (Pos(C, Extra) > 0);
end;

function IsIdChar(C: Char; const Extra: AnsiString): Boolean;
begin
  Result := (C in ['a'..'z', 'A'..'Z', '0'..'9']) or (Byte(C) >= $80) or (Pos(C, Extra) > 0);
end;

function TTveLanguage.WordClass(const C: TContext; const Word_: AnsiString): Integer;
var
  K, Lo, Hi, Mid, D: Integer;
  Key: AnsiString;
begin
  Result := -1;
  for K := 0 to High(C.AllWords) do
  begin
    if C.AllWords[K].NoCase then
      Key := LowerCase(Word_)
    else
      Key := Word_;
    Lo := 0;
    Hi := High(C.AllWords[K].Words);
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) shr 1;
      D := CompareStr(C.AllWords[K].Words[Mid], Key);
      if D = 0 then
        Exit(C.AllWords[K].Cls)
      else if D < 0 then
        Lo := Mid + 1
      else
        Hi := Mid - 1;
    end;
  end;
end;

procedure TTveLanguage.Classify(const Text: AnsiString; StartState: LongInt; out Cls: TByteClasses; out EndState: LongInt);
var
  Stack: array[0..MaxDepth] of Byte;
  Depth: Integer;       // the index of the top
  LiteralMode: Boolean;
  N, Pos_, ZeroRun, K, J, RI, E, B, G, Len, Start: Integer;
  Key, Word_: AnsiString;
  Caps, LCaps: TCaps;
  Ctx: ^TContext;
  Found, Hex: Boolean;
  Rule: ^TRule;

  procedure Fill(From, To_: Integer; C: Byte);
  var
    X: Integer;
  begin
    for X := From to To_ do
      if (X >= 1) and (X <= N) then
        Cls[X - 1] := C;
  end;

  function LiteralAt(const R: TRule; At: Integer): Integer;
  var
    I: Integer;
  begin
    Result := 0;
    if At + Length(R.Lit) - 1 > N then
      Exit;
    if not R.NoCase then
    begin
      if CompareByte(Text[At], R.Lit[1], Length(R.Lit)) = 0 then
        Result := Length(R.Lit);
      Exit;
    end;
    for I := 1 to Length(R.Lit) do
      if LowerCase(Text[At + I - 1]) <> R.Lit[I] then
        Exit;
    Result := Length(R.Lit);
  end;

  function TryRule(var R: TRule; At: Integer; out EndAt: Integer): Boolean;
  var
    L: Integer;
  begin
    Result := False;
    EndAt := At;
    if R.Re = nil then
    begin
      L := LiteralAt(R, At);
      if L = 0 then
        Exit;
      EndAt := At + L;
    end
    else
    begin
      if not R.Re.ExecAt(Text, At, Caps) then
        Exit;
      EndAt := Caps[1];
    end;
    if R.Look <> nil then
    begin
      Result := R.Look.ExecAt(Text, EndAt, LCaps) <> R.LookNeg;
      Exit;
    end;
    Result := True;
  end;

  procedure ApplyClasses(var R: TRule; At, EndAt: Integer);
  var
    I: Integer;
  begin
    if Length(R.Classes) = 0 then
    begin
      Fill(At, EndAt - 1, hcNormal);
      Exit;
    end;
    if (Length(R.Classes) = 1) or (R.Re = nil) or (R.Re.Groups = 0) then
      Fill(At, EndAt - 1, R.Classes[0])
    else
    begin
      Fill(At, EndAt - 1, hcNormal);
      for I := 1 to R.Re.Groups do
        if (I <= Length(R.Classes)) and (Caps[2 * I] >= 0) then
          Fill(Caps[2 * I], Caps[2 * I + 1] - 1, R.Classes[I - 1]);
    end;
  end;

begin
  N := Length(Text);
  SetLength(Cls, N);
  if N > 0 then
    FillChar(Cls[0], N, hcNormal);
  if (StartState < 0) or (StartState > High(FStacks)) then
    StartState := 0;
  Key := FStacks[StartState];
  Depth := Length(Key) - 2;
  for K := 0 to Depth do
    Stack[K] := Byte(Key[K + 1]);
  LiteralMode := Key[Length(Key)] = #1;
  Pos_ := 1;
  ZeroRun := 0;
  while Pos_ <= N do
  begin
    Ctx := @FCtx[Stack[Depth]];
    B := Byte(Text[Pos_]);
    Found := False;
    for K := 0 to High(Ctx^.Cand[B]) do
    begin
      RI := Ctx^.Cand[B][K];
      Rule := @Ctx^.All[RI];
      if LiteralMode and Rule^.Injected and not Rule^.Always then
        Continue;
      if not TryRule(Rule^, Pos_, E) then
        Continue;
      if (E = Pos_) and (Rule^.Push < 0) and (Rule^.Switch < 0) and not Rule^.Pop and (Rule^.LiteralSet < 0) then
        Continue;
      if (E = Pos_) and (ZeroRun >= 8) then
        Continue;
      if E = Pos_ then
        Inc(ZeroRun)
      else
        ZeroRun := 0;
      ApplyClasses(Rule^, Pos_, E);
      if Rule^.LiteralSet >= 0 then
        LiteralMode := Rule^.LiteralSet = 1;
      if Rule^.Pop and (Depth > 0) then
        Dec(Depth);
      if Rule^.Switch >= 0 then
        Stack[Depth] := Rule^.Switch;
      if (Rule^.Push >= 0) and (Depth < MaxDepth) then
      begin
        Inc(Depth);
        Stack[Depth] := Rule^.Push;
      end;
      Pos_ := E;
      Found := True;
      Break;
    end;
    if Found then
      Continue;
    ZeroRun := 0;
    // identifiers and words
    if (Length(Ctx^.AllWords) > 0) and IsIdStart(Text[Pos_], FIdent) then
    begin
      Start := Pos_;
      while (Pos_ <= N) and IsIdChar(Text[Pos_], FIdent) do
        Inc(Pos_);
      Word_ := Copy(Text, Start, Pos_ - Start);
      G := WordClass(Ctx^, Word_);
      if G < 0 then
        G := Ctx^.DefaultClass;
      Fill(Start, Pos_ - 1, G);
      Continue;
    end;
    // numbers
    if (Ctx^.AllNum <> '') and ((Text[Pos_] in ['0'..'9']) or ((Ctx^.AllNum = 'pascal') and (Text[Pos_] = '$') and (Pos_ < N) and
       (Text[Pos_ + 1] in ['0'..'9', 'a'..'f', 'A'..'F']))) and ((Pos_ = 1) or not IsIdChar(Text[Pos_ - 1], FIdent)) then
    begin
      J := Pos_;
      Hex := False;
      if Text[J] = '$' then
      begin
        Hex := True;
        Inc(J);
      end
      else if (Text[J] = '0') and (J < N) and (Text[J + 1] in ['x', 'X', 'b', 'B', 'o', 'O']) and (Ctx^.AllNum <> 'pascal') then
      begin
        Hex := True;
        Inc(J, 2);
      end;
      while (J <= N) and (Text[J] in ['0'..'9', 'a'..'f', 'A'..'F', '_']) and (Hex or (Text[J] in ['0'..'9', '_'])) do
        Inc(J);
      if not Hex then
      begin
        if (J < N) and (Text[J] = '.') and (Text[J + 1] in ['0'..'9']) then
        begin
          Inc(J);
          while (J <= N) and (Text[J] in ['0'..'9', '_']) do
            Inc(J);
        end;
        if (J < N) and (Text[J] in ['e', 'E']) and ((Text[J + 1] in ['0'..'9']) or ((Text[J + 1] in ['+', '-']) and (J + 1 < N) and (Text[J + 2] in ['0'..'9']))) then
        begin
          Inc(J, 2);
          while (J <= N) and (Text[J] in ['0'..'9']) do
            Inc(J);
        end;
        while (J <= N) and (Ctx^.AllNum = 'c') and (Text[J] in ['u', 'U', 'l', 'L', 'f', 'F']) do
          Inc(J);
      end;
      Fill(Pos_, J - 1, hcNumber);
      Pos_ := J;
      Continue;
    end;
    // an operator, or the default class (a whole UTF-8 sequence together)
    if (Ctx^.AllOps <> '') and (Pos(Text[Pos_], Ctx^.AllOps) > 0) then
    begin
      Cls[Pos_ - 1] := hcOperator;
      Inc(Pos_);
      Continue;
    end;
    Len := 1;
    if B >= $C0 then
      while (Pos_ + Len <= N) and ((Byte(Text[Pos_ + Len]) and $C0) = $80) do
        Inc(Len);
    Fill(Pos_, Pos_ + Len - 1, Ctx^.DefaultClass);
    Inc(Pos_, Len);
  end;
  // a context that lasts to the end of the line
  while (Depth > 0) and FCtx[Stack[Depth]].EolPop do
    Dec(Depth);
  SetLength(Key, Depth + 2);
  for K := 0 to Depth do
    Key[K + 1] := Chr(Stack[K]);
  if LiteralMode then
    Key[Depth + 2] := #1
  else
    Key[Depth + 2] := #0;
  EndState := Intern(Key);
end;

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

procedure TTveHighlighter.Classify(const Text: AnsiString; StartState: LongInt; out Cls: TByteClasses; out EndState: LongInt);
begin
  FLang.Classify(Text, StartState, Cls, EndState);
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
      FLang.Classify(FDoc.Buffer.LineText(K), St, Cls, St);
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
  FLang.Classify(FDoc.Buffer.LineText(L), StateAt(L), Cls, Dummy);
end;

end.
