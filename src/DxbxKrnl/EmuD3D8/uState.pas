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

unit uState;

{$INCLUDE Dxbx.inc}

interface

uses
  // Delphi
  Windows,
  // DirectX
  Direct3D8, // IDirect3DBaseTexture8
  // Dxbx
  uTypes,
  uConvert,
  uDxbxUtils, // iif
  uDxbxKrnlUtils;

procedure XTL_EmuUpdateDeferredStates(); {NOPATCH}

// deferred state lookup tables
var XTL_EmuD3DDeferredRenderState: PDWORDs;
var XTL_EmuD3DDeferredTextureState: PDWORDs;

var XTL_EmuD3DDeferredRenderState_Start: DWord; // Dxbx addition, to allow for SDK version dependant shifting
var XTL_EmuD3DDeferredRenderState_Size: DWord; // Dxbx addition
var XTL_EmuD3DRenderState_ComplexCorrection: Integer; // Dxbx addition, to allow for SDK version dependant shifting

var g_BuildVersion: uint32;
// var g_OrigBuildVersion: uint32; // Dxbx note : Unused

implementation

uses
  uEmuD3D8, // g_BuildVersion
  uEmuD3D8Types;

procedure XTL_EmuUpdateDeferredStates(); {NOPATCH}
// Branch:shogun  Revision:163  Translator:PatrickvL  Done:100
var
  dwConv: DWORD;
  v: int;
  pCur: PDWORDs;
  pTexture: XTL_PIDirect3DBaseTexture8;
  dwValue: DWORD;
  bHack3925: _bool;
  Adjust1: int;
  Adjust2: int;
