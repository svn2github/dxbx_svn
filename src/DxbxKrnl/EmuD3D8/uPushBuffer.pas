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

unit uPushBuffer;

{$INCLUDE Dxbx.inc}

interface

uses
  // Delphi
  Windows
  , Classes
  , SysUtils
  , Direct3D8
  // Dxbx
  , uDxbxUtils // iif
  , uTypes
  , uVertexBuffer
  , uEmu
  , uEmuXG
  , uEmuD3D8Types;

var
  // primary push buffer
  g_dwPrimaryPBCount: UInt32 = 0;
  g_pPrimaryPB: PDWORD = nil;

  // push buffer debugging
  XTL_g_bStepPush: Boolean = False;
  XTL_g_bSkipPush: Boolean = False;
  XTL_g_bBrkPush: Boolean = False;

  g_bPBSkipPusher: Boolean = False;

var
  pIBMem: array [0..3] of Word = ($FFFF, $FFFF, $FFFF, $FFFF);


procedure XTL_EmuExecutePushBuffer(pPushBuffer: PX_D3DPushBuffer; pFixup: PX_D3DFixup); stdcall;
procedure XTL_EmuExecutePushBufferRaw(pdwPushData: PDWord); stdcall; // forward

implementation

uses
  // Dxbx
  uDxbxKrnlUtils
  , uEmuD3D8
  , uLog
  , uState
  , uEmuXTL
  , JwaWinType
  , uVertexShader
  , uConvert;


procedure XTL_EmuExecutePushBuffer
(
    pPushBuffer: PX_D3DPushBuffer; 
    pFixup: PX_D3DFixup
); stdcall;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:100
begin
  if Assigned(pFixup) then
    CxbxKrnlCleanup('PushBuffer has fixups');

  XTL_EmuExecutePushBufferRaw(PDWORD(pPushBuffer.Data));
end;

procedure EmuUnswizzleActiveTexture();
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:95
var
  pPixelContainer: PX_D3DPixelContainer;
  XBFormat: DWord;
  dwBPP: DWord;
  pTexture: IDirect3DTexture8;
  dwLevelCount: DWord;
  v: uint32;
  SurfaceDesc: D3DSURFACE_DESC;
  hRet: HRESULT;
  LockedRect: D3DLOCKED_RECT;

  dwWidth: DWord;
  dwHeight: DWord;
  dwDepth: DWord;
  dwPitch: DWord;
  iRect: TRect;
  iPoint: TPoint;

  pTemp: Pointer;
begin
  // for current usages, we're always on stage 0
  pPixelContainer := PX_D3DPixelContainer(EmuD3DActiveTexture[0]);

  if (pPixelContainer = nil) or ((pPixelContainer.Common and X_D3DCOMMON_ISLOCKED) = 0) then
    Exit;

  XBFormat := (pPixelContainer.Format and X_D3DFORMAT_FORMAT_MASK) shr X_D3DFORMAT_FORMAT_SHIFT;
  dwBPP := 0;

  if (not EmuXBFormatIsSwizzled(XBFormat, @dwBPP)) then
    Exit;

  // remove lock
  pPixelContainer.EmuTexture8.UnlockRect(0);
  pPixelContainer.Common := pPixelContainer.Common and (not X_D3DCOMMON_ISLOCKED);

  // Cxbx TODO: potentially CRC to see if this surface was actually modified..
  // unswizzle texture

  begin
    pTexture := pPixelContainer.EmuTexture8;

    dwLevelCount := pTexture.GetLevelCount();

    for v := 0 to dwLevelCount - 1 do
    begin
      hRet := pTexture.GetLevelDesc(v, SurfaceDesc);

      if (FAILED(hRet)) then
        Continue;

      //
      // perform unswizzle
      //

      begin
        // Cxbx has this commented out :
        //if (SurfaceDesc.Format <> XTL_D3DFMT_A8R8G8B8) then
        //  Break;
        //CxbxKrnlCleanup('Temporarily unsupported format for active texture unswizzle (0x%.08X)', [SurfaceDesc.Format]);

        hRet := pTexture.LockRect(v, LockedRect, nil, 0);

        if (FAILED(hRet)) then
          Continue;

        dwWidth := SurfaceDesc.Width;
        dwHeight := SurfaceDesc.Height;
        dwDepth := 1;
        dwPitch := LockedRect.Pitch;
        iRect := Classes.Rect(0,0,0,0);
        iPoint := Classes.Point(0,0);

        pTemp := malloc(dwHeight*dwPitch);

        XTL_EmuXGUnswizzleRect
        (
            LockedRect.pBits, dwWidth, dwHeight, dwDepth,
            pTemp, dwPitch, iRect, iPoint, dwBPP
        );

        memcpy(LockedRect.pBits, pTemp, dwPitch*dwHeight);

        pTexture.UnlockRect(0);

        free(pTemp);
      end;
    end;

