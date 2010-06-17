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

unit uVertexBuffer;

{$INCLUDE Dxbx.inc}

interface

uses
  // Delphi
  Windows
  , SysUtils // Abort
  , StrUtils
  , Classes
  // Jedi Win32API
  , JwaWinType
  // DirectX
  , Direct3D
  , Direct3D8
  , D3DX8
  // Dxbx
  , uTypes // CLOCKS_PER_SEC, clock()
  , uLog
  , uEmu
  , uEmuXG
  , uState
  , uDxbxKrnlUtils
  , uResourceTracker
  , uEmuAlloc
  , uConvert
  , uVertexShader
  , uEmuD3D8Types
  , uEmuD3D8Utils;

const MAX_NBR_STREAMS = 16;

// Dxbx note :
// When _VertexPatchDesc is sized like Cxbx, all vertex drawing
// is corrupted (see mesh, light and texture demo's).
// However, the sizeof of _VertexPatchDesc is wrong this way!
// TODO -cDxbx :
// Either the layout has to be fixed (while keeping it's size)
// or the offending code must be fixed. For now keep this :
{.$ALIGN 1}

type _VertexPatchDesc = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    PrimitiveType: X_D3DPRIMITIVETYPE;
    dwVertexCount: DWORD;
    dwPrimitiveCount: DWORD;
    dwOffset: DWORD;
    // Data if Draw...UP call
    pVertexStreamZeroData: PVOID;
    uiVertexStreamZeroStride: UINT;
    // The current vertex shader, used to identify the streams
    hVertexShader: DWORD;
    procedure VertexPatchDesc();
  end; // size = 28 (as in Cxbx)
  VertexPatchDesc = _VertexPatchDesc;
  PVertexPatchDesc = ^VertexPatchDesc;

{.$ALIGN 4} // Restore 4-byte alignment

type _PATCHEDSTREAM = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    pOriginalStream: XTL_PIDirect3DVertexBuffer8;
    pPatchedStream: XTL_PIDirect3DVertexBuffer8;
    uiOrigStride: UINT;
    uiNewStride: UINT;
    bUsedCached: _bool;
  end; // size = 20 (as in Cxbx)
  PATCHEDSTREAM = _PATCHEDSTREAM;
  PPATCHEDSTREAM = ^PATCHEDSTREAM;

type _CACHEDSTREAM = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    uiCRC32: uint32;
    uiCheckFrequency: uint32;
    uiCacheHit: uint32;
    bIsUP: _bool;
    Stream: PATCHEDSTREAM;
    pStreamUP: Pvoid;            // Draw..UP (instead of pOriginalStream)
    uiLength: uint32;            // The length of the stream
    uiCount: uint32;             // CRC32 check count
    dwPrimitiveCount: uint32;
    lLastUsed: long;             // For cache removal purposes
  end; // size = 56 (as in Cxbx)
  CACHEDSTREAM = _CACHEDSTREAM;
  PCACHEDSTREAM = ^CACHEDSTREAM;

type VertexPatcher = object
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
  public
    procedure VertexPatcher;
    procedure _VertexPatcher;

    function Apply(pPatchDesc: PVertexPatchDesc; pbFatalError: P_bool): _bool;
    function Restore(): _bool;
    // Dumps the cache to the console
    procedure DumpCache();
  private
    m_uiNbrStreams: UINT;
    m_pStreams: array [0..MAX_NBR_STREAMS-1] of PATCHEDSTREAM;

    m_pNewVertexStreamZeroData: PVOID;

    m_bPatched: _bool;
    m_bAllocatedStreamZeroData: _bool;

    m_pDynamicPatch: PVERTEX_DYNAMIC_PATCH;
    // Returns the number of streams of a patch
    function GetNbrStreams(pPatchDesc: PVertexPatchDesc): UINT;
    // Caches a patched stream
    procedure CacheStream(pPatchDesc: PVertexPatchDesc; 
                          uiStream: UINT);
    // Frees a cached, patched stream
    procedure FreeCachedStream(pStream: Pvoid);
    // Tries to apply a previously patched stream from the cache
    function ApplyCachedStream(pPatchDesc: PVertexPatchDesc; 
                               uiStream: UINT; 
                               pbFatalError: P_bool): _bool;
    // Patches the types of the stream
    function PatchStream(pPatchDesc: PVertexPatchDesc; uiStream: UINT): _bool;
    // Normalize texture coordinates in FVF stream if needed
    function NormalizeTexCoords(pPatchDesc: PVertexPatchDesc; uiStream: UINT): _bool;
    // Patches the primitive of the stream
    function PatchPrimitive(pPatchDesc: PVertexPatchDesc; uiStream: UINT): _bool;
  end; // size = 336 (as in Cxbx)

// inline vertex buffer emulation
var g_pIVBVertexBuffer: PDWORD = nil;
var g_IVBPrimitiveType: X_D3DPRIMITIVETYPE = X_D3DPT_INVALID;
var g_IVBFVF: DWORD = 0;

type _D3DIVB = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    Position: TD3DXVECTOR3; // Position
    Rhw: FLOAT; // Rhw
    Blend1: FLOAT; // Blend1
    dwSpecular: DWORD; // Specular
    dwDiffuse: DWORD; // Diffuse
    Normal: TD3DXVECTOR3; // Normal
    TexCoord1: TD3DXVECTOR2; // TexCoord1
    TexCoord2: TD3DXVECTOR2; // TexCoord2
    TexCoord3: TD3DXVECTOR2; // TexCoord3
    TexCoord4: TD3DXVECTOR2; // TexCoord4
  end; // size = 72 (as in Cxbx)
  D3DIVB = _D3DIVB;
  PD3DIVB = ^D3DIVB;

  TD3DIVBArray = array [0..(MaxInt div SizeOf(D3DIVB)) - 1] of D3DIVB;
  PD3DIVBs = ^TD3DIVBArray;

procedure XTL_EmuFlushIVB(); {NOPATCH}
procedure XTL_EmuUpdateActiveTexture(); {NOPATCH}

procedure CRC32Init;
function CRC32(data: PByte; len: int): uint;

const VERTEX_BUFFER_CACHE_SIZE = 64;
const MAX_STREAM_NOT_USED_TIME = (2 * CLOCKS_PER_SEC); // TODO -oCXBX: Trim the not used time

// inline vertex buffer emulation
var g_IVBTblOffs: UINT = 0;
var g_IVBTable: PD3DIVBs = nil;

implementation

uses
  uEmuD3D8;

var crctab: array [0..256-1] of uint;

{static}var bFirstTime: boolean = true;
procedure CRC32Init;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
var
  i, j: int;
  crc: uint;
begin
  if not bFirstTime then
    Exit;

  for i := 0 to 256-1 do
  begin
    crc := i shl 24;
    for j := 0 to 8-1 do
    begin
      if (crc and $80000000) > 0 then
        crc := (crc shl 1) xor $04c11db7
      else
        crc := crc shl 1;
    end;

    crctab[i] := crc;
  end;

  bFirstTime := false;
end;

function CRC32(data: PByte; len: int): uint;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
var
  i: int;
begin
  if len < 4 then abort;

  result :=           (data^ shl 24); Inc(data);
  result := result or (data^ shl 16); Inc(data);
  result := result or (data^ shl  8); Inc(data);
  result := result or  data^        ; Inc(data);
  result := not result;
  Dec(len, 4);

  for i := 0 to len - 1 do
  begin
    result := ((result shl 8) or data^) xor crctab[result shr 24];
    Inc(data);
  end;

  result := not result;
end;

{ _VertexPatchDesc }

procedure _VertexPatchDesc.VertexPatchDesc();
begin
  ZeroMemory(@Self, SizeOf(Self));
end;

{ VertexPatcher }

procedure VertexPatcher.VertexPatcher;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
begin
  m_uiNbrStreams := 0;
  ZeroMemory(@(m_pStreams[0]), sizeof(PATCHEDSTREAM) * MAX_NBR_STREAMS);
  m_bPatched := false;
  m_bAllocatedStreamZeroData := false;
  m_pNewVertexStreamZeroData := NULL;
  m_pDynamicPatch := NULL;
  CRC32Init();
end;

procedure VertexPatcher._VertexPatcher;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
begin
end;

procedure VertexPatcher.DumpCache();
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
var
  pNode: PRTNode;
  pCachedStream_: PCACHEDSTREAM;
begin
  DbgPrintf('--- Dumping streams cache ---');

  pNode := g_PatchedStreamsCache.getHead();
  while Assigned(pNode) do
  begin
    pCachedStream_ := PCACHEDSTREAM(pNode.pResource);
    if Assigned(pCachedStream_) then
    begin
      // TODO -oCXBX: Write nicer dump presentation
      DbgPrintf('Key: 0x%.08X Cache Hits: %d IsUP: %s OrigStride: %d NewStride: %d CRCCount: %d CRCFreq: %d Lengh: %d CRC32: 0x%.08X',
             [pNode.uiKey, pCachedStream_.uiCacheHit, ifThen(pCachedStream_.bIsUP, 'YES', 'NO'),
             pCachedStream_.Stream.uiOrigStride, pCachedStream_.Stream.uiNewStride,
             pCachedStream_.uiCount, pCachedStream_.uiCheckFrequency,
             pCachedStream_.uiLength, pCachedStream_.uiCRC32]);
    end;

    pNode := pNode.pNext;
  end;
end;

procedure VertexPatcher.CacheStream(pPatchDesc: PVertexPatchDesc;
                                        uiStream: UINT);
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
var
//  uiStride: UINT; // DXBX, uiStride never used
  pOrigVertexBuffer: XTL_PIDirect3DVertexBuffer8;
  Desc: D3DVERTEXBUFFER_DESC;
  pCalculateData: Pvoid;
  uiKey: uint32;
  uiMinHit: uint32;
  uiLength: UINT;
  pCachedStream_: PCACHEDSTREAM;
  pNode: PRTNode;
  uiChecksum: UINT;
