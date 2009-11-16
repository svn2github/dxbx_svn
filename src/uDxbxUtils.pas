(*
    This file is part of Dxbx - a XBox emulator written in Delphi (ported over from cxbx)
    Copyright (C) 2007 Shadow_tj and other members of the development team.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*)
unit uDxbxUtils;

interface

uses
  // Delphi
  Windows,
  SysUtils,
  Classes,
  // Dxbx
  uTypes;

const
  NUMBER_OF_THUNKS = 379;
  
  DXBX_CONSOLE_DEBUG_FILENAME = 'DxbxDebug.txt';
  DXBX_KERNEL_DEBUG_FILENAME = 'KrnlDebug.txt';
  
type
  EMU_STATE = (esNone, esFileOpen, esRunning);

  TDebugInfoType = (ditConsole, ditFile);
  EnumAutoConvert = (CONVERT_TO_MANUAL, CONVERT_TO_XBEPATH, CONVERT_TO_WINDOWSTEMP);

  TDebugMode = (dmNone, dmConsole, dmFile);

  TEntryProc = procedure();
  PEntryProc = ^TEntryProc;

  TSetXbePath = procedure(const Path: PAnsiChar); cdecl;

  TKernelThunkTable = packed array[0..NUMBER_OF_THUNKS - 1] of UIntPtr;
  PKernelThunkTable = ^TKernelThunkTable;

  TGetKernelThunkTable = function: PKernelThunkTable; cdecl;

  TLineCallback = function (aLinePtr: PAnsiChar; aLength: Integer; aData: Pointer): Boolean;

procedure SetFS(const aNewFS: WORD);
function GetFS(): WORD;
function GetTIBEntry(const aOffset: DWORD): Pointer;
function GetTIBEntryWord(const aOffset: DWORD): WORD;
function GetTIB(): Pointer;

procedure ScanPCharLines(const aPChar: PAnsiChar; const aLineCallback: TLineCallback; const aCallbackData: Pointer);

function ScanHexByte(aLine: PAnsiChar; var Value: Integer): Boolean;
function ScanHexWord(aLine: PAnsiChar; var Value: Integer): Boolean;
function ScanHexDWord(aLine: PAnsiChar; var Value: Integer): Boolean;

function Sscanf(const s: AnsiString; const fmt: AnsiString; const Pointers: array of Pointer): Integer;
function iif(aTest: Boolean; const aTrue, aFalse: Integer): Integer; overload;
function iif(aTest: Boolean; const aTrue, aFalse: string): string; overload;

function FindFiles(const aFolder, aFileMask: TFileName; aFileNames: TStrings): Integer;

function StartsWithText(const aString, aPrefix: string): Boolean;

procedure Swap(var aElement1, aElement2); overload;
function RoundUp(dwValue, dwMult: DWord): DWord;

function FixInvalidFilePath(const aFilePath: string): string;

function DebugModeToString(const aDebugMode: TDebugMode): string;

function IsValidHandle(const aHandle: LongWord): Boolean;
function IsValidLibraryHandle(const aHandle: LongWord): Boolean;

function GetLastErrorString: string;
function GetErrorString(const aError: DWord): string;

function PointerToString(const aPointer: Pointer): string;

implementation

{$STACKFRAMES OFF}

procedure SetFS(const aNewFS: WORD);
asm
  MOV FS, aNewFS
end;

function GetFS(): WORD;
asm
  XOR EAX, EAX
  MOV AX, FS
end;

function GetTIBEntry(const aOffset: DWORD): Pointer;
asm
  MOV EAX, FS:[aOffset]
end;

function GetTIBEntryWord(const aOffset: DWORD): WORD;
asm
  MOV AX, FS:[aOffset]
end;

function GetTIB(): Pointer;
begin
  Result := GetTIBEntry({FS_Self=}$18);
end;

{$STACKFRAMES ON}

function FixInvalidFilePath(const aFilePath: string): string;
var
  i: Integer;
begin
  Result := aFilePath;
  for i := 1 to Length(Result) do
  begin
    case AnsiChar(Result[i]) of
      #0..#31, #127:
        Result[i] := ' ';
      '/', '\':
        Result[i] := '_';
      ':':
        Result[i] := ';';
      '*':
        Result[i] := '�';
      '?':
        Result[i] := '�';
      '"':
        Result[i] := '�';
      '<':
        Result[i] := '�';
      '>':
        Result[i] := '�';
      '|':
        Result[i] := '�';
    end;
  end;