{$IFDEF DEBUG}
    DbgPrintf('Active texture was unswizzled');
{$ENDIF}
  end;

end;

procedure XTL_EmuExecutePushBufferRaw
(
    pdwPushData: PDWord
); stdcall;
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:80
var
  pdwOrigPushData: PDWord;
  pIndexData: PVOID;
  pVertexData: PVOID;

  dwVertexShader: DWord;
  dwStride: DWord;
  bShowPB: bool;

  PCPrimitiveType: D3DPRIMITIVETYPE;
  XBPrimitiveType: X_D3DPRIMITIVETYPE;

  pIndexBuffer: IDIRECT3DINDEXBUFFER8;
  pVertexBuffer: IDIRECT3DVERTEXBUFFER8;
  maxIBSize: uint;

  dwCount: DWord;
  dwMethod: DWord;

  bInc: BOOL;

  hRet: HRESULT;
  pData: PWORDArray;

  VertexCount: UINT;
  PrimitiveCount: UINT;
  VPDesc: VertexPatchDesc;

  VertPatch: XTL_VertexPatcher;
  bPatched: bool;

  pwVal: PWORD;
  s: uint;
  mi: uint;
  pVBData: PBYTE;

  uiStride: UINT;
begin
  if XTL_g_bSkipPush then
    Exit;

  pdwOrigPushData := pdwPushData;

  pIndexData := nil;
  pVertexData := nil;

  dwVertexShader := 0;
  dwStride := 0;

  PCPrimitiveType := D3DPRIMITIVETYPE(-1);
  XBPrimitiveType := X_D3DPT_INVALID;

  // Cxbx TODO: This technically should be enabled
  XTL_EmuUpdateDeferredStates();

{$ifdef _DEBUG_TRACK_PB}
  bShowPB := False;
  g_PBTrackTotal.insert(pdwPushData);

  if (g_PBTrackShowOnce.exists(pdwPushData)) then
  begin
    g_PBTrackShowOnce.remove(pdwPushData);