begin
  pCalculateData := NULL;
  pCachedStream_ := PCACHEDSTREAM(CxbxMalloc(sizeof(CACHEDSTREAM)));

  ZeroMemory(pCachedStream_, sizeof(CACHEDSTREAM));

  // Check if the cache is full, if so, throw away the least used stream
  if (g_PatchedStreamsCache.get_count() > VERTEX_BUFFER_CACHE_SIZE) then
  begin
    uiKey := 0;
    uiMinHit := $FFFFFFFF;

    pNode := g_PatchedStreamsCache.getHead();
    while Assigned(pNode) do
    begin
      if Assigned(pNode.pResource) then
      begin
        // First, check if there is an 'expired' stream in the cache (not recently used)
        if (DWord(PCACHEDSTREAM(pNode.pResource).lLastUsed) < (clock() + MAX_STREAM_NOT_USED_TIME)) then
        begin
{$IFDEF DEBUG}
          printf('!!!Found an old stream, %2.2f', [{FLOAT}((clock() + MAX_STREAM_NOT_USED_TIME) - DWord(PCACHEDSTREAM(pNode.pResource).lLastUsed)) / {FLOAT}(CLOCKS_PER_SEC)]);
{$ENDIF}
          uiKey := pNode.uiKey;
          break;
        end;
        // Find the least used cached stream
        if (uint32(PCACHEDSTREAM(pNode.pResource).uiCacheHit) < uiMinHit) then
        begin
          uiMinHit := PCACHEDSTREAM(pNode.pResource).uiCacheHit;
          uiKey := pNode.uiKey;
        end;
      end;
      pNode := pNode.pNext;
    end;
    if (uiKey <> 0) then
    begin
{$IFDEF DEBUG}
      printf('!!!Removing stream');
{$ENDIF}
      FreeCachedStream(Pvoid(uiKey));
    end;
  end;

  // Start the actual stream caching
  if (nil=pPatchDesc.pVertexStreamZeroData) then
  begin
    pOrigVertexBuffer := m_pStreams[uiStream].pOriginalStream;
    IDirect3DVertexBuffer8(pOrigVertexBuffer)._AddRef();
    IDirect3DVertexBuffer8(m_pStreams[uiStream].pPatchedStream)._AddRef();
    if (FAILED(IDirect3DVertexBuffer8(pOrigVertexBuffer).GetDesc({out}Desc))) then
    begin
      CxbxKrnlCleanup('Could not retrieve original buffer size');
    end;
    if (FAILED(IDirect3DVertexBuffer8(pOrigVertexBuffer).Lock(0, 0, {out}PByte(pCalculateData), 0))) then
    begin
      CxbxKrnlCleanup('Couldn''t lock the original buffer');
    end;

    uiLength := Desc.Size;
    pCachedStream_.bIsUP := false;
    uiKey := uint32(pOrigVertexBuffer);
  end
  else
  begin
    // There should only be one stream (stream zero) in this case
    if (uiStream <> 0) then
    begin
      CxbxKrnlCleanup('Trying to patch a Draw..UP with more than stream zero!');
    end;
    // uiStride := pPatchDesc.uiVertexStreamZeroStride; // DXBX, uiStride never used
    pCalculateData := Puint08(pPatchDesc.pVertexStreamZeroData);
    // TODO -oCXBX: This is sometimes the number of indices, which isn't too good
    uiLength := pPatchDesc.dwVertexCount * pPatchDesc.uiVertexStreamZeroStride;
    pCachedStream_.bIsUP := true;
    pCachedStream_.pStreamUP := pCalculateData;
    uiKey := uint32(pCalculateData);
  end;

  uiChecksum := CRC32(PByte(pCalculateData), uiLength);
  if (nil=pPatchDesc.pVertexStreamZeroData) then
  begin
    IDirect3DVertexBuffer8(pOrigVertexBuffer).Unlock();
  end;

  pCachedStream_.uiCRC32 := uiChecksum;
  pCachedStream_.Stream := m_pStreams[uiStream];
  pCachedStream_.uiCheckFrequency := 1; // Start with checking every 1th Draw..
  pCachedStream_.uiCount := 0;
  pCachedStream_.uiLength := uiLength;
  pCachedStream_.uiCacheHit := 0;
  pCachedStream_.dwPrimitiveCount := pPatchDesc.dwPrimitiveCount;
  pCachedStream_.lLastUsed := clock();
  g_PatchedStreamsCache.insert(uiKey, pCachedStream_);
end; // VertexPatcher.CacheStream


procedure VertexPatcher.FreeCachedStream(pStream: Pvoid);
// Branch:shogun  Revision:0.8.1-Pre2  Translator:Shadow_Tj  Done:100
var
  pCachedStream_: PCACHEDSTREAM;
begin
  g_PatchedStreamsCache.Lock();
  pCachedStream_ := PCACHEDSTREAM(g_PatchedStreamsCache.get(pStream));
  if Assigned(pCachedStream_) then
  begin
    if pCachedStream_.bIsUP and Assigned(pCachedStream_.pStreamUP) then
    begin
      CxbxFree(pCachedStream_.pStreamUP);
      pCachedStream_.pStreamUP := nil; // Dxbx addition - nil out after freeing
    end;
    if Assigned(pCachedStream_.Stream.pOriginalStream) then
    begin
      IDirect3DVertexBuffer8(pCachedStream_.Stream.pOriginalStream)._Release();
      pCachedStream_.Stream.pOriginalStream := nil; // Dxbx addition - nil out after decreasing reference count
    end;
    if Assigned(pCachedStream_.Stream.pPatchedStream) then
    begin
{.$MESSAGE 'FreeCachedStream hits an int 3 because of this call to pPatchedStream._Release() :'}
      IDirect3DVertexBuffer8(pCachedStream_.Stream.pPatchedStream)._Release();
      pCachedStream_.Stream.pPatchedStream := nil; // Dxbx addition - nil out after decreasing reference count
    end;
    CxbxFree(pCachedStream_);
  end;
  g_PatchedStreamsCache.Unlock(); // Dxbx addition - Unlock _after_ update!
  g_PatchedStreamsCache.remove(pStream);
end;

function VertexPatcher.ApplyCachedStream(pPatchDesc: PVertexPatchDesc;
                                         uiStream: UINT; 
                                         pbFatalError: P_bool): _bool;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
var
  uiStride: UINT;
  pOrigVertexBuffer: XTL_PIDirect3DVertexBuffer8;
  Desc: D3DVERTEXBUFFER_DESC;
  pCalculateData: Pvoid;
  uiLength: UINT;
  bApplied: _bool;
  uiKey: uint32;
  pCachedStream_: PCACHEDSTREAM;
  bMismatch: _bool;
  Checksum: uint32;
begin
  pCalculateData := NULL;
  bApplied := false;
  //pCachedStream_ := PCACHEDSTREAM(CxbxMalloc(sizeof(CACHEDSTREAM)));

  if (nil=pPatchDesc.pVertexStreamZeroData) then
  begin
    IDirect3DDevice8(g_pD3DDevice8).GetStreamSource(uiStream, PIDirect3DVertexBuffer8(@pOrigVertexBuffer), {out}uiStride);
    if (nil=pOrigVertexBuffer) then
    begin
      (*if(nil=g_pVertexBuffer) or (nil=g_pVertexBuffer.EmuVertexBuffer8) then
        CxbxKrnlCleanup('Unable to retrieve original buffer (Stream := %d)', [uiStream]);
      else
        pOrigVertexBuffer := g_pVertexBuffer.EmuVertexBuffer8;*)

      if Assigned(pbFatalError) then
        pbFatalError^ := true;

      Result := false;
      Exit;
    end;

    if (FAILED(IDirect3DVertexBuffer8(pOrigVertexBuffer).GetDesc({out}Desc))) then
    begin
      CxbxKrnlCleanup('Could not retrieve original buffer size');
    end;
    uiLength := Desc.Size;
    uiKey := uint32(pOrigVertexBuffer);
    //pCachedStream_.bIsUP := false;
  end
  else
  begin
    // There should only be one stream (stream zero) in this case
    if (uiStream <> 0) then
    begin
      CxbxKrnlCleanup('Trying to find a cached Draw..UP with more than stream zero!');
    end;
    uiStride := pPatchDesc.uiVertexStreamZeroStride;
    pCalculateData := Puint08(pPatchDesc.pVertexStreamZeroData);
    // TODO -oCXBX: This is sometimes the number of indices, which isn't too good
    uiLength := pPatchDesc.dwVertexCount * pPatchDesc.uiVertexStreamZeroStride;
    uiKey := uint32(pCalculateData);
    //pCachedStream_.bIsUP := true;
    //pCachedStream_.pStreamUP := pCalculateData;
  end;
  g_PatchedStreamsCache.Lock();

  pCachedStream_ := PCACHEDSTREAM(g_PatchedStreamsCache.get(uiKey));
  if Assigned(pCachedStream_) then
  begin
    pCachedStream_.lLastUsed := clock();
    Inc(pCachedStream_.uiCacheHit);
    bMismatch := false;
    if (pCachedStream_.uiCount = (pCachedStream_.uiCheckFrequency - 1)) then
    begin
      if (nil=pPatchDesc.pVertexStreamZeroData) then
      begin
        if (FAILED(IDirect3DVertexBuffer8(pOrigVertexBuffer).Lock(0, 0, {out}PByte(pCalculateData), 0))) then
        begin
          CxbxKrnlCleanup('Couldn''t lock the original buffer');
        end;
      end;
      // Use the cached stream length (which is a must for the UP stream)
      Checksum := CRC32(PByte(pCalculateData), pCachedStream_.uiLength);
      if (Checksum = pCachedStream_.uiCRC32) then
      begin
        // Take a while longer to check
        if (pCachedStream_.uiCheckFrequency < 32*1024) then
        begin
          pCachedStream_.uiCheckFrequency:= pCachedStream_.uiCheckFrequency * 2;
        end;
        pCachedStream_.uiCount := 0;
      end
      else
      begin
        // TODO -oCXBX: Do something about this
        if (pCachedStream_.bIsUP) then
        begin
          FreeCachedStream(pCachedStream_.pStreamUP);
        end
        else
        begin
          FreeCachedStream(pCachedStream_.Stream.pOriginalStream);
        end;
        pCachedStream_ := NULL;
        bMismatch := true;
      end;
      if (nil=pPatchDesc.pVertexStreamZeroData) then
      begin
        IDirect3DVertexBuffer8(pOrigVertexBuffer).Unlock();
      end;
    end
    else
    begin
      Inc(pCachedStream_.uiCount);
    end;
    if (not bMismatch) then
    begin
      if (not pCachedStream_.bIsUP) then
      begin
        m_pStreams[uiStream].pOriginalStream := pOrigVertexBuffer;
        m_pStreams[uiStream].uiOrigStride := uiStride;
        IDirect3DDevice8(g_pD3DDevice8).SetStreamSource(uiStream, IDirect3DVertexBuffer8(pCachedStream_.Stream.pPatchedStream), pCachedStream_.Stream.uiNewStride);
        IDirect3DVertexBuffer8(pCachedStream_.Stream.pPatchedStream)._AddRef();
        IDirect3DVertexBuffer8(pCachedStream_.Stream.pOriginalStream)._AddRef();
        m_pStreams[uiStream].pPatchedStream := pCachedStream_.Stream.pPatchedStream;
        m_pStreams[uiStream].uiNewStride := pCachedStream_.Stream.uiNewStride;
      end
      else
      begin
        pPatchDesc.pVertexStreamZeroData := pCachedStream_.pStreamUP;
        pPatchDesc.uiVertexStreamZeroStride := pCachedStream_.Stream.uiNewStride;
      end;
      if (pCachedStream_.dwPrimitiveCount > 0) then
      begin
        // The primitives were patched, draw with the correct number of primimtives from the cache
        pPatchDesc.dwPrimitiveCount := pCachedStream_.dwPrimitiveCount;
      end;
      bApplied := true;
      m_bPatched := true;
    end;
  end;
  g_PatchedStreamsCache.Unlock();

  if (nil=pPatchDesc.pVertexStreamZeroData) then
  begin
    IDirect3DVertexBuffer8(pOrigVertexBuffer)._Release();
    pOrigVertexBuffer := nil; // Dxbx addition - nil out after decreasing reference count
  end;

  Result := bApplied;