end;

procedure Swap(var aElement1, aElement2);
var
  Tmp: Pointer;
begin
  Tmp := Pointer(aElement1);
  Pointer(aElement1) := Pointer(aElement2);
  Pointer(aElement2) := Tmp;
end;

function RoundUp(dwValue, dwMult: DWord): DWord;
begin
  if dwMult = 0 then
    Result := dwValue
  else
    Result := dwValue - ((dwValue - 1) mod dwMult) + (dwMult - 1);
end;

function StartsWithText(const aString, aPrefix: string): Boolean;
begin
  Result := AnsiStrLIComp(PChar(aString), PChar(aPrefix), Length(aPrefix)) = 0;
end;

function FindFiles(const aFolder, aFileMask: TFileName; aFileNames: TStrings): Integer;
var
  Status: Integer;
  SearchRec: TSearchRec;
begin
  with aFileNames do
  begin
    BeginUpdate;
    try
      Clear;
      Status := FindFirst(IncludeTrailingPathDelimiter(aFolder) + aFileMask, faAnyFile, SearchRec);
      while Status = 0 do
      begin
        if (SearchRec.Attr and faDirectory) = 0 then
          Add(IncludeTrailingPathDelimiter(aFolder) + SearchRec.Name);

        Status := FindNext(SearchRec);
      end;

      FindClose(SearchRec);
    finally
      EndUpdate;
    end;

    Result := Count;
  end;
end;

function _ScanAndAddHexDigit(var Value: Integer; const aHexDigit: AnsiChar): Boolean;
begin
  Result := True;
  case aHexDigit of
    '0'..'9':
      Value := (Value * 16) + (Ord(aHexDigit) - Ord('0'));
    'A'..'F':
      Value := (Value * 16) + (Ord(aHexDigit) - Ord('A') + 10);
    'a'..'f':
      Value := (Value * 16) + (Ord(aHexDigit) - Ord('a') + 10);
  else
    Result := False;
  end;
end;

function _ScanHexDigits(aLine: PAnsiChar; var Value: Integer; Digits: Integer): Boolean;
begin
  Value := 0;
  while Digits > 0 do
  begin
    Result := _ScanAndAddHexDigit(Value, aLine^);
    if not Result then
      Exit;

    Inc(aLine);
    Dec(Digits);
  end;

  Result := True;
end;

function ScanHexByte(aLine: PAnsiChar; var Value: Integer): Boolean;
begin
  Result := _ScanHexDigits(aLine, Value, 2);
end;

function ScanHexWord(aLine: PAnsiChar; var Value: Integer): Boolean;
begin
  Result := _ScanHexDigits(aLine, Value, 4);
end;

function ScanHexDWord(aLine: PAnsiChar; var Value: Integer): Boolean;
begin
  Result := _ScanHexDigits(aLine, Value, 8);
end;

procedure ScanPCharLines(const aPChar: PAnsiChar; const aLineCallback: TLineCallback; const aCallbackData: Pointer);
var
  p1, p2: PAnsiChar;