begin
  // Certain D3DRS values need to be checked on each Draw[Indexed]Vertices
  if (XTL_EmuD3DDeferredRenderState <> nil) then
  begin
    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGENABLE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_FOGENABLE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGENABLE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGTABLEMODE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_FOGTABLEMODE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGTABLEMODE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGSTART] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_FOGSTART, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGSTART]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGEND] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_FOGEND, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGEND]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGDENSITY] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_FOGDENSITY, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_FOGDENSITY]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_RANGEFOGENABLE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_RANGEFOGENABLE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_RANGEFOGENABLE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_WRAP0] <> X_D3DRS_UNK) then
    begin
      dwConv := 0;

      if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_WRAP0] and X_D3DWRAP_U) > 0 then dwConv := dwConv or D3DWRAP_U;
      if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_WRAP0] and X_D3DWRAP_V) > 0 then dwConv := dwConv or D3DWRAP_V;
      if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_WRAP0] and X_D3DWRAP_W) > 0 then dwConv := dwConv or D3DWRAP_W;

      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_WRAP0, dwConv);
    end;

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_WRAP1] <> X_D3DRS_UNK) then
    begin
      dwConv := 0;

      if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_WRAP1] and X_D3DWRAP_U) > 0 then dwConv := dwConv or D3DWRAP_U;
      if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_WRAP1] and X_D3DWRAP_V) > 0 then dwConv := dwConv or D3DWRAP_V;
      if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_WRAP1] and X_D3DWRAP_W) > 0 then dwConv := dwConv or D3DWRAP_W;

      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_WRAP1, dwConv);
    end;

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_LIGHTING] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_LIGHTING, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_LIGHTING]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_SPECULARENABLE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_SPECULARENABLE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_SPECULARENABLE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_COLORVERTEX] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_COLORVERTEX, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_COLORVERTEX]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_DIFFUSEMATERIALSOURCE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_DIFFUSEMATERIALSOURCE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_DIFFUSEMATERIALSOURCE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_AMBIENTMATERIALSOURCE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_AMBIENTMATERIALSOURCE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_AMBIENTMATERIALSOURCE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_EMISSIVEMATERIALSOURCE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_EMISSIVEMATERIALSOURCE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_EMISSIVEMATERIALSOURCE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_AMBIENT] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_AMBIENT, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_AMBIENT]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSIZE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_POINTSIZE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSIZE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSIZE_MIN] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_POINTSIZE_MIN, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSIZE_MIN]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSPRITEENABLE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_POINTSPRITEENABLE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSPRITEENABLE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSCALEENABLE] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_POINTSCALEENABLE, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSCALEENABLE]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSCALE_A] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_POINTSCALE_A, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSCALE_A]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSCALE_B] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_POINTSCALE_B, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSCALE_B]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSCALE_C] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_POINTSCALE_C, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSCALE_C]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSIZE_MAX] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_POINTSIZE_MAX, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSIZE_MAX]);

    if (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_PATCHSEGMENTS] <> X_D3DRS_UNK) then
      IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_PATCHSEGMENTS, XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_PATCHSEGMENTS]);

    (* Cxbx has this disabled :
    // To check for unhandled RenderStates
    for(int v=0;v<117-82;v++)
    begin
      if (XTL_EmuD3DDeferredRenderState[v] <> X_D3DRS_UNK) then
      begin
        if  (v <>  0) and (v <>  1) and (v <>  2) and (v <>  3) and (v <>  4) and (v <>  5) and (v <>  6) and (v <>  7)
        and (v <> 10) and (v <> 11) and (v <> 13) and (v <> 19) and (v <> 20) and (v <> 21) and (v <> 23) and (v <> 24)
        and (v <> 25) and (v <> 26) and (v <> 27) and (v <> 28) and (v <> 29) and (v <> 30) and (v <> 31) and (v <> 33) then
          EmuWarning('Unhandled RenderState Change @ %d (%d)', [v, v + 82]);
      end;
    end;
    *)
  end;

  // For 3925, the actual D3DTSS flags have different values.
  // TODO -oDxbx : Check all other SDK versions if they differ too...
  bHack3925 := (g_BuildVersion = 3925);
  Adjust1 := iif(bHack3925, 12, 0);
  Adjust2 := iif(bHack3925, 10, 0);

  // Certain D3DTS values need to be checked on each Draw[Indexed]Vertices
  if (XTL_EmuD3DDeferredTextureState <> nil) then
  begin
    for v := 0 to X_D3DTS_STAGECOUNT-1 do
    begin
      pCur := @(XTL_EmuD3DDeferredTextureState[v*X_D3DTS_STAGESIZE]);

      if (pCur[X_D3DTSS_ADDRESSU+Adjust2] <> X_D3DTSS_UNK) then
      begin
        if (pCur[X_D3DTSS_ADDRESSU+Adjust2] = 5) then
          DxbxKrnlCleanup('ClampToEdge is unsupported (temporarily)');

        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ADDRESSU, pCur[X_D3DTSS_ADDRESSU+Adjust2]);
      end;

      if (pCur[X_D3DTSS_ADDRESSV+Adjust2] <> X_D3DTSS_UNK) then
      begin
        if (pCur[X_D3DTSS_ADDRESSV+Adjust2] = 5) then
          DxbxKrnlCleanup('ClampToEdge is unsupported (temporarily)');

        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ADDRESSV, pCur[X_D3DTSS_ADDRESSV+Adjust2]);
      end;

      if (pCur[X_D3DTSS_ADDRESSW+Adjust2] <> X_D3DTSS_UNK) then
      begin
        if (pCur[X_D3DTSS_ADDRESSW+Adjust2] = 5) then
          DxbxKrnlCleanup('ClampToEdge is unsupported (temporarily)');

        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ADDRESSW, pCur[X_D3DTSS_ADDRESSW+Adjust2]);
      end;

      if (pCur[X_D3DTSS_MAGFILTER+Adjust2] <> X_D3DTSS_UNK) then
      begin
        if (pCur[X_D3DTSS_MAGFILTER+Adjust2] = 4) then
          DxbxKrnlCleanup('QuinCunx is unsupported (temporarily)');

        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_MAGFILTER, pCur[X_D3DTSS_MAGFILTER+Adjust2]);
      end;

      if (pCur[X_D3DTSS_MINFILTER+Adjust2] <> X_D3DTSS_UNK) then
      begin
        if (pCur[X_D3DTSS_MINFILTER+Adjust2] = 4) then
          DxbxKrnlCleanup('QuinCunx is unsupported (temporarily)');

        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_MINFILTER, pCur[X_D3DTSS_MINFILTER+Adjust2]);
      end;

      if (pCur[X_D3DTSS_MIPFILTER+Adjust2] <> X_D3DTSS_UNK) then
      begin
        if (pCur[X_D3DTSS_MIPFILTER+Adjust2] = 4) then
          DxbxKrnlCleanup('QuinCunx is unsupported (temporarily)');

        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_MIPFILTER, pCur[X_D3DTSS_MIPFILTER+Adjust2]);
      end;

      if (pCur[X_D3DTSS_MIPMAPLODBIAS+Adjust2] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_MIPMAPLODBIAS, pCur[X_D3DTSS_MIPMAPLODBIAS+Adjust2]);

      if (pCur[X_D3DTSS_MAXMIPLEVEL+Adjust2] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_MAXMIPLEVEL, pCur[X_D3DTSS_MAXMIPLEVEL+Adjust2]);

      if (pCur[X_D3DTSS_MAXANISOTROPY+Adjust2] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_MAXANISOTROPY, pCur[X_D3DTSS_MAXANISOTROPY+Adjust2]);

      // TODO -oDxbx : Handle X_D3DTSS_COLORKEYOP (Xbox ext.)
      // TODO -oDxbx : Handle X_D3DTSS_COLORSIGN (Xbox ext.)
      // TODO -oDxbx : Handle X_D3DTSS_ALPHAKILL (Xbox ext.)

      if (pCur[X_D3DTSS_COLOROP-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_COLOROP, EmuXB2PC_D3DTEXTUREOP(pCur[X_D3DTSS_COLOROP-Adjust1]));

      if (pCur[X_D3DTSS_COLORARG0-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_COLORARG0, pCur[X_D3DTSS_COLORARG0-Adjust1]);

      if (pCur[X_D3DTSS_COLORARG1-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_COLORARG1, pCur[X_D3DTSS_COLORARG1-Adjust1]);

      if (pCur[X_D3DTSS_COLORARG2-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_COLORARG2, pCur[X_D3DTSS_COLORARG2-Adjust1]);

      if (pCur[X_D3DTSS_ALPHAOP-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ALPHAOP, EmuXB2PC_D3DTEXTUREOP(pCur[X_D3DTSS_ALPHAOP-Adjust1]));

      if (pCur[X_D3DTSS_ALPHAARG0-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ALPHAARG0, pCur[X_D3DTSS_ALPHAARG0-Adjust1]);

      if (pCur[X_D3DTSS_ALPHAARG1-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ALPHAARG1, pCur[X_D3DTSS_ALPHAARG1-Adjust1]);

      if (pCur[X_D3DTSS_ALPHAARG2-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ALPHAARG2, pCur[X_D3DTSS_ALPHAARG2-Adjust1]);

      if (pCur[X_D3DTSS_RESULTARG-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_RESULTARG, pCur[X_D3DTSS_RESULTARG-Adjust1]);

      if (pCur[X_D3DTSS_TEXTURETRANSFORMFLAGS-Adjust1] <> X_D3DTSS_UNK) then
        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_TEXTURETRANSFORMFLAGS, pCur[X_D3DTSS_TEXTURETRANSFORMFLAGS-Adjust1]);

//      if (pCur[X_D3DTSS_BORDERCOLOR] <> X_D3DTSS_UNK) then // Cxbx : This is NOT a deferred texture state!
//        IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_BORDERCOLOR, pCur[X_D3DTSS_BORDERCOLOR]);


      (* Cxbx has this disabled :
      // To check for unhandled texture stage state changes
      for(int r=0;r<X_D3DTS_STAGESIZE;r++)
      begin
        static const int unchecked[] =
        begin
          0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 29, 30, 31
        end;;

        if (pCur[r] <> X_D3DTSS_UNK) then
        begin
          _bool pass := true;

          for(int q=0;q<sizeof(unchecked)/sizeof(int);q++)
          begin
            if (r = unchecked[q]) then
            begin
              pass := false;
              break;
            end;
          end;

          if (pass) then
            EmuWarning('Unhandled TextureState Change @ %d.%d', [v, r]);
        end;
      end;
      *)
    end;

    // if point sprites are enabled, copy stage 3 over to 0
    if  Assigned(XTL_EmuD3DDeferredRenderState) // Dxbx addition
    and (XTL_EmuD3DDeferredRenderState[X_D3DRS_DEFERRED_POINTSPRITEENABLE] = DWord(BOOL_TRUE)) then // Dxbx note : DWord cast to prevent warning
    begin
      // pCur := Texture Stage 3 States
      pCur := @(XTL_EmuD3DDeferredTextureState[3*X_D3DTS_STAGESIZE]); // StrikerX3: why was this 2*32? PatrickvL: Probably a bug.

      // set the point sprites texture
      IDirect3DDevice8(g_pD3DDevice8).GetTexture(3, PIDirect3DBaseTexture8(@pTexture));
      IDirect3DDevice8(g_pD3DDevice8).SetTexture(0, IDirect3DBaseTexture8(pTexture));
      // TODO -oDXBX: Should we clear the pTexture interface (and how)?

      // disable all other stages
      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(1, D3DTSS_COLOROP, D3DTOP_DISABLE);
      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(1, D3DTSS_ALPHAOP, D3DTOP_DISABLE);

      // in that case we have to copy over the stage by hand
      for v := 0 to XTL_EmuD3DDeferredRenderState_Size-1 do
      begin
        if (pCur[v] <> X_D3DTSS_UNK) then
        begin
          IDirect3DDevice8(g_pD3DDevice8).GetTextureStageState(3, D3DTEXTURESTAGESTATETYPE(v), {Out}dwValue);
          IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(0, D3DTEXTURESTAGESTATETYPE(v), dwValue);
        end;
      end;
    end;
  end;

  if (g_bFakePixelShaderLoaded) then
  begin
    IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_FOGENABLE, BOOL_FALSE);

    // programmable pipeline
    //*
    for v:=0 to X_D3DTS_STAGECOUNT-1 do
    begin
      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_COLOROP, D3DTOP_DISABLE);
      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ALPHAOP, D3DTOP_DISABLE);
    end;
    //*/

    // fixed pipeline
    (* Cxbx has this disabled :
    for v:=0 to 4-1 do
    begin
      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_COLOROP,   D3DTOP_MODULATE);
      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_COLORARG1, D3DTA_TEXTURE);
      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_COLORARG2, D3DTA_CURRENT);

      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ALPHAOP,   D3DTOP_MODULATE);
      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ALPHAARG1, D3DTA_TEXTURE);
      IDirect3DDevice8(g_pD3DDevice8).SetTextureStageState(v, D3DTSS_ALPHAARG2, D3DTA_CURRENT);
    end;

    IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_NORMALIZENORMALS, BOOL_TRUE);
    IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_LIGHTING,BOOL_TRUE);
    IDirect3DDevice8(g_pD3DDevice8).SetRenderState(D3DRS_AMBIENT, $FFFFFFFF);
    *)
  end;
end;

{.$MESSAGE 'PatrickvL reviewed up to here'}
end.