end; // VertexPatcher.ApplyCachedStream


function VertexPatcher.GetNbrStreams(pPatchDesc: PVertexPatchDesc): UINT;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:Shadow_Tj  Done:100
var
  pDynamicPatch: PVERTEX_DYNAMIC_PATCH;
begin
  if (VshHandleIsVertexShader(g_CurrentVertexShader)) then
  begin
    pDynamicPatch := XTL_VshGetVertexDynamicPatch(g_CurrentVertexShader);
    if Assigned(pDynamicPatch) then
    begin
      Result := pDynamicPatch.NbrStreams;
      Exit;
    end
    else
    begin
      Result := 1; // Could be more, but it doesn't matter as we're not going to patch the types
      Exit;
    end;
  end
  else if g_CurrentVertexShader > 0 then
  begin
    Result := 1;
    Exit;
  end;
  Result := 0;
end;

function VertexPatcher.PatchStream(pPatchDesc: PVertexPatchDesc;
                                   uiStream: UINT): _bool;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
var
  pStream: PPATCHEDSTREAM;

  pOrigVertexBuffer: XTL_PIDirect3DVertexBuffer8;
  pNewVertexBuffer: XTL_PIDirect3DVertexBuffer8;
  pOrigData: Puint08;
  pNewData: Puint08;
  uiStride: UINT;
  Desc: D3DVERTEXBUFFER_DESC;
  pStreamPatch: PSTREAM_DYNAMIC_PATCH;
  dwNewSize: DWORD;

  uiVertex: uint32;
  dwPosOrig: DWORD;
  dwPosNew: DWORD;
  uiType: UINT;
  dwPacked: DWORD;