{$IFDEF DEBUG}
    DbgPrintf('');
    DbgPrintf('');
    DbgPrintf('  PushBuffer@$%.08X...', [pdwPushData]);
    DbgPrintf('');
{$ENDIF}

    bShowPB := True;
  end;
{$endif}

  pIndexBuffer  := nil;
  pVertexBuffer := nil;
  maxIBSize     := 0;

  while True do
  begin
    dwCount := (pdwPushData^ shr 18);
    dwMethod := (pdwPushData^ and $3FFFF);

    // Interpret GPU Instruction
    if (dwMethod = $000017FC) then  // NVPB_SetBeginEnd
    begin
      Inc(pdwPushData); // Dxbx Todo : Verify correct use of Inc

      {$ifdef _DEBUG_TRACK_PB}
      if (bShowPB) then
      begin
        DbgPrintf('  NVPB_SetBeginEnd(');
      end;
      {$endif}

      if (pdwPushData^ = 0) then
      begin
        {$ifdef _DEBUG_TRACK_PB}
        if (bShowPB) then
        begin
          DbgPrintf('DONE)');
        end;
        {$endif}
        Break;  // done?
      end
      else
      begin
        {$IFDEF DEBUG}
        if (bShowPB) then
        begin
          DbgPrintf('PrimitiveType := %d)', [pdwPushData^]);
        end;
        {$endif}

        XBPrimitiveType := X_D3DPRIMITIVETYPE(pdwPushData^);
        PCPrimitiveType := EmuPrimitiveType(XBPrimitiveType);
      end;
    end
    else if (dwMethod = $1818) then  // NVPB_InlineVertexArray
    begin
      bInc := (pdwPushData^ and $40000000) > 0;

      if (bInc) then
      begin
        dwCount := (pdwPushData^ - ($40000000 or $00001818)) shr 18;
      end;

      Inc(pdwPushData); pVertexData := pdwPushData;

      Inc(pdwPushData, dwCount);

      // retrieve vertex shader
      g_pD3DDevice8.GetVertexShader({out}dwVertexShader);

      if (dwVertexShader > $FFFF) then
      begin
        CxbxKrnlCleanup('Non-FVF Vertex Shaders not yet supported for PushBuffer emulation!');
        dwVertexShader := 0;
      end
      else if (dwVertexShader = 0) then
      begin
        EmuWarning('FVF Vertex Shader is null');
        dwVertexShader := DWORD(-1);
      end;

      //
      // calculate stride
      //

      dwStride := 0;

      if (not VshHandleIsVertexShader(dwVertexShader)) then
      begin
        if (dwVertexShader and D3DFVF_XYZRHW) > 0 then begin Inc(dwStride, SizeOf(FLOAT) * 4); end;
        if (dwVertexShader and D3DFVF_DIFFUSE) > 0 then begin Inc(dwStride, SizeOf(DWord)); end;
        if (dwVertexShader and D3DFVF_SPECULAR) > 0 then begin Inc(dwStride, SizeOf(DWord)); end;

        Inc(dwStride, ((dwVertexShader and D3DFVF_TEXCOUNT_MASK) shr D3DFVF_TEXCOUNT_SHIFT)*SizeOf(FLOAT)*2);
      end;

      { MARKED OUT BY CXBX
      // create cached vertex buffer only once, with maxed out size
      if (pVertexBuffer = nil) then
      begin
        hRet := IDirect3DDevice8_CreateVertexBuffer(g_pD3DDevice8, 2047*SizeOf(DWord), D3DUSAGE_WRITEONLY, dwVertexShader, D3DPOOL_MANAGED, @pVertexBuffer);

        if (FAILED(hRet)) then
          CxbxKrnlCleanup('Unable to create vertex buffer cache for PushBuffer emulation ($1818, dwCount : %d)', [dwCount]);

      end;

      // copy vertex data
      begin
        pData: PUInt8 := nil;

        hRet := pVertexBuffer.Lock(0, dwCount*4, @pData, 0);

        if (FAILED(hRet)) then
          CxbxKrnlCleanup('Unable to lock vertex buffer cache for PushBuffer emulation ($1818, dwCount : %d)', [dwCount]);

        memcpy(pData, pVertexData, dwCount*4);

        pVertexBuffer.Unlock();
      end;
      }

      {$ifdef _DEBUG_TRACK_PB}
      if (bShowPB) then
      begin
        printf('NVPB_InlineVertexArray(...)');
        printf('  dwCount : %d', dwCount);
        printf('  dwVertexShader : $%08X', dwVertexShader);
      end;
      {$endif}

      EmuUnswizzleActiveTexture();

      // render vertices
      if (dwVertexShader <> -1) then
      begin
        VertexCount := (dwCount*SizeOf(DWord)) div dwStride;
        PrimitiveCount := EmuD3DVertex2PrimitiveCount(XBPrimitiveType, VertexCount);

        VPDesc.dwVertexCount := VertexCount;
        VPDesc.PrimitiveType := XBPrimitiveType;
        VPDesc.dwPrimitiveCount := PrimitiveCount;
        VPDesc.dwOffset := 0;
        VPDesc.pVertexStreamZeroData := pVertexData;
        VPDesc.uiVertexStreamZeroStride := dwStride;
        VPDesc.hVertexShader := dwVertexShader;

        bPatched := VertPatch.Apply(@VPDesc);

        g_pD3DDevice8.DrawPrimitiveUP
        (
            PCPrimitiveType,
            VPDesc.dwPrimitiveCount,
            VPDesc.pVertexStreamZeroData,
            VPDesc.uiVertexStreamZeroStride
        );

        VertPatch.Restore();
      end;

      Dec(pdwPushData);
    end
    else if (dwMethod = $1808) then  // NVPB_FixLoop
    begin
      {$ifdef _DEBUG_TRACK_PB}
      if (bShowPB) then
      begin
        printf('  NVPB_FixLoop(%d)', dwCount);
        printf('');
        printf('  Index Array Data...');

        pwVal := PWORD(pdwPushData + 1);

        for s := 0 to dwCount - 1 do
        begin
          if (s mod 8 = 0) then printf('  ');

          printf('  %.04X', pwVal^); Inc(pwVal);
        end;

        printf('');
        printf('');
      end;
      {$endif}