begin
  // Scan Lines:
  p1 := aPChar;
  while p1^ > #0 do
  begin
    // Scan this line until end of line (#0..#13) :
    p2 := p1;
    while p2^ > #13 do
      Inc(p2);

    // Handle this line :
    if not aLineCallback(p1, {Length=}p2-p1, aCallbackData) then
      Exit;

    // Step over to the start of the next line :
    p1 := p2 + 1;
    while p1^ in [#10, #13] do
      Inc(p1);
  end;
end;

function Sscanf(const s: AnsiString; const fmt: AnsiString; const Pointers: array of Pointer): Integer;
var
  i, j, n, m: Integer;
  s1: AnsiString;
  L: LongInt;
  X: Extended;

  function GetInt: Integer;
  begin
    s1 := '';
    while (n <= Length(s)) and (s[n] = ' ') do
      Inc(n);

    while (n <= Length(s))
      and (s[n] in ['0'..'9', '+', '-']) do
    begin
      s1 := s1 + s[n];
      Inc(n);
    end;

    Result := Length(s1); 
  end; 

  function GetFloat: Integer; 
  begin 
    s1 := ''; 
    while (n <= Length(s)) and (s[n] = ' ') do
      Inc(n);

    while (s[n] in ['0'..'9', '+', '-', '.', 'e', 'E'])
      and (Length(s) >= n) do
    begin
      s1 := s1 + s[n];
      Inc(n);
    end;

    Result := Length(s1);
  end;

  function GetString: Integer;
  begin
    s1 := '';
    while (n <= Length(s)) and (s[n] = ' ') do
      Inc(n);

    while (n <= Length(s)) and (s[n] <> ' ') do
    begin
      s1 := s1 + s[n];
      Inc(n);
    end;

    Result := Length(s1);
  end;

  function ScanStr(c: AnsiChar): Boolean;
  begin
    while (n <= Length(s)) and (s[n] <> c) do
      Inc(n);

    Inc(n);

    if (n <= Length(s)) then
      Result := True
    else
      Result := False; 
  end; 

  function GetFmt: Integer; 
  begin 
    Result := -1; 

    while True do 
    begin
      while (m <= Length(fmt)) and (fmt[m] = ' ') do
        Inc(m);

      if m >= Length(fmt) then 
        Break;

      if fmt[m] = '%' then
      begin 
        Inc(m); 
        case fmt[m] of
          'd': Result := vtInteger;
          'f': Result := vtExtended;
          's': Result := vtString;
        end;

        Inc(m);
        Break;
      end;

      if (ScanStr(fmt[m]) = False) then
        Break;

      Inc(m);
    end; 
  end; 

begin 
  n := 1; 
  m := 1; 
  Result := 0; 

  for i := 0 to High(Pointers) do 
  begin 
    j := GetFmt; 

    case j of 
      vtInteger: 
        begin 
          if GetInt > 0 then 
          begin 
            L := StrToInt(string(s1));
            Move(L, Pointers[i]^, SizeOf(LongInt));
            Inc(Result);
          end
          else
            Break;
        end;

      vtExtended:
        begin
          if GetFloat > 0 then
          begin
            X := StrToFloat(string(s1));
            Move(X, Pointers[i]^, SizeOf(Extended));
            Inc(Result); 
          end 
          else 
            Break; 
        end; 

      vtString: 
        begin 
          if GetString > 0 then 
          begin 
            Move(s1, Pointers[i]^, Length(s1) + 1); 
            Inc(Result);
          end
          else
            Break;
        end;
    else
      Break;
    end;
  end;
end;

function iif(aTest: Boolean; const aTrue, aFalse: Integer): Integer; overload;
begin
  if aTest then
    Result := aTrue
  else
    Result := aFalse;
end;

function iif(aTest: Boolean; const aTrue, aFalse: string): string; overload;
begin
  if aTest then
    Result := aTrue
  else
    Result := aFalse;
end;

function PointerToString(const aPointer: Pointer): string;
begin
  Result := IntToHex(Integer(aPointer), 8);
end;

function DebugModeToString(const aDebugMode: TDebugMode): string;
begin
  case aDebugMode of
    dmNone: Result := 'DM_NONE';
    dmConsole: Result := 'DM_CONSOLE';
    dmFile: Result := 'DM_FILE';
  else
    Result := '?Unknown?';
  end;
end;

function IsValidHandle(const aHandle: LongWord): Boolean;
begin
  Result := (aHandle <> INVALID_HANDLE_VALUE);
end;

// (Safe)LoadLibrary returns 32 or greater on a succesfull call.
// See http://support.microsoft.com/kb/142814 for details.
function IsValidLibraryHandle(const aHandle: LongWord): Boolean;
begin
  Result := IsValidHandle(aHandle) and (aHandle >= 32);
end;

function GetLastErrorString: string;
begin
  Result := GetErrorString(GetLastError);
end;

function GetErrorString(const aError: DWord): string;
begin
  Result := SysErrorMessage(aError);
  if Result = '' then
    Result := 'No description for error #' + IntToStr(aError)
  else
    Result := Result + ' (#' + IntToStr(aError) + ')';
end;

end.