begin
  // FVF buffers doesn't have Xbox extensions, but texture coordinates may
  // need normalization if used with linear textures.
  if (not VshHandleIsVertexShader(pPatchDesc.hVertexShader)) then
  begin
    if (pPatchDesc.hVertexShader and D3DFVF_TEXCOUNT_MASK) > 0 then
    begin
      Result := NormalizeTexCoords(pPatchDesc, uiStream);
      Exit;
    end
    else
    begin
      Result := false;
      Exit;
    end;
  end;

  if (nil=m_pDynamicPatch) or (not m_pDynamicPatch.pStreamPatches[uiStream].NeedPatch) then
  begin
    Result := false;
    Exit;
  end;

  // Do some groovey patchin'

  ZeroMemory(@Desc, Sizeof(D3DVERTEXBUFFER_DESC));
  pStream := @(m_pStreams[uiStream]);
  pStreamPatch := @(m_pDynamicPatch.pStreamPatches[uiStream]);

  if (nil=pPatchDesc.pVertexStreamZeroData) then
  begin
    IDirect3DDevice8(g_pD3DDevice8).GetStreamSource(uiStream, PIDirect3DVertexBuffer8(@pOrigVertexBuffer), {out}uiStride);
    if (FAILED(IDirect3DVertexBuffer8(pOrigVertexBuffer).GetDesc({out}Desc))) then
    begin
      CxbxKrnlCleanup('Could not retrieve original buffer size');
    end;
    // Set a new (exact) vertex count
    pPatchDesc.dwVertexCount := Desc.Size div uiStride;
    dwNewSize := pPatchDesc.dwVertexCount * pStreamPatch.ConvertedStride;

    if (FAILED(IDirect3DVertexBuffer8(pOrigVertexBuffer).Lock(0, 0, {out}PByte(pOrigData), 0))) then
    begin
      CxbxKrnlCleanup('Couldn''t lock the original buffer');
    end;
    IDirect3DDevice8(g_pD3DDevice8).CreateVertexBuffer(dwNewSize, 0, 0, D3DPOOL_MANAGED, PIDirect3DVertexBuffer8(@pNewVertexBuffer));
    if (FAILED(IDirect3DVertexBuffer8(pNewVertexBuffer).Lock(0, 0, {out}PByte(pNewData), 0))) then
    begin
      CxbxKrnlCleanup('Couldn''t lock the new buffer');
    end;
    if (nil=pStream.pOriginalStream) then
    begin
      // The stream was not previously patched, we'll need this when restoring
      pStream.pOriginalStream := pOrigVertexBuffer;
    end;
  end
  else
  begin
    // There should only be one stream (stream zero) in this case
    if (uiStream <> 0) then
    begin
      CxbxKrnlCleanup('Trying to patch a Draw..UP with more than stream zero!');
    end;
    uiStride  := pPatchDesc.uiVertexStreamZeroStride;
    pOrigData := Puint08(pPatchDesc.pVertexStreamZeroData);
    // TODO -oCXBX: This is sometimes the number of indices, which isn't too good
    dwNewSize := pPatchDesc.dwVertexCount * pStreamPatch.ConvertedStride;
    pNewVertexBuffer := NULL;
    pNewData := CxbxMalloc(dwNewSize);
    if (nil=pNewData) then
    begin
      CxbxKrnlCleanup('Couldn''t allocate the new stream zero buffer');
    end;
  end;

  if pPatchDesc.dwVertexCount > 0 then // Dxbx addition, to prevent underflow
  for uiVertex := 0 to pPatchDesc.dwVertexCount - 1 do
  begin
    dwPosOrig := 0;
    dwPosNew := 0;
    if pStreamPatch.NbrTypes > 0 then // Dxbx addition, to prevent underflow
    for uiType := 0 to pStreamPatch.NbrTypes - 1 do
    begin
      case(pStreamPatch.pTypes[uiType]) of
           $12: begin // FLOAT1
              memcpy(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew],
                     @pOrigData[uiVertex * uiStride + dwPosOrig],
                     sizeof(FLOAT));
              Inc(dwPosOrig, sizeof(FLOAT));
              Inc(dwPosNew, sizeof(FLOAT));
              end;
           $22: begin // FLOAT2
              memcpy(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew],
                     @pOrigData[uiVertex * uiStride + dwPosOrig],
                     2 * sizeof(FLOAT));
              Inc(dwPosOrig, 2 * sizeof(FLOAT));
              Inc(dwPosNew, 2 * sizeof(FLOAT));
              end;
           $32: begin // FLOAT3
              memcpy(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew],
                     @pOrigData[uiVertex * uiStride + dwPosOrig],
                     3 * sizeof(FLOAT));
              Inc(dwPosOrig, 3 * sizeof(FLOAT));
              Inc(dwPosNew, 3 * sizeof(FLOAT));
              end;
           $42: begin // FLOAT4
              memcpy(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew],
                     @pOrigData[uiVertex * uiStride + dwPosOrig],
                     4 * sizeof(FLOAT));
              Inc(dwPosOrig, 4 * sizeof(FLOAT));
              Inc(dwPosNew, 4 * sizeof(FLOAT));
              end;
           $40: begin // D3DCOLOR
              memcpy(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew],
                     @pOrigData[uiVertex * uiStride + dwPosOrig],
                     sizeof(D3DCOLOR));
              Inc(dwPosOrig, sizeof(D3DCOLOR));
              Inc(dwPosNew, sizeof(D3DCOLOR));
              end;
           $16: //NORMPACKED3
              begin
                dwPacked := PDWORDs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0];

                PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := (ToFLOAT(dwPacked and $7ff)) / 1023.0;
                PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[1] := (ToFLOAT((dwPacked shr 11) and $7ff)) / 1023.0;
                PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[2] := (ToFLOAT((dwPacked shr 22) and $3ff)) / 511.0;

                Inc(dwPosOrig, sizeof(DWORD));
                Inc(dwPosNew, 3 * sizeof(FLOAT));
              end;
           $15: begin// SHORT1
              // Make it a SHORT2
              PSHORTs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := PSHORT(@pOrigData[uiVertex * uiStride + dwPosOrig])^;
              PSHORTs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[1] := $00;

              Inc(dwPosOrig, 1 * sizeof(SHORT));
              Inc(dwPosNew, 2 * sizeof(SHORT));
              end;
           $25: begin // SHORT2
              memcpy(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew],
                     @pOrigData[uiVertex * uiStride+dwPosOrig],
                     2 * sizeof(SHORT));
              Inc(dwPosOrig, 2 * sizeof(SHORT));
              Inc(dwPosNew, 2 * sizeof(SHORT));
              end;
           $35: begin // SHORT3
              memcpy(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew],
                     @pOrigData[uiVertex * uiStride + dwPosOrig],
                     3 * sizeof(SHORT));
              // Make it a SHORT4 and set the last short to 1
              PSHORTs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[3] := $01;

              Inc(dwPosOrig, 3 * sizeof(SHORT));
              Inc(dwPosNew, 4 * sizeof(SHORT));
              end;
           $45: begin // SHORT4
              memcpy(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew],
                     @pOrigData[uiVertex * uiStride + dwPosOrig],
                     4 * sizeof(SHORT));
              Inc(dwPosOrig, 4 * sizeof(SHORT));
              Inc(dwPosNew, 4 * sizeof(SHORT));
              end;
           $14: begin // PBYTE1
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0]) / 255.0;

              Inc(dwPosOrig, 1 * sizeof(BYTE));
              Inc(dwPosNew, 1 * sizeof(FLOAT));
              end;
           $24: begin // PBYTE2
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0]) / 255.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[1] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[1]) / 255.0;

              Inc(dwPosOrig, 2 * sizeof(BYTE));
              Inc(dwPosNew, 2 * sizeof(FLOAT));
              end;
           $34: begin // PBYTE3
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0]) / 255.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[1] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[1]) / 255.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[2] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[2]) / 255.0;

              Inc(dwPosOrig, 3 * sizeof(BYTE));
              Inc(dwPosNew, 3 * sizeof(FLOAT));
              end;
           $44: begin // PBYTE4
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0]) / 255.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[1] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[1]) / 255.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[2] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[2]) / 255.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[3] := ToFLOAT(PBYTEs(@pOrigData[uiVertex * uiStride + dwPosOrig])[3]) / 255.0;

              Inc(dwPosOrig, 4 * sizeof(BYTE));
              Inc(dwPosNew, 4 * sizeof(FLOAT));
              end;
           $11: begin // NORMSHORT1
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0]) / 32767.0;

              Inc(dwPosOrig, 1 * sizeof(SHORT));
              Inc(dwPosNew, 1 * sizeof(FLOAT));
              end;
           $21: begin // NORMSHORT2
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0]) / 32767.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[1] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[1]) / 32767.0;

              Inc(dwPosOrig, 2 * sizeof(SHORT));
              Inc(dwPosNew, 2 * sizeof(FLOAT));
              end;
           $31: begin // NORMSHORT3
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0]) / 32767.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[1] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[1]) / 32767.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[2] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[2]) / 32767.0;

              Inc(dwPosOrig, 3 * sizeof(SHORT));
              Inc(dwPosNew, 3 * sizeof(FLOAT));
              end;
           $41: begin// NORMSHORT4
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0]) / 32767.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[1] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[1]) / 32767.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[2] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[2]) / 32767.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[3] := ToFLOAT(PSHORTs(@pOrigData[uiVertex * uiStride + dwPosOrig])[3]) / 32767.0;

              Inc(dwPosOrig, 4 * sizeof(SHORT));
              Inc(dwPosNew, 4 * sizeof(FLOAT));
              end;
           $72: begin// FLOAT2H
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[0] := PFLOATs(@pOrigData[uiVertex * uiStride + dwPosOrig])[0];
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[1] := PFLOATs(@pOrigData[uiVertex * uiStride + dwPosOrig])[1];
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[2] := 0.0;
              PFLOATs(@pNewData[uiVertex * pStreamPatch.ConvertedStride + dwPosNew])[3] := PFLOATs(@pOrigData[uiVertex * uiStride + dwPosOrig])[2];

          (*TODO -oCXBX:
           $02:
              printf('D3DVSDT_NONE / xbox ext. nsp /');
              dwNewDataType := $FF; *)
              end;
          else
          begin
            CxbxKrnlCleanup('Unhandled stream type: 0x%.02X', [pStreamPatch.pTypes[uiType]]);
          end;
       end;
    end;
  end;
  if (nil = pPatchDesc.pVertexStreamZeroData) then
  begin
    IDirect3DVertexBuffer8(pNewVertexBuffer).Unlock();
    IDirect3DVertexBuffer8(pOrigVertexBuffer).Unlock();

    if (FAILED(IDirect3DDevice8(g_pD3DDevice8).SetStreamSource(uiStream, IDirect3DVertexBuffer8(pNewVertexBuffer), pStreamPatch.ConvertedStride))) then
    begin
      CxbxKrnlCleanup('Failed to set the type patched buffer as the new stream source!');
    end;
    if Assigned(pStream.pPatchedStream) then
    begin
      // The stream was already primitive patched, release the previous vertex buffer to avoid memory leaks
      IDirect3DVertexBuffer8(pStream.pPatchedStream)._Release();
      pStream.pPatchedStream := nil; // Dxbx addition - nil out after decreasing reference count
    end;
    pStream.pPatchedStream := pNewVertexBuffer;
  end
  else
  begin
    pPatchDesc.pVertexStreamZeroData := pNewData;
    pPatchDesc.uiVertexStreamZeroStride := pStreamPatch.ConvertedStride;
    if (not m_bAllocatedStreamZeroData) then
    begin
      // The stream was not previously patched. We'll need this when restoring
      m_bAllocatedStreamZeroData := true;
      m_pNewVertexStreamZeroData := pNewData;
    end;
  end;
  pStream.uiOrigStride := uiStride;
  pStream.uiNewStride := pStreamPatch.ConvertedStride;
  m_bPatched := true;

  Result := true;
end; // VertexPatcher.PatchStream

function VertexPatcher.NormalizeTexCoords(pPatchDesc: PVertexPatchDesc; uiStream: UINT): _bool;
// Branch:shogun  Revision:  Translator:PatrickvL  Done:100
var
  bHasLinearTex: _bool;
  bTexIsLinear: array [0..4-1] of _bool;
  pLinearPixelContainer: array [0..4-1] of PX_D3DPixelContainer;
  i: uint08;
  pPixelContainer: PX_D3DPixelContainer;

  pOrigVertexBuffer: XTL_PIDirect3DVertexBuffer8;
  pNewVertexBuffer: XTL_PIDirect3DVertexBuffer8;
  pStream: PPATCHEDSTREAM;
  pData: Puint08;
  pUVData: Puint08;
  uiStride: uint;
  uiVertexCount: uint;

  Desc: D3DVERTEXBUFFER_DESC;
  pOrigData: PByte;
  uiOffset: uint;
  dwTexN: DWORD;
  uiVertex: uint32;