(*
      pwVal := PWORD(pdwPushData + 1);
      for mi := 0 to dwCount - 1 do
      begin
        pIBMem[mi+2] := pwVal[mi];
      end;
*)

      // perform rendering
      if (pIBMem[0] <> $FFFF) then
      begin
        // Cxbx TODO: depreciate maxIBSize after N milliseconds..then N milliseconds later drop down to new highest
        if ((dwCount*2 + 2*2) > maxIBSize) then
        begin
          if Assigned(pIndexBuffer) then
          begin
            pIndexBuffer._Release();
          end;

          hRet := g_pD3DDevice8.CreateIndexBuffer(dwCount*2 + 2*2, 0, D3DFMT_INDEX16, D3DPOOL_MANAGED, {out}pIndexBuffer);

          maxIBSize := dwCount*2 + 2*2;
        end
        else
        begin
          hRet := D3D_OK;
        end;

        if (FAILED(hRet)) then
          CxbxKrnlCleanup('Unable to create index buffer for PushBuffer emulation ($1808, dwCount : %d)', [dwCount]);

        // copy index data
        begin
          pData := nil;

          pIndexBuffer.Lock(0, dwCount*2 + 2*2, {out}PByte(pData), 0);

          memcpy(pData, @pIBMem[0], dwCount*2 + 2*2);

          pIndexBuffer.Unlock();
        end;

        // render indexed vertices
        begin
          PrimitiveCount := EmuD3DVertex2PrimitiveCount(XBPrimitiveType, dwCount + 2);

          VPDesc.dwVertexCount := dwCount;
          VPDesc.PrimitiveType := XBPrimitiveType;
          VPDesc.dwPrimitiveCount := PrimitiveCount;
          VPDesc.dwOffset := 0;
          VPDesc.pVertexStreamZeroData := 0;
          VPDesc.uiVertexStreamZeroStride := 0;
          // Cxbx TODO: Set the current shader and let the patcher handle it..
          VPDesc.hVertexShader := g_CurrentVertexShader;

          bPatched := VertPatch.Apply(@VPDesc);

          g_pD3DDevice8.SetIndices(pIndexBuffer, 0);

          {$ifdef _DEBUG_TRACK_PB}
          if ( not g_PBTrackDisable.exists(pdwOrigPushData)) then
          begin
          {$endif}

          if (not g_bPBSkipPusher) then
          begin
            if (XTL_IsValidCurrentShader()) then
            begin
              g_pD3DDevice8.DrawIndexedPrimitive
              (
                  PCPrimitiveType, 0, 8*1024*1024, 0, PrimitiveCount
//                  PCPrimitiveType, 0, dwCount*2, 0, PrimitiveCount
              );
            end;
          end;

          {$ifdef _DEBUG_TRACK_PB}
          end;
          {$endif}

          VertPatch.Restore();

          g_pD3DDevice8.SetIndices(nil, 0);
        end;
      end;

      Inc(pdwPushData, dwCount);
    end
    else if (dwMethod = $1800) then  // NVPB_InlineIndexArray
    begin
      bInc := (pdwPushData^ and $40000000) > 0;

      if (bInc) then
      begin
        dwCount := ((pdwPushData^ - ($40000000 or $00001818)) shr 18)*2 + 2;
      end;

      Inc(pdwPushData); pIndexData := pdwPushData;

      {$ifdef _DEBUG_TRACK_PB}
      if (bShowPB) then
      begin
{$IFDEF DEBUG}
        printf('  NVPB_InlineIndexArray($%.08X, %d)...', pIndexData, dwCount);
        printf('');
        printf('  Index Array Data...');
{$ENDIF}

        pwVal := PWORD(pIndexData);

        for(uint s:=0;s<dwCount;s++)
        begin
          if (s mod 8) = 0 then printf(#13#10'  ');

          printf('  %.04X', [pwVal^]); Inc(pwVal);
        end;

{$IFDEF DEBUG}
        printf(#13#10);
{$ENDIF}

        XTL.IDirect3DVertexBuffer8 *pActiveVB := 0;

        D3DVERTEXBUFFER_DESC VBDesc;

        pVBData := nil;

        // retrieve stream data
        g_pD3DDevice8.GetStreamSource(0, {out}IDirect3DVertexBuffer8(pActiveVB), @uiStride);

        // retrieve stream desc
        pActiveVB.GetDesc(@VBDesc);

        // unlock just in case
        pActiveVB.Unlock();

        // grab ptr
        pActiveVB.Lock(0, 0, @pVBData, D3DLOCK_READONLY);

        // print out stream data
        begin
{$IFDEF DEBUG}
          printf('');
          printf('  Vertex Stream Data ($%.08X)...', pActiveVB);
          printf('');
          printf('  Format : %d', VBDesc.Format);
          printf('  Size   : %d bytes', VBDesc.Size);
          printf('  FVF    : $%.08X', VBDesc.FVF);
          printf('');
{$ENDIF}
        end;

        // release ptr
        pActiveVB.Unlock();

        DbgDumpMesh(PWORD(pIndexData), dwCount);
      end;
      {$endif}

(*
      Inc(pdwPushData, (dwCount/2) - iif(bInc, 0, 2));
*)
      // perform rendering
      begin
        // Cxbx TODO: depreciate maxIBSize after N milliseconds..then N milliseconds later drop down to new highest
        if (dwCount*2 > maxIBSize) then
        begin
          if Assigned(pIndexBuffer) then
          begin
            pIndexBuffer._Release();
          end;

          hRet := g_pD3DDevice8.CreateIndexBuffer(dwCount*2, 0, D3DFMT_INDEX16, D3DPOOL_MANAGED, {out}pIndexBuffer);

          maxIBSize := dwCount*2;
        end
        else
        begin
          hRet := D3D_OK;
        end;

        if (FAILED(hRet)) then
          CxbxKrnlCleanup('Unable to create index buffer for PushBuffer emulation ($1800, dwCount : %d)', [dwCount]);

        // copy index data
        begin
          pData := nil;

          pIndexBuffer.Lock(0, dwCount*2, {out}PByte(pData), 0);

          memcpy(pData, pIndexData, dwCount*2);

          // remember last 2 indices
          if (dwCount >= 2) then
          begin
            pIBMem[0] := pData[dwCount - 2];
            pIBMem[1] := pData[dwCount - 1];
          end
          else
          begin
            pIBMem[0] := $FFFF;
          end;

          pIndexBuffer.Unlock();
        end;

        // render indexed vertices
        begin
          PrimitiveCount := EmuD3DVertex2PrimitiveCount(XBPrimitiveType, dwCount);

          VPDesc.dwVertexCount := dwCount;
          VPDesc.PrimitiveType := XBPrimitiveType;
          VPDesc.dwPrimitiveCount := PrimitiveCount;
          VPDesc.dwOffset := 0;
          VPDesc.pVertexStreamZeroData := 0;
          VPDesc.uiVertexStreamZeroStride := 0;
          // Cxbx TODO: Set the current shader and let the patcher handle it..
          VPDesc.hVertexShader := g_CurrentVertexShader;

          bPatched := VertPatch.Apply(@VPDesc);

          g_pD3DDevice8.SetIndices(pIndexBuffer, 0);

          {$ifdef _DEBUG_TRACK_PB}
          if (not g_PBTrackDisable.exists(pdwOrigPushData)) then
          begin
          {$endif}

          if (not g_bPBSkipPusher) and XTL_IsValidCurrentShader() then
          begin
            g_pD3DDevice8.DrawIndexedPrimitive
            (
                PCPrimitiveType, 0, (*dwCount*2*)8*1024*1024, 0, PrimitiveCount
            );
          end;

          {$ifdef _DEBUG_TRACK_PB}
          end;
          {$endif}

          VertPatch.Restore();

          g_pD3DDevice8.SetIndices(nil, 0);
        end;
      end;

      Dec(pdwPushData);
    end
    else
    begin
      EmuWarning('Unknown PushBuffer Operation ($%.04X, %d)', [dwMethod, dwCount]);
      Exit;
    end;

    Inc(pdwPushData);
  end;

{$ifdef _DEBUG_TRACK_PB}
  if (bShowPB) then
  begin
{$IFDEF DEBUG}
    printf('');
    printf('CxbxDbg> ');
{$ENDIF}
    fflush(stdout);
  end;
{$endif}

  if (XTL_g_bStepPush) then
  begin
    g_pD3DDevice8.Present(0, 0, 0, 0);
    Sleep(500);
  end;
end;


{$IFDEF _DEBUG_TRACK_PB}

procedure DbgDumpMesh(pIndexData: PWord; dwCount: DWord);
// Branch:shogun  Revision:0.8.1-Pre2  Translator:PatrickvL  Done:10
(*var
  pActiveVB: IDirect3DVertexBuffer8;
  VBDesc: D3DVERTEXBUFFER_DESC;
  pVBData: PBYTE;
  uiStride: UINT;
  szFileName: array [0..128 - 1] of Char;
  pwVal: PWORD;
  maxIndex: uint32;
  pwChk: PWORD;
*)
begin
(*  if (not XTL_IsValidCurrentShader() or (dwCount = 0)) then
    Exit;

  pActiveVB := nil;

  // retrieve stream data
  g_pD3DDevice8.GetStreamSource(0, {out}IDirect3DVertexBuffer8(pActiveVB), uiStride);
 (* StrFmt(szFileName, 'C:\CxbxMesh-$%.08X.x', pIndexData);
  file * dbgVertices := FileOpen(szFileName, 'wt');

    // retrieve stream desc
  pActiveVB.GetDesc(@VBDesc);

    // unlock just in case
  pActiveVB.Unlock();

    // grab ptr
  pActiveVB.Lock(0, 0, @pVBData, D3DLOCK_READONLY);

    // print out stream data
  begin
    uint32 maxIndex := 0;

    pwChk := PWORD(pIndexData);

    for (uint chk := 0; chk < dwCount; chk++)
    begin
      DWord x = pwChk^; Inc(pwChk);

      if (x > maxIndex) then
        maxIndex := x;
    end;

    if (maxIndex > ((VBDesc.Size / uiStride) - 1)) then
      maxIndex := (VBDesc.Size / uiStride) - 1;

{$IFDEF DEBUG}
    fprintf(dbgVertices, 'xof 0303txt 0032');
    fprintf(dbgVertices, '');
    fprintf(dbgVertices, '//'#13#10);
    fprintf(dbgVertices, '//  Vertex Stream Data (0x%.08X)...'#13#10, pActiveVB);
    fprintf(dbgVertices, '//'#13#10);
    fprintf(dbgVertices, '//  Format : %d'#13#10, VBDesc.Format);
    fprintf(dbgVertices, '//  Size   : %d bytes'#13#10, VBDesc.Size);
    fprintf(dbgVertices, '//  FVF    : 0x%.08X'#13#10, VBDesc.FVF);
    fprintf(dbgVertices, '//  iCount : %d'#13#10, dwCount / 2);
    fprintf(dbgVertices, '//'#13#10);
    fprintf(dbgVertices, '');
    fprintf(dbgVertices, 'Frame SCENE_ROOT begin ');
    fprintf(dbgVertices, '');
    fprintf(dbgVertices, '  FrameTransformMatrix begin ');
    fprintf(dbgVertices, '    1.000000,0.000000,0.000000,0.000000,');
    fprintf(dbgVertices, '    0.000000,1.000000,0.000000,0.000000,');
    fprintf(dbgVertices, '    0.000000,0.000000,1.000000,0.000000,');
    fprintf(dbgVertices, '    0.000000,0.000000,0.000000,1.000000;;');
    fprintf(dbgVertices, '   end;');
    fprintf(dbgVertices, '');
    fprintf(dbgVertices, '  Frame Turok1 begin ');
    fprintf(dbgVertices, '');
    fprintf(dbgVertices, '    FrameTransformMatrix begin ');
    fprintf(dbgVertices, '      1.000000,0.000000,0.000000,0.000000,');
    fprintf(dbgVertices, '      0.000000,1.000000,0.000000,0.000000,');
    fprintf(dbgVertices, '      0.000000,0.000000,1.000000,0.000000,');
    fprintf(dbgVertices, '      0.000000,0.000000,0.000000,1.000000;;');
    fprintf(dbgVertices, '     end;');
    fprintf(dbgVertices, '');
    fprintf(dbgVertices, '    Mesh begin ');
    fprintf(dbgVertices, '      %d;', maxIndex + 1);
{$ENDIF}

    uint max := maxIndex + 1;
    for (uint v := 0; v < max; v++)
    begin
{$IFDEF DEBUG}
      fprintf(dbgVertices, '      %f;%f;%f;%s',
        * (FLOAT)@pVBData[v * uiStride + 0],
        * (FLOAT)@pVBData[v * uiStride + 4],
        * (FLOAT)@pVBData[v * uiStride + 8],
        (v < (max - 1))? ',': ';');
{$ENDIF}
    end;

{$IFDEF DEBUG}
    fprintf(dbgVertices, '      %d;', dwCount - 2);
{$ENDIF}

    pwVal := PWORD(pIndexData);

    max := dwCount;

    DWord a := pwVal^; Inc(pwVal);
    DWord b := pwVal^; Inc(pwVal);
    DWord c := pwVal^; Inc(pwVal);

    DWord la := a, lb = b, lc = c;

    for (uint i := 2; i < max; i++)
    begin
{$IFDEF DEBUG}
      fprintf(dbgVertices, '      3;%d,%d,%d;%s',
        a, b, c, (i < (max - 1))? ',': ';');
{$ENDIF}

      a := b;
      b := c;
      c  := pwVal^; Inc(pwVal);

      la := a;
      lb := b;
      lc := c;
    end;

{$IFDEF DEBUG}
    fprintf(dbgVertices, '     end;');
    fprintf(dbgVertices, '   end;');
    fprintf(dbgVertices, ' end;');
{$ENDIF}

    FileClose(dbgVertices);
  end;

    // release ptr
  pActiveVB.Unlock();    *)
end;
{$ENDIF}

exports
  XTL_EmuExecutePushBuffer,
  XTL_EmuExecutePushBufferRaw;

end.