begin
  // Check for active linear textures.
  bHasLinearTex := false;
  pStream := nil; // DXBX - pstream might not have been initialized

  for i := 0 to 4-1 do
  begin
    pPixelContainer := PX_D3DPixelContainer(EmuD3DActiveTexture[i]);
    if (Assigned(pPixelContainer) and EmuXBFormatIsLinear((X_D3DFORMAT(pPixelContainer.Format) and X_D3DFORMAT_FORMAT_MASK) shr X_D3DFORMAT_FORMAT_SHIFT)) then
    begin
      bHasLinearTex := true; bTexIsLinear[i] := true;
      pLinearPixelContainer[i] := pPixelContainer;
    end
    else
    begin
      bTexIsLinear[i] := false;
    end
  end;

  if (not bHasLinearTex) then
  begin
    Result := false;
    Exit;
  end;

  if Assigned(pPatchDesc.pVertexStreamZeroData) then
  begin
    // In-place patching of inline buffer.
    pNewVertexBuffer := nil;
    pData := Puint08(pPatchDesc.pVertexStreamZeroData);
    uiStride := pPatchDesc.uiVertexStreamZeroStride;
    uiVertexCount := pPatchDesc.dwVertexCount;
  end
  else
  begin
    // Copy stream for patching and caching.

    IDirect3DDevice8(g_pD3DDevice8).GetStreamSource(uiStream, PIDirect3DVertexBuffer8(@pOrigVertexBuffer), {out}uiStride);

    if (nil=pOrigVertexBuffer) or (FAILED(IDirect3DVertexBuffer8(pOrigVertexBuffer).GetDesc({out}Desc))) then
    begin
      CxbxKrnlCleanup('Could not retrieve original FVF buffer size.');
    end;
    uiVertexCount := Desc.Size div uiStride;

    if(FAILED(IDirect3DVertexBuffer8(pOrigVertexBuffer).Lock(0, 0, {out}pOrigData, 0))) then
    begin
      CxbxKrnlCleanup('Couldn''t lock original FVF buffer.');
    end;
    IDirect3DDevice8(g_pD3DDevice8).CreateVertexBuffer(Desc.Size, 0, 0, D3DPOOL_MANAGED, PIDirect3DVertexBuffer8(@pNewVertexBuffer));
    if(FAILED(IDirect3DVertexBuffer8(pNewVertexBuffer).Lock(0, 0, {out}PByte(pData), 0))) then
    begin
      CxbxKrnlCleanup('Couldn''t lock new FVF buffer.');
    end;
    memcpy(pData, pOrigData, Desc.Size);
    IDirect3DVertexBuffer8(pOrigVertexBuffer).Unlock();

    pStream := @m_pStreams[uiStream];
    if (nil=pStream.pOriginalStream) then
    begin
      pStream.pOriginalStream := pOrigVertexBuffer;
    end;
  end;

  // Locate texture coordinate offset in vertex structure.
  uiOffset := 0;
  if (pPatchDesc.hVertexShader and D3DFVF_XYZRHW) > 0  then
    Inc(uiOffset, (sizeof(FLOAT) * 4))
  else
  begin
    if (pPatchDesc.hVertexShader and D3DFVF_XYZ) > 0 then
      Inc(uiOffset, (sizeof(FLOAT) * 3 ))
    else if (pPatchDesc.hVertexShader and D3DFVF_XYZB1) > 0 then
      Inc(uiOffset, (sizeof(FLOAT) *4 ))
    else if (pPatchDesc.hVertexShader and D3DFVF_XYZB2) > 0 then
      Inc(uiOffset, (sizeof(FLOAT) * 5))
    else if (pPatchDesc.hVertexShader and D3DFVF_XYZB3) > 0 then
      Inc(uiOffset, (sizeof(FLOAT) * 6))
    else if (pPatchDesc.hVertexShader and D3DFVF_XYZB4) > 0 then
      Inc (uiOffset, (sizeof(FLOAT) * 7));

    if (pPatchDesc.hVertexShader and D3DFVF_NORMAL) > 0 then
      Inc(uiOffset, (sizeof(FLOAT) * 3));
  end;

  if(pPatchDesc.hVertexShader and D3DFVF_DIFFUSE) > 0 then
    Inc(uiOffset, sizeof(DWORD));
  if(pPatchDesc.hVertexShader and D3DFVF_SPECULAR) > 0 then
    Inc(uiOffset, sizeof(DWORD));

  dwTexN := (pPatchDesc.hVertexShader and D3DFVF_TEXCOUNT_MASK) shr D3DFVF_TEXCOUNT_SHIFT;

  // Normalize texture coordinates.
  if uiVertexCount > 0 then // Dxbx addition, to prevent underflow
  for uiVertex := 0 to uiVertexCount - 1 do
  begin
    pUVData := Puint08(pData + (uiVertex * uiStride) + uiOffset);

    if (dwTexN >= 1) then
    begin
      if (bTexIsLinear[0]) then
      begin
        PFLOATs(pUVData)[0] := PFLOATs(pUVData)[0] / (( pLinearPixelContainer[0].Size and X_D3DSIZE_WIDTH_MASK) + 1);
        PFLOATs(pUVData)[1] := PFLOATs(pUVData)[1] / (((pLinearPixelContainer[0].Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1);
      end;
      Inc(PByte(pUVData), sizeof(FLOAT) * 2);
    end;

    if (dwTexN >= 2) then
    begin
      if (bTexIsLinear[1]) then
      begin
        PFLOATs(pUVData)[0] := PFLOATs(pUVData)[0] / (( pLinearPixelContainer[1].Size and X_D3DSIZE_WIDTH_MASK) + 1);
        PFLOATs(pUVData)[1] := PFLOATs(pUVData)[1] / (((pLinearPixelContainer[1].Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1);
      end;
      Inc(PByte(pUVData), sizeof(FLOAT) * 2);
    end;

    if (dwTexN >= 3) then
    begin
      if (bTexIsLinear[2]) then
      begin
        PFLOATs(pUVData)[0] := PFLOATs(pUVData)[0] / (( pLinearPixelContainer[2].Size and X_D3DSIZE_WIDTH_MASK) + 1);
        PFLOATs(pUVData)[1] := PFLOATs(pUVData)[1] / (((pLinearPixelContainer[2].Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1);
      end;
      Inc(PByte(pUVData), sizeof(FLOAT) * 2);
    end;

    if((dwTexN >= 4) and bTexIsLinear[3]) then
    begin
      PFLOATs(pUVData)[0] := PFLOATs(pUVData)[0] / (( pLinearPixelContainer[3].Size and X_D3DSIZE_WIDTH_MASK) + 1);
      PFLOATs(pUVData)[1] := PFLOATs(pUVData)[1] / (((pLinearPixelContainer[3].Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1);
    end;
  end;

  if Assigned(pNewVertexBuffer) then
  begin
    IDirect3DVertexBuffer8(pNewVertexBuffer).Unlock();

    if (FAILED(IDirect3DDevice8(g_pD3DDevice8).SetStreamSource(uiStream, IDirect3DVertexBuffer8(pNewVertexBuffer), uiStride))) then
    begin
      CxbxKrnlCleanup('Failed to set the texcoord patched FVF buffer as the new stream source.');
    end;
    if Assigned(pStream.pPatchedStream) then
    begin
      IDirect3DVertexBuffer8(pStream.pPatchedStream)._Release();
      pStream.pPatchedStream := nil; // Dxbx addition - nil out after decreasing reference count
    end;

    pStream.pPatchedStream := pNewVertexBuffer;
    pStream.uiOrigStride := uiStride;
    pStream.uiNewStride := uiStride;
    m_bPatched := true;
  end;

  Result := m_bPatched;
end; // VertexPatcher.NormalizeTexCoords

const
  VERTICES_PER_QUAD = 4;
  VERTICES_PER_TRIANGLE = 3;
  TRIANGLES_PER_QUAD = 2;

function VertexPatcher.PatchPrimitive(pPatchDesc: PVertexPatchDesc;
                                      uiStream: UINT): _bool;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:90
var
  pStream: PPATCHEDSTREAM;
  dwOriginalSize: DWORD;
  dwNewSize: DWORD;
  dwOriginalSizeWR: DWORD;
  dwNewSizeWR: DWORD;
  pOrigVertexData: PBYTE;
  pPatchedVertexData: PBYTE;
  Desc: D3DVERTEXBUFFER_DESC;

  pPatch012: Puint08;
  pPatch34: Puint08;
  pPatch3: Puint08;
  pPatch5: Puint08;

  pOrig012: Puint08;
  pOrig2: Puint08;
  pOrig3: Puint08;
  i: uint32;
  z: uint32;
begin
  pStream := @(m_pStreams[uiStream]);

  if(pPatchDesc.PrimitiveType < X_D3DPT_POINTLIST) or (pPatchDesc.PrimitiveType >= X_D3DPT_MAX) then
  begin
    CxbxKrnlCleanup('Unknown primitive type: 0x%.02X', [Ord(pPatchDesc.PrimitiveType)]);
  end;

  // Unsupported primitives that don't need deep patching.
  case(pPatchDesc.PrimitiveType) of
    // Quad strip is just like a triangle strip, but requires two
    // vertices per primitive.
    X_D3DPT_QUADSTRIP: begin
      // Dxbx note : Shouldn't the 'two vertices per primitive' requirement always be met?
      // In other words : Is the next fixup ever needed at all?
      Dec(pPatchDesc.dwVertexCount, pPatchDesc.dwVertexCount mod 2);
      pPatchDesc.PrimitiveType := X_D3DPT_TRIANGLESTRIP;
      end;

    // Convex polygon is the same as a triangle fan.
    X_D3DPT_POLYGON: begin
      pPatchDesc.PrimitiveType := X_D3DPT_TRIANGLEFAN;
      end;
  end;

  pPatchDesc.dwPrimitiveCount := EmuD3DVertex2PrimitiveCount(pPatchDesc.PrimitiveType, pPatchDesc.dwVertexCount);

  // Skip primitives that don't need further patching.
  case (pPatchDesc.PrimitiveType) of
    X_D3DPT_QUADLIST: begin
      //EmuWarning('VertexPatcher::PatchPrimitive: Processing D3DPT_QUADLIST');
      end;
    X_D3DPT_LINELOOP: begin
      //EmuWarning('VertexPatcher::PatchPrimitive: Processing D3DPT_LINELOOP');
      end;

  else //    default:
    Result := false;
    Exit;
  end;

  if Assigned(pPatchDesc.pVertexStreamZeroData) and (uiStream > 0) then
  begin
    CxbxKrnlCleanup('Draw..UP call with more than one stream!');
  end;

  pStream.uiOrigStride := 0;

  // sizes of our part in the vertex buffer
  dwOriginalSize    := 0;
  dwNewSize         := 0;

  // sizes with the rest of the buffer
  dwOriginalSizeWR  := 0;
  dwNewSizeWR       := 0;

  // vertex data arrays
  pOrigVertexData := nil;
  pPatchedVertexData := nil;

  if (pPatchDesc.pVertexStreamZeroData = nil) then
  begin
    IDirect3DDevice8(g_pD3DDevice8).GetStreamSource(0, PIDirect3DVertexBuffer8(@(pStream.pOriginalStream)), {out}pStream.uiOrigStride);
    pStream.uiNewStride := pStream.uiOrigStride; // The stride is still the same
  end
  else
  begin
    pStream.uiOrigStride := pPatchDesc.uiVertexStreamZeroStride;
  end;

  // Quad list
  if (pPatchDesc.PrimitiveType = X_D3DPT_QUADLIST) then
  begin
    // We're going to convert 1 quad (4 vertices) to 2 triangles (2*3=6 vertices),
    // so that's 2 times as many primitives, and 50% more vertices :
    pPatchDesc.dwPrimitiveCount := pPatchDesc.dwPrimitiveCount * TRIANGLES_PER_QUAD;

    // This is a list of sqares/rectangles, so we convert it to a list of triangles
    dwOriginalSize  := pPatchDesc.dwVertexCount * pStream.uiOrigStride * VERTICES_PER_QUAD;
    dwNewSize       := pPatchDesc.dwVertexCount * pStream.uiOrigStride * VERTICES_PER_TRIANGLE * TRIANGLES_PER_QUAD;
  end
  // Line loop
  else if (pPatchDesc.PrimitiveType = X_D3DPT_LINELOOP) then
  begin
    Inc(pPatchDesc.dwPrimitiveCount, 1);

    // We will add exactly one more line
    dwOriginalSize  := pPatchDesc.dwVertexCount * pStream.uiOrigStride;
    dwNewSize       := dwOriginalSize + pStream.uiOrigStride;
  end;

  if(pPatchDesc.pVertexStreamZeroData = nil) then
  begin
    // Retrieve the original buffer size
    begin
      if (FAILED(IDirect3DVertexBuffer8(pStream.pOriginalStream).GetDesc({out}Desc))) then
      begin
        CxbxKrnlCleanup('Could not retrieve buffer size');
      end;

      // Here we save the full buffer size
      dwOriginalSizeWR := Desc.Size;

      // So we can now calculate the size of the rest (dwOriginalSizeWR - dwOriginalSize) and
      // add it to our new calculated size of the patched buffer
      dwNewSizeWR := dwNewSize + dwOriginalSizeWR - dwOriginalSize;
    end;

    IDirect3DDevice8(g_pD3DDevice8).CreateVertexBuffer(dwNewSizeWR, 0, 0, D3DPOOL_MANAGED, PIDirect3DVertexBuffer8(@(pStream.pPatchedStream)));

    if (pStream.pOriginalStream <> nil) then
    begin
      IDirect3DVertexBuffer8(pStream.pOriginalStream).Lock(0, 0, {out}pOrigVertexData, 0);
    end;

    if (pStream.pPatchedStream <> nil) then
    begin
      IDirect3DVertexBuffer8(pStream.pPatchedStream).Lock(0, 0, {out}pPatchedVertexData, 0);
    end;
  end
  else
  begin
    dwOriginalSizeWR := dwOriginalSize;
    dwNewSizeWR := dwNewSize;

    m_pNewVertexStreamZeroData := CxbxMalloc(dwNewSizeWR);
    m_bAllocatedStreamZeroData := true;

    pPatchedVertexData := m_pNewVertexStreamZeroData;
    pOrigVertexData := pPatchDesc.pVertexStreamZeroData;

    pPatchDesc.pVertexStreamZeroData := pPatchedVertexData;
  end;

(* Dxbx Note : This seems to be completely wrong, as for starters the dwOffset isn't multiplied with the stride,
   and what about the preceding vertices, shouldn't they be converted too?!?
   This mainly becomes a problem whenever dwOffset <> 0 though.
*)
  // Copy the nonmodified data
  memcpy(pPatchedVertexData, pOrigVertexData, pPatchDesc.dwOffset);
  memcpy(@pPatchedVertexData[pPatchDesc.dwOffset+dwNewSize],
         @pOrigVertexData[pPatchDesc.dwOffset+dwOriginalSize],
         dwOriginalSizeWR - pPatchDesc.dwOffset - dwOriginalSize);

  // Quad list
  if (pPatchDesc.PrimitiveType = X_D3DPT_QUADLIST) then
  begin
    // Calculate where the new vertices should go :
    pPatch012 := @pPatchedVertexData[ pPatchDesc.dwOffset      * pStream.uiOrigStride];
    pPatch34 :=  @pPatchedVertexData[(pPatchDesc.dwOffset + 3) * pStream.uiOrigStride];
    pPatch5 :=   @pPatchedVertexData[(pPatchDesc.dwOffset + 5) * pStream.uiOrigStride];

    // Calculate where the original vertices come from :
    pOrig012 := @pOrigVertexData[ pPatchDesc.dwOffset      * pStream.uiOrigStride];
    pOrig2 :=   @pOrigVertexData[(pPatchDesc.dwOffset + 2) * pStream.uiOrigStride];

    // Now that dwOffset isn't used anymore, make sure the index points to the vertex of the same 'virtual' primitive :
    pPatchDesc.dwOffset := (pPatchDesc.dwOffset * VERTICES_PER_TRIANGLE * TRIANGLES_PER_QUAD) div VERTICES_PER_QUAD;

    // Loop over all quads :
    if (pPatchDesc.dwVertexCount div VERTICES_PER_QUAD) > 0 then // Dxbx addition, to prevent underflow
    for i := 0 to (pPatchDesc.dwVertexCount div VERTICES_PER_QUAD) - 1 do
    begin
      memcpy(pPatch012, pOrig012, pStream.uiOrigStride * 3); // Vertex T1_V0,T1_V1,T1_V2 := Vertex Q_V0,Q_V1,Q_V2
      memcpy(pPatch34,  pOrig2,   pStream.uiOrigStride * 2); // Vertex T2_V0,T2_V1       := Vertex Q_V2,Q_V3
      memcpy(pPatch5,   pOrig012, pStream.uiOrigStride);     // Vertex T2_V2             := Vertex Q_V0

      if (pPatchDesc.hVertexShader and D3DFVF_XYZRHW) > 0 then
      begin
        for z := 0 to (VERTICES_PER_TRIANGLE*TRIANGLES_PER_QUAD)-1 do
        begin
          if (PFLOATs(@pPatch012[z * pStream.uiOrigStride])[2] = 0.0) then
              PFLOATs(@pPatch012[z * pStream.uiOrigStride])[2] := 1.0;
          if (PFLOATs(@pPatch012[z * pStream.uiOrigStride])[3] = 0.0) then
              PFLOATs(@pPatch012[z * pStream.uiOrigStride])[3] := 1.0;
        end;
      end;

      Inc(pPatch012, pStream.uiOrigStride * VERTICES_PER_TRIANGLE * TRIANGLES_PER_QUAD);
      Inc(pPatch34,  pStream.uiOrigStride * VERTICES_PER_TRIANGLE * TRIANGLES_PER_QUAD);
      Inc(pPatch5,   pStream.uiOrigStride * VERTICES_PER_TRIANGLE * TRIANGLES_PER_QUAD);

      Inc(pOrig012, pStream.uiOrigStride * VERTICES_PER_QUAD);
      Inc(pOrig2,   pStream.uiOrigStride * VERTICES_PER_QUAD);
    end;
  end
  // LineLoop
  else if (pPatchDesc.PrimitiveType = X_D3DPT_LINELOOP) then
  begin
    memcpy(@pPatchedVertexData[pPatchDesc.dwOffset], @pOrigVertexData[pPatchDesc.dwOffset], dwOriginalSize);
    // Append a second copy of the first vertex to the end, completing the strip to form a loop :
    memcpy(@pPatchedVertexData[pPatchDesc.dwOffset + dwOriginalSize], @pOrigVertexData[pPatchDesc.dwOffset], pStream.uiOrigStride);
  end;

  if (pPatchDesc.pVertexStreamZeroData = nil) then
  begin
//    if (pStream.pOriginalStream <> nil) then // Dxbx addition
      IDirect3DVertexBuffer8(pStream.pOriginalStream).Unlock();

//    if (pStream.pPatchedStream <> nil) then // Dxbx addition
    begin
      IDirect3DVertexBuffer8(pStream.pPatchedStream).Unlock();

      IDirect3DDevice8(g_pD3DDevice8).SetStreamSource(0, IDirect3DVertexBuffer8(pStream.pPatchedStream), pStream.uiOrigStride);
    end;
  end;

  m_bPatched := true;

  Result := true;
end; // VertexPatcher.PatchPrimitive

function VertexPatcher.Apply(pPatchDesc: PVertexPatchDesc; pbFatalError: P_bool): _bool;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:Shadow_Tj  Done:100
var
  Patched: _bool;
  uiStream: UINT;
  LocalPatched: _bool;
begin
  Patched := false;
  // Get the number of streams
  m_uiNbrStreams := GetNbrStreams(pPatchDesc);
  if (VshHandleIsVertexShader(pPatchDesc.hVertexShader)) then
  begin
    m_pDynamicPatch := @(PVERTEX_SHADER(VshHandleGetVertexShader(pPatchDesc.hVertexShader).Handle).VertexDynamicPatch);
  end;
  if m_uiNbrStreams > 0 then // Dxbx addition, to prevent underflow
  for uiStream := 0 to m_uiNbrStreams - 1 do
  begin
    LocalPatched := false;

    if (ApplyCachedStream(pPatchDesc, uiStream, pbFatalError)) then
    begin
      m_pStreams[uiStream].bUsedCached := true;
      continue;
    end;

	// Dxbx note : Different from Cxbx, to avoid lazy boolean evaluation :
    if PatchPrimitive(pPatchDesc, uiStream) then
      LocalPatched := True;
    if PatchStream(pPatchDesc, uiStream) then
      LocalPatched := True;
    if LocalPatched and (nil=pPatchDesc.pVertexStreamZeroData) then
    begin
      // Insert the patched stream in the cache
      CacheStream(pPatchDesc, uiStream);
      m_pStreams[uiStream].bUsedCached := true;
    end;
    Patched := Patched or LocalPatched;
  end;

  Result := Patched;
end; // VertexPatcher.Apply

function VertexPatcher.Restore(): _bool;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:Shadow_Tj  Done:100
var
  uiStream: UINT;
begin
  if (not m_bPatched) then
  begin
    Result := false;
    Exit;
  end;

  if m_uiNbrStreams > 0 then // Dxbx addition, to prevent underflow
  for uiStream := 0 to m_uiNbrStreams - 1 do
  begin
    if (m_pStreams[uiStream].pOriginalStream <> NULL) and (m_pStreams[uiStream].pPatchedStream <> NULL) then
    begin
      IDirect3DDevice8(g_pD3DDevice8).SetStreamSource(0, IDirect3DVertexBuffer8(m_pStreams[uiStream].pOriginalStream), m_pStreams[uiStream].uiOrigStride);
    end;

    if (m_pStreams[uiStream].pOriginalStream <> NULL) then
    begin
      IDirect3DVertexBuffer8(m_pStreams[uiStream].pOriginalStream)._Release();
      m_pStreams[uiStream].pOriginalStream := nil; // Dxbx addition - nil out after decreasing reference count
    end;

    if (m_pStreams[uiStream].pPatchedStream <> NULL) then
    begin
      IDirect3DVertexBuffer8(m_pStreams[uiStream].pPatchedStream)._Release();
      m_pStreams[uiStream].pPatchedStream := nil; // Dxbx addition - nil out after decreasing reference count
    end;

    if (not m_pStreams[uiStream].bUsedCached) then
    begin
      if (Self.m_bAllocatedStreamZeroData) then
      begin
        CxbxFree(m_pNewVertexStreamZeroData);
      end;
    end
    else
    begin
      m_pStreams[uiStream].bUsedCached := false;
    end;

  end;

  Result := true;
end; // VertexPatcher.Restore

procedure XTL_EmuFlushIVB(); {NOPATCH}
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
var
  pdwVB: PDWORD;
  uiStride: UINT;
  bFVF: _bool;
  dwCurFVF: DWORD;
  v: uint;
  dwPos: DWORD;
  dwTexN: DWORD;
  VPDesc: VertexPatchDesc;
  VertPatch: VertexPatcher;
  //bPatched: _bool;
begin
  XTL_EmuUpdateDeferredStates();

  pdwVB := PDWORD(g_IVBTable);

  uiStride := 0;

  // Parse IVB table with current FVF shader if possible.
  bFVF := not VshHandleIsVertexShader(g_CurrentVertexShader);

  if(bFVF and ((g_CurrentVertexShader and D3DFVF_POSITION_MASK) <> D3DFVF_XYZRHW)) then
  begin
    dwCurFVF := g_CurrentVertexShader;

    // HACK: Halo...
    if(dwCurFVF = 0) then
    begin
      EmuWarning('EmuFlushIVB(): using g_IVBFVF instead of current FVF!');
      dwCurFVF := g_IVBFVF;
    end;
  end
  else
  begin
    dwCurFVF := g_IVBFVF;
  end;

  DbgPrintf('g_IVBTblOffs := %d', [g_IVBTblOffs]);

  if g_IVBTblOffs > 0 then // Dxbx addition, to prevent underflow
  for v := 0 to g_IVBTblOffs - 1 do
  begin
    dwPos := dwCurFVF and D3DFVF_POSITION_MASK;

    if(dwPos = D3DFVF_XYZ) then
    begin
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Position.x; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Position.y; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Position.z; Inc(PFLOAT(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, (sizeof(FLOAT)*3));
      end;

      DbgPrintf('IVB Position := {%f, %f, %f}', [g_IVBTable[v].Position.x, g_IVBTable[v].Position.y, g_IVBTable[v].Position.z]);

    end
    else if(dwPos = D3DFVF_XYZRHW) then
    begin
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Position.x; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Position.y; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Position.z; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Rhw;        Inc(PFLOAT(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, (sizeof(FLOAT)*4));
      end;

      DbgPrintf('IVB Position := {%f, %f, %f, %f}', [g_IVBTable[v].Position.x, g_IVBTable[v].Position.y, g_IVBTable[v].Position.z, g_IVBTable[v].Position.z, g_IVBTable[v].Rhw]);
    end
    else if(dwPos = D3DFVF_XYZB1) then
    begin
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Position.x; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Position.y; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Position.z; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Blend1;     Inc(PFLOAT(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, (sizeof(FLOAT)*4));
      end;

      DbgPrintf('IVB Position := {%f, %f, %f, %f', [g_IVBTable[v].Position.x, g_IVBTable[v].Position.y, g_IVBTable[v].Position.z, g_IVBTable[v].Blend1]);
    end

    else
    begin
      CxbxKrnlCleanup('Unsupported Position Mask (FVF := 0x%.08X dwPos := 0x%.08X)', [g_IVBFVF, dwPos]);
    end;

// Cxbx     if(dwPos = D3DFVF_NORMAL) then // <- This didn't look right but if it is, change it back...
    if(dwCurFVF and D3DFVF_NORMAL) > 0 then
    begin
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Normal.x; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Normal.y; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].Normal.z; Inc(PFLOAT(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, (sizeof(FLOAT)*3));
      end;

      DbgPrintf('IVB Normal := {%f, %f, %f}', [g_IVBTable[v].Normal.x, g_IVBTable[v].Normal.y, g_IVBTable[v].Normal.z]);

    end;

    if(dwCurFVF and D3DFVF_DIFFUSE) > 0 then
    begin
      PDWORDs(pdwVB)[0] := g_IVBTable[v].dwDiffuse; Inc(PDWORD(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, sizeof(DWORD));
      end;

      DbgPrintf('IVB Diffuse := 0x%.08X', [g_IVBTable[v].dwDiffuse]);
    end;

    if(dwCurFVF and D3DFVF_SPECULAR) > 0 then
    begin
      PDWORDs(pdwVB)[0] := g_IVBTable[v].dwSpecular; Inc(PDWORD(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, sizeof(DWORD));
      end;

      DbgPrintf('IVB Specular := 0x%.08X', [g_IVBTable[v].dwSpecular]);
    end;

    dwTexN := (dwCurFVF and D3DFVF_TEXCOUNT_MASK) shr D3DFVF_TEXCOUNT_SHIFT;

    if(dwTexN >= 1) then
    begin
      PFLOATs(pdwVB)[0] := g_IVBTable[v].TexCoord1.x; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].TexCoord1.y; Inc(PFLOAT(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, sizeof(FLOAT)*2);
      end;

      DbgPrintf('IVB TexCoord1 := {%f, %f}', [g_IVBTable[v].TexCoord1.x, g_IVBTable[v].TexCoord1.y]);
    end;

    if(dwTexN >= 2) then
    begin
      PFLOATs(pdwVB)[0] := g_IVBTable[v].TexCoord2.x; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].TexCoord2.y; Inc(PFLOAT(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, sizeof(FLOAT)*2);
      end;

      DbgPrintf('IVB TexCoord2 := {%f, %f}', [g_IVBTable[v].TexCoord2.x, g_IVBTable[v].TexCoord2.y]);
    end;

    if(dwTexN >= 3) then
    begin
      PFLOATs(pdwVB)[0] := g_IVBTable[v].TexCoord3.x; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].TexCoord3.y; Inc(PFLOAT(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, sizeof(FLOAT)*2);
      end;

      DbgPrintf('IVB TexCoord3 := {%f, %f}', [g_IVBTable[v].TexCoord3.x, g_IVBTable[v].TexCoord3.y]);
    end;

    if(dwTexN >= 4) then
    begin
      PFLOATs(pdwVB)[0] := g_IVBTable[v].TexCoord4.x; Inc(PFLOAT(pdwVB));
      PFLOATs(pdwVB)[0] := g_IVBTable[v].TexCoord4.y; Inc(PFLOAT(pdwVB));

      if(v = 0) then
      begin
        Inc(uiStride, sizeof(FLOAT)*2);
      end;

      DbgPrintf('IVB TexCoord4 := {%f, %f}', [g_IVBTable[v].TexCoord4.x, g_IVBTable[v].TexCoord4.y]);
    end;
  end;

  VPDesc.VertexPatchDesc(); // Dxbx addition : explicit initializer

  VPDesc.PrimitiveType := g_IVBPrimitiveType;
  VPDesc.dwVertexCount := g_IVBTblOffs;
  // Dxbx : Why not this : VPDesc.dwPrimitiveCount := EmuD3DVertex2PrimitiveCount(VPDesc.PrimitiveType, VPDesc.dwVertexCount);
  VPDesc.dwOffset := 0;
  VPDesc.pVertexStreamZeroData := g_IVBTable;
  VPDesc.uiVertexStreamZeroStride := uiStride;
  VPDesc.hVertexShader := g_CurrentVertexShader;

  VertPatch.VertexPatcher(); // Dxbx addition : explicit initializer

  {bPatched := }VertPatch.Apply(@VPDesc, NULL);

  if(bFVF) then
  begin
    IDirect3DDevice8(g_pD3DDevice8).SetVertexShader(dwCurFVF);
  end;

  IDirect3DDevice8(g_pD3DDevice8).DrawPrimitiveUP(
      EmuPrimitiveType(VPDesc.PrimitiveType),
      VPDesc.dwPrimitiveCount,
      VPDesc.pVertexStreamZeroData,
      VPDesc.uiVertexStreamZeroStride);

  if(bFVF) then
  begin
    IDirect3DDevice8(g_pD3DDevice8).SetVertexShader(g_CurrentVertexShader);
  end;

  VertPatch.Restore();

  VertPatch._VertexPatcher(); // Dxbx addition : explicit finalizer

  g_IVBTblOffs := 0;
end; // XTL_EmuFlushIVB

procedure XTL_EmuUpdateActiveTexture(); {NOPATCH}
// Branch:shogun  Revision:162  Translator:Shadow_Tj  Done:100
var
  Stage: int;
  pTexture: PX_D3DResource;
  pResource: PX_D3DResource;
  pPixelContainer: PX_D3DPixelContainer;
  X_Format: X_D3DFORMAT;
  dwWidth: DWORD;
  dwHeight: DWORD;
  dwBPP: DWORD;
  dwDepth: DWORD;
  dwPitch: DWORD;
  dwMipMapLevels: DWORD;
  bSwizzled: BOOL_;
  bCompressed: BOOL_;
  dwCompressedSize: DWORD;
  bCubemap: BOOL_;

  dwCompressedOffset: DWORD;
  dwMipOffs: DWORD;
  dwMipWidth: DWORD;
  dwMipHeight: DWORD;
  dwMipPitch: DWORD;
  level: uint;

  LockedRect: D3DLOCKED_RECT;

  hRet: HRESULT;

  iRect: TRect;
  iPoint: TPoint;
  pSrc: PBYTE;
  pDest: PBYTE;
  v: DWORD;
begin
  dwWidth := 0;
  dwHeight := 0;
  dwBPP := 0;

  //
  // DEBUGGING
  //
  for Stage := 0 to 4-1 do
  begin
    pTexture := EmuD3DActiveTexture[Stage];

    if (pTexture = NULL) then
      continue;

    pResource := pTexture;
    pPixelContainer := PX_D3DPixelContainer(pTexture);

    X_Format := X_D3DFORMAT(((pPixelContainer.Format and X_D3DFORMAT_FORMAT_MASK) shr X_D3DFORMAT_FORMAT_SHIFT));

    if (X_Format <> $CD) and (IDirect3DResource8(pTexture.Emu.Resource8).GetType() = D3DRTYPE_TEXTURE) then
    begin
      dwWidth := 1; dwHeight := 1; dwBPP := 1; dwDepth := 1; dwPitch := 0; dwMipMapLevels := 1;
      bSwizzled := FALSE; bCompressed := FALSE; dwCompressedSize := 0;
      //bCubemap := (pPixelContainer.Format and X_D3DFORMAT_CUBEMAP) > 0;

      // Interpret Width/Height/BPP
      if (X_Format = X_D3DFMT_X8R8G8B8) or (X_Format = X_D3DFMT_A8R8G8B8) then
      begin
        bSwizzled := TRUE;

        // Swizzled 32 Bit
        dwWidth  := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_USIZE_MASK) shr X_D3DFORMAT_USIZE_SHIFT);
        dwHeight := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_VSIZE_MASK) shr X_D3DFORMAT_VSIZE_SHIFT);
        dwMipMapLevels := (pPixelContainer.Format and X_D3DFORMAT_MIPMAP_MASK) shr X_D3DFORMAT_MIPMAP_SHIFT;
        dwDepth  := 1;// HACK? 1 << ((pPixelContainer.Format and X_D3DFORMAT_PSIZE_MASK) shr X_D3DFORMAT_PSIZE_SHIFT);
        dwPitch  := dwWidth*4;
        dwBPP := 4;
      end
      else if (X_Format = X_D3DFMT_R5G6B5) or (X_Format = X_D3DFMT_A4R4G4B4)
           or (X_Format = X_D3DFMT_A1R5G5B5)
           or (X_Format = X_D3DFMT_G8B8) then
      begin
        bSwizzled := TRUE;

        // Swizzled 16 Bit
        dwWidth := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_USIZE_MASK) shr X_D3DFORMAT_USIZE_SHIFT);
        dwHeight := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_VSIZE_MASK) shr X_D3DFORMAT_VSIZE_SHIFT);
        dwMipMapLevels := (pPixelContainer.Format and X_D3DFORMAT_MIPMAP_MASK) shr X_D3DFORMAT_MIPMAP_SHIFT;
        dwDepth := 1; // HACK? 1 << ((pPixelContainer.Format and X_D3DFORMAT_PSIZE_MASK) shr X_D3DFORMAT_PSIZE_SHIFT);
        dwPitch := dwWidth * 2;
        dwBPP := 2;
      end
      else if (X_Format = X_D3DFMT_L8) or (X_Format = X_D3DFMT_P8) 
           or (X_Format = X_D3DFMT_AL8) or (X_Format = X_D3DFMT_A8L8) then
      begin
        bSwizzled := TRUE;

        // Swizzled 8 Bit
        dwWidth  := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_USIZE_MASK) shr X_D3DFORMAT_USIZE_SHIFT);
        dwHeight := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_VSIZE_MASK) shr X_D3DFORMAT_VSIZE_SHIFT);
        dwMipMapLevels := (pPixelContainer.Format and X_D3DFORMAT_MIPMAP_MASK) shr X_D3DFORMAT_MIPMAP_SHIFT;
        dwDepth  := 1;// HACK? 1 << ((pPixelContainer.Format and X_D3DFORMAT_PSIZE_MASK) shr X_D3DFORMAT_PSIZE_SHIFT);
        dwPitch  := dwWidth;
        dwBPP := 1;
      end
      else if (X_Format = X_D3DFMT_LIN_X8R8G8B8) or (X_Format = X_D3DFMT_LIN_A8R8G8B8{=$12})
           or (X_Format = X_D3DFMT_LIN_D24S8) or (X_Format = X_D3DFMT_LIN_A8B8G8R8) then
      begin
        // Linear 32 Bit
        dwWidth  := (pPixelContainer.Size and X_D3DSIZE_WIDTH_MASK) + 1;
        dwHeight := ((pPixelContainer.Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1;
        dwPitch  := (((pPixelContainer.Size and X_D3DSIZE_PITCH_MASK) shr X_D3DSIZE_PITCH_SHIFT)+1)*64;
        dwBPP := 4;
      end
      else if (X_Format = X_D3DFMT_LIN_R5G6B5)   or (X_Format = X_D3DFMT_LIN_D16)
           or (X_Format = X_D3DFMT_LIN_A4R4G4B4) or (X_Format = X_D3DFMT_LIN_A1R5G5B5) then
      begin
        // Linear 16 Bit
        dwWidth := (pPixelContainer.Size and X_D3DSIZE_WIDTH_MASK) + 1;
        dwHeight := ((pPixelContainer.Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1;
        dwPitch := (((pPixelContainer.Size and X_D3DSIZE_PITCH_MASK) shr X_D3DSIZE_PITCH_SHIFT) + 1) * 64;
        dwBPP := 2;
      end
      else if (X_Format = X_D3DFMT_DXT1) or (X_Format = X_D3DFMT_DXT3) or (X_Format = X_D3DFMT_DXT5) then
      begin
        bCompressed := TRUE;

        // Compressed
        dwWidth  := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_USIZE_MASK) shr X_D3DFORMAT_USIZE_SHIFT);
        dwHeight := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_VSIZE_MASK) shr X_D3DFORMAT_VSIZE_SHIFT);
        dwDepth  := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_PSIZE_MASK) shr X_D3DFORMAT_PSIZE_SHIFT);
        dwMipMapLevels := (pPixelContainer.Format and X_D3DFORMAT_MIPMAP_MASK) shr X_D3DFORMAT_MIPMAP_SHIFT;

        // D3DFMT_DXT2...D3DFMT_DXT5 : 128bits per block/per 16 texels
        dwCompressedSize := dwWidth * dwHeight;

        if (X_Format = X_D3DFMT_DXT1) then // 64bits per block/per 16 texels
          dwCompressedSize := dwCompressedSize div 2;

        dwBPP := 1;
      end
      else if (X_Format = X_D3DFMT_YUY2) then
      begin
        // Linear 32 Bit
        dwWidth := (pPixelContainer.Size and X_D3DSIZE_WIDTH_MASK) + 1;
        dwHeight := ((pPixelContainer.Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1;
        dwPitch := (((pPixelContainer.Size and X_D3DSIZE_PITCH_MASK) shr X_D3DSIZE_PITCH_SHIFT) + 1) * 64;
      end
      else
      begin
        CxbxKrnlCleanup('0x%.08X is not a supported format!', [X_Format]);
      end;

      // as we iterate through mipmap levels, we'll adjust the source resource offset
      dwCompressedOffset := 0;

      dwMipOffs := 0;
      dwMipWidth := dwWidth;
      dwMipHeight := dwHeight;
      dwMipPitch := dwPitch;

      if (dwMipMapLevels > 6) then
        dwMipMapLevels := 6;

      // iterate through the number of mipmap levels
      if dwMipMapLevels > 0 then // Dxbx addition, to prevent underflow
      for level := 0 to dwMipMapLevels - 1 do
      begin
        {hRet := }IDirect3DTexture8(pResource.Emu.Texture8).LockRect(level, {out}LockedRect, NULL, 0);

        iRect := classes.Rect(0, 0, 0, 0);
        iPoint := classes.Point(0, 0);

        pSrc := PBYTE(pTexture.Data);

        if IsSpecialResource(pResource.Data) and ((pResource.Data and X_D3DRESOURCE_DATA_FLAG_SURFACE) > 0) then
        begin

        end
        else
        begin
          if (bSwizzled) then
          begin
            if (DWORD(pSrc) = $80000000) then
            begin
              // TODO -oCXBX: Fix or handle this situation..?
            end
            else
            begin
              XTL_EmuXGUnswizzleRect
              (
                pSrc + dwMipOffs, dwMipWidth, dwMipHeight, dwDepth, LockedRect.pBits,
                LockedRect.Pitch, iRect, iPoint, dwBPP
              );
            end;
          end
          else if (bCompressed) then
          begin
            // NOTE: compressed size is (dwWidth/2)*(dwHeight/2)/2, so each level divides by 4

            memcpy(LockedRect.pBits, pSrc + dwCompressedOffset, dwCompressedSize shr (level * 2));

            Inc(dwCompressedOffset, (dwCompressedSize shr (level * 2)));
          end
          else
          begin
            pDest := PBYTE(LockedRect.pBits);

            if (DWORD(LockedRect.Pitch) = dwMipPitch) and (dwMipPitch = dwMipWidth * dwBPP) then
            begin
              memcpy(pDest, pSrc + dwMipOffs, dwMipWidth * dwMipHeight * dwBPP);
            end
            else
            begin
              if dwMipHeight > 0 then // Dxbx addition, to prevent underflow
              for v := 0 to dwMipHeight - 1 do
              begin
                memcpy(pDest, pSrc + dwMipOffs, dwMipWidth * dwBPP);

                Inc(pDest, LockedRect.Pitch);
                Inc(pSrc, dwMipPitch);
              end;
            end;
          end;
        end;

        IDirect3DTexture8(pResource.Emu.Texture8).UnlockRect(level);

        Inc(dwMipOffs, dwMipWidth * dwMipHeight * dwBPP);

        dwMipWidth := dwMipWidth div 2;
        dwMipHeight := dwMipHeight div 2;
        dwMipPitch := dwMipPitch div 2;
      end;
    end;

    IDirect3DDevice8(g_pD3DDevice8).SetTexture(Stage, IDirect3DTexture8(pTexture.Emu.Texture8));

  end;
end; // XTL_EmuUpdateActiveTexture

{.$MESSAGE 'PatrickvL reviewed up to here'}
end.
