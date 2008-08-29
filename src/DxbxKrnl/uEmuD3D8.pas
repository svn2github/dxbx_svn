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
unit uEmuD3D8;

{$INCLUDE Dxbx.inc}

interface

uses
  // Delphi
  Windows,
  Messages,
  SysUtils,
  MMSystem, // timeBeginPeriod
  // Directx
  Direct3D,
  Direct3D8,
  DirectDraw,
  // Dxbx
  uDxbxKrnl,
  uConvert,
  uEmuD3D8Types,
  uDxbxKrnlUtils,
  uEmuDInput,
  uPushBuffer,
  uVertexShader,
  uEmu,
  uEmuKrnl,
  uLog,
  uTypes,
  uXbe,
  uXbVideo,
  uEmuShared,
  uEmuFS,
  uEmuXapi;

function EmuUpdateTickCount(LPVOID: Pointer): DWord; //stdcall;
function EmuCreateDeviceProxy(LPVOID: Pointer): DWord; //stdcall;
function EmuRenderWindow(lpVoid: Pointer): DWord; //stdcall;

procedure XTL_EmuD3DInit(XbeHeader: pXBE_HEADER; XbeHeaderSize: DWord); stdcall;
function XTL_EmuIDirect3DDevice8_GetViewport(pViewport: D3DVIEWPORT8): HRESULT; stdcall;
function XTL_EmuIDirect3DDevice8_SetVertexData4f(aRegister: integer; a: FLOAT; b: FLOAT; c: FLOAT; d: FLOAT): HRESULT; stdcall;

function EmuMsgProc(hWnd: HWND; msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; // forward

implementation

uses
  uVertexBuffer,
  D3DX8;

var
  // Static Variable(s)
  g_hEmuWindow: THandle = 0; // rendering window

  g_XbeHeader: pXBE_HEADER; // XbeHeader
  g_XbeHeaderSize: DWord = 0; // XbeHeaderSize
  g_bIsFauxFullscreen: Boolean = False;
  g_hBgBrush: HBrush = 0; // Background Brush
  g_CurrentVertexShader: DWord = 0;
  g_VertexShaderConstantMode: X_VERTEXSHADERCONSTANTMODE = X_VSCM_192;

  g_pD3DDevice8: IDIRECT3DDEVICE8; // Direct3D8 Device
  g_pDDSPrimary: IDIRECTDRAWSURFACE7; // DirectDraw7 Primary Surface
  g_pDDSOverlay7: IDIRECTDRAWSURFACE7; // DirectDraw7 Overlay Surface
  g_pDDClipper: IDIRECTDRAWCLIPPER; // DirectDraw7 Clipper
  g_bFakePixelShaderLoaded: Boolean = False;

  g_pD3D8: IDIRECT3D8; // Direct3D8
  g_bRenderWindowActive: bool = False; // volatile?

  g_XBVideo: XBVideo;
  g_pVBCallback: D3DVBLANKCALLBACK = nil; // Vertical-Blank callback routine

  // wireframe toggle
  g_iWireframe: Integer = 0;

  // current vertical blank information
  g_VBData: D3DVBLANKDATA;
  g_VBLastSwap: DWORD = 0;

procedure XTL_EmuD3DInit(XbeHeader: pXBE_HEADER; XbeHeaderSize: DWord);
var
  dwThreadId: DWORD;
  hThread: THandle;
  hDupHandle: THandle;
  DevType: D3DDEVTYPE;
begin
  g_EmuShared.GetXBVideo(g_XBVideo);

  if g_XBVideo.GetFullscreen() then
    CxbxKrnl_hEmuParent := 0;

  // cache XbeHeader and size of XbeHeader
  g_XbeHeader := XbeHeader;
  g_XbeHeaderSize := XbeHeaderSize;

  // create timing thread
  begin
    hThread := BeginThread(nil, 0, @EmuUpdateTickCount, nil, 0, {var} dwThreadId);

    // we must duplicate this handle in order to retain Suspend/Resume thread rights from a remote thread
    begin
      hDupHandle := 0;

      DuplicateHandle(GetCurrentProcess(), hThread, GetCurrentProcess(), @hDupHandle, 0, False, DUPLICATE_SAME_ACCESS);

      CxbxKrnlRegisterThread(hDupHandle);
    end;
  end;

  // create the create device proxy thread
  begin
    BeginThread(nil, 0, @EmuCreateDeviceProxy, nil, 0, {var} dwThreadId);
  end;

  // create window message processing thread
  begin
    g_bRenderWindowActive := False;

    BeginThread(nil, 0, @EmuRenderWindow, nil, 0, {var} dwThreadId);

    (*while not g_bRenderWindowActive do
      Sleep(10); *)

    Sleep(50);
  end;

  // create Direct3D8 and retrieve caps
  //  using namespace XTL;

    // xbox Direct3DCreate8 returns '1' always, so we need our own ptr
  g_pD3D8 := Direct3DCreate8(D3D_SDK_VERSION);

  if g_pD3D8 = nil then
    CxbxKrnlCleanup('Could not initialize Direct3D8!');

(*    DevType := (g_XBVideo.GetDirect3DDevice() = 0) ? D3DDEVTYPE_HAL : D3DDEVTYPE_REF;

    g_pD3D8.GetDeviceCaps(g_XBVideo.GetDisplayAdapter(), DevType, @g_D3DCaps);

  SetFocus(g_hEmuWindow);

  // create default device
    XTL.X_D3DPRESENT_PARAMETERS PresParam;

    ZeroMemory(@PresParam, SizeOf(PresParam));

    PresParam.BackBufferWidth  := 640;
    PresParam.BackBufferHeight := 480;
    PresParam.BackBufferFormat := 6; (* X_D3DFMT_A8R8G8B8 * )
    PresParam.BackBufferCount  := 1;
    PresParam.EnableAutoDepthStencil := TRUE;
    PresParam.AutoDepthStencilFormat := $2A; (* X_D3DFMT_D24S8 * )
    PresParam.SwapEffect := XTL.D3DSWAPEFFECT_DISCARD;

    EmuSwapFS();    // XBox FS
    XTL.EmuIDirect3D8_CreateDevice(0, XTL.D3DDEVTYPE_HAL, 0, $00000040, @PresParam, @g_pD3DDevice8);
    EmuSwapFS();    // Win2k/XP FS
*)
end;




// information passed to the create device proxy thread

type EmuD3D8CreateDeviceProxyData = record
    Adapter : UINT;
    DeviceType : D3DDEVTYPE;
    hFocusWindow : HWND;
    BehaviorFlags : DWORD;
    pPresentationParameters : X_D3DPRESENT_PARAMETERS;
    ppReturnedDeviceInterface : IDirect3DDevice8;
    bReady : bool;
    hRet : HRESULT;
    bCreate : bool;   // False : release
end;

g_EmuCDPD = EmuD3D8CreateDeviceProxyData;

// cleanup Direct3D

procedure XTL_EmuD3DCleanup;
begin
  XTL_EmuDInputCleanup;
  Exit;
end;

// enumeration procedure for locating display device GUIDs
(*function EmuEnumDisplayDevices(var FARlpGUID: GUID; lpDriverDescription: PChar; lpDriverName: PChar; lpContext: Pointer; hm: HMONITOR): BOOL;
begin
     DWORD dwEnumCount := 0;

    if(dwEnumCount++ = g_XBVideo.GetDisplayAdapter()+1) then
    begin
        g_hMonitor := hm;
        dwEnumCount := 0;
        if(lpGUID <> 0) then
        begin
            memcpy(@g_ddguid, lpGUID, SizeOf(GUID));
         end;
        else
        begin
            FillChar(@g_ddguid, 0, SizeOf(GUID));
         end;

        Result:= False;
     end;

    Result:= TRUE;
 end;*)

// window message processing thread

function EmuRenderWindow(lpVoid: Pointer): DWord;
var
  msg: TMsg;
  AsciiTitle: array[0..50 - 1] of Char;
  hDxbxDLL: HMODULE;
  logBrush: TLogBrush;
  wc: WNDCLASSEX;
  tAsciiTitle: array[0..40 - 1] of Char;
  CertAddr: IntPtr; //uint32
  XbeCert: Xbe_Certificate;
  dwStyle: DWORD;

  nTitleHeight: integer;
  nBorderWidth: integer;
  nBorderHeight: integer;
  x, y, nWidth, nHeight: integer;
  hwndParent: HWND;
  lPrintfOn : bool;

begin
  // register window class
  begin
    hDxbxDLL := MainInstance;

    logBrush.lbStyle := BS_SOLID;
    logBrush.lbColor := RGB(0, 0, 0);

    g_hBgBrush := CreateBrushIndirect(logBrush);

    wc.cbSize := SizeOf(WNDCLASSEX);
    wc.style := CS_CLASSDC;
    wc.lpfnWndProc := @EmuMsgProc;
    wc.cbClsExtra := 0;
    wc.cbWndExtra := 0;
    wc.hInstance := GetModuleHandle(nil);
    wc.hIcon := LoadIcon(hDxbxDll, MAKEINTRESOURCE({IDI_CXBX=}101));
    wc.hCursor := LoadCursor(0, IDC_ARROW);
    wc.hbrBackground := g_hBgBrush;
    wc.lpszMenuName := '';
    wc.lpszClassName := 'CxbxRender';
    wc.hIconSm := 0;

    RegisterClassEx(wc);
  end;


  // retrieve Xbe title (if possible)
  begin
    tAsciiTitle := 'Unknown';

    CertAddr := g_XbeHeader.dwCertificateAddr - g_XbeHeader.dwBaseAddr;

    if CertAddr + $0C + 40 < g_XbeHeaderSize then
    begin
      { TODO : Need to be translated to delphi }
      (*
      XbeCert := g_XbeHeader + CertAddr;
      setlocale(LC_ALL, 'English');
      wcstombs(tAsciiTitle, XbeCert.wszTitleName, 40); *)
    end;

    { TODO : Need to be translated to delphi }
    (*
    AsciiTitle := Format('Dxbx : Emulating %s', [tAsciiTitle]);*)
  end;

    // create the window
  begin
        { TODO : Need to be translated to delphi }
        (*
        dwStyle := (g_XBVideo.GetFullscreen() or (CxbxKrnl_hEmuParent = 0))? WS_OVERLAPPEDWINDOW : WS_CHILD;
        *)

    nTitleHeight := GetSystemMetrics(SM_CYCAPTION);
    nBorderWidth := GetSystemMetrics(SM_CXSIZEFRAME);
    nBorderHeight := GetSystemMetrics(SM_CYSIZEFRAME);

    x := 100;
    y := 100;
    nWidth := 640;
    nHeight := 480;

    nWidth := nWidth + nBorderWidth * 2;
    nHeight := nHeight + nBorderHeight * 2 + nTitleHeight;

        { TODO : Need to be translated to delphi }
        (*
        sscanf(g_XBVideo.GetVideoResolution(), '%d x %d', @nWidth, @nHeight);
        *)

    if (g_XBVideo.GetFullscreen()) then
    begin
      { TODO : Need to be translated to delphi }
      (*
      x := y = nWidth = nHeight = 0;
      *)
      dwStyle := WS_POPUP;
    end;

    hwndParent := GetDesktopWindow();

    if (not g_XBVideo.GetFullscreen()) then
    begin
      hwndParent := CxbxKrnl_hEmuParent;
    end;

    g_hEmuWindow := CreateWindow
      (
      #13#10'CxbxRender', AsciiTitle,
      dwStyle, x, y, nWidth, nHeight,
      hwndParent, 0, GetModuleHandle(0), 0
      );
  end;

    { TODO : Need to be translated to delphi }
    (*
    ShowWindow(g_hEmuWindow, (g_XBVideo.GetFullscreen() or (CxbxKrnl_hEmuParent := 0) ) ? SW_SHOWDEFAULT : SW_SHOWMAXIMIZED);
    UpdateWindow(g_hEmuWindow); *)
  if (not g_XBVideo.GetFullscreen and (CxbxKrnl_hEmuParent <> 0)) then
  begin
    SetFocus(CxbxKrnl_hEmuParent);
  end;

    // initialize direct input
  if (not XTL_EmuDInputInit) then
    CxbxKrnlCleanup('Could not initialize DirectInput!');

  DbgPrintf('EmuD3D8 : Message-Pump thread is running.');

  SetFocus(g_hEmuWindow);

  { TODO : Need to be translated to delphi }
  (*
  DbgConsole * dbgConsole := new DbgConsole();
  *)


  // message processing loop
  begin
//    ZeroMemory(msg, SizeOf(msg));

    lPrintfOn := g_bPrintfOn;

    while msg.message <> WM_QUIT do
    begin
      if PeekMessage({var}msg, 0, 0, 0, PM_REMOVE) then
      begin
        g_bRenderWindowActive := True;
        TranslateMessage(msg);
        DispatchMessage(msg);
      end
      else
      begin
        Sleep(10);


        { TODO : Need to be translated to delphi }
        (*
        // if we've just switched back to display off, clear buffer & display prompt
        if not g_bPrintfOn and lPrintfOn then
          dbgConsole.Reset();

        lPrintfOn := g_bPrintfOn;

        dbgConsole.Process();
        *)
      end;
    end;

    g_bRenderWindowActive := False;

//        delete dbgConsole;

    CxbxKrnlCleanup('');
  end;

  Result := 0;
end;

// simple helper function

procedure ToggleFauxFullscreen(hWnd: HWND);
var
  lRestore: LongInt;
  lRestoreEx: LongInt;
  lRect: TRect;
begin
  if (g_XBVideo.GetFullscreen()) then
    Exit;

  lRestore := 0;
  lRestoreEx := 0;

{ TODO : need to be translated to delphi }
(*  lRect := (0);
*)

  if (not g_bIsFauxFullscreen) then
  begin
    if (CxbxKrnl_hEmuParent <> 0) then
    begin
      SetParent(hWnd, 0);
    end
    else
    begin
      { TODO : need to be translated to delphi }
      (*
      lRestore := GetWindowLong(hWnd, GWL_STYLE);
      lRestoreEx := GetWindowLong(hWnd, GWL_EXSTYLE);
      GetWindowRect(hWnd, @lRect); *)

    end;

    { TODO : need to be translated to delphi }
    (*SetWindowLong(hWnd, GWL_STYLE, WS_POPUP);*)
    ShowWindow(hWnd, SW_MAXIMIZE);
    SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE or SWP_NOMOVE);
  end
  else begin
    if (CxbxKrnl_hEmuParent <> 0) then
    begin
      SetParent(hWnd, CxbxKrnl_hEmuParent);
      SetWindowLong(hWnd, GWL_STYLE, WS_CHILD);
      ShowWindow(hWnd, SW_MAXIMIZE);
      SetFocus(CxbxKrnl_hEmuParent);
    end
    else
    begin
      SetWindowLong(hWnd, GWL_STYLE, lRestore);
      SetWindowLong(hWnd, GWL_EXSTYLE, lRestoreEx);
      ShowWindow(hWnd, SW_RESTORE);
      SetWindowPos(hWnd, HWND_NOTOPMOST, lRect.left, lRect.top, lRect.right - lRect.left, lRect.bottom - lRect.top, 0);
      SetFocus(hWnd);
    end;
  end;

  g_bIsFauxFullscreen := not g_bIsFauxFullscreen;
end;

// rendering window message procedure

function EmuMsgProc(hWnd: HWND; msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT;
var
  bAutoPaused: Boolean;
begin
  bAutoPaused := False;

  Result := 0;
  case (msg) of
    WM_DESTROY:
      begin
        DeleteObject(g_hBgBrush);
        PostQuitMessage(0);
        Result := 0;
      end;

    WM_SYSKEYDOWN:
      begin
        if (wParam = VK_RETURN) then
        begin
          ToggleFauxFullscreen(hWnd);
        end
        else if (wParam = VK_F4) then
        begin
          PostMessage(hWnd, WM_CLOSE, 0, 0);
        end;
      end;

    WM_KEYDOWN:
      begin
        // disable fullscreen if we are set to faux mode, and faux fullscreen is active
        if (wParam = VK_ESCAPE) then
        begin
          if (g_XBVideo.GetFullscreen()) then
          begin
            SendMessage(hWnd, WM_CLOSE, 0, 0);
          end
          else if (g_bIsFauxFullscreen) then
          begin
            ToggleFauxFullscreen(hWnd);
          end;
        end
        else if (wParam = VK_F8) then
        begin
          g_bPrintfOn := not g_bPrintfOn;
        end
        else if (wParam = VK_F9) then
        begin
          XTL_g_bBrkPush := True;
        end
        else if (wParam = VK_F10) then
        begin
          ToggleFauxFullscreen(hWnd);
        end
        else if (wParam = VK_F11) then
        begin
          Inc(g_iWireframe);
          if g_iWireframe = 2 then
            g_iWireframe := 0;
        end
        else if (wParam = VK_F12) then
        begin
          XTL_g_bStepPush := not XTL_g_bStepPush;
        end;
      end;

    WM_SIZE:
      begin
        case (wParam) of
          SIZE_RESTORED,
            SIZE_MAXIMIZED:
            begin
              if (bAutoPaused) then
              begin
                bAutoPaused := False;
                CxbxKrnlResume();
              end;
            end;

          SIZE_MINIMIZED:
            begin
              if (g_XBVideo.GetFullscreen()) then
                CxbxKrnlCleanup('0');

              if (not g_bEmuSuspended) then
              begin
                bAutoPaused := True;
                CxbxKrnlSuspend();
              end;
            end;
        end;
      end;

    WM_CLOSE: DestroyWindow(hWnd);

    WM_SETFOCUS:
      begin
        if (CxbxKrnl_hEmuParent <> 0) then
        begin
          SetFocus(CxbxKrnl_hEmuParent);
        end;
      end;

    WM_SETCURSOR:
      begin
        if (g_XBVideo.GetFullscreen() or g_bIsFauxFullscreen) then
        begin
          SetCursor(0);
          Result := 0;
        end;

        Result := DefWindowProc(hWnd, msg, wParam, lParam);
      end;
  else
    Result := DefWindowProc(hWnd, msg, wParam, lParam);
  end;
end;

// timing thread procedure

function EmuUpdateTickCount(LPVOID: Pointer): DWord;
var
  curvb: Integer;
  v: Integer;
  hDevice: THandle;
  dwLatency: DWORD;
  pFeedback: PXINPUT_FEEDBACK;
begin
  // since callbacks come from here
  EmuGenerateFS(CxbxKrnl_TLS, CxbxKrnl_TLSData);

  DbgPrintf('EmuD3D8 : Timing thread is running.');

  timeBeginPeriod(0);

  // current vertical blank count
  curvb := 0;
  while True do
  begin
    xboxkrnl_KeTickCount := timeGetTime();
    Sleep(1);

    //
    // Poll input
    //
    begin
      for v := 0 to XINPUT_SETSTATE_SLOTS - 1 do
      begin
        hDevice := g_pXInputSetStateStatus[v].hDevice;

        if hDevice = 0 then
          Continue;

        dwLatency := g_pXInputSetStateStatus[v].dwLatency + 1;
        g_pXInputSetStateStatus[v].dwLatency := dwLatency;

        if dwLatency < XINPUT_SETSTATE_LATENCY then
          Continue;

        g_pXInputSetStateStatus[v].dwLatency := 0;

        pFeedback := PXINPUT_FEEDBACK(g_pXInputSetStateStatus[v].pFeedback);
        if pFeedback = nil then
          Continue;

        //
        // Only update slot if it has not already been updated
        //
        if pFeedback.Header.dwStatus <> ERROR_SUCCESS then
        begin
          if pFeedback.Header.hEvent <> 0 then
            SetEvent(pFeedback.Header.hEvent);

          pFeedback.Header.dwStatus := ERROR_SUCCESS;
        end;
      end;
    end;

    // trigger vblank callback
    begin
      g_VBData.VBlank := g_VBData.VBlank + 1;

      if Assigned(g_pVBCallback) then
      begin
        EmuSwapFS(); // Xbox FS
        g_pVBCallback(@g_VBData);
        EmuSwapFS(); // Win2k/XP FS
      end;

      g_VBData.Swap := 0;
    end;

  end; // while

  timeEndPeriod(0);
end;

// thread dedicated to create devices

function EmuCreateDeviceProxy(LPVOID: Pointer): DWord;
begin
  DbgPrintf('EmuD3D8 : CreateDevice proxy thread is running.');

    (*while(true) do begin
        // if we have been signalled, create the device with cached parameters
        if(g_EmuCDPD.bReady) then
        begin
            DbgPrintf('EmuD3D8 : CreateDevice proxy thread recieved request.');

            if(g_EmuCDPD.bCreate) then
            begin
                // only one device should be created at once
                // TODO: ensure all surfaces are somehow cleaned up?
                if(g_pD3DDevice8 <> 0) then
                begin
                    DbgPrintf('EmuD3D8 : CreateDevice proxy thread releasing old Device.');

                    g_pD3DDevice8.EndScene();

                    while(g_pD3DDevice8.Release() <> 0);

                    g_pD3DDevice8 := 0;
                 end;

                if(g_EmuCDPD.pPresentationParameters.BufferSurfaces[0] <> 0) then
                    EmuWarning('BufferSurfaces[0] : 0x%.08X', g_EmuCDPD.pPresentationParameters.BufferSurfaces[0]);

                if(g_EmuCDPD.pPresentationParameters.DepthStencilSurface <> 0) then
                    EmuWarning('DepthStencilSurface : 0x%.08X', g_EmuCDPD.pPresentationParameters.DepthStencilSurface);

                // make adjustments to parameters to make sense with windows Direct3D
                begin
                    g_EmuCDPD.DeviceType :=(g_XBVideo.GetDirect3DDevice() = 0) ? XTL.D3DDEVTYPE_HAL : XTL.D3DDEVTYPE_REF;
                    g_EmuCDPD.Adapter    := g_XBVideo.GetDisplayAdapter();

                    g_EmuCDPD.pPresentationParameters.Windowed :=  not g_XBVideo.GetFullscreen();

                    if(g_XBVideo.GetVSync()) then
                        g_EmuCDPD.pPresentationParameters.SwapEffect := XTL.D3DSWAPEFFECT_COPY_VSYNC;

                    g_EmuCDPD.hFocusWindow := g_hEmuWindow;

                    g_EmuCDPD.pPresentationParameters.BackBufferFormat       := XTL.EmuXB2PC_D3Dg_EmuCDPD.pPresentationParameters.BackBufferFormat);
                    g_EmuCDPD.pPresentationParameters.AutoDepthStencilFormat := XTL.EmuXB2PC_D3Dg_EmuCDPD.pPresentationParameters.AutoDepthStencilFormat);

                    if( not g_XBVideo.GetVSync() and (g_D3DCaps.PresentationIntervals and D3DPRESENT_INTERVAL_IMMEDIATE) and g_XBVideo.GetFullscreen()) then
                        g_EmuCDPD.pPresentationParameters.FullScreen_PresentationInterval := D3DPRESENT_INTERVAL_IMMEDIATE;
                    else
                    begin
                        if(g_D3DCaps.PresentationIntervals and D3DPRESENT_INTERVAL_ONE and g_XBVideo.GetFullscreen()) then
                            g_EmuCDPD.pPresentationParameters.FullScreen_PresentationInterval := D3DPRESENT_INTERVAL_ONE;
                        else
                            g_EmuCDPD.pPresentationParameters.FullScreen_PresentationInterval := D3DPRESENT_INTERVAL_DEFAULT;
                     end;

                    // TODO: Support Xbox extensions if possible
                    if(g_EmuCDPD.pPresentationParameters.MultiSampleType <> 0) then
                    begin
                        EmuWarning('MultiSampleType 0x%.08X is not supported!', g_EmuCDPD.pPresentationParameters.MultiSampleType);

                        g_EmuCDPD.pPresentationParameters.MultiSampleType := XTL.D3DMULTISAMPLE_NONE;

                        // TODO: Check card for multisampling abilities
            //            if(pPresentationParameters->MultiSampleType == 0x00001121)
            //                pPresentationParameters->MultiSampleType = D3DMULTISAMPLE_2_SAMPLES;
            //            else
            //                CxbxKrnlCleanup('Unknown MultiSampleType (0x%.08X)', pPresentationParameters->MultiSampleType);
                     end;

                    g_EmuCDPD.pPresentationParameters.Flags := D3DPRESENTFLAG_LOCKABLE_BACKBUFFER;

                    // retrieve resolution from configuration
                    if(g_EmuCDPD.pPresentationParameters.Windowed) then
                    begin
                        sscanf(g_XBVideo.GetVideoResolution(), '%d x %d', @g_EmuCDPD.pPresentationParameters.BackBufferWidth, @g_EmuCDPD.pPresentationParameters.BackBufferHeight);

                        XTL.D3DDISPLAYMODE D3DDisplayMode;

                        g_pD3D8.GetAdapterDisplayMode(g_XBVideo.GetDisplayAdapter(), @D3DDisplayMode);

                        g_EmuCDPD.pPresentationParameters.BackBufferFormat := D3DDisplayMode.Format;
                        g_EmuCDPD.pPresentationParameters.FullScreen_RefreshRateInHz := 0;
                     end;
                    else
                    begin
                         szBackBufferFormat: array[0..16-1] of Char;

                        sscanf(g_XBVideo.GetVideoResolution(), '%d x %d %*dbit %s (%d hz)',
                            @g_EmuCDPD.pPresentationParameters.BackBufferWidth,
                            @g_EmuCDPD.pPresentationParameters.BackBufferHeight,
                            szBackBufferFormat,
                            @g_EmuCDPD.pPresentationParameters.FullScreen_RefreshRateInHz);

                        if(StrComp(szBackBufferFormat, 'x1r5g5b5') = 0) then
                            g_EmuCDPD.pPresentationParameters.BackBufferFormat := XTL.D3DFMT_X1R5G5B5;
                        else if(StrComp(szBackBufferFormat, 'r5g6r5') = 0) then
                            g_EmuCDPD.pPresentationParameters.BackBufferFormat := XTL.D3DFMT_R5G6B5;
                        else if(StrComp(szBackBufferFormat, 'x8r8g8b8') = 0) then
                            g_EmuCDPD.pPresentationParameters.BackBufferFormat := XTL.D3DFMT_X8R8G8B8;
                        else if(StrComp(szBackBufferFormat, 'a8r8g8b8') = 0) then
                            g_EmuCDPD.pPresentationParameters.BackBufferFormat := XTL.D3DFMT_A8R8G8B8;
                     end;
                 end;

                // detect vertex processing capabilities
                if((g_D3DCaps.DevCaps and D3DDEVCAPS_HWTRANSFORMANDLIGHT) and g_EmuCDPD.DeviceType = XTL.D3DDEVTYPE_HAL) then
                begin
                    DbgPrintf('EmuD3D8 : Using hardware vertex processing');

                    g_EmuCDPD.BehaviorFlags := D3DCREATE_HARDWARE_VERTEXPROCESSING;
                    g_dwVertexShaderUsage := 0;
                 end;
                else
                begin
                    DbgPrintf('EmuD3D8 : Using software vertex processing');

                    g_EmuCDPD.BehaviorFlags := D3DCREATE_SOFTWARE_VERTEXPROCESSING;
                    g_dwVertexShaderUsage := D3DUSAGE_SOFTWAREPROCESSING;
                 end;

                // redirect to windows Direct3D
                g_EmuCDPD.hRet = g_pD3D8.CreateDevice
                (
                    g_EmuCDPD.Adapter,
                    g_EmuCDPD.DeviceType,
                    g_EmuCDPD.hFocusWindow,
                    g_EmuCDPD.BehaviorFlags,
                    (XTL.D3DPRESENT_PARAMETERS)g_EmuCDPD.pPresentationParameters,
                    g_EmuCDPD.ppReturnedDeviceInterface
                );

                // report error
                if(FAILED(g_EmuCDPD.hRet)) then
                begin
                    if(g_EmuCDPD.hRet = D3DERR_INVALIDCALL) then
                        CxbxKrnlCleanup('IDirect3D8.CreateDevice failed (Invalid Call)');
                    else if(g_EmuCDPD.hRet = D3DERR_NOTAVAILABLE) then
                        CxbxKrnlCleanup('IDirect3D8.CreateDevice failed (Not Available)');
                    else if(g_EmuCDPD.hRet = D3DERR_OUTOFVIDEOMEMORY) then
                        CxbxKrnlCleanup('IDirect3D8.CreateDevice failed (Out of Video Memory)');

                    CxbxKrnlCleanup('IDirect3D8.CreateDevice failed (Unknown)');
                 end;

                // cache device pointer
                g_pD3DDevice8 := *g_EmuCDPD.ppReturnedDeviceInterface;

                // default NULL guid
                ZeroMemory(@g_ddguid, SizeOf(GUID));

                // enumerate device guid for this monitor, for directdraw
                HRESULT hRet := XTL.DirectDrawEnumerateExA(EmuEnumDisplayDevices, 0, DDENUM_ATTACHEDSECONDARYDEVICES);

                // create DirectDraw7
                begin
                    if(FAILED(hRet)) then
                        hRet := XTL.DirectDrawCreateEx(0, @g_pDD7, XTL.IID_IDirectDraw7, 0);
                    else
                        hRet := XTL.DirectDrawCreateEx(@g_ddguid, @g_pDD7, XTL.IID_IDirectDraw7, 0);

                    if(FAILED(hRet)) then
                        CxbxKrnlCleanup('Could not initialize DirectDraw7');

                    hRet := g_pDD7.SetCooperativeLevel(0, DDSCL_NORMAL);

                    if(FAILED(hRet)) then
                        CxbxKrnlCleanup('Could not set cooperative level');
                 end;

                // check for YUY2 overlay support TODO: accept other overlay types
                begin
                    DWORD  dwCodes := 0;
                    DWORD *lpCodes := 0;

                    g_pDD7.GetFourCCCodes(@dwCodes, lpCodes);

                    lpCodes := (DWORD)CxbxMalloc(dwCodes*SizeOf(DWORD));

                    g_pDD7.GetFourCCCodes(@dwCodes, lpCodes);

                    g_bSupportsYUY2 := False;
                    for(DWORD v:=0;v<dwCodes;v++)
                    begin
                        if(lpCodes[v] = MAKEFOURCC('Y','U','Y','2')) then
                        begin
                            g_bSupportsYUY2 := true;
                            break;
                         end;
                     end;

                    CxbxFree(lpCodes);

                    if( not g_bSupportsYUY2) then
                        EmuWarning('YUY2 overlays are not supported in hardware, could be slow!');
                 end;

                // initialize primary surface
                if(g_bSupportsYUY2) then
                begin
                    XTL.DDSURFACEDESC2 ddsd2;

                    ZeroMemory(@ddsd2, SizeOf(ddsd2));

                    ddsd2.dwSize := SizeOf(ddsd2);
                    ddsd2.dwFlags := DDSD_CAPS;
                    ddsd2.ddsCaps.dwCaps := DDSCAPS_PRIMARYSURFACE;

                    HRESULT hRet := g_pDD7.CreateSurface(@ddsd2, @g_pDDSPrimary, 0);

                    if(FAILED(hRet)) then
                        CxbxKrnlCleanup('Could not create primary surface (0x%.08X)', hRet);
                 end;

                // update render target cache
                g_pCachedRenderTarget := new XTL.X_D3DSurface();
                g_pCachedRenderTarget.Common := 0;
                g_pCachedRenderTarget.Data := X_D3DRESOURCE_DATA_FLAG_SPECIAL or X_D3DRESOURCE_DATA_FLAG_D3DREND;
                g_pD3DDevice8.GetRenderTarget(@g_pCachedRenderTarget.EmuSurface8);

                // update z-stencil surface cache
                g_pCachedZStencilSurface := new XTL.X_D3DSurface();
                g_pCachedZStencilSurface.Common := 0;
                g_pCachedZStencilSurface.Data := X_D3DRESOURCE_DATA_FLAG_SPECIAL or X_D3DRESOURCE_DATA_FLAG_D3DSTEN;
                g_pD3DDevice8.GetDepthStencilSurface(@g_pCachedZStencilSurface.EmuSurface8);


                g_pD3DDevice8.CreateVertexBuffer
                (
                    1, 0, 0, XTL.D3DPOOL_MANAGED,
                    @g_pDummyBuffer
                );

                for(integer Streams := 0; Streams < 8; Streams++)
                begin
                    g_pD3DDevice8.SetStreamSource(Streams, g_pDummyBuffer, 1);
                 end;

                // begin scene
                g_pD3DDevice8.BeginScene();

                // initially, show a black screen
                g_pD3DDevice8.Clear(0, 0, D3DCLEAR_TARGET, $FF000000, 0, 0);
                g_pD3DDevice8.Present(0, 0, 0, 0);

                // signal completion
                g_EmuCDPD.bReady := False;
             end;
            else
            begin
                // release direct3d
                if(g_pD3DDevice8 <> 0) then
                begin
                    DbgPrintf('EmuD3D8 : CreateDevice proxy thread releasing old Device.');

                    g_pD3DDevice8.EndScene();

                    g_EmuCDPD.hRet := g_pD3DDevice8.Release();

                    if(g_EmuCDPD.hRet = 0) then
                        g_pD3DDevice8 := 0;
                 end;

                if(g_bSupportsYUY2) then
                begin
                    // cleanup directdraw surface
                    if(g_pDDSPrimary <> 0) then
                    begin
                        g_pDDSPrimary.Release();
                        g_pDDSPrimary := 0;
                     end;
                 end;

                // cleanup directdraw
                if(g_pDD7 <> 0) then
                begin
                    g_pDD7.Release();
                    g_pDD7 := 0;
                 end;

                // signal completion
                g_EmuCDPD.bReady := False;
             end;
         end;

        Sleep(1);
     end; *)

  Result := 0;
end;

// check if a resource has been registered yet (if not, register it)

procedure EmuVerifyResourceIsRegistered(var pResource: X_D3DResource);
begin
  // 0xEEEEEEEE and 0xFFFFFFFF are somehow set in Halo :(
  if (pResource.Lock <> 0) and (pResource.Lock <> $EEEEEEEE) and (pResource.Lock <> $FFFFFFFF) then
    Exit;

{ TODO : Need to be translated to delphi }
  // Already 'Registered' implicitly
  (*if (( IsSpecialResource(pResource.Data) and ((pResource.Data and X_D3DRESOURCE_DATA_FLAG_D3DREND) or (pResource.Data and X_D3DRESOURCE_DATA_FLAG_D3DSTEN))) then
    or (pResource.Data = $B00BBABE))
    Exit;

  integer v := 0;

  for (v := 0; v < 16; v + +)
  begin
    if (pCache[v].Data = pResource.Data and pResource.Data <> 0) then
    begin
      pResource.EmuResource8 := pCache[v].EmuResource8;
      Exit;
    end;
  end;

  EmuSwapFS(); // XBox FS;
  { TODO : Need to be translated to delphi }
(*  XTL.EmuIDirect3DResource8_Register(pResource, 0 (*(PVOID)pResource->Data*)//);
(*  EmuSwapFS(); // Win2k/XP FS

  if (pResource.Lock <> X_D3DRESOURCE_LOCK_FLAG_NOSIZE) then
  begin
    for (v := 0; v < 16; v + +)
    begin
      if (pCache[v].Data = 0) then
      begin
        pCache[v].Data := pResource.Data;
        pCache[v].EmuResource8 := pResource.EmuResource8;
        break;
      end;

      if (v = 16) then
        CxbxKrnlCleanup('X_D3DResource cache is maxed out!');
    end;
  end;      *)
end;

// ensure a given width/height are powers of 2

procedure EmuAdjustPower2(var dwWidth: UINT; var dwHeight: UINT);
(*var
  NewWidth, NewHeight: uInt;
  v: Integer;
  mask: integer; *)
begin
  (*for v := 0 to 31 do begin
        { TODO : need to be translated to delphi }
    mask := 1 shl v;

        if(dwWidth and mask) then
            NewWidth := mask;

        if(dwHeight and mask) then
            NewHeight := mask;
  end;

  if (dwWidth <> NewWidth) then
  begin
    NewWidth := NewWidth shl 1;
    EmuWarning(Format('Needed to resize width (%d.%d)', [dwWidth, NewWidth]));
  end;

  if (dwHeight <> NewHeight) then
  begin
    NewHeight := NewHeight shl 1;
    EmuWarning(Format('Needed to resize height (%d.%d)', [dwHeight, NewHeight]));
  end;

  dwWidth := NewWidth;
  dwHeight := NewHeight;      *)
end;

// func: EmuIDirect3D8_CreateDevice

function XTL_EmuIDirect3D8_CreateDevice(Adapter: UINT; DeviceType: D3DDEVTYPE;
  hFocusWindow: HWND; BehaviorFlags: DWORD;
  pPresentationParameters: X_D3DPRESENT_PARAMETERS;
  ppReturnedDeviceInterface: IDirect3DDevice8): HRESULT;
begin
  Result := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3D8_CreateDevice' +
    #13#10'(' +
    #13#10'   Adapter                   : 0x%.08X' +
    #13#10'   DeviceType                : 0x%.08X' +
    #13#10'   hFocusWindow              : 0x%.08X' +
    #13#10'   BehaviorFlags             : 0x%.08X' +
    #13#10'   pPresentationParameters   : 0x%.08X' +
    #13#10'   ppReturnedDeviceInterface : 0x%.08X' +
    #13#10');',
    [Adapter, @DeviceType, hFocusWindow,
    BehaviorFlags, @pPresentationParameters, ppReturnedDeviceInterface]);

    // Cache parameters
    { TODO : Need to be translated to delphi }
(*    g_EmuCDPD.Adapter := Adapter;
    g_EmuCDPD.DeviceType := DeviceType;
    g_EmuCDPD.hFocusWindow := hFocusWindow;
    g_EmuCDPD.pPresentationParameters := pPresentationParameters;
    g_EmuCDPD.ppReturnedDeviceInterface := ppReturnedDeviceInterface;

    // Wait until proxy is done with an existing call (i highly doubt this situation will come up)
    while(g_EmuCDPD.bReady)
        Sleep(10);

    // Signal proxy thread, and wait for completion
    g_EmuCDPD.bReady := true;
    g_EmuCDPD.bCreate := true;

    // Wait until proxy is completed
    while(g_EmuCDPD.bReady)
        Sleep(10);               *)

  EmuSwapFS(); // XBox FS

(*    Result:= g_EmuCDPD.hRet;
*)
end;

// func: EmuIDirect3DResource8_IsBusy

function XTL_EmuIDirect3DDevice8_IsBusy: LongBOOL;
begin
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_IsBusy();');
  EmuWarning('EmuIDirect3DDevice8_IsBusy ignored!');
  EmuSwapFS(); // XBox FS
  Result := False;
end;

// func: EmuIDirect3DDevice8_GetCreationParameters

procedure XTL_EmuIDirect3DDevice8_GetCreationParameters(pParameters: D3DDEVICE_CREATION_PARAMETERS);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetCreationParameters' +
    #13#10'(' +
    #13#10'   pParameters               : 0x%.08X' +
    #13#10');',
    [@pParameters]);

  pParameters.AdapterOrdinal := D3DADAPTER_DEFAULT;
  pParameters.DeviceType := D3DDEVTYPE_HAL;
  pParameters.hFocusWindow := 0;
  pParameters.BehaviorFlags := D3DCREATE_HARDWARE_VERTEXPROCESSING;

  EmuSwapFS(); // XBox FS

  Exit;
end;


// func: EmuIDirect3D8_CheckDeviceFormat

function XTL_EmuIDirect3D8_CheckDeviceFormat(Adapter: UINT; DeviceType: D3DDEVTYPE;
  AdapterFormat: D3DFORMAT; Usage: DWORD; RType: X_D3DRESOURCETYPE; CheckFormat: X_D3DFORMAT): HRESULT;
var
  hRet: HRESULT;
begin
  hRet := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3D8_CheckDeviceFormat' +
    #13#10'(' +
    #13#10'   Adapter                   : 0x%.08X' +
    #13#10'   DeviceType                : 0x%.08X' +
    #13#10'   AdapterFormat             : 0x%.08X' +
    #13#10'   Usage                     : 0x%.08X' +
    #13#10'   RType                     : 0x%.08X' +
    #13#10'   CheckFormat               : 0x%.08X' +
    #13#10');',
    [Adapter, @DeviceType, @AdapterFormat,
    Usage, @RType, CheckFormat]);

  if (Ord(RType) > 7) then
    CxbxKrnlCleanup('RType > 7');

  { TODO : Need to be translated to delphi }
  (*hRet := g_pD3D8.CheckDeviceFormat(
    g_XBVideo.GetDisplayAdapter(), (g_XBVideo.GetDirect3DDevice() = 0)? XTL.D3DDEVTYPE_HAL: XTL.D3DDEVTYPE_REF,
    EmuXB2PC_D3DAdapterFormat), Usage, (D3DRESOURCETYPE)RType, EmuXB2PC_D3DCheckFormat)); *)


  EmuSwapFS(); // XBox FS
  Result := hRet;
end;

// func: EmuIDirect3DDevice8_GetDisplayFieldStatus

procedure XTL_EmuIDirect3DDevice8_GetDisplayFieldStatus(pFieldStatus: X_D3DFIELD_STATUS);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetDisplayFieldStatus' +
    #13#10'(' +
    #13#10'   pFieldStatus              : 0x%.08X' +
    #13#10');',
    [@pFieldStatus]);

    { TODO : Need to be translated to delphi }
    (*pFieldStatus.Field := (g_VBData.VBlank%2 = 0) ? X_D3DFIELD_ODD : X_D3DFIELD_EVEN;
    pFieldStatus.VBlankCount := g_VBData.VBlank; *)

  EmuSwapFS(); // XBox FS

  Exit;
end;

// func: EmuIDirect3DDevice8_BeginPush

function XTL_EmuIDirect3DDevice8_BeginPush(Count: DWORD): DWORD;
var
  pRet: DWORD;
begin
  pRet := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_BeginPush(%d);', [Count]);

    { TODO : Need to be translated to delphi }
    (*DWORD *pRet := new DWORD[Count];

    g_dwPrimaryPBCount := Count;
    g_pPrimaryPB := pRet; *)

  EmuSwapFS(); // XBox FS

  Result := pRet;
end;

// func: EmuIDirect3DDevice8_EndPush

procedure XTL_EmuIDirect3DDevice8_EndPush(pPush: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_EndPush(0x%.08X);', [pPush]);

  XTL_EmuExecutePushBufferRaw(g_pPrimaryPB);

    { TODO : Need to be translated to delphi }
    (*
    delete[] g_pPrimaryPB; *)

  g_pPrimaryPB := 0;


  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_BeginVisibilityTest

function XTL_EmuIDirect3DDevice8_BeginVisibilityTest: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_BeginVisibilityTest();');
  EmuSwapFS(); // XBox FS
  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_EndVisibilityTest

function XTL_EmuIDirect3DDevice8_EndVisibilityTest(Index: DWord): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_EndVisibilityTest' +
    #13#10'(' +
    #13#10'   Index                     : 0x%.08X' +
    #13#10');)',
    [Index]);
  EmuSwapFS(); // XBox FS
  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_SetBackBufferScale

procedure XTL_EmuIDirect3DDevice8_SetBackBufferScale(x, y: Single);
begin
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetBackBufferScale' +
    #13#10'(' +
    #13#10'   x                         :  0x%f' +
    #13#10'   y                         :  0x%f' +
    #13#10');',
    [x, y]);
  EmuWarning('SetBackBufferScale ignored');
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_GetVisibilityTestResult

function XTL_EmuIDirect3DDevice8_GetVisibilityTestResult(Index: DWORD;
  pResult: UINT; pTimeStamp: ULONGLONG): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetVisibilityTestResult' +
    #13#10'(' +
    #13#10'   Index                     : 0x%.08X' +
    #13#10'   pResult                   : 0x%.08X' +
    #13#10'   pTimeStamp                : 0x%.08X' +
    #13#10');',
    [Index, pResult, pTimeStamp]);

    // TODO: actually emulate this!?

  if (pResult <> 0) then
    pResult := 640 * 480;

  if (pTimeStamp <> 0) then
    pTimeStamp := 0;

  EmuSwapFS(); // XBox FS

  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_GetDeviceCaps

procedure XTL_EmuIDirect3DDevice8_GetDeviceCaps(pCaps: D3DCAPS8);
begin
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetDeviceCaps' +
    #13#10'(' +
    #13#10'   pCaps                     : 0x%.08X' +
    #13#10');',
    [@pCaps]);

    { TODO : need to be translated to delphi }
    (*g_pD3D8.GetDeviceCaps(g_XBVideo.GetDisplayAdapter(), (g_XBVideo.GetDirect3DDevice() := 0) ? XTL.D3DDEVTYPE_HAL : XTL.D3DDEVTYPE_REF, pCaps);
    *)
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_LoadVertexShader

function XTL_EmuIDirect3DDevice8_LoadVertexShader(Handle: DWord; Address: DWord): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  // debug trace
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_LoadVertexShader' +
    #13#10'(' +
    #13#10'   Handle              : 0x%.08X' +
    #13#10'   Address             : 0x%.08X' +
    #13#10');',
    [Handle, Address]);

{ TODO : Need to be translated to delphi }
(*    if(Address < 136 and VshHandleIsVertexShader(Handle)) then
    begin
        VERTEX_SHADER *pVertexShader := (VERTEX_SHADER )(VshHandleGetVertexShader(Handle)).Handle;
        for (DWORD i := Address; i < pVertexShader.Size; i++)
        begin
            // TODO: This seems very fishy
            g_VertexShaderSlots[i] := Handle;
         end;
     end;
*)

  EmuSwapFS(); // Xbox FS
  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_SelectVertexShader

function XTL_EmuIDirect3DDevice8_SelectVertexShader(Handle: DWord; Address: DWord): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SelectVertexShader' +
    #13#10'(' +
    #13#10'   Handle              : 0x%.08X' +
    #13#10'   Address             : 0x%.08X' +
    #13#10');',
    [Handle, Address]);

{ TODO : Need to be translated to delphi }
(*    if(VshHandleIsVertexShader(Handle)) then
    begin
        VERTEX_SHADER *pVertexShader := (VERTEX_SHADER )(((X_D3DVertexShader )(Handle and $7FFFFFFF)).Handle);
        g_pD3DDevice8.SetVertexShader(pVertexShader.Handle);
     end;
    else if(Handle = 0) then
    begin
        g_pD3DDevice8.SetVertexShader(D3DFVF_XYZ or D3DFVF_TEX0);
     end;
    else if(Address < 136) then
    begin
        X_D3DVertexShader *pVertexShader := (X_D3DVertexShader)g_VertexShaderSlots[Address];

        if(pVertexShader <> 0) then
        begin
            g_pD3DDevice8.SetVertexShader(((VERTEX_SHADER )((X_D3DVertexShader )g_VertexShaderSlots[Address]).Handle).Handle);
         end;
        else
        begin
            EmuWarning('g_VertexShaderSlots[%d] := 0', Address);
         end;
     end;
*)

  EmuSwapFS(); // XBox FS
  Result := D3D_OK;
end;

// func: EmuIDirect3D8_GetAdapterModeCount

function XTL_EmuIDirect3D8_GetAdapterModeCount(Adapter: DWord): DWord;
var
  ret: UINT;
  Mode: D3DDISPLAYMODE;
  v: uInt32;
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3D8_GetAdapterModeCount' +
    #13#10'(' +
    #13#10'   Adapter                   : 0x%.08X' +
    #13#10');',
    [Adapter]);

  ret := g_pD3D8.GetAdapterModeCount(g_XBVideo.GetDisplayAdapter);

  for v := 0 to ret - 1 do begin
    hRet := g_pD3D8.EnumAdapterModes(g_XBVideo.GetDisplayAdapter, v, Mode);

    if (hRet <> D3D_OK) then
      break;

    if (Mode.Width <> 640) or (Mode.Height <> 480) then
      ret := ret - 1;
  end;


  EmuSwapFS(); // XBox FS
  Result := ret;
end;

// func: EmuIDirect3D8_GetAdapterDisplayMode

function XTL_EmuIDirect3D8_GetAdapterDisplayMode(Adapter: UINT; pMode: X_D3DDISPLAYMODE): HRESULT;
var
  hRet: HRESULT;
  (*pPCMode: D3DDISPLAYMODE; *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3D8_GetAdapterDisplayMode' +
    #13#10'(' +
    #13#10'   Adapter                   : 0x%.08X' +
    #13#10'   pMode                     : 0x%.08X' +
    #13#10');',
    [@Adapter, @pMode]);

    { TODO : need to be translated to delphi }
    // NOTE: WARNING: We should cache the 'Emulated' display mode and return
    // This value. We can initialize the cache with the default Xbox mode data.
(*  hRet := g_pD3D8.GetAdapterDisplayMode(g_XBVideo.GetDisplayAdapter(), pMode as D3DDISPLAYMODE);

    // make adjustments to the parameters to make sense with windows direct3d
  begin
    pPCMode := D3DDISPLAYMODE(pMode);

        // Convert Format (PC->Xbox)
        { TODO : need to be translated to delphi }
        (*pMode.Format := EmuPC2XB_D3DpPCMode.Format);

        // TODO: Make this configurable in the future?
        // D3DPRESENTFLAG_FIELD | D3DPRESENTFLAG_INTERLACED | D3DPRESENTFLAG_LOCKABLE_BACKBUFFER
    pMode.Flags := $000000A1;

        // TODO: Retrieve from current CreateDevice settings?
    pMode.Width := 640;
    pMode.Height := 480;
  end;
*)
  EmuSwapFS(); // XBox FS
  Result := hRet;
end;


// func: EmuIDirect3D8_EnumAdapterModes

function XTL_EmuIDirect3D8_EnumAdapterModes(Adapter: UINT; Mode: UINT; pMode: X_D3DDISPLAYMODE): HRESULT;
var

  hRet: HRESULT;
  ModeAdder: integer;

  PCMode: D3DDISPLAYMODE;
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3D8_EnumAdapterModes' +
    #13#10'(' +
    #13#10'   Adapter                   : 0x%.08X' +
    #13#10'   Mode                      : 0x%.08X' +
    #13#10'   pMode                     : 0x%.08X' +
    #13#10');',
    [@Adapter, @Mode, @pMode]);


  ModeAdder := 0;

  if (Mode = 0) then
    ModeAdder := 0;

    { TODO : need to be translated to delphi }
    (*


    do
    begin
        hRet := g_pD3D8.EnumAdapterModes(g_XBVideo.GetDisplayAdapter(), Mode+ModeAdder, (D3DDISPLAYMODE)@PCMode);

        if(hRet <> D3D_OK or (PCMode.Width = 640 and PCMode.Height = 480)) then
            break;

        ModeAdder:= ModeAdder + 1;
     end;
    while(true);
    *)

    // make adjustments to parameters to make sense with windows direct3d
  if (hRet = D3D_OK) then begin
        //
        // NOTE: WARNING: PC D3DDISPLAYMODE is different than Xbox D3DDISPLAYMODE!
        //

        // Convert Format (PC->Xbox)
    pMode.Width := PCMode.Width;
    pMode.Height := PCMode.Height;
    pMode.RefreshRate := PCMode.RefreshRate;

        // TODO: Make this configurable in the future?
        // D3DPRESENTFLAG_FIELD | D3DPRESENTFLAG_INTERLACED | D3DPRESENTFLAG_LOCKABLE_BACKBUFFER
    pMode.Flags := $000000A1;

    { TODO -oDxbx : Need to be translated to delphi }
    (*
    pMode.Format := XTL_EmuPC2XB_D3DFormat(PCMode.Format)
    *)
  end
  else
  begin
    hRet := D3DERR_INVALIDCALL;
  end;

  EmuSwapFS(); // XBox FS
  Result := hRet;
end;

// func: EmuIDirect3D8_KickOffAndWaitForIdle

procedure XTL_EmuIDirect3D8_KickOffAndWaitForIdle;
begin
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3D8_KickOffAndWaitForIdle();');
  // TODO: Actually do something here?
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3D8_KickOffAndWaitForIdle2

procedure XTL_EmuIDirect3D8_KickOffAndWaitForIdle2(dwDummy1, dwDummy2: DWORD);
begin
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3D8_KickOffAndWaitForIdle' +
    #13#10'(' +
    #13#10'   dwDummy1            : 0x%.08X' +
    #13#10'   dwDummy2            : 0x%.08X' +
    #13#10');',
    [dwDummy1, dwDummy2]);
    // TODO: Actually do something here?
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetGammaRamp

procedure XTL_EmuIDirect3DDevice8_SetGammaRamp(dwFlags: DWORD; pRamp: X_D3DGAMMARAMP);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetGammaRamp' +
    #13#10'(' +
    #13#10'   dwFlags             : 0x%.08X' +
    #13#10'   pRamp               : 0x%.08X' +
    #13#10');',
    [dwFlags, @pRamp]);

{ TODO : Need to be translated to delphi }
    // remove D3DSGR_IMMEDIATE
(*    DWORD dwPCFlags := dwFlags and (~$00000002);
    D3DGAMMARAMP PCRamp;

    for(integer v:=0;v<255;v++)
    begin
        PCRamp.red[v]   := pRamp.red[v];
        PCRamp.green[v] := pRamp.green[v];
        PCRamp.blue[v]  := pRamp.blue[v];
     end;

    g_pD3DDevice8.SetGammaRamp(dwPCFlags, @PCRamp);
*)
  EmuSwapFS(); // XBox FS

end;

// func: EmuIDirect3DDevice8_AddRef

function XTL_EmuIDirect3DDevice8_AddRef(): ULONG;
var
  ret: ULONG;
begin
  ret := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_AddRef()');

    { TODO : Need to be translated to delphi }
    (*
    ret := g_pD3DDevice8.AddRef(); *)
  EmuSwapFS(); // XBox FS
  Result := ret;
end;

// func: EmuIDirect3DDevice8_BeginStateBlock

function XTL_EmuIDirect3DDevice8_BeginStateBlock: HRESULT;
var
  ret: ULONG;
begin
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_BeginStateBlock();');

  ret := g_pD3DDevice8.BeginStateBlock();
  EmuSwapFS(); // XBox FS
  Result := ret;
end;

// func: EmuIDirect3DDevice8_BeginStateBig

function XTL_EmuIDirect3DDevice8_BeginStateBig: HRESULT;
var
  ret: ULONG;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_BeginStateBig();');
  ret := g_pD3DDevice8.BeginStateBlock();

  CxbxKrnlCleanup('BeginStateBig is not implemented');
  EmuSwapFS(); // XBox FS
  Result := ret;
end;

// func: EmuIDirect3DDevice8_CaptureStateBlock

function XTL_EmuIDirect3DDevice8_CaptureStateBlock(Token: DWORD): HRESULT;
var
  ret: ULONG;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CaptureStateBlock' +
    #13#10'(' +
    #13#10'   Token               : 0x%.08X' +
    #13#10');',
    [Token]);

  ret := g_pD3DDevice8.CaptureStateBlock(Token);
  EmuSwapFS(); // XBox FS
  Result := ret;
end;

// func: EmuIDirect3DDevice8_ApplyStateBlock

function XTL_EmuIDirect3DDevice8_ApplyStateBlock(Token: DWORD): HRESULT;
var
  ret: ULONG;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_ApplyStateBlock' +
    #13#10'(' +
    #13#10'   Token               : 0x%.08X' +
    #13#10');',
    [Token]);

  ret := g_pD3DDevice8.ApplyStateBlock(Token);


  EmuSwapFS(); // XBox FS
  Result := ret;
end;

// func: EmuIDirect3DDevice8_EndStateBlock

function XTL_EmuIDirect3DDevice8_EndStateBlock(pToken: DWORD): HRESULT;
var
  ret: LONG;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_EndStateBlock' +
    #13#10'(' +
    #13#10'   pToken              : 0x%.08X' +
    #13#10');',
    [pToken]);

  ret := g_pD3DDevice8.EndStateBlock(pToken);


  EmuSwapFS(); // XBox FS
  Result := ret;
end;

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_CopyRects

function XTL_EmuIDirect3DDevice8_CopyRects: HRESULT;
var
  hRet: HRESULT;
(*(
    X_D3DSurface       *pSourceSurface,
    CONST TRect         *pSourceRectsArray,
    UINT                cRects,
    X_D3DSurface       *pDestinationSurface,
    CONST TPoint        *pDestPointsArray
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CopyRects' +
           #13#10'(' +
           #13#10'   pSourceSurface      : 0x%.08X' +
           #13#10'   pSourceRectsArray   : 0x%.08X' +
           #13#10'   cRects              : 0x%.08X' +
           #13#10'   pDestinationSurface : 0x%.08X' +
           #13#10'   pDestPointsArray    : 0x%.08X' +
           #13#10');',
           pSourceSurface, pSourceRectsArray, cRects,
           pDestinationSurface, pDestPointsArray);

    pSourceSurface.EmuSurface8.UnlockRect();

    (*
     integer kthx := 0;
     fileName: array[0..255-1] of Char;

    StrFmt(fileName, 'C:\Aaron\Textures\SourceSurface-%d.bmp', kthx++);

    D3DXSaveSurfaceToFile(fileName, D3DXIFF_BMP, pSourceSurface.EmuSurface8, 0, 0);
    //*/

    HRESULT hRet = g_pD3DDevice8.CopyRects
    (
        pSourceSurface.EmuSurface8,
        pSourceRectsArray,
        cRects,
        pDestinationSurface.EmuSurface8,
        pDestPointsArray
    );
*)

  EmuSwapFS(); // Xbox FS

  Result := hRet;
end;

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_CreateImageSurface

function XTL_EmuIDirect3DDevice8_CreateImageSurface(
  aFormat: X_D3DFORMAT; Width: UINT; Height: UINT; ppBackBuffer: X_D3DSurface): HRESULT;
var
  hRet: HRESULT;
  PCFormat: D3DFORMAT;
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CreateImageSurface' +
    #13#10'(' +
    #13#10'   Width               : 0x%.08X' +
    #13#10'   Height              : 0x%.08X' +
    #13#10'   Format              : 0x%.08X' +
    #13#10'   ppBackBuffer        : 0x%.08X' +
    #13#10');',
    [Width, Height, aFormat, ppBackBuffer]);

    { TODO -oDxbx : Need to be translated to delphi }
    (**ppBackBuffer := new X_D3DSurface();
    *)

  (*PCFormat := XTL_EmuXB2PC_D3DFormat(aFormat); *)

    { TODO -oDxbx : Need to be translated to delphi }
    (*
    HRESULT hRet := g_pD3DDevice8.CreateImageSurface(Width, Height, PCFormat,  and ((ppBackBuffer).EmuSurface8));
    *)

  EmuSwapFS(); // Xbox FS
  Result := hRet;
end;

// func: EmuIDirect3DDevice8_GetGammaRamp

procedure XTL_EmuIDirect3DDevice8_GetGammaRamp(pRamp: X_D3DGAMMARAMP);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetGammaRamp' +
    #13#10'(' +
    #13#10'   pRamp               : 0x%.08X' +
    #13#10');',
    [@pRamp]);

    { TODO : Need to be translated to delphi }
    (*D3DGAMMARAMP *pGammaRamp := (D3DGAMMARAMP )malloc(SizeOf(D3DGAMMARAMP));

    g_pD3DDevice8.GetGammaRamp(pGammaRamp);

    for(integer v:=0;v<256;v++)
    begin
        pRamp.red[v] := (BYTE)pGammaRamp.red[v];
        pRamp.green[v] := (BYTE)pGammaRamp.green[v];
        pRamp.blue[v] := (BYTE)pGammaRamp.blue[v];
     end;

    free(pGammaRamp); *)

  EmuSwapFS(); // Xbox FS
end;

// func: EmuIDirect3DDevice8_GetBackBuffer2

function XTL_EmuIDirect3DDevice8_GetBackBuffer2(BackBuffer: Integer): X_D3DSurface;
begin
  Result := nil;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetBackBuffer2' +
    #13#10'(' +
    #13#10'   BackBuffer          : 0x%.08X' +
    #13#10');',
    [BackBuffer]);

    { unsafe, somehow
    HRESULT hRet := S_OK;

    X_D3DSurface *pBackBuffer := new X_D3DSurface();

    if(BackBuffer = -1) then
    begin
         IDirect3DSurface8 *pCachedPrimarySurface := 0;

        if(pCachedPrimarySurface = 0) then
        begin
            // create a buffer to return
            // TODO: Verify the surface is always 640x480
            g_pD3DDevice8.CreateImageSurface(640, 480, D3DFMT_A8R8G8B8, @pCachedPrimarySurface);
         end;

        pBackBuffer.EmuSurface8 := pCachedPrimarySurface;

        hRet := g_pD3DDevice8.GetFrontBuffer(pBackBuffer.EmuSurface8);

        if(FAILED(hRet)) then
        begin
            EmuWarning('Could not retrieve primary surface, using backbuffer');
            pCachedPrimarySurface := 0;
            pBackBuffer.EmuSurface8.Release();
            pBackBuffer.EmuSurface8 := 0;
            BackBuffer := 0;
         end;

        // Debug: Save this image temporarily
        //D3DXSaveSurfaceToFile('C:\\Aaron\\Textures\\FrontBuffer.bmp', D3DXIFF_BMP, pBackBuffer->EmuSurface8, NULL, NULL);
     end;

    if(BackBuffer <> -1) then
        hRet := g_pD3DDevice8.GetBackBuffer(BackBuffer, D3DBACKBUFFER_TYPE_MONO,  and (pBackBuffer.EmuSurface8));
    }

   { TODO : need to be translated to delphi }
(*     X_D3DSurface *pBackBuffer := new X_D3DSurface();

    if(BackBuffer = -1) then
        BackBuffer := 0;

    HRESULT hRet := g_pD3DDevice8.GetBackBuffer(BackBuffer, D3DBACKBUFFER_TYPE_MONO,  and (pBackBuffer.EmuSurface8));

    if(FAILED(hRet)) then
        CxbxKrnlCleanup('Unable to retrieve back buffer');

    // update data pointer
    pBackBuffer.Data := X_D3DRESOURCE_DATA_FLAG_SPECIAL or X_D3DRESOURCE_DATA_FLAG_SURFACE;

    EmuSwapFS();   // Xbox FS

    Result:= pBackBuffer;          *)
end;

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_GetBackBuffer

procedure XTL_EmuIDirect3DDevice8_GetBackBuffer(BackBuffer: Integer; cType: D3DBACKBUFFER_TYPE; ppBackBuffer: X_D3DSurface);
begin
    // debug trace
{$IFDEF _DEBUG_TRACE}
  begin
    EmuSwapFS(); // Win2k/XP FS
    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetBackBuffer' +
      #13#10'(' +
      #13#10'   BackBuffer          : 0x%.08X' +
      #13#10'   cType                : 0x%.08X' +
      #13#10'   ppBackBuffer        : 0x%.08X' +
      #13#10');',
      [BackBuffer, @cType, ppBackBuffer]);
    EmuSwapFS(); // Xbox FS
  end;
{$ENDIF}

  ppBackBuffer := XTL_EmuIDirect3DDevice8_GetBackBuffer2(BackBuffer);
end;

// func: EmuIDirect3DDevice8_SetViewport

function XTL_EmuIDirect3DDevice8_SetViewport(pViewport: D3DVIEWPORT8): HRESULT;
var
  hRet: HRESULT;
  dwWidth: DWORD;
  dwHeight: DWORD;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetViewport' +
    #13#10'(' +
    #13#10'   pViewport           : 0x%.08X (%d, %d, %d, %d, %f, %f)' +
    #13#10');',
    [@pViewport, pViewport.X, pViewport.Y, pViewport.Width,
    pViewport.Height, pViewport.MinZ, pViewport.MaxZ]);

  dwWidth := pViewport.Width;
  dwHeight := pViewport.Height;

  // resize to fit screen (otherwise crashes occur)
  begin
    if (dwWidth <> 640) then
    begin
      EmuWarning('Resizing Viewport.Width to 640');
      pViewport.Width := 640;
    end;

    if (dwHeight <> 480) then
    begin
      EmuWarning('Resizing Viewport.Height to 480');
      pViewport.Height := 480;
    end;
  end;

  hRet := g_pD3DDevice8.SetViewport(pViewport);

  // restore originals
  begin
    if (dwWidth > 640) then
      pViewport.Width := dwWidth;

    if (dwHeight > 480) then
      pViewport.Height := dwHeight;
  end;

  if (FAILED(hRet)) then
  begin
    EmuWarning('Unable to set viewport!');
    hRet := D3D_OK;
  end;

  EmuSwapFS(); // Xbox FS
  Result := hRet;
end;

// func: EmuIDirect3DDevice8_GetViewport

function XTL_EmuIDirect3DDevice8_GetViewport(pViewport: D3DVIEWPORT8): HRESULT;
var
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetViewport' +
    #13#10'(' +
    #13#10'   pViewport           : 0x%.08X' +
    #13#10');',
    [@pViewport]);

  hRet := g_pD3DDevice8.GetViewport(pViewport);

  if (FAILED(hRet)) then
  begin
    EmuWarning('Unable to get viewport!');
    hRet := D3D_OK;
  end;

  EmuSwapFS(); // Xbox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_GetViewportOffsetAndScale

procedure XTL_EmuIDirect3DDevice8_GetViewportOffsetAndScale(pOffset: TD3DXVECTOR4; pScale: TD3DXVECTOR4);
var
  fScaleX: Single;
  fScaleY: Single;
  fScaleZ: Single;
  fOffsetX: Single;
  fOffsetY: Single;
  Viewport: D3DVIEWPORT8;

begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetViewportOffsetAndScale' +
    #13#10'(' +
    #13#10'   pOffset             : 0x%.08X' +
    #13#10'   pScale              : 0x%.08X' +
    #13#10');',
    [@pOffset, @pScale]);

  fScaleX := 1.0;
  fScaleY := 1.0;
  fScaleZ := 1.0;
  fOffsetX := 0.5 + 1.0 / 32;
  fOffsetY := 0.5 + 1.0 / 32;

  EmuSwapFS();
  XTL_EmuIDirect3DDevice8_GetViewport(Viewport);
  EmuSwapFS();

  pScale.x := 1.0;
  pScale.y := 1.0;
  pScale.z := 1.0;
  pScale.w := 1.0;

  pOffset.x := 0.0;
  pOffset.y := 0.0;
  pOffset.z := 0.0;
  pOffset.w := 0.0;


  pScale.x := Viewport.Width * 0.5 * fScaleX;
  pScale.y := Viewport.Height * -0.5 * fScaleY;
  pScale.z := (Viewport.MaxZ - Viewport.MinZ) * fScaleZ;
  pScale.w := 0;

  pOffset.x := Viewport.Width * fScaleX * 0.5 + Viewport.X * fScaleX + fOffsetX;
  pOffset.y := Viewport.Height * fScaleY * 0.5 + Viewport.Y * fScaleY + fOffsetY;
  pOffset.z := Viewport.MinZ * fScaleZ;
  pOffset.w := 0;


  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetShaderConstantMode

function XTL_EmuIDirect3DDevice8_SetShaderConstantMode(Mode: X_VERTEXSHADERCONSTANTMODE): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetShaderConstantMode' +
    #13#10'(' +
    #13#10'   Mode                : 0x%.08X' +
    #13#10');',
    [Mode]);

  g_VertexShaderConstantMode := Mode;
  EmuSwapFS(); // Xbox FS

  Result := S_OK;
end;


// func: EmuIDirect3DDevice8_Reset

function XTL_EmuIDirect3DDevice8_Reset(pPresentationParameters: X_D3DPRESENT_PARAMETERS): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_Reset' +
    #13#10'(' +
    #13#10'   pPresentationParameters  : 0x%.08X' +
    #13#10');',
    [@pPresentationParameters]);
  EmuWarning('Device Reset is being utterly ignored');
  EmuSwapFS(); // Xbox FS
  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_GetRenderTarget

function XTL_EmuIDirect3DDevice8_GetRenderTarget: HRESULT;
(*(
    X_D3DSurface  **ppRenderTarget
) *)
begin
  EmuSwapFS(); // Win2k/XP FS

(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetRenderTarget'
           #13#10'('
           #13#10'   ppRenderTarget      : 0x%.08X'
           #13#10');',
           ppRenderTarget);

    IDirect3DSurface8 *pSurface8 := g_pCachedRenderTarget.EmuSurface8;

    pSurface8.AddRef();

    *ppRenderTarget := g_pCachedRenderTarget;

    DbgPrintf('EmuD3D8 : RenderTarget := 0x%.08X', pSurface8);

   *)
  EmuSwapFS(); // Xbox FS

  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_GetRenderTarget2
{ TODO : Need to be translated to delphi }
(*XTL.X_D3DSurface * WINAPI XTL.EmuIDirect3DDevice8_GetRenderTarget2()
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetRenderTarget2()');

    IDirect3DSurface8 *pSurface8 := g_pCachedRenderTarget.EmuSurface8;

    pSurface8.AddRef();

    DbgPrintf('EmuD3D8 : RenderTarget := 0x%.08X', pSurface8);

    EmuSwapFS();   // Xbox FS

    Result:= g_pCachedRenderTarget;
 end; *)

// func: EmuIDirect3DDevice8_GetDepthStencilSurface
{ TODO : Need to be translated to delphi }

function XTL_EmuIDirect3DDevice8_GetDepthStencilSurface: HRESULT;
(*(
    X_D3DSurface  **ppZStencilSurface
) *)
begin
  EmuSwapFS(); // Win2k/XP FS

(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetDepthStencilSurface'
           #13#10'('
           #13#10'   ppZStencilSurface   : 0x%.08X'
           #13#10');',
           ppZStencilSurface);

    IDirect3DSurface8 *pSurface8 := g_pCachedZStencilSurface.EmuSurface8;

    if(pSurface8 <> 0) then
        pSurface8.AddRef();

    *ppZStencilSurface := g_pCachedZStencilSurface;

    DbgPrintf('EmuD3D8 : DepthStencilSurface := 0x%.08X', pSurface8);
*)
  EmuSwapFS(); // Xbox FS

  Result := D3D_OK;
end;

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_GetDepthStencilSurface2
(*XTL.X_D3DSurface * WINAPI XTL.EmuIDirect3DDevice8_GetDepthStencilSurface2()
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetDepthStencilSurface2()');

    IDirect3DSurface8 *pSurface8 := g_pCachedZStencilSurface.EmuSurface8;

    if(pSurface8 <> 0) then
        pSurface8.AddRef();

    DbgPrintf('EmuD3D8 : DepthStencilSurface := 0x%.08X', pSurface8);

    EmuSwapFS();   // Xbox FS

    Result:= g_pCachedZStencilSurface;
 end; *)

// func: EmuIDirect3DDevice8_GetTile
{ TODO : Need to be translated to delphi }

function XTL_EmuIDirect3DDevice8_GetTile: HRESULT;
(*Index : DWORD; pTile : X_D3DTILE*)

begin
  EmuSwapFS(); // Win2k/XP FS

{ TODO : parameters are not implemented into delphi yet }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetTile'
           #13#10'('
           #13#10'   Index               : 0x%.08X'
           #13#10'   pTile               : 0x%.08X'
           #13#10');',
           Index, pTile);

    if(pTile <> 0) then
        memcpy(pTile, @EmuD3DTileCache[Index], SizeOf(X_D3DTILE));
*)
  EmuSwapFS(); // XBox FS

  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_SetTileNoWait
{ TODO : Need to be translated to delphi }

function XTL_EmuIDirect3DDevice8_SetTileNoWait: HRESULT;
(*(
    DWORD               Index,
    CONST X_D3DTILE    *pTile
) *)
begin
  EmuSwapFS(); // Win2k/XP FS

{ TODO : parameters are not implemented into delphi yet }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetTileNoWait'
           #13#10'('
           #13#10'   Index               : 0x%.08X'
           #13#10'   pTile               : 0x%.08X'
           #13#10');',
           Index, pTile);

    if(pTile <> 0) then
        memcpy(@EmuD3DTileCache[Index], pTile, SizeOf(X_D3DTILE));
*)

  EmuSwapFS(); // XBox FS

  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_CreateVertexShader

function XTL_EmuIDirect3DDevice8_CreateVertexShader: HRESULT;
var
  hRet: HRESULT;
(*(
    CONST DWORD    *pDeclaration,
    CONST DWORD    *pFunction,
    DWORD          *pHandle,
    DWORD           Usage
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CreateVertexShader'
           #13#10'('
           #13#10'   pDeclaration        : 0x%.08X'
           #13#10'   pFunction           : 0x%.08X'
           #13#10'   pHandle             : 0x%.08X'
           #13#10'   Usage               : 0x%.08X'
           #13#10');',
           pDeclaration, pFunction, pHandle, Usage);

    // create emulated shader struct
    X_D3DVertexShader *pD3DVertexShader := (X_D3DVertexShader)CxbxMalloc(SizeOf(X_D3DVertexShader));
    VERTEX_SHADER     *pVertexShader := (VERTEX_SHADER)CxbxMalloc(SizeOf(VERTEX_SHADER));

    // TODO: Intelligently fill out these fields as necessary
    ZeroMemory(pD3DVertexShader, SizeOf(X_D3DVertexShader));
    ZeroMemory(pVertexShader, SizeOf(VERTEX_SHADER));

    // HACK: TODO: support this situation
    if(pDeclaration = 0) then
    begin
        *pHandle := 0;

        EmuSwapFS();   // Win2k/XP FS

        Result:= S_OK;
     end;

    LPD3DXBUFFER pRecompiledBuffer := 0;
    DWORD        *pRecompiledDeclaration;
    DWORD        *pRecompiledFunction := 0;
    DWORD        VertexShaderSize;
    DWORD        DeclarationSize;
    DWORD        Handle := 0;

    HRESULT hRet = XTL.EmuRecompileVshDeclaration((DWORD)pDeclaration,
                                                   @pRecompiledDeclaration,
                                                   @DeclarationSize,
                                                   pFunction = 0,
                                                   @pVertexShader.VertexDynamicPatch);

    if(SUCCEEDED(hRet) and pFunction) then
    begin
        hRet = XTL.EmuRecompileVshFunction((DWORD)pFunction,
                                            @pRecompiledBuffer,
                                            @VertexShaderSize,
                                            g_VertexShaderConstantMode := X_VSCM_NONERESERVED);
        if(SUCCEEDED(hRet)) then
        begin
            pRecompiledFunction := (DWORD)pRecompiledBuffer.GetBufferPointer();
         end;
        else
        begin
            pRecompiledFunction := 0;
            EmuWarning('Couldn't recompile vertex shader function.': );
            hRet := D3D_OK; // Try using a fixed function vertex shader instead
         end;
     end;

    //DbgPrintf('MaxVertexShaderConst = %d\n', g_D3DCaps.MaxVertexShaderConst);

    if(SUCCEEDED(hRet)) then
    begin
        hRet = g_pD3DDevice8.CreateVertexShader
        (
            pRecompiledDeclaration,
            pRecompiledFunction,
            @Handle,
            g_dwVertexShaderUsage   // TODO: HACK: Xbox has extensions!
        );
        if(pRecompiledBuffer) then
        begin
            pRecompiledBuffer.Release();
            pRecompiledBuffer := 0;
         end;
     end;
    // Save the status, to remove things later
    pVertexShader.Status := hRet;

    CxbxFree(pRecompiledDeclaration);

    pVertexShader.pDeclaration := (DWORD)CxbxMalloc(DeclarationSize);
    memcpy(pVertexShader.pDeclaration, pDeclaration, DeclarationSize);

    pVertexShader.FunctionSize := 0;
    pVertexShader.pFunction := 0;
    pVertexShader.cType := X_VST_NORMAL;
    pVertexShader.Size := (VertexShaderSize - SizeOf(VSH_SHADER_HEADER)) / VSH_INSTRUCTION_SIZE_BYTES;
    pVertexShader.DeclarationSize := DeclarationSize;

    if(SUCCEEDED(hRet)) then
    begin
        if(pFunction <> 0) then
        begin
            pVertexShader.pFunction := (DWORD)CxbxMalloc(VertexShaderSize);
            memcpy(pVertexShader.pFunction, pFunction, VertexShaderSize);
            pVertexShader.FunctionSize := VertexShaderSize;
         end;
        else
        begin
            pVertexShader.pFunction := 0;
            pVertexShader.FunctionSize := 0;
         end;
        pVertexShader.Handle := Handle;
     end;
    else
    begin
        pVertexShader.Handle := D3DFVF_XYZ or D3DFVF_TEX0;
     end;

    pD3DVertexShader.Handle := (DWORD)pVertexShader;

    *pHandle := ((DWORD)pD3DVertexShader) or $80000000;

    if(FAILED(hRet)) then
    begin
#ifdef _DEBUG_TRACK_VS
        if (pFunction) then
        begin
             pFileName: array[0..30-1] of Char;
             integer FailedShaderCount := 0;
            VSH_SHADER_HEADER *pHeader := (VSH_SHADER_HEADER)pFunction;
            EmuWarning('Couldn't create vertex shader!');
            StrFmt(pFileName, 'failed%05d.xvu', FailedShaderCount);
            FILE *f := FileOpen(pFileName, 'wb');
            if(f) then
            begin
                FileWrite(pFunction, SizeOf(VSH_SHADER_HEADER) + pHeader.NumInst * 16, 1, f);
                FileClose(f);
             end;
            FailedShaderCount:= FailedShaderCount + 1;
         end;
//endif // _DEBUG_TRACK_VS
        //hRet = D3D_OK;
     end;   *)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_SetPixelShaderConstant
{ TODO : Need to be translated to delphi }

procedure XTL_EmuIDirect3DDevice8_SetPixelShaderConstant;
(*(
    DWORD       Register,
    CONST PVOID pConstantData,
    DWORD       ConstantCount
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetPixelShaderConstant'
           #13#10'('
           #13#10'   Register            : 0x%.08X'
           #13#10'   pConstantData       : 0x%.08X'
           #13#10'   ConstantCount       : 0x%.08X'
           #13#10');',
           Register, pConstantData, ConstantCount);

    EmuSwapFS();   // XBox FS

    Exit; *)
end;

// func: EmuIDirect3DDevice8_SetVertexShaderConstant
{ TODO : Need to be translated to delphi }

function XTL_EmuIDirect3DDevice8_SetVertexShaderConstant: HRESULT;
var
  hRet: HRESULT;
(*(
    INT         Register,
    CONST PVOID pConstantData,
    DWORD       ConstantCount
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexShaderConstant'
           #13#10'('
           #13#10'   Register            : 0x%.08X'
           #13#10'   pConstantData       : 0x%.08X'
           #13#10'   ConstantCount       : 0x%.08X'
           #13#10');',
           Register, pConstantData, ConstantCount);

#ifdef _DEBUG_TRACK_VS_CONST
    for (uint32 i := 0; i < ConstantCount; i++)
    begin
        printf('SetVertexShaderConstant, c%d (c%d) := ( %f, %f, %f, %f  end;',
               Register - 96 + i, Register + i,
               *((Single)pConstantData + 4 * i),
               *((Single)pConstantData + 4 * i + 1),
               *((Single)pConstantData + 4 * i + 2),
               *((Single)pConstantData + 4 * i + 3));
     end;
//endif // _DEBUG_TRACK_VS_CONST

    HRESULT hRet = g_pD3DDevice8.SetVertexShaderConstant
    (
        Register,
        pConstantData,
        ConstantCount
    );

    if(FAILED(hRet)) then
    begin
        EmuWarning('We're lying about setting a vertex shader constant!');

        hRet := D3D_OK;
     end;
*)
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_SetVertexShaderConstant1
(*VOID __fastcall XTL.EmuIDirect3DDevice8_SetVertexShaderConstant1
(
    INT         Register,
    CONST PVOID pConstantData
)
begin
    // debug trace
    #ifdef _DEBUG_TRACE
    begin
        EmuSwapFS();   // Win2k/XP FS
        DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexShaderConstant1'
               #13#10'('
               #13#10'   Register            : 0x%.08X'
               #13#10'   pConstantData       : 0x%.08X'
               #13#10');',
               Register, pConstantData);
        EmuSwapFS();   // XBox FS
     end;
    //endif

    XTL.EmuIDirect3DDevice8_SetVertexShaderConstant(Register, pConstantData, 1);

    Exit;
 end; *)

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_SetVertexShaderConstant4
(* VOID __fastcall XTL.EmuIDirect3DDevice8_SetVertexShaderConstant4
(
    INT         Register,
    CONST PVOID pConstantData
)
begin
    // debug trace
    #ifdef _DEBUG_TRACE
    begin
        EmuSwapFS();   // Win2k/XP FS
        DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexShaderConstant4'
               #13#10'('
               #13#10'   Register            : 0x%.08X'
               #13#10'   pConstantData       : 0x%.08X'
               #13#10');',
               Register, pConstantData);
        EmuSwapFS();   // XBox FS
     end;
    //endif

    XTL.EmuIDirect3DDevice8_SetVertexShaderConstant(Register, pConstantData, 4);

    Exit;
 end; *)

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_SetVertexShaderConstantNotInline
(*VOID __fastcall XTL.EmuIDirect3DDevice8_SetVertexShaderConstantNotInline
(
    INT         Register,
    CONST PVOID pConstantData,
    DWORD       ConstantCount
)
begin
    // debug trace
    #ifdef _DEBUG_TRACE
    begin
        EmuSwapFS();   // Win2k/XP FS
        DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexShaderConstantNotInline'
               #13#10'('
               #13#10'   Register            : 0x%.08X'
               #13#10'   pConstantData       : 0x%.08X'
               #13#10'   ConstantCount       : 0x%.08X'
               #13#10');',
               Register, pConstantData, ConstantCount);
        EmuSwapFS();   // XBox FS
     end;
    //endif

    XTL.EmuIDirect3DDevice8_SetVertexShaderConstant(Register, pConstantData, ConstantCount / 4);

    Exit;
 end; *)

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_DeletePixelShader
(*VOID WINAPI XTL.EmuIDirect3DDevice8_DeletePixelShader
(
    DWORD          Handle
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_DeletePixelShader'
           #13#10'('
           #13#10'   Handle              : 0x%.08X'
           #13#10');',
           Handle);

    if(Handle = X_PIXELSHADER_FAKE_HANDLE) then
    begin
        // Do Nothing!
     end;
    else
    begin
        g_pD3DDevice8.DeletePixelShader(Handle);
     end;

    EmuSwapFS();   // XBox FS

    Exit;
 end; *)

// func: EmuIDirect3DDevice8_CreatePixelShader

function XTL_EmuIDirect3DDevice8_CreatePixelShader(pFunction: DWORD; pHandle: DWORD): HRESULT;
var
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CreatePixelShader' +
    #13#10'(' +
    #13#10'   pFunction           : 0x%.08X' +
    #13#10'   pHandle             : 0x%.08X' +
    #13#10');',
    [pFunction, pHandle]);

  // redirect to windows d3d
  hRet := g_pD3DDevice8.CreatePixelShader(@pFunction, pHandle);

  if (FAILED(hRet)) then
  begin
    pHandle := X_PIXELSHADER_FAKE_HANDLE;
    EmuWarning('We`re lying about the creation of a pixel shader!');
    hRet := D3D_OK;
  end;

  EmuSwapFS(); // XBox FS
  Result := hRet;
end;

// func: EmuIDirect3DDevice8_SetPixelShader

function XTL_EmuIDirect3DDevice8_SetPixelShader(Handle: DWORD; hRet: HRESULT): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetPixelShader' +
    #13#10'(' +
    #13#10'   Handle             : 0x%.08X' +
    #13#10');',
    [Handle]);

    // redirect to windows d3d
  hRet := D3D_OK;

    { TODO : Need to translated to delphi }
    // Fake Programmable Pipeline
   (* if(Handle = X_PIXELSHADER_FAKE_HANDLE) then
    begin
        // programmable pipeline
        //*
         DWORD dwHandle := 0;

        if(dwHandle = 0) then
        begin
   // simplest possible pixel shader, simply output the texture input
              Char szDiffusePixelShader[] =
    #13#10'ps.1.0'
    #13#10'tex t0'
    #13#10'mov r0, t0';

            LPD3DXBUFFER pShader := 0;
            LPD3DXBUFFER pErrors := 0;

            // assemble the shader
            D3DXAssembleShader(szDiffusePixelShader, strlen(szDiffusePixelShader) - 1, 0, 0, @pShader, @pErrors);

            // create the shader device handle
            hRet := g_pD3DDevice8.CreatePixelShader((DWORD)pShader.GetBufferPointer(), @dwHandle);

            if(FAILED(hRet)) then
                EmuWarning('Could not create pixel shader');
         end;

        if( not FAILED(hRet)) then
            hRet := g_pD3DDevice8.SetPixelShader(dwHandle);

        if(FAILED(hRet)) then
            EmuWarning('Could not set pixel shader!');
        //*/

        g_bFakePixelShaderLoaded := TRUE;
     end;
    // Fixed Pipeline, or Recompiled Programmable Pipeline
    else if(Handle = 0) then
    begin
        g_bFakePixelShaderLoaded := False;
        g_pD3DDevice8.SetPixelShader(Handle);
     end;

    if(FAILED(hRet)) then
    begin
        EmuWarning('We're lying about setting a pixel shader!');

        hRet := D3D_OK;
     end;          *)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_CreateTexture2
(*XTL.X_D3DResource * WINAPI XTL.EmuIDirect3DDevice8_CreateTexture2
(
    UINT                Width,
    UINT                Height,
    UINT                Depth,
    UINT                Levels,
    DWORD               Usage,
    D3DFORMAT           Format,
    D3DRESOURCETYPE     D3DResource
)
begin
    X_D3DTexture *pTexture;

    case(D3DResource) of
    begin
         3: //D3DRTYPE_TEXTURE
            EmuIDirect3DDevice8_CreateTexture(Width, Height, Levels, Usage, Format, D3DPOOL_MANAGED, @pTexture);
            break;
         4: //D3DRTYPE_VOLUMETEXTURE
            EmuIDirect3DDevice8_CreateVolumeTexture(Width, Height, Depth, Levels, Usage, Format, D3DPOOL_MANAGED, (X_D3DVolumeTexture)@pTexture);
            break;
         5: //D3DRTYPE_CUBETEXTURE
            CxbxKrnlCleanup('Cube textures temporarily not supported!');
            break;
        default:
            CxbxKrnlCleanup('D3DResource := %d is not supported!', D3DResource);
     end;

    Result:= pTexture;
 end;                  *)

// func: EmuIDirect3DDevice8_CreateTexture

function XTL_EmuIDirect3DDevice8_CreateTexture: HRESULT;
var
  (*PCFormat: D3DFORMAT;
  aFormat: D3DFORMAT; *)
  hRet: HRESULT;
(*(
    UINT            Width,
    UINT            Height,
    UINT            Levels,
    DWORD           Usage,
    D3DPOOL         Pool,
    X_D3DTexture  **ppTexture
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

    { TODO -oDxbx : Need to be translated to delphi }
    (*DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CreateTexture' +
           #13#10'(' +
           #13#10'   Width               : 0x%.08X' +
           #13#10'   Height              : 0x%.08X' +
           #13#10'   Levels              : 0x%.08X' +
           #13#10'   Usage               : 0x%.08X' +
           #13#10'   Format              : 0x%.08X' +
           #13#10'   Pool                : 0x%.08X' +
           #13#10'   ppTexture           : 0x%.08X' +
           #13#10');',
           Width, Height, Levels, Usage, Format, Pool, ppTexture);


    // Convert Format (Xbox->PC)
    PCFormat := XTL_EmuXB2PC_D3DFormat(aFormat);

    // TODO: HACK: Devices that don't support this should somehow emulate it!
    //* This is OK on my GeForce FX 5600
  if (PCFormat = D3DFMT_D16) then
  begin
        EmuWarning('D3DFMT_D16 is an unsupported texture format!');
    PCFormat := D3DFMT_R5G6B5;
  end
    //*
  else if (PCFormat = D3DFMT_P8) then
  begin
        EmuWarning('D3DFMT_P8 is an unsupported texture format!');
    PCFormat := D3DFMT_X8R8G8B8;
  end
    //*/
    //* This is OK on my GeForce FX 5600
  else if (PCFormat = D3DFMT_D24S8) then
  begin
        EmuWarning('D3DFMT_D24S8 is an unsupported texture format!');
    PCFormat := D3DFMT_X8R8G8B8;
  end //*/
  else if (PCFormat = D3DFMT_YUY2) then
  begin
        // cache the overlay size
    g_dwOverlayW := Width;
    g_dwOverlayH := Height;
    g_dwOverlayP := RoundUp(g_dwOverlayW, 64) * 2;
  end;



  if (PCFormat <> D3DFMT_YUY2) then
  begin
    DWORD PCUsage := Usage and (D3DUSAGE_RENDERTARGET);
//        DWORD   PCUsage = Usage & (D3DUSAGE_RENDERTARGET | D3DUSAGE_DEPTHSTENCIL);
    D3DPOOL PCPool := D3DPOOL_MANAGED;

    EmuAdjustPower2(@Width, @Height);

    * ppTexture := new X_D3DTexture();

//        if(Usage & (D3DUSAGE_RENDERTARGET | D3DUSAGE_DEPTHSTENCIL))
    if (Usage and (D3DUSAGE_RENDERTARGET)) then
      PCPool := D3DPOOL_DEFAULT;

    hRet = g_pD3DDevice8.CreateTexture
      (
      Width, Height, Levels,
      PCUsage, // TODO: Xbox Allows a border to be drawn (maybe hack this in software ;[)
      PCFormat, PCPool, and ((ppTexture).EmuTexture8)
      );

    if (FAILED(hRet)) then
    begin
      EmuWarning('CreateTexture Failed!');
      (ppTexture).Data := $BEADBEAD;
    end
    else
    begin
      D3DLOCKED_RECT LockedRect;

      (ppTexture).EmuTexture8.LockRect(0, @LockedRect, 0, 0);

      (ppTexture).Data := (DWORD)LockedRect.pBits;
      (ppTexture).Format := Format shl X_D3DFORMAT_FORMAT_SHIFT;

      g_DataToTexture.insert((ppTexture).Data, * ppTexture);

      (ppTexture).EmuTexture8.UnlockRect(0);
    end;

    DbgPrintf('EmuD3D8 : Created Texture : 0x%.08X (0x%.08X)', * ppTexture, (ppTexture).EmuTexture8);
  end
  else
  begin
    DWORD dwSize := g_dwOverlayP * g_dwOverlayH;
    DWORD dwPtr := (DWORD)CxbxMalloc(dwSize + SizeOf(DWORD));

    DWORD * pRefCount := (DWORD)(dwPtr + dwSize);

        // initialize ref count
    * pRefCount := 1;

        // If YUY2 is not supported in hardware, we'll actually mark this as a special fake texture (set highest bit)
    * ppTexture := new X_D3DTexture();

    (ppTexture).Data := X_D3DRESOURCE_DATA_FLAG_SPECIAL or X_D3DRESOURCE_DATA_FLAG_YUVSURF;
    (ppTexture).Lock := dwPtr;
    (ppTexture).Format := $24;

    (ppTexture).Size := (g_dwOverlayW and X_D3DSIZE_WIDTH_MASK);
    (ppTexture).Size := (ppTexture).Size or (g_dwOverlayH shl X_D3DSIZE_HEIGHT_SHIFT);
    (ppTexture).Size := (ppTexture).Size or (g_dwOverlayP shl X_D3DSIZE_PITCH_SHIFT);

    hRet := D3D_OK;
  end;    *)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_CreateVolumeTexture

function XTL_EmuIDirect3DDevice8_CreateVolumeTexture: HRESULT;
var
  hRet: HRESULT;
(*(
    UINT                 Width,
    UINT                 Height,
    UINT                 Depth,
    UINT                 Levels,
    DWORD                Usage,
    D3DFORMAT            Format,
    D3DPOOL              Pool,
    X_D3DVolumeTexture **ppVolumeTexture
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CreateVolumeTexture'
           #13#10'('
           #13#10'   Width               : 0x%.08X'
           #13#10'   Height              : 0x%.08X'
           #13#10'   Depth               : 0x%.08X'
           #13#10'   Levels              : 0x%.08X'
           #13#10'   Usage               : 0x%.08X'
           #13#10'   Format              : 0x%.08X'
           #13#10'   Pool                : 0x%.08X'
           #13#10'   ppVolumeTexture     : 0x%.08X'
           #13#10');',
           Width, Height, Depth, Levels, Usage, Format, Pool, ppVolumeTexture);

    // Convert Format (Xbox->PC)
    D3DFORMAT PCFormat := EmuXB2PC_D3DFormat);

    // TODO: HACK: Devices that don't support this should somehow emulate it!
    if(PCFormat = D3DFMT_D16) then
    begin
        EmuWarning('D3DFMT_16 is an unsupported texture format!');
        PCFormat := D3DFMT_X8R8G8B8;
     end;
    else if(PCFormat = D3DFMT_P8) then
    begin
        EmuWarning('D3DFMT_P8 is an unsupported texture format!');
        PCFormat := D3DFMT_X8R8G8B8;
     end;
    else if(PCFormat = D3DFMT_D24S8) then
    begin
        EmuWarning('D3DFMT_D24S8 is an unsupported texture format!');
        PCFormat := D3DFMT_X8R8G8B8;
     end;
    else if(PCFormat = D3DFMT_YUY2) then
    begin
        // cache the overlay size
        g_dwOverlayW := Width;
        g_dwOverlayH := Height;
        g_dwOverlayP := RoundUp(g_dwOverlayW, 64)*2;
     end;

    if(PCFormat <> D3DFMT_YUY2) then
    begin
        EmuAdjustPower2(@Width, @Height);

        *ppVolumeTexture := new X_D3DVolumeTexture();

        hRet = g_pD3DDevice8.CreateVolumeTexture
        (
            Width, Height, Depth, Levels,
            0,  // TODO: Xbox Allows a border to be drawn (maybe hack this in software ;[)
            PCFormat, D3DPOOL_MANAGED,  and ((ppVolumeTexture).EmuVolumeTexture8)
        );

        if(FAILED(hRet)) then
            EmuWarning('CreateVolumeTexture Failed not  (0x%.08X)', hRet);

        DbgPrintf('EmuD3D8 : Created Volume Texture : 0x%.08X (0x%.08X)', *ppVolumeTexture, (ppVolumeTexture).EmuVolumeTexture8);
     end;
    else
    begin
        DWORD dwSize := g_dwOverlayP*g_dwOverlayH;
        DWORD dwPtr := (DWORD)CxbxMalloc(dwSize + SizeOf(DWORD));

        DWORD *pRefCount := (DWORD)(dwPtr + dwSize);

        // initialize ref count
        *pRefCount := 1;

        // If YUY2 is not supported in hardware, we'll actually mark this as a special fake texture (set highest bit)
        (ppVolumeTexture).Data := X_D3DRESOURCE_DATA_FLAG_SPECIAL or X_D3DRESOURCE_DATA_FLAG_YUVSURF;
        (ppVolumeTexture).Lock := dwPtr;
        (ppVolumeTexture).Format := $24;

        (ppVolumeTexture).Size  := (g_dwOverlayW and X_D3DSIZE_WIDTH_MASK);
        (ppVolumeTexture).Size:= (ppVolumeTexture).Size or (g_dwOverlayH shl X_D3DSIZE_HEIGHT_SHIFT);
        (ppVolumeTexture).Size:= (ppVolumeTexture).Size or (g_dwOverlayP shl X_D3DSIZE_PITCH_SHIFT);

        hRet := D3D_OK;
     end;      *)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_CreateCubeTexture

function XTL_EmuIDirect3DDevice8_CreateCubeTexture: HRESULT;
var
  hRet: HRESULT;
(*(
    UINT                 EdgeLength,
    UINT                 Levels,
    DWORD                Usage,
    D3DFORMAT            Format,
    D3DPOOL              Pool,
    X_D3DCubeTexture  **ppCubeTexture
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CreateCubeTexture'
           #13#10'('
           #13#10'   EdgeLength          : 0x%.08X'
           #13#10'   Levels              : 0x%.08X'
           #13#10'   Usage               : 0x%.08X'
           #13#10'   Format              : 0x%.08X'
           #13#10'   Pool                : 0x%.08X'
           #13#10'   ppCubeTexture       : 0x%.08X'
           #13#10');',
           EdgeLength, Levels, Usage, Format, Pool, ppCubeTexture);

    // Convert Format (Xbox->PC)
    D3DFORMAT PCFormat := EmuXB2PC_D3DFormat);

    // TODO: HACK: Devices that don't support this should somehow emulate it!
    if(PCFormat = D3DFMT_D16) then
    begin
        EmuWarning('D3DFMT_16 is an unsupported texture format!');
        PCFormat := D3DFMT_X8R8G8B8;
     end;
    else if(PCFormat = D3DFMT_P8) then
    begin
        EmuWarning('D3DFMT_P8 is an unsupported texture format!');
        PCFormat := D3DFMT_X8R8G8B8;
     end;
    else if(PCFormat = D3DFMT_D24S8) then
    begin
        EmuWarning('D3DFMT_D24S8 is an unsupported texture format!');
        PCFormat := D3DFMT_X8R8G8B8;
     end;
    else if(PCFormat = D3DFMT_YUY2) then
    begin
        CxbxKrnlCleanup('YUV not supported for cube textures');
     end;

    *ppCubeTexture := new X_D3DCubeTexture();

    HRESULT hRet = g_pD3DDevice8.CreateCubeTexture
    (
        EdgeLength, Levels,
        0,  // TODO: Xbox Allows a border to be drawn (maybe hack this in software ;[)
        PCFormat, D3DPOOL_MANAGED,  and ((ppCubeTexture).EmuCubeTexture8)
    );

    DbgPrintf('EmuD3D8 : Created Cube Texture : 0x%.08X (0x%.08X)', *ppCubeTexture, (ppCubeTexture).EmuCubeTexture8);

    if(FAILED(hRet)) then
        EmuWarning('CreateCubeTexture Failed!');
*)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_CreateIndexBuffer

function XTL_EmuIDirect3DDevice8_CreateIndexBuffer: HRESULT;
var
  hRet: HRESULT;
(*(
    UINT                 Length,
    DWORD                Usage,
    D3DFORMAT            Format,
    D3DPOOL              Pool,
    X_D3DIndexBuffer   **ppIndexBuffer
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CreateIndexBuffer'
           #13#10'('
           #13#10'   Length              : 0x%.08X'
           #13#10'   Usage               : 0x%.08X'
           #13#10'   Format              : 0x%.08X'
           #13#10'   Pool                : 0x%.08X'
           #13#10'   ppIndexBuffer       : 0x%.08X'
           #13#10');',
           Length, Usage, Format, Pool, ppIndexBuffer);

    *ppIndexBuffer := new X_D3DIndexBuffer();

    hRet = g_pD3DDevice8.CreateIndexBuffer
    (
        Length, 0, D3DFMT_INDEX16, D3DPOOL_MANAGED,  and ((ppIndexBuffer).EmuIndexBuffer8)
    );

    DbgPrintf('EmuD3D8 : EmuIndexBuffer8 := 0x%.08X', (ppIndexBuffer).EmuIndexBuffer8);

    if(FAILED(hRet)) then
        EmuWarning('CreateIndexBuffer Failed not  (0x%.08X)', hRet);

    //
    // update data ptr
    //

    begin
        BYTE *pData := 0;

        (ppIndexBuffer).EmuIndexBuffer8.Lock(0, Length, @pData, 0);

        (ppIndexBuffer).Data := (DWORD)pData;
     end;
*)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_CreateIndexBuffer2
(*XTL.X_D3DIndexBuffer * WINAPI XTL.EmuIDirect3DDevice8_CreateIndexBuffer2(UINT Length)
begin
    X_D3DIndexBuffer *pIndexBuffer := 0;

    EmuIDirect3DDevice8_CreateIndexBuffer
    (
        Length,
        0,
        D3DFMT_INDEX16,
        D3DPOOL_MANAGED,
        @pIndexBuffer
    );

    Result:= pIndexBuffer;
 end; *)

// func: EmuIDirect3DDevice8_SetIndices

function XTL_EmuIDirect3DDevice8_SetIndices: HRESULT;
var
  hRet: HRESULT;
(*(
    X_D3DIndexBuffer   *pIndexData,
    UINT                BaseVertexIndex
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetIndices'
           #13#10'('
           #13#10'   pIndexData          : 0x%.08X'
           #13#10'   BaseVertexIndex     : 0x%.08X'
           #13#10');',
           pIndexData, BaseVertexIndex);

    (*
    fflush(stdout);
    if(pIndexData <> 0) then
    begin
         integer chk := 0;
        if(chk++ = 0) then
        begin
            asm integer 3
         end;
     end;
    //*/

    HRESULT hRet := D3D_OK;

    if(pIndexData <> 0) then
    begin
        g_pIndexBuffer := pIndexData;
        g_dwBaseVertexIndex := BaseVertexIndex;

        // HACK: Halo Hack
        if(pIndexData.Lock = $00840863) then
            pIndexData.Lock := 0;

        EmuVerifyResourceIsRegistered(pIndexData);

        IDirect3DIndexBuffer8 *pIndexBuffer := pIndexData.EmuIndexBuffer8;

        if(pIndexData.Lock <> X_D3DRESOURCE_LOCK_FLAG_NOSIZE) then
            hRet := g_pD3DDevice8.SetIndices(pIndexBuffer, BaseVertexIndex);
     end;
    else
    begin
        g_pIndexBuffer := 0;

        hRet := g_pD3DDevice8.SetIndices(0, BaseVertexIndex);
     end;          *)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_SetTexture

function XTL_EmuIDirect3DDevice8_SetTexture: HRESULT;
var
  hRet: HRESULT;
(*(
    DWORD           Stage,
    X_D3DResource  *pTexture
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetTexture'
           #13#10'('
           #13#10'   Stage               : 0x%.08X'
           #13#10'   pTexture            : 0x%.08X'
           #13#10');',
           Stage, pTexture);

    IDirect3DBaseTexture8 *pBaseTexture8 := 0;

    EmuD3DActiveTexture[Stage] := pTexture;

    if(pTexture <> 0) then
    begin
        EmuVerifyResourceIsRegistered(pTexture);

        if(IsSpecialResource(pTexture.Data) and (pTexture.Data and X_D3DRESOURCE_DATA_FLAG_YUVSURF)) then
        begin
            //
            // NOTE: TODO: This is almost a hack! :)
            //

            EmuSwapFS();
            EmuIDirect3DDevice8_EnableOverlay(TRUE);
            EmuIDirect3DDevice8_UpdateOverlay((X_D3DSurface)pTexture, 0, 0, False, 0);
            EmuSwapFS();
         end;
        else
        begin
            pBaseTexture8 := pTexture.EmuBaseTexture8;

            #ifdef _DEBUG_DUMP_TEXTURE_SETTEXTURE
            if(pTexture <> 0 and (pTexture.EmuTexture8 <> 0)) then
            begin
                 integer dwDumpTexture := 0;

                 szBuffer: array[0..256-1] of Char;

                case(pTexture.EmuResource8.GetType()) of
                begin
                     D3DRTYPE_TEXTURE:
                    begin
                        StrFmt(szBuffer, _DEBUG_DUMP_TEXTURE_SETTEXTURE 'SetTextureNorm - %.03d (0x%.08X).bmp', dwDumpTexture++, pTexture.EmuTexture8);

                        pTexture.EmuTexture8.UnlockRect(0);

                        D3DXSaveTextureToFile(szBuffer, D3DXIFF_BMP, pTexture.EmuTexture8, 0);
                     end;
                    break;

                     D3DRTYPE_CUBETEXTURE:
                    begin
                        for(integer face:=0;face<6;face++)
                        begin
                            StrFmt(szBuffer, _DEBUG_DUMP_TEXTURE_SETTEXTURE 'SetTextureCube%d - %.03d (0x%.08X).bmp', face, dwDumpTexture++, pTexture.EmuTexture8);

                            pTexture.EmuCubeTexture8.UnlockRect((D3DCUBEMAP_FACES)face, 0);

                            D3DXSaveTextureToFile(szBuffer, D3DXIFF_BMP, pTexture.EmuTexture8, 0);
                         end;
                     end;
                    break;
                 end;
             end;
            //endif
         end;
     end;

    (*
     IDirect3DTexture8 *pDummyTexture[4] := (0, 0, 0, 0);

    if(pDummyTexture[Stage] = 0) then
    begin
        if(Stage = 0) then
        begin
            if(D3DXCreateTextureFromFile(g_pD3DDevice8, 'C:\dummy1.bmp', @pDummyTexture[Stage]) <> D3D_OK) then
                CxbxKrnlCleanup('Could not create dummy texture!');
         end;
        else if(Stage = 1) then
        begin
            if(D3DXCreateTextureFromFile(g_pD3DDevice8, 'C:\dummy2.bmp', @pDummyTexture[Stage]) <> D3D_OK) then
                CxbxKrnlCleanup('Could not create dummy texture!');
         end;
     end;
    //*/

    (*
     integer dwDumpTexture := 0;
     szBuffer: array[0..256-1] of Char;
    StrFmt(szBuffer, 'C:\Aaron\Textures\DummyTexture - %.03d (0x%.08X).bmp', dwDumpTexture++, pDummyTexture);
    pDummyTexture.UnlockRect(0);
    D3DXSaveTextureToFile(szBuffer, D3DXIFF_BMP, pDummyTexture, 0);
    //*/

    //HRESULT hRet = g_pD3DDevice8->SetTexture(Stage, pDummyTexture[Stage]);
    HRESULT hRet := g_pD3DDevice8.SetTexture(Stage, (g_iWireframe = 0) ? pBaseTexture8 : 0);
                    *)
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DDevice8_SwitchTexture
(*VOID __fastcall XTL.EmuIDirect3DDevice8_SwitchTexture
(
    DWORD           Method,
    DWORD           Data,
    DWORD           Format
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SwitchTexture'
           #13#10'('
           #13#10'   Method              : 0x%.08X'
           #13#10'   Data                : 0x%.08X'
           #13#10'   Format              : 0x%.08X'
           #13#10');',
           Method, Data, Format);

    DWORD StageLookup[] := ( $00081b00, $00081b40, $00081b80, $00081bc0 );
    DWORD Stage := -1;

    for(integer v:=0;v<4;v++)
    begin
        if(StageLookup[v] = Method) then
        begin
            Stage := v;
         end;
     end;

    if(Stage = -1) then
    begin
        EmuWarning('Unknown Method (0x%.08X)', Method);
     end;
    else
    begin
        //
        // WARNING: TODO: Correct reference counting has not been completely verified for this code
        //

        X_D3DTexture *pTexture := (X_D3DTexture )g_DataToTexture.get(Data);

        EmuWarning('Switching Texture 0x%.08X (0x%.08X) @ Stage %d', pTexture, pTexture.EmuBaseTexture8, Stage);

        HRESULT hRet := g_pD3DDevice8.SetTexture(Stage, pTexture.EmuBaseTexture8);

        (*
        if(pTexture.EmuBaseTexture8 <> 0) then
        begin
             integer dwDumpTexture := 0;

             szBuffer: array[0..255-1] of Char;

            StrFmt(szBuffer, 'C:\Aaron\Textures\0x%.08X-SwitchTexture%.03d.bmp', pTexture, dwDumpTexture++);

            pTexture.EmuTexture8.UnlockRect(0);

            D3DXSaveTextureToFile(szBuffer, D3DXIFF_BMP, pTexture.EmuBaseTexture8, 0);
         end;
        //*/
     end;

    EmuSwapFS();   // XBox FS

    Exit;
 end; *)

// func: EmuIDirect3DDevice8_GetDisplayMode

function XTL_EmuIDirect3DDevice8_GetDisplayMode(pMode: X_D3DDISPLAYMODE): HRESULT;
var
  hRet: HRESULT;
  pPCMode: D3DDISPLAYMODE;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetDisplayMode' +
    #13#10'(' +
    #13#10'   pMode               : 0x%.08X' +
    #13#10');',
    [@pMode]);


    // make adjustments to parameters to make sense with windows d3d
  begin
    { TODO : Need to be translated to delphi }
    (*pPCMode := D3DDISPLAYMODE(pMode); *)

    hRet := g_pD3DDevice8.GetDisplayMode(pPCMode);

        // Convert Format (PC->Xbox)
        { TODO : Need to be translated to delphi }
        (*
        pMode.Format := EmuPC2XB_D3DpPCMode.Format); *)

        // TODO: Make this configurable in the future?
    pMode.Flags := $000000A1; // D3DPRESENTFLAG_FIELD | D3DPRESENTFLAG_INTERLACED | D3DPRESENTFLAG_LOCKABLE_BACKBUFFER

    // TODO: Retrieve from current CreateDevice settings?
    pMode.Width := 640;
    pMode.Height := 457; // Battlestar Galactica PAL Version
  end;

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_Begin

function XTL_EmuIDirect3DDevice8_Begin(PrimitiveType: X_D3DPRIMITIVETYPE): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_Begin' +
    #13#10'(' +
    #13#10'   PrimitiveType       : 0x%.08X' +
    #13#10');',
    [@PrimitiveType]);

{ TODO : Need to be translated to delphi }
(*    if((PrimitiveType <> X_D3DPT_TRIANGLEFAN) and (PrimitiveType <> X_D3DPT_QUADSTRIP) and (PrimitiveType <> X_D3DPT_QUADLIST)) then
        CxbxKrnlCleanup('EmuIDirect3DDevice8_Begin does not support primitive : %d', PrimitiveType);

    g_IVBPrimitiveType := PrimitiveType;

    if(g_IVBTable = 0) then
    begin
        g_IVBTable := (struct XTL::_D3DIVB)CxbxMalloc(SizeOf(XTL::_D3DIVB)*1024);
     end;

    g_IVBTblOffs := 0;
    g_IVBFVF := 0;

    // default values
    ZeroMemory(g_IVBTable, SizeOf(XTL::_D3DIVB)*1024);

    if(g_pIVBVertexBuffer = 0) then
    begin
        g_pIVBVertexBuffer := (DWORD)CxbxMalloc(SizeOf(XTL::_D3DIVB)*1024);
     end;
*)
  EmuSwapFS(); // XBox FS

  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_SetVertexData2f

function XTL_EmuIDirect3DDevice8_SetVertexData2f(aRegister: integer; a: FLOAT; b: FLOAT): HRESULT;
begin
  // debug trace
{$IFDEF _DEBUG_TRACE}
  begin
    EmuSwapFS(); // Win2k/XP FS
    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexData2f  shr ' +
      #13#10'(' +
      #13#10'   Register            : 0x%.08X' +
      #13#10'   a                   : %f' +
      #13#10'   b                   : %f' +
      #13#10');',
      [aRegister, a, b]);
    EmuSwapFS(); // XBox FS
  end;
{$ENDIF}
  Result := XTL_EmuIDirect3DDevice8_SetVertexData4f(aRegister, a, b, 0.0, 1.0);
end;


function FtoDW(f: FLOAT): DWORD;
begin
  Result := Round(f);
end;

function DWtoF(f: DWORD): FLOAT;
begin
  Result := f;
end;


// func: EmuIDirect3DDevice8_SetVertexData2s

function XTL_EmuIDirect3DDevice8_SetVertexData2s(aRegister: integer; a: SmallInt; b: SmallInt): HRESULT;
var
  DwA, dwB: DWORD;
begin
    // debug trace
{$IFDEF _DEBUG_TRACE}
  begin
    EmuSwapFS(); // Win2k/XP FS
    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexData2s  shr ' +
      #13#10'(' +
      #13#10'   Register            : 0x%.08X' +
      #13#10'   a                   : %d' +
      #13#10'   b                   : %d' +
      #13#10');',
      [aRegister, a, b]);
    EmuSwapFS(); // XBox FS
  end;
{$ENDIF}

  dwA := a;
  dwB := b;

  Result := XTL_EmuIDirect3DDevice8_SetVertexData4f(aRegister, DWtoF(dwA), DWtoF(dwB), 0.0, 1.0);
end;

// func: EmuIDirect3DDevice8_SetVertexData4f

function XTL_EmuIDirect3DDevice8_SetVertexData4f(aRegister: integer; a: FLOAT; b: FLOAT; c: FLOAT; d: FLOAT): HRESULT;
var
  hRet: HRESULT;
(*  o: integer;*)
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexData4f' +
    #13#10'(' +
    #13#10'   Register            : 0x%.08X' +
    #13#10'   a                   : %f' +
    #13#10'   b                   : %f' +
    #13#10'   c                   : %f' +
    #13#10'   d                   : %f' +
    #13#10');',
    [aRegister, a, b, c, d]);

  hRet := S_OK;

  case (aRegister) of
    0: // D3DVSDE_POSITION
      begin
        (*o := g_IVBTblOffs;
        g_IVBTable[o].Position.x := a; //vertices[o*2+0];//a;
        g_IVBTable[o].Position.y := b; //vertices[o*2+1];//b;
        g_IVBTable[o].Position.z := c;
        g_IVBTable[o].Rhw := 1.0;

        g_IVBTblOffs := g_IVBTblOffs + 1;

        g_IVBFVF := g_IVBFVF or D3DFVF_XYZRHW; *)
      end;

    3: // D3DVSDE_DIFFUSE
      begin
        (*o := g_IVBTblOffs;
        DWORD ca := FtoDW(d) shl 24;
        DWORD cr := FtoDW(a) shl 16;
        DWORD cg := FtoDW(b) shl 8;
        DWORD cb := FtoDW(c) shl 0;

        g_IVBTable[o].dwDiffuse := ca or cr or cg or cb;

        g_IVBFVF := g_IVBFVF or D3DFVF_DIFFUSE; *)
      end;

    4: // D3DVSDE_SPECULAR
      begin
        (*o := g_IVBTblOffs;
        DWORD ca := FtoDW(d) shl 24;
        DWORD cr := FtoDW(a) shl 16;
        DWORD cg := FtoDW(b) shl 8;
        DWORD cb := FtoDW(c) shl 0;

        g_IVBTable[o].dwSpecular := ca or cr or cg or cb;

        g_IVBFVF := g_IVBFVF or D3DFVF_SPECULAR; *)
      end;

    9: // D3DVSDE_TEXCOORD0
      begin
        (*integer o := g_IVBTblOffs;
            {
            if(a > 640) then  a := 640;
            if(b > 480) then  b := 480;

            if(a > 1.0f) then  a:= a div 640.0f;
            if(b > 1.0f) then  b:= b div 480.0f;
            }
        g_IVBTable[o].TexCoord1.x := a;
        g_IVBTable[o].TexCoord1.y := b;

        if ((g_IVBFVF and D3DFVF_TEXCOUNT_MASK) < D3DFVF_TEX1) then
        begin
          g_IVBFVF := g_IVBFVF or D3DFVF_TEX1;
        end; *)
      end;

    10: // D3DVSDE_TEXCOORD1
      begin
        (*
        integer o := g_IVBTblOffs;
            {
            if(a > 640) then  a := 640;
            if(b > 480) then  b := 480;

            if(a > 1.0f) then  a:= a div 640.0f;
            if(b > 1.0f) then  b:= b div 480.0f;
            }
        g_IVBTable[o].TexCoord2.x := a;
        g_IVBTable[o].TexCoord2.y := b;

        if ((g_IVBFVF and D3DFVF_TEXCOUNT_MASK) < D3DFVF_TEX2) then
        begin
          g_IVBFVF := g_IVBFVF or D3DFVF_TEX2;
        end;  *)
      end;

    11: // D3DVSDE_TEXCOORD2
      begin
        (*
        integer o := g_IVBTblOffs;
            {
            if(a > 640) then  a := 640;
            if(b > 480) then  b := 480;

            if(a > 1.0f) then  a:= a div 640.0f;
            if(b > 1.0f) then  b:= b div 480.0f;
            }
        g_IVBTable[o].TexCoord3.x := a;
        g_IVBTable[o].TexCoord3.y := b;

        if ((g_IVBFVF and D3DFVF_TEXCOUNT_MASK) < D3DFVF_TEX3) then
        begin
          g_IVBFVF := g_IVBFVF or D3DFVF_TEX3;
        end;   *)
      end;

    12: // D3DVSDE_TEXCOORD3
      begin
        (*
        integer o := g_IVBTblOffs;
            {
            if(a > 640) then  a := 640;
            if(b > 480) then  b := 480;

            if(a > 1.0f) then  a:= a div 640.0f;
            if(b > 1.0f) then  b:= b div 480.0f;
            }
        g_IVBTable[o].TexCoord4.x := a;
        g_IVBTable[o].TexCoord4.y := b;

        if ((g_IVBFVF and D3DFVF_TEXCOUNT_MASK) < D3DFVF_TEX4) then
        begin
          g_IVBFVF := g_IVBFVF or D3DFVF_TEX4;
        end;   *)
      end;

    (* $FFFFFFFF:
      begin
        integer o := g_IVBTblOffs;

            {
            a := (a*320.0f) + 320.0f;
            b := (b*240.0f) + 240.0f;
            }

        g_IVBTable[o].Position.x := a; //vertices[o*2+0];//a;
        g_IVBTable[o].Position.y := b; //vertices[o*2+1];//b;
        g_IVBTable[o].Position.z := c;
        g_IVBTable[o].Rhw := 1.0 f;

        g_IVBTblOffs := g_IVBTblOffs + 1;

        g_IVBFVF := g_IVBFVF or D3DFVF_XYZRHW;
      end; *)

  else
    CxbxKrnlCleanup(Format('Unknown IVB Register : %d', [aRegister]));
  end;

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_SetVertexDataColor

function XTL_EmuIDirect3DDevice8_SetVertexDataColor(aRegister: integer; Color: D3DCOLOR): HRESULT;
begin
    // debug trace
  Result := 0;
{$IFDEF _DEBUG_TRACE}

  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexDataColor  shr ' +
    #13#10'(' +
    #13#10'   Register            : 0x%.08X' +
    #13#10'   Color               : 0x%.08X' +
    #13#10');',
    [aRegister, Color]);
  EmuSwapFS(); // XBox FS
{$ENDIF}

    { TODO : need to be translated to delphi }
    (*
    FLOAT a := DWtoF((Color and $FF000000) shr 24);
    FLOAT r := DWtoF((Color and $00FF0000) shr 16);
    FLOAT g := DWtoF((Color and $0000FF00) shr 8);
    FLOAT b := DWtoF((Color and $000000FF) shr 0);

    Result:= EmuIDirect3DDevice8_SetVertexData4f(Register, r, g, b, a); *)
end;

// func: EmuIDirect3DDevice8_End

function XTL_EmuIDirect3DDevice8_End: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_End();');

    { TODO -oDxbx : Need to be translated to delphi }
    (*if(g_IVBTblOffs <> 0) then
        EmuFlushIVB();
    *)

    // TODO: Should technically clean this up at some point..but on XP doesnt matter much
//    CxbxFree(g_pIVBVertexBuffer);
//    CxbxFree(g_IVBTable);

  EmuSwapFS(); // XBox FS

  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_RunPushBuffer
{ TODO : Need to be translated to delphi }

procedure XTL_EmuIDirect3DDevice8_RunPushBuffer;
(*(
    X_D3DPushBuffer       *pPushBuffer,
    X_D3DFixup            *pFixup
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_RunPushBuffer'
           #13#10'('
           #13#10'   pPushBuffer         : 0x%.08X'
           #13#10'   pFixup              : 0x%.08X'
           #13#10');',
           pPushBuffer, pFixup);

    XTL.EmuExecutePushBuffer(pPushBuffer, pFixup);

    EmuSwapFS();   // XBox FS

    Exit; *)
end;

// func: EmuIDirect3DDevice8_Clear

function XTL_EmuIDirect3DDevice8_Clear: HRESULT;
var
  ret: HRESULT;
(*(
    DWORD           Count,
    CONST D3DRECT  *pRects,
    DWORD           Flags,
    D3DCOLOR        Color,
    Single           Z,
    DWORD           Stencil
) *)
begin
  ret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_Clear'
           #13#10'('
           #13#10'   Count               : 0x%.08X'
           #13#10'   pRects              : 0x%.08X'
           #13#10'   Flags               : 0x%.08X'
           #13#10'   Color               : 0x%.08X'
           #13#10'   Z                   : %f'
           #13#10'   Stencil             : 0x%.08X'
           #13#10');',
           Count, pRects, Flags,
           Color, Z, Stencil);

    // make adjustments to parameters to make sense with windows d3d
    begin
        // TODO: D3DCLEAR_TARGET_A, *R, *G, *B don't exist on windows
        DWORD newFlags := 0;

        if(Flags and $000000f0) then
            newFlags:= newFlags or D3DCLEAR_TARGET;

        if(Flags and $00000001) then
            newFlags:= newFlags or D3DCLEAR_ZBUFFER;

        if(Flags and $00000002) then
            newFlags:= newFlags or D3DCLEAR_STENCIL;

        if(Flags and ~($000000f0 or $00000001 or $00000002)) then
            EmuWarning('Unsupported Flag(s) for IDirect3DDevice8_Clear : 0x%.08X', Flags and ~($000000f0 or $00000001 or $00000002));

        Flags := newFlags;
     end;

    HRESULT ret := g_pD3DDevice8.Clear(Count, pRects, Flags, Color, Z, Stencil);
*)
  EmuSwapFS(); // XBox FS

  Result := ret;
end;

// func: EmuIDirect3DDevice8_Present

function XTL_EmuIDirect3DDevice8_Present: HRESULT;
var
  hRet: HRESULT;
(*(
    CONST TRect* pSourceRect,
    CONST TRect* pDestRect,
    PVOID       pDummy1,
    PVOID       pDummy2
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_Present'
           #13#10'('
           #13#10'   pSourceRect         : 0x%.08X'
           #13#10'   pDestRect           : 0x%.08X'
           #13#10'   pDummy1             : 0x%.08X'
           #13#10'   pDummy2             : 0x%.08X'
           #13#10');',
           pSourceRect, pDestRect, pDummy1, pDummy2);

    // release back buffer lock
    begin
        IDirect3DSurface8 *pBackBuffer;

        g_pD3DDevice8.GetBackBuffer(0, D3DBACKBUFFER_TYPE_MONO, @pBackBuffer);

        pBackBuffer.UnlockRect();
     end;

    HRESULT hRet := g_pD3DDevice8.Present(pSourceRect, pDestRect, (HWND)pDummy1, (CONST RGNDATA)pDummy2);

    // not really accurate because you definately dont always present on every vblank
    g_VBData.Swap := g_VBData.VBlank;

    if(g_VBData.VBlank = g_VBLastSwap + 1) then
        g_VBData.Flags := 1; // D3DVBLANK_SWAPDONE
    else
        g_VBData.Flags := 2; // D3DVBLANK_SWAPMISSED
*)
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_Swap

function XTL_EmuIDirect3DDevice8_Swap(Flags: DWORD): HRESULT;
var
  hRet: HRESULT;
  pBackBuffer: IDirect3DSurface8;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_Swap' +
    #13#10'(' +
    #13#10'   Flags               : 0x%.08X' +
    #13#10');',
    [Flags]);

  // TODO: Ensure this flag is always the same across library versions
  if (Flags <> 0) then
    EmuWarning('XTL.EmuIDirect3DDevice8_Swap: Flags <> 0');

  // release back buffer lock
  begin
    g_pD3DDevice8.GetBackBuffer(0, D3DBACKBUFFER_TYPE_MONO, pBackBuffer);

    pBackBuffer.UnlockRect();
  end;

  hRet := g_pD3DDevice8.Present(nil, nil, 0, nil);
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DResource8_Register

function XTL_EmuIDirect3DResource8_Register(pThis: X_D3DResource; pBase: PVOID): HRESULT;
var
  hRet: HRESULT;
(*  pResource: X_D3DResource;
  dwCommonType: DWORD; *)
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DResource8_Register' +
    #13#10'(' +
    #13#10'   pThis               : 0x%.08X (.Data : 0x%.08X)' +
    #13#10'   pBase               : 0x%.08X' +
    #13#10');',
    [pThis, pThis.Data, pBase]);

  hRet := S_OK;

(*  pResource := pThis;

    { TODO : Need to be translated to delphi }
    (*dwCommonType := pResource.Common and X_D3DCOMMON_TYPE_MASK;

    // add the offset of the current texture to the base
    pBase := (PVOID)((DWORD)pBase+pThis.Data);        *)

    // Determine the resource type, and initialize
    (*case(dwCommonType) of
         X_D3DCOMMON_TYPE_VERTEXBUFFER:
        begin
            DbgPrintf('EmuIDirect3DResource8_Register (0x%X) : Creating VertexBufferArgs: array of const');

            X_D3DVertexBuffer *pVertexBuffer := (X_D3DVertexBuffer)pResource;

            // create vertex buffer
            begin
                DWORD dwSize := EmuCheckAllocationSize(pBase, true);

                if(dwSize = -1) then
                begin
                    // TODO: once this is known to be working, remove the warning
                    EmuWarning('Vertex buffer allocation size unknown');
                    dwSize := $2000;  // temporarily assign a small buffer, which will be increased later
                 end;

                hRet = g_pD3DDevice8.CreateVertexBuffer
                (
                    dwSize, 0, 0, D3DPOOL_MANAGED,
                    @pResource.EmuVertexBuffer8
                );

                #ifdef _DEBUG_TRACK_VB
                g_VBTrackTotal.insert(pResource.EmuVertexBuffer8);
                //endif

                BYTE *pData := 0;

                hRet := pResource.EmuVertexBuffer8.Lock(0, 0, @pData, 0);

                if(FAILED(hRet)) then
                    CxbxKrnlCleanup('VertexBuffer Lock Failed!');

                memcpy(pData, pBase, dwSize);

                pResource.EmuVertexBuffer8.Unlock();

                pResource.Data := (ULONG)pData;
             end;

            DbgPrintf('EmuIDirect3DResource8_Register (0x%X) : Successfully Created VertexBuffer (0x%.08X)', pResource.EmuVertexBuffer8);
         end;
        break;

         X_D3DCOMMON_TYPE_INDEXBUFFER:
        begin
            DbgPrintf('EmuIDirect3DResource8_Register :. IndexBufferArgs: array of const');

            X_D3DIndexBuffer *pIndexBuffer := (X_D3DIndexBuffer)pResource;

            // create index buffer
            begin
                DWORD dwSize := EmuCheckAllocationSize(pBase, true);

                if(dwSize = -1) then
                begin
                    // TODO: once this is known to be working, remove the warning
                    EmuWarning('Index buffer allocation size unknown');

                    pIndexBuffer.Lock := X_D3DRESOURCE_LOCK_FLAG_NOSIZE;

                    break;
                    // Halo dwSize = 0x336;
                 end;

                HRESULT hRet = g_pD3DDevice8.CreateIndexBuffer
                (
                    dwSize, 0, D3DFMT_INDEX16, D3DPOOL_MANAGED,
                    @pIndexBuffer.EmuIndexBuffer8
                );

                if(FAILED(hRet)) then
                    CxbxKrnlCleanup('CreateIndexBuffer Failed!');

                BYTE *pData := 0;

                hRet := pResource.EmuIndexBuffer8.Lock(0, dwSize, @pData, 0);

                if(FAILED(hRet)) then
                    CxbxKrnlCleanup('IndexBuffer Lock Failed!');

                memcpy(pData, pBase, dwSize);

                pResource.EmuIndexBuffer8.Unlock();

                pResource.Data := (ULONG)pData;
             end;

            DbgPrintf('EmuIDirect3DResource8_Register (0x%X) : Successfully Created IndexBuffer (0x%.08X)', pResource.EmuIndexBuffer8);
         end;
        break;

         X_D3DCOMMON_TYPE_PUSHBUFFER:
        begin
            DbgPrintf('EmuIDirect3DResource8_Register :. PushBufferArgs: array of const');

            X_D3DPushBuffer *pPushBuffer := (X_D3DPushBuffer)pResource;

            // create push buffer
            begin
                DWORD dwSize := EmuCheckAllocationSize(pBase, true);

                if(dwSize = -1) then
                begin
                    // TODO: once this is known to be working, remove the warning
                    EmuWarning('Push buffer allocation size unknown');

                    pPushBuffer.Lock := X_D3DRESOURCE_LOCK_FLAG_NOSIZE;

                    break;
                 end;

                pResource.Data := (ULONG)pBase;
             end;

            DbgPrintf('EmuIDirect3DResource8_Register (0x%X) : Successfully Created PushBuffer (0x%.08X, 0x%.08X, 0x%.08X)', pResource.Data, pPushBuffer.Size, pPushBuffer.AllocationSize);
         end;
        break;

         X_D3DCOMMON_TYPE_SURFACE:
         X_D3DCOMMON_TYPE_TEXTURE:
        begin
            if(dwCommonType = X_D3DCOMMON_TYPE_SURFACE) then
                DbgPrintf('EmuIDirect3DResource8_Register :. SurfaceArgs: array of const');
            else
                DbgPrintf('EmuIDirect3DResource8_Register :. TextureArgs: array of const');

            X_D3DPixelContainer *pPixelContainer := (X_D3DPixelContainer)pResource;

            X_D3DFORMAT X_Format := (X_D3DFORMAT)((pPixelContainer.Format and X_D3DFORMAT_FORMAT_MASK) shr X_D3DFORMAT_FORMAT_SHIFT);
            D3DFORMAT   Format   := EmuXB2PC_D3DX_Format);
   D3DFORMAT	CacheFormat;
            // TODO: check for dimensions

            // TODO: HACK: Temporary?
            if(X_Format = $2E) then
            begin
                CxbxKrnlCleanup('D3DFMT_LIN_D24S8 not yet supported!');
                X_Format := $12;
                Format   := D3DFMT_A8R8G8B8;
             end;

            DWORD dwWidth, dwHeight, dwBPP, dwDepth := 1, dwPitch = 0, dwMipMapLevels = 1;
            BOOL  bSwizzled := False, bCompressed = False, dwCompressedSize = 0;
            BOOL  bCubemap := pPixelContainer.Format and X_D3DFORMAT_CUBEMAP;

            // Interpret Width/Height/BPP
            if(X_Format = $07 (* X_D3DFMT_X8R8G8B8 *)(*|| X_Format == 0x06 /* X_D3DFMT_A8R8G8B8 */) then
            begin
                bSwizzled := TRUE;

                // Swizzled 32 Bit
                dwWidth  := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_USIZE_MASK) shr X_D3DFORMAT_USIZE_SHIFT);
                dwHeight := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_VSIZE_MASK) shr X_D3DFORMAT_VSIZE_SHIFT);
                dwMipMapLevels := (pPixelContainer.Format and X_D3DFORMAT_MIPMAP_MASK) shr X_D3DFORMAT_MIPMAP_SHIFT;
                dwDepth  := 1;// HACK? 1 << ((pPixelContainer->Format & X_D3DFORMAT_PSIZE_MASK) >> X_D3DFORMAT_PSIZE_SHIFT);
                dwPitch  := dwWidth*4;
                dwBPP := 4;
             end;
            else if(X_Format = $05 (* X_D3DFMT_R5G6B5 *)(*then  || X_Format == 0x04 /* X_D3DFMT_A4R4G4B4 */
                 or X_Format = $1D (* X_D3DFMT_LIN_A4R4G4B4 *)(*|| X_Format == 0x02 /* X_D3DFMT_A1R5G5B5 */
                 or X_Format = $28 (* X_D3DFMT_G8B8 *)//)
            (*begin
                bSwizzled := TRUE;

                // Swizzled 16 Bit
                dwWidth  := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_USIZE_MASK) shr X_D3DFORMAT_USIZE_SHIFT);
                dwHeight := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_VSIZE_MASK) shr X_D3DFORMAT_VSIZE_SHIFT);
                dwMipMapLevels := (pPixelContainer.Format and X_D3DFORMAT_MIPMAP_MASK) shr X_D3DFORMAT_MIPMAP_SHIFT;
                dwDepth  := 1;// HACK? 1 << ((pPixelContainer->Format & X_D3DFORMAT_PSIZE_MASK) >> X_D3DFORMAT_PSIZE_SHIFT);
                dwPitch  := dwWidth*2;
                dwBPP := 2;
             end;
            else if(X_Format = $00 (* X_D3DFMT_L8 *)(*|| X_Format == 0x0B /* X_D3DFMT_P8 */ || X_Format == 0x01 /* X_D3DFMT_AL8 */ || X_Format == 0x1A /* X_D3DFMT_A8L8 */) then
            begin
                bSwizzled := TRUE;

                // Swizzled 8 Bit
                dwWidth  := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_USIZE_MASK) shr X_D3DFORMAT_USIZE_SHIFT);
                dwHeight := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_VSIZE_MASK) shr X_D3DFORMAT_VSIZE_SHIFT);
                dwMipMapLevels := (pPixelContainer.Format and X_D3DFORMAT_MIPMAP_MASK) shr X_D3DFORMAT_MIPMAP_SHIFT;
                dwDepth  := 1;// HACK? 1 << ((pPixelContainer->Format & X_D3DFORMAT_PSIZE_MASK) >> X_D3DFORMAT_PSIZE_SHIFT);
                dwPitch  := dwWidth;
                dwBPP := 1;
             end;
            else if(X_Format = $1E (* X_D3DFMT_LIN_X8R8G8B8 *)(*|| X_Format == 0x12 /* X_D3DFORMAT_A8R8G8B8 */ || X_Format == 0x2E /* D3DFMT_LIN_D24S8 */) then
            begin
                // Linear 32 Bit
                dwWidth  := (pPixelContainer.Size and X_D3DSIZE_WIDTH_MASK) + 1;
                dwHeight := ((pPixelContainer.Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1;
                dwPitch  := (((pPixelContainer.Size and X_D3DSIZE_PITCH_MASK) shr X_D3DSIZE_PITCH_SHIFT)+1)*64;
                dwBPP := 4;
             end;
            else if(X_Format = $11 (* D3DFMT_LIN_R5G6B5 *)(*)then
  begin
                // Linear 16 Bit
    dwWidth := (pPixelContainer.Size and X_D3DSIZE_WIDTH_MASK) + 1;
    dwHeight := ((pPixelContainer.Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1;
    dwPitch := (((pPixelContainer.Size and X_D3DSIZE_PITCH_MASK) shr X_D3DSIZE_PITCH_SHIFT) + 1) * 64;
    dwBPP := 2;
  end;
  else if (X_Format = $0C (* D3DFMT_DXT1 *) (*|| X_Format == 0x0E /* D3DFMT_DXT2 */ || X_Format == 0x0F /* D3DFMT_DXT3 */) then
            begin
                bCompressed := TRUE;

                // Compressed
                dwWidth  := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_USIZE_MASK) shr X_D3DFORMAT_USIZE_SHIFT);
                dwHeight := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_VSIZE_MASK) shr X_D3DFORMAT_VSIZE_SHIFT);
                dwDepth  := 1 shl ((pPixelContainer.Format and X_D3DFORMAT_PSIZE_MASK) shr X_D3DFORMAT_PSIZE_SHIFT);
                dwMipMapLevels := (pPixelContainer.Format and X_D3DFORMAT_MIPMAP_MASK) shr X_D3DFORMAT_MIPMAP_SHIFT;

                // D3DFMT_DXT2...D3DFMT_DXT5 : 128bits per block/per 16 texels
                dwCompressedSize := dwWidth*dwHeight;

                if(X_Format = $0C) then     // D3DFMT_DXT1 : 64bits per block/per 16 texels
                    dwCompressedSize:= dwCompressedSize div 2;

                dwBPP := 1;
             end;
            else if(X_Format = $24 (* D3DFMT_YUY2 *)(*)then
    begin
                // Linear 32 Bit
      dwWidth := (pPixelContainer.Size and X_D3DSIZE_WIDTH_MASK) + 1;
      dwHeight := ((pPixelContainer.Size and X_D3DSIZE_HEIGHT_MASK) shr X_D3DSIZE_HEIGHT_SHIFT) + 1;
      dwPitch := (((pPixelContainer.Size and X_D3DSIZE_PITCH_MASK) shr X_D3DSIZE_PITCH_SHIFT) + 1) * 64;
    end;
  else
    begin
      CxbxKrnlCleanup('0x%.08 X is not a supported format!', X_Format);
    end;

    if (X_Format = $24 (* X_D3DFMT_YUY2 *) (*) then
      begin
                //
                // cache the overlay size
                //

        g_dwOverlayW := dwWidth;
        g_dwOverlayH := dwHeight;
        g_dwOverlayP := RoundUp(g_dwOverlayW, 64) * 2;

                //
                // create texture resource
                //

        DWORD dwSize := g_dwOverlayP * g_dwOverlayH;
        DWORD dwPtr := (DWORD)CxbxMalloc(dwSize + SizeOf(DWORD));

        DWORD * pRefCount := (DWORD)(dwPtr + dwSize);

                // initialize ref count
        * pRefCount := 1;

                // If YUY2 is not supported in hardware, we'll actually mark this as a special fake texture (set highest bit)
        pPixelContainer.Data := X_D3DRESOURCE_DATA_FLAG_SPECIAL or X_D3DRESOURCE_DATA_FLAG_YUVSURF;
        pPixelContainer.Lock := dwPtr;
        pPixelContainer.Format := $24;

        pPixelContainer.Size := (g_dwOverlayW and X_D3DSIZE_WIDTH_MASK);
        pPixelContainer.Size := pPixelContainer.Size or (g_dwOverlayH shl X_D3DSIZE_HEIGHT_SHIFT);
        pPixelContainer.Size := pPixelContainer.Size or (g_dwOverlayP shl X_D3DSIZE_PITCH_SHIFT);
      end;
  else
    begin
      if (bSwizzled or bCompressed) then
      begin
        uint32 w := dwWidth;
        uint32 h := dwHeight;

        for (uint32 v := 0; v < dwMipMapLevels; v + +)
        begin
          if (((1 u shl v) >= w) or ((1 u shl v) >= h)) then
          begin
            dwMipMapLevels := v + 1;
            break;
          end;
        end;
      end;

                // create the happy little texture
      if (dwCommonType = X_D3DCOMMON_TYPE_SURFACE) then
      begin
        hRet := g_pD3DDevice8.CreateImageSurface(dwWidth, dwHeight, Format, @pResource.EmuSurface8);

        if (FAILED(hRet)) then
          CxbxKrnlCleanup('CreateImageSurface Failed!');

        DbgPrintf('EmuIDirect3DResource8_Register(0x%X): Successfully Created ImageSurface(0x%.08 X, 0x%.08 X)', pResource, pResource.EmuSurface8);
        DbgPrintf('EmuIDirect3DResource8_Register(0x%X): Width:%d, Height:%d, Format:%d', dwWidth, dwHeight, Format);
      end;
  else
    begin
                    // TODO: HACK: Figure out why this is necessary!
                    // TODO: This is necessary for DXT1 textures at least (4x4 blocks minimum)
      if (dwWidth < 4) then
      begin
        EmuWarning('Expanding texture width(mod d.4)', dwWidth);
        dwWidth := 4;

        dwMipMapLevels := 3;
      end;

      if (dwHeight < 4) then
      begin
        EmuWarning('Expanding texture height(mod d.4)', dwHeight);
        dwHeight := 4;

        dwMipMapLevels := 3;
      end;

     // HACK HACK HACK HACK HACK HACK HACK HACK HACK HACK
     // Since most modern graphics cards does not support
     // palette based textures we need to expand it to
     // ARGB texture format
      if (Format = D3DFMT_P8) then //Palette
      begin
        CacheFormat := Format; // Save this for later
        Format := D3DFMT_A8R8G8B8; // ARGB
      end;

      if (bCubemap) then
      begin
        DbgPrintf('CreateCubeTexture(mod d,%d, 0,%d, D3DPOOL_MANAGED, 0x%.08 X)', dwWidth,
          dwMipMapLevels, Format, @pResource.EmuTexture8);

        hRet = g_pD3DDevice8.CreateCubeTexture
          (
          dwWidth, dwMipMapLevels, 0, Format,
          D3DPOOL_MANAGED, @pResource.EmuCubeTexture8
          );

        if (FAILED(hRet)) then
          CxbxKrnlCleanup('CreateCubeTexture Failed!');

        DbgPrintf('EmuIDirect3DResource8_Register(0x%X): Successfully Created CubeTexture(0x%.08 X, 0x%.08 X)', pResource, pResource.EmuCubeTexture8);
      end;
  else
    begin
      DbgPrintf('CreateTexture(mod d,%d,%d, 0,%d, D3DPOOL_MANAGED, 0x%.08 X)', dwWidth, dwHeight,
        dwMipMapLevels, Format, @pResource.EmuTexture8);

      hRet = g_pD3DDevice8.CreateTexture
        (
        dwWidth, dwHeight, dwMipMapLevels, 0, Format,
        D3DPOOL_MANAGED, @pResource.EmuTexture8
        );

      if (FAILED(hRet)) then
        CxbxKrnlCleanup('CreateTexture Failed!');


      DbgPrintf('EmuIDirect3DResource8_Register(0x%X): Successfully Created Texture(0x%.08 X, 0x%.08 X)', pResource, pResource.EmuTexture8);
    end; * )
end;

(*
uint32 stop := bCubemap ? 6: 1;

for (uint32 r := 0; r < stop; r + +)
begin
                    // as we iterate through mipmap levels, we'll adjust the source resource offset
  DWORD dwCompressedOffset := 0;

  DWORD dwMipOffs := 0;
  DWORD dwMipWidth := dwWidth;
  DWORD dwMipHeight := dwHeight;
  DWORD dwMipPitch := dwPitch;

                    // iterate through the number of mipmap levels
  for (uint level := 0; level < dwMipMapLevels; level + +)
  begin
    D3DLOCKED_RECT LockedRect;

                        // copy over data (deswizzle if necessary)
    if (dwCommonType = X_D3DCOMMON_TYPE_SURFACE) then
      hRet := pResource.EmuSurface8.LockRect(@LockedRect, 0, 0);
else
  begin
    if (bCubemap) then
    begin
      hRet := pResource.EmuCubeTexture8.LockRect((D3DCUBEMAP_FACES)r, 0, @LockedRect, 0, 0);
    end;
else
  begin
    hRet := pResource.EmuTexture8.LockRect(level, @LockedRect, 0, 0);
  end;
end;

TRect iRect := (0, 0, 0, 0);
TPoint iPoint := (0, 0);

BYTE * pSrc := (BYTE)pBase;

pThis.Data := (DWORD)pSrc;

if ((IsSpecialResource(pResource.Data) and (pResource.Data and X_D3DRESOURCE_DATA_FLAG_SURFACE)) then
  or (IsSpecialResource(pBase) and ((DWORD)pBase and X_D3DRESOURCE_DATA_FLAG_SURFACE)))
begin
  EmuWarning('Attempt to registered to another resource's data (eww not )');

                            // TODO: handle this horrible situation
    BYTE * pDest := (BYTE)LockedRect.pBits;
    for (DWORD v := 0; v < dwMipHeight; v + +)
    begin
      FillChar(pDest, 0, dwMipWidth * dwBPP);

      pDest := pDest + LockedRect.Pitch;
      pSrc := pSrc + dwMipPitch;
    end;
end;
else
  begin
    if (bSwizzled) then
    begin
      if ((DWORD)pSrc = $80000000) then
      begin
                                    // TODO: Fix or handle this situation..?
      end;
    else
    begin
      if (CacheFormat = D3DFMT_P8) then //Palette
      begin
        EmuWarning('Unsupported texture format D3DFMT_P8, expanding to D3DFMT_A8R8G8B8');

          //
          // create texture resource
          //
        BYTE * pPixelData := (BYTE)LockedRect.pBits;
        DWORD dwDataSize := dwMipWidth * dwMipHeight * 4;
        DWORD dwPaletteSize := 256 * 4; // Note: This is not allways true, it can be 256- 128- 64- or 32*4

        BYTE * pTextureCache := (BYTE)CxbxMalloc(dwDataSize);
        BYTE * pExpandedTexture := (BYTE)CxbxMalloc(dwDataSize);
        BYTE * pTexturePalette := (BYTE)CxbxMalloc(256 * 4);

          // First we need to unswizzle the texture data
        XTL.EmuXGUnswizzleRect
          (
          pSrc + dwMipOffs, dwMipWidth, dwMipHeight, dwDepth, LockedRect.pBits,
          LockedRect.Pitch, iRect, iPoint, dwBPP
          );

          // Copy the unswizzled data to a temporary buffer
        memcpy(pTextureCache, pPixelData, dwDataSize);

          // Copy the currently selected palette's data to the buffer
        memcpy(pTexturePalette, pCurrentPalette, dwPaletteSize);

        Word w := 0;
        Word c := 0;
        Byte p := 0;
        for (Word y := 0; y < dwDataSize / 4; y + +)
        begin
          if (c = dwMipWidth) then
          begin
            w := w + dwMipWidth * 3;
            c := 0;
          end;
          p := (Byte)pTextureCache[w];
          pExpandedTexture[y * 4 + 0] := pTexturePalette[p * 4 + 0];
          pExpandedTexture[y * 4 + 1] := pTexturePalette[p * 4 + 1];
          pExpandedTexture[y * 4 + 2] := pTexturePalette[p * 4 + 2];
          pExpandedTexture[y * 4 + 3] := pTexturePalette[p * 4 + 3];
          w := w + 1;
          c := c + 1;
        end;

          // Copy the expanded texture back to the buffer
        memcpy(pPixelData, pExpandedTexture, dwDataSize);

          // Flush unused data buffers
        CxbxFree(pTexturePalette);
        CxbxFree(pExpandedTexture);
        CxbxFree(pTextureCache);
      end;
  else
    begin
      XTL.EmuXGUnswizzleRect
        (
        pSrc + dwMipOffs, dwMipWidth, dwMipHeight, dwDepth, LockedRect.pBits,
        LockedRect.Pitch, iRect, iPoint, dwBPP
        );
    end;
  end;
end;
else if (bCompressed) then
begin
                                // NOTE: compressed size is (dwWidth/2)*(dwHeight/2)/2, so each level divides by 4

  memcpy(LockedRect.pBits, pSrc + dwCompressedOffset, dwCompressedSize shr (level * 2));

  dwCompressedOffset := dwCompressedOffset + (dwCompressedSize shr (level * 2));
end;
else
  begin
    BYTE * pDest := (BYTE)LockedRect.pBits;

    if ((DWORD)LockedRect.Pitch = dwMipPitch and dwMipPitch = dwMipWidth * dwBPP) then
    begin
      memcpy(pDest, pSrc + dwMipOffs, dwMipWidth * dwMipHeight * dwBPP);
    end;
else
  begin
    for (DWORD v := 0; v < dwMipHeight; v + +)
    begin
      memcpy(pDest, pSrc + dwMipOffs, dwMipWidth * dwBPP);

      pDest := pDest + LockedRect.Pitch;
      pSrc := pSrc + dwMipPitch;
    end;
  end;
end;
end;

if (dwCommonType = X_D3DCOMMON_TYPE_SURFACE) then
  pResource.EmuSurface8.UnlockRect();
else
  begin
    if (bCubemap) then
      pResource.EmuCubeTexture8.UnlockRect((D3DCUBEMAP_FACES)r, 0);
else
  pResource.EmuTexture8.UnlockRect(level);
end;

dwMipOffs := dwMipOffs + dwMipWidth * dwMipHeight * dwBPP;

dwMipWidth := dwMipWidth div 2;
dwMipHeight := dwMipHeight div 2;
dwMipPitch := dwMipPitch div 2;
end;
end;

                // Debug Texture Dumping
# ifdef _DEBUG_DUMP_TEXTURE_REGISTER
if (dwCommonType = X_D3DCOMMON_TYPE_SURFACE) then
begin
  integer dwDumpSurface := 0;

  szBuffer: array[0..255 - 1] of Char;

  StrFmt(szBuffer, _DEBUG_DUMP_TEXTURE_REGISTER '%.03 d - RegSurface%.03 d.bmp', X_Format, dwDumpSurface + +);

  D3DXSaveSurfaceToFile(szBuffer, D3DXIFF_BMP, pResource.EmuSurface8, 0, 0);
end;
else
  begin
    if (bCubemap) then
    begin
      integer dwDumpCube := 0;

      szBuffer: array[0..255 - 1] of Char;

      for (integer v := 0; v < 6; v + +)
      begin
        IDirect3DSurface8 * pSurface := 0;

        StrFmt(szBuffer, _DEBUG_DUMP_TEXTURE_REGISTER '%.03 d - RegCubeTex%.03 d -%d.bmp', X_Format, dwDumpCube + +, v);

        pResource.EmuCubeTexture8.GetCubeMapSurface((D3DCUBEMAP_FACES)v, 0, @pSurface);

        D3DXSaveSurfaceToFile(szBuffer, D3DXIFF_BMP, pSurface, 0, 0);
      end;
    end;
else
  begin
    integer dwDumpTex := 0;

    szBuffer: array[0..255 - 1] of Char;

    StrFmt(szBuffer, _DEBUG_DUMP_TEXTURE_REGISTER '%.03 d - RegTexture%.03 d.bmp', X_Format, dwDumpTex + +);

    D3DXSaveTextureToFile(szBuffer, D3DXIFF_BMP, pResource.EmuTexture8, 0);
  end;
end;
                //endif
end;
end;
break;

X_D3DCOMMON_TYPE_PALETTE:
begin
  DbgPrintf('EmuIDirect3DResource8_Register: .PaletteArgs: array of const');

  X_D3DPalette * pPalette := (X_D3DPalette)pResource;

            // create palette
  begin
    DWORD dwSize := EmuCheckAllocationSize(pBase, true);

    if (dwSize = -1) then
    begin
                    // TODO: once this is known to be working, remove the warning
      EmuWarning('Palette allocation size unknown');

      pPalette.Lock := X_D3DRESOURCE_LOCK_FLAG_NOSIZE;
    end;

    pCurrentPalette := pBase;

    pResource.Data := (ULONG)pBase;
  end;

            //DbgPrintf('EmuIDirect3DResource8_Register (0x%X) : Successfully Created Palette (0x%.08X, 0x%.08X, 0x%.08X)\n', pResource->Data, pResource->Size, pResource->AllocationSize);
end;
break;

X_D3DCOMMON_TYPE_FIXUP:
begin
  X_D3DFixup * pFixup := (X_D3DFixup)pResource;

  CxbxKrnlCleanup('IDirect3DReosurce8.Register.X_D3DCOMMON_TYPE_FIXUP is not yet supported'
    #13#10'0x%.08 X(pFixup.Common)'
    #13#10'0x%.08 X(pFixup.Data)'
    #13#10'0x%.08 X(pFixup.Lock)'
    #13#10'0x%.08 X(pFixup.Run)'
    #13#10'0x%.08 X(pFixup.Next)'
    #13#10'0x%.08 X(pFixup.Size)', pFixup.Common, pFixup.Data, pFixup.Lock, pFixup.Run, pFixup.Next, pFixup.Size);
end;

default:
CxbxKrnlCleanup('IDirect3DResource8.Register.Common cType 0x%.08 X not yet supported', dwCommonType);
end;            *)

EmuSwapFS(); // XBox FS

Result := hRet;
end;

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DResource8_AddRef
(*ULONG WINAPI XTL.EmuIDirect3DResource8_AddRef
(
    X_D3DResource      *pThis
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DResource8_AddRef'
           #13#10'('
           #13#10'   pThis               : 0x%.08X'
           #13#10');',
           pThis);

    ULONG uRet := 0;

    IDirect3DResource8 *pResource8 := pThis.EmuResource8;

    if(pThis.Lock = $8000BEEF) then
        uRet := ++pThis.Lock;
    else if(pResource8 <> 0) then
        uRet := pResource8.AddRef();

    EmuSwapFS();   // XBox FS

    Result:= uRet;
 end; *)

 { TODO : Need to be translated to delphi }
// func: EmuIDirect3DResource8_Release
(*ULONG WINAPI XTL.EmuIDirect3DResource8_Release
(
    X_D3DResource      *pThis
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DResource8_Release'
           #13#10'('
           #13#10'   pThis               : 0x%.08X'
           #13#10');',
           pThis);

    ULONG uRet := 0;

    if(IsSpecialResource(pThis.Data) and (pThis.Data and X_D3DRESOURCE_DATA_FLAG_YUVSURF)) then
    begin
        DWORD  dwPtr := (DWORD)pThis.Lock;
        DWORD *pRefCount := (DWORD)(dwPtr + g_dwOverlayP*g_dwOverlayH);

        if(--(pRefCount) = 0) then
        begin
            // free memory associated with this special resource handle
            CxbxFree((PVOID)dwPtr);
         end;

        EmuSwapFS();
        EmuIDirect3DDevice8_EnableOverlay(False);
        EmuSwapFS();
     end;
    else
    begin
        IDirect3DResource8 *pResource8 := pThis.EmuResource8;

        if(pThis.Lock = $8000BEEF) then
        begin
            delete[] (PVOID)pThis.Data;
            uRet := --pThis.Lock;
         end;
        else if(pResource8 <> 0) then
        begin
            for(integer v:=0;v<16;v++)
            begin
                if(pCache[v].Data = pThis.Data and pThis.Data <> 0) then
                begin
                    pCache[v].Data := 0;
                    break;
                 end;
             end;

            #ifdef _DEBUG_TRACE_VB
            D3DRESOURCETYPE cType := pResource8.GetType();
            //endif

            uRet := pResource8.Release();

            if(uRet = 0) then
            begin
                DbgPrintf('EmuIDirect3DResource8_Release : Cleaned up a Resource!');

                #ifdef _DEBUG_TRACE_VB
                if(cType = D3DRTYPE_VERTEXBUFFER) then
                begin
                    g_VBTrackTotal.remove(pResource8);
                    g_VBTrackDisable.remove(pResource8);
                 end;
                //endif

                //delete pThis;
             end;
         end;
     end;

    EmuSwapFS();   // XBox FS

    Result:= uRet;
 end;  *)

// func: EmuIDirect3DResource8_IsBusy

function XTL_EmuIDirect3DResource8_IsBusy: LongBool;
    (*pThis : X_D3DResource; *)
begin
  EmuSwapFS(); // Win2k/XP FS

    (* too much output
    DbgPrintf('EmuD3D8 : EmuIDirect3DResource8_IsBusy'
           #13#10'('
           #13#10'   pThis               : 0x%.08X'
           #13#10');',
           pThis);
    //*/
{ TODO : Need to be translated to delphi }
(*
    IDirect3DResource8 *pResource8 := pThis.EmuResource8;
*)
  EmuSwapFS(); // XBox FS

  Result := False;
end;

{ TODO : Need to be translated to delphi }
// func: EmuIDirect3DResource8_GetType
(*XTL.X_D3DRESOURCETYPE WINAPI XTL.EmuIDirect3DResource8_GetType
(
    X_D3DResource      *pThis
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DResource8_GetType'
           #13#10'('
           #13#10'   pThis               : 0x%.08X'
           #13#10');',
           pThis);

    // TODO: Handle situation where the resource type is >7
    D3DRESOURCETYPE rType := pThis.EmuResource8.GetType();

    EmuSwapFS();   // XBox FS

    Result:= (X_D3DRESOURCETYPE)rType;
 end; *)

// func: EmuLock2DSurface
{ TODO : Need to be translated to delphi }

procedure XTL_EmuLock2DSurface;
(*(
    X_D3DPixelContainer *pPixelContainer,
    D3DCUBEMAP_FACES     FaceType,
    UINT                 Level,
    D3DLOCKED_RECT      *pLockedRect,
    TRect                *pRect,
    DWORD                Flags
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuLock2DSurface'
           #13#10'('
           #13#10'   pPixelContainer     : 0x%.08X'
           #13#10'   FaceType            : 0x%.08X'
           #13#10'   Level               : 0x%.08X'
           #13#10'   pLockedRect         : 0x%.08X'
           #13#10'   pRect               : 0x%.08X'
           #13#10'   Flags               : 0x%.08X'
           #13#10');',
           pPixelContainer, FaceType, Level, pLockedRect, pRect, Flags);

    EmuVerifyResourceIsRegistered(pPixelContainer);

    HRESULT hRet := pPixelContainer.EmuCubeTexture8.LockRect(FaceType, Level, pLockedRect, pRect, Flags);

    EmuSwapFS();   // XBox FS

    Exit; *)
end;

// func: EmuGet2DSurfaceDesc

{ TODO : Need to be translated to delphi }

procedure XTL_EmuGet2DSurfaceDesc;
(*(
    X_D3DPixelContainer *pPixelContainer,
    DWORD                dwLevel,
    X_D3DSURFACE_DESC   *pDesc
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuGet2DSurfaceDesc'
           #13#10'('
           #13#10'   pPixelContainer     : 0x%.08X'
           #13#10'   dwLevel             : 0x%.08X'
           #13#10'   pDesc               : 0x%.08X'
           #13#10');',
           pPixelContainer, dwLevel, pDesc);

    EmuVerifyResourceIsRegistered(pPixelContainer);

    D3DSURFACE_DESC SurfaceDesc;

    ZeroMemory(@SurfaceDesc, SizeOf(SurfaceDesc));

    HRESULT hRet;

    if(dwLevel = $FEFEFEFE) then
    begin
        hRet := pPixelContainer.EmuSurface8.GetDesc(@SurfaceDesc);

        (*
         integer dwDumpSurface := 0;

         szBuffer: array[0..255-1] of Char;

        StrFmt(szBuffer, 'C:\Aaron\Textures\Surface%.03d.bmp', dwDumpSurface++);

        D3DXSaveSurfaceToFile(szBuffer, D3DXIFF_BMP, pPixelContainer.EmuSurface8, 0, 0);
        *)
(*     end;
    else
    begin
        hRet := pPixelContainer.EmuTexture8.GetLevelDesc(dwLevel, @SurfaceDesc);

        (*
         integer dwDumpTexture := 0;

         szBuffer: array[0..255-1] of Char;

        StrFmt(szBuffer, 'C:\Aaron\Textures\GetDescTexture%.03d.bmp', dwDumpTexture++);

        D3DXSaveTextureToFile(szBuffer, D3DXIFF_BMP, pPixelContainer.EmuTexture8, 0);
        *)
(*     end;

    // rearrange into xbox format (remove D3DPOOL)
    begin
        // Convert Format (PC->Xbox)
        pDesc.Format := EmuPC2XB_D3DSurfaceDesc.Format);
        pDesc.cType   := (X_D3DRESOURCETYPE)SurfaceDesc.cType;

        if(pDesc.cType > 7) then
            CxbxKrnlCleanup('EmuGet2DSurfaceDesc: pDesc.cType > 7');

        pDesc.Usage  := SurfaceDesc.Usage;
        pDesc.Size   := SurfaceDesc.Size;

        // TODO: Convert from Xbox to PC!!
        if(SurfaceDesc.MultiSampleType = D3DMULTISAMPLE_NONE) then
            pDesc.MultiSampleType := (XTL.D3DMULTISAMPLE_TYPE)$0011;
        else
            CxbxKrnlCleanup('EmuGet2DSurfaceDesc Unknown Multisample format not  (%d)', SurfaceDesc.MultiSampleType);

        pDesc.Width  := SurfaceDesc.Width;
        pDesc.Height := SurfaceDesc.Height;
     end;

    EmuSwapFS();   // XBox FS

    Exit; *)
end;

// func: EmuGet2DSurfaceDescD
{ TODO : Need to be translated to delphi }

procedure XTL_EmuGet2DSurfaceDescD;
(*(
    X_D3DPixelContainer *pPixelContainer,
    X_D3DSURFACE_DESC   *pDesc
) *)
begin
(*    // debug trace
    #ifdef _DEBUG_TRACE
    begin
        EmuSwapFS();   // Win2k/XP FS
        DbgPrintf('EmuD3D8 : EmuGet2DSurfaceDescD'
               #13#10'('
               #13#10'   pPixelContainer     : 0x%.08X'
               #13#10'   pDesc               : 0x%.08X'
               #13#10');',
               pPixelContainer, pDesc);
        EmuSwapFS();   // Xbox FS
     end;
    //endif

    EmuGet2DSurfaceDesc(pPixelContainer, $FEFEFEFE, pDesc);

    Exit; *)
end;

// func: EmuIDirect3DSurface8_GetDesc

function XTL_EmuIDirect3DSurface8_GetDesc: HRESULT;
var
  hRet: HRESULT;
(*(
    X_D3DResource      *pThis,
    X_D3DSURFACE_DESC  *pDesc
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DSurface8_GetDesc'
           #13#10'('
           #13#10'   pThis               : 0x%.08X'
           #13#10'   pDesc               : 0x%.08X'
           #13#10');',
           pThis, pDesc);

    EmuVerifyResourceIsRegistered(pThis);

    if(IsSpecialResource(pThis.Data) and (pThis.Data and X_D3DRESOURCE_DATA_FLAG_YUVSURF)) then
    begin
        pDesc.Format := EmuPC2XB_D3DD3DFMT_YUY2);
        pDesc.Height := g_dwOverlayH;
        pDesc.Width  := g_dwOverlayW;
        pDesc.MultiSampleType := (D3DMULTISAMPLE_TYPE)0;
        pDesc.Size   := g_dwOverlayP*g_dwOverlayH;
        pDesc.cType   := X_D3DRTYPE_SURFACE;
        pDesc.Usage  := 0;

        hRet := D3D_OK;
     end;
    else
    begin
        IDirect3DSurface8 *pSurface8 := pThis.EmuSurface8;

        D3DSURFACE_DESC SurfaceDesc;

        hRet := pSurface8.GetDesc(@SurfaceDesc);

        // rearrange into windows format (remove D3DPool)
        begin
            // Convert Format (PC->Xbox)
            pDesc.Format := EmuPC2XB_D3DSurfaceDesc.Format);
            pDesc.cType   := (X_D3DRESOURCETYPE)SurfaceDesc.cType;

            if(pDesc.cType > 7) then
                CxbxKrnlCleanup('EmuIDirect3DSurface8_GetDesc: pDesc.cType > 7');

            pDesc.Usage  := SurfaceDesc.Usage;
            pDesc.Size   := SurfaceDesc.Size;

            // TODO: Convert from Xbox to PC!!
            if(SurfaceDesc.MultiSampleType = D3DMULTISAMPLE_NONE) then
                pDesc.MultiSampleType := (XTL.D3DMULTISAMPLE_TYPE)$0011;
            else
                CxbxKrnlCleanup('EmuIDirect3DSurface8_GetDesc Unknown Multisample format not  (%d)', SurfaceDesc.MultiSampleType);

            pDesc.Width  := SurfaceDesc.Width;
            pDesc.Height := SurfaceDesc.Height;
         end;
     end;  *)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DSurface8_LockRect

function XTL_EmuIDirect3DSurface8_LockRect: HRESULT;
var
  hRet: HRESULT;

(*(
    X_D3DResource      *pThis,
    D3DLOCKED_RECT     *pLockedRect,
    CONST TRect         *pRect,
    DWORD               Flags
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DSurface8_LockRect'
           #13#10'('
           #13#10'   pThis               : 0x%.08X'
           #13#10'   pLockedRect         : 0x%.08X'
           #13#10'   pRect               : 0x%.08X'
           #13#10'   Flags               : 0x%.08X'
           #13#10');',
           pThis, pLockedRect, pRect, Flags);

    EmuVerifyResourceIsRegistered(pThis);

    if(IsSpecialResource(pThis.Data) and (pThis.Data and X_D3DRESOURCE_DATA_FLAG_YUVSURF)) then
    begin
        pLockedRect.Pitch := g_dwOverlayP;
        pLockedRect.pBits := (PVOID)pThis.Lock;

        hRet := D3D_OK;
     end;
    else
    begin
        if(Flags and $40) then
            EmuWarning('D3DLOCK_TILED ignored!');

        IDirect3DSurface8 *pSurface8 := pThis.EmuSurface8;

        DWORD NewFlags := 0;

        if(Flags and $80) then
            NewFlags:= NewFlags or D3DLOCK_READONLY;

        if(Flags and  not ($80 or $40)) then
            CxbxKrnlCleanup('EmuIDirect3DSurface8_LockRect: Unknown Flags not  (0x%.08X)', Flags);

        // Remove old lock(s)
        pSurface8.UnlockRect();

        hRet := pSurface8.LockRect(pLockedRect, pRect, NewFlags);

        if(FAILED(hRet)) then
            EmuWarning('LockRect Failed!');
     end;    *)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DBaseTexture8_GetLevelCount

function XTL_EmuIDirect3DBaseTexture8_GetLevelCount(pThis: X_D3DBaseTexture): DWORD;
var
  dwRet: DWORD;
  (*pBaseTexture8: IDirect3DBaseTexture8; *)
begin
  dwRet := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DBaseTexture8_GetLevelCount' +
    #13#10'(' +
    #13#10'   pThis               : 0x%.08X' +
    #13#10');',
    [@pThis]);

  { TODO : Need to be translated to delphi }
  (*EmuVerifyResourceIsRegistered(pThis);

  pBaseTexture8 := pThis.EmuBaseTexture8;

  dwRet := pBaseTexture8.GetLevelCount(); *)
  EmuSwapFS(); // XBox FS

  Result := dwRet;
end;

// func: EmuIDirect3DTexture8_GetSurfaceLevel2
(*XTL.X_D3DResource * WINAPI XTL.EmuIDirect3DTexture8_GetSurfaceLevel2
(
    X_D3DTexture   *pThis,
    UINT            Level
)
begin
    X_D3DSurface *pSurfaceLevel;

    // In a special situation, we are actually returning a memory ptr with high bit set
    if(IsSpecialResource(pThis.Data) and (pThis.Data and X_D3DRESOURCE_DATA_FLAG_YUVSURF)) then
    begin
        DWORD dwSize := g_dwOverlayP*g_dwOverlayH;

        DWORD *pRefCount := (DWORD)((DWORD)pThis.Lock + dwSize);

        // initialize ref count
        (pRefCount):= (pRefCount) + 1;

        Result:= pThis;
     end;

    EmuIDirect3DTexture8_GetSurfaceLevel(pThis, Level, @pSurfaceLevel);

    Result:= pSurfaceLevel;
 end; *)

// func: EmuIDirect3DTexture8_LockRect

function XTL_EmuIDirect3DTexture8_LockRect: HRESULT;
var
  hRet: HRESULT;
(*(
    X_D3DTexture   *pThis,
    UINT            Level,
    D3DLOCKED_RECT *pLockedRect,
    CONST TRect     *pRect,
    DWORD           Flags
) *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DTexture8_LockRect'
           #13#10'('
           #13#10'   pThis               : 0x%.08X'
           #13#10'   Level               : 0x%.08X'
           #13#10'   pLockedRect         : 0x%.08X'
           #13#10'   pRect               : 0x%.08X'
           #13#10'   Flags               : 0x%.08X'
           #13#10');',
           pThis, Level, pLockedRect, pRect, Flags);

    EmuVerifyResourceIsRegistered(pThis);

    // check if we have an unregistered YUV2 resource
    if( (pThis <> 0) and IsSpecialResource(pThis.Data) and (pThis.Data and X_D3DRESOURCE_DATA_FLAG_YUVSURF)) then
    begin
        pLockedRect.Pitch := g_dwOverlayP;
        pLockedRect.pBits := (PVOID)pThis.Lock;

        hRet := D3D_OK;
     end;
    else
    begin
        IDirect3DTexture8 *pTexture8 := pThis.EmuTexture8;

        DWORD NewFlags := 0;

        if(Flags and $80) then
            NewFlags:= NewFlags or D3DLOCK_READONLY;

        if(Flags and  not ($80 or $40)) then
            CxbxKrnlCleanup('EmuIDirect3DTexture8_LockRect: Unknown Flags not  (0x%.08X)', Flags);

        // Remove old lock(s)
        pTexture8.UnlockRect(Level);

        hRet := pTexture8.LockRect(Level, pLockedRect, pRect, NewFlags);

        pThis.Common:= pThis.Common or X_D3DCOMMON_ISLOCKED;
     end;          *)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DTexture8_GetSurfaceLevel

function XTL_EmuIDirect3DTexture8_GetSurfaceLevel: HRESULT;
var
  hRet: HRESULT;
  (*  pThis : X_D3DTexture;
    Level : UINT;
    ppSurfaceLevel : X_D3DSurface; *)

begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DTexture8_GetSurfaceLevel'
           #13#10'('
           #13#10'   pThis               : 0x%.08X'
           #13#10'   Level               : 0x%.08X'
           #13#10'   ppSurfaceLevel      : 0x%.08X'
           #13#10');',
           pThis, Level, ppSurfaceLevel);

    EmuVerifyResourceIsRegistered(pThis);

    // if highest bit is set, this is actually a raw memory pointer (for YUY2 simulation)
    if(IsSpecialResource(pThis.Data) and (pThis.Data and X_D3DRESOURCE_DATA_FLAG_YUVSURF)) then
    begin
        DWORD dwSize := g_dwOverlayP*g_dwOverlayH;

        DWORD *pRefCount := (DWORD)((DWORD)pThis.Lock + dwSize);

        // initialize ref count
        (pRefCount):= (pRefCount) + 1;

        *ppSurfaceLevel := (X_D3DSurface)pThis;

        hRet := D3D_OK;
     end;
    else
    begin
        IDirect3DTexture8 *pTexture8 := pThis.EmuTexture8;

        *ppSurfaceLevel := new X_D3DSurface();

        (ppSurfaceLevel).Data := $B00BBABE;
        (ppSurfaceLevel).Common := 0;
        (ppSurfaceLevel).Format := 0;
        (ppSurfaceLevel).Size := 0;

        hRet := pTexture8.GetSurfaceLevel(Level,  and ((ppSurfaceLevel).EmuSurface8));

        if(FAILED(hRet)) then
        begin
            EmuWarning('EmuIDirect3DTexture8_GetSurfaceLevel Failed!');
         end;
        else
        begin
            DbgPrintf('EmuD3D8 : EmuIDirect3DTexture8_GetSurfaceLevel := 0x%.08X', (ppSurfaceLevel).EmuSurface8);
         end;
     end;        *)

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DVolumeTexture8_LockBox

function XTL_EmuIDirect3DVolumeTexture8_LockBox(pThis: X_D3DVolumeTexture; Level: UINT;
  pLockedVolume: D3DLOCKED_BOX; pBox: D3DBOX; Flags: DWORD): HRESULT;
var
  hRet: HRESULT;
  (*pVolumeTexture8 : IDirect3DVolumeTexture8; *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DVolumeTexture8_LockBox' +
    #13#10'(' +
    #13#10'   pThis               : 0x%.08X' +
    #13#10'   Level               : 0x%.08X' +
    #13#10'   pLockedVolume       : 0x%.08X' +
    #13#10'   pBox                : 0x%.08X' +
    #13#10'   Flags               : 0x%.08X' +
    #13#10');',
    [pThis, Level, @pLockedVolume, @pBox, Flags]);

    { TODO : Need to be translated to delphi }
   (* EmuVerifyResourceIsRegistered(pThis);

    IDirect3DVolumeTexture8 *pVolumeTexture8 := pThis.EmuVolumeTexture8;

    hRet := pVolumeTexture8.LockBox(Level, pLockedVolume, pBox, Flags);
     *)
  if (FAILED(hRet)) then
    EmuWarning('LockBox Failed!');

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DCubeTexture8_LockRect

function XTL_EmuIDirect3DCubeTexture8_LockRect(pThis: X_D3DCubeTexture; FaceType: D3DCUBEMAP_FACES;
  Level: UINT; pLockedBox: D3DLOCKED_RECT; pRect: TRect; Flags: DWORD): HRESULT;
var
  hRet: HRESULT;
  (*pCubeTexture8 : IDirect3DCubeTexture8; *)
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DCubeTexture8_LockRect' +
    #13#10'(' +
    #13#10'   pThis               : 0x%.08X' +
    #13#10'   FaceType            : 0x%.08X' +
    #13#10'   Level               : 0x%.08X' +
    #13#10'   pLockedBox          : 0x%.08X' +
    #13#10'   pRect               : 0x%.08X' +
    #13#10'   Flags               : 0x%.08X' +
    #13#10');',
    [pThis, @FaceType, Level, @pLockedBox, @pRect, Flags]);

    { TODO : Need to be translated to delphi }
    (*EmuVerifyResourceIsRegistered(pThis);

    pCubeTexture8 := pThis.EmuCubeTexture8;

    hRet := pCubeTexture8.LockRect(FaceType, Level, pLockedBox, pRect, Flags); *)
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_Release
(*ULONG WINAPI XTL.EmuIDirect3DDevice8_Release()
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_Release();');

    g_pD3DDevice8.AddRef();
    DWORD RefCount := g_pD3DDevice8.Release();
    if (RefCount = 1) then
    begin
        // Signal proxy thread, and wait for completion
        g_EmuCDPD.bReady := true;
        g_EmuCDPD.bCreate := False;

        while(g_EmuCDPD.bReady)
            Sleep(10);
        RefCount := g_EmuCDPD.hRet;
     end;
    else
    begin
        RefCount := g_pD3DDevice8.Release();
     end;

    EmuSwapFS();   // XBox FS

    Result:= RefCount;
 end;            *)

// func: EmuIDirect3DDevice8_CreateVertexBuffer

function XTL_EmuIDirect3DDevice8_CreateVertexBuffer: HRESULT;
(*(
    UINT                Length,
    DWORD               Usage,
    DWORD               FVF,
    D3DPOOL             Pool,
    X_D3DVertexBuffer **ppVertexBuffer
) *)
begin
{ TODO : Need to be translated to delphi }
(*    *ppVertexBuffer := EmuIDirect3DDevice8_CreateVertexBuffer2(Length);
*)

  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_CreateVertexBuffer2
(*XTL.X_D3DVertexBuffer* WINAPI XTL.EmuIDirect3DDevice8_CreateVertexBuffer2
(
    UINT Length
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CreateVertexBuffer2'
           #13#10'('
           #13#10'   Length              : 0x%.08X'
           #13#10');',
           Length);

    X_D3DVertexBuffer *pD3DVertexBuffer := new X_D3DVertexBuffer();

    HRESULT hRet = g_pD3DDevice8.CreateVertexBuffer
    (
        Length,
        0,
        0,
        D3DPOOL_MANAGED,
        @pD3DVertexBuffer.EmuVertexBuffer8
    );

    if(FAILED(hRet)) then
        EmuWarning('CreateVertexBuffer Failed!');

    #ifdef _DEBUG_TRACK_VB
    g_VBTrackTotal.insert(pD3DVertexBuffer.EmuVertexBuffer8);
    //endif

    EmuSwapFS();   // XBox FS

    Result:= pD3DVertexBuffer;
 end;            *)

// func: EmuIDirect3DDevice8_EnableOverlay

procedure XTL_EmuIDirect3DDevice8_EnableOverlay(Enable: Boolean);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_EnableOverlay' +
    #13#10'(' +
    #13#10'   Enable              : 0x%.08X' +
    #13#10');',
    [Enable]);

  if (Enable = False and (g_pDDSOverlay7 <> nil)) then
  begin
    g_pDDSOverlay7.UpdateOverlay(nil, g_pDDSPrimary, nil, DDOVER_HIDE, nil);

        // cleanup overlay clipper
    if (g_pDDClipper <> nil) then
    begin
      g_pDDClipper._Release();
      g_pDDClipper := nil;
    end;

        // cleanup overlay surface
    if (g_pDDSOverlay7 <> nil) then
    begin
      g_pDDSOverlay7._Release();
      g_pDDSOverlay7 := nil;
    end;
  end
  else
    if (Enable = TRUE and (g_pDDSOverlay7 = nil)) then
    begin
        { TODO : Need to be translated to delphi }
        (*
        // initialize overlay surface
        if(g_bSupportsYUY2) then
        begin
            XTL.DDSURFACEDESC2 ddsd2;

            ZeroMemory(@ddsd2, SizeOf(ddsd2));

            ddsd2.dwSize := SizeOf(ddsd2);
            ddsd2.dwFlags := DDSD_CAPS or DDSD_WIDTH or DDSD_HEIGHT or DDSD_PIXELFORMAT;
            ddsd2.ddsCaps.dwCaps := DDSCAPS_OVERLAY;
            ddsd2.dwWidth := g_dwOverlayW;
            ddsd2.dwHeight := g_dwOverlayH;
            ddsd2.ddpfPixelFormat.dwSize := SizeOf(XTL.DDPIXELFORMAT);
            ddsd2.ddpfPixelFormat.dwFlags := DDPF_FOURCC;
            ddsd2.ddpfPixelFormat.dwFourCC := MAKEFOURCC('Y','U','Y','2');

            HRESULT hRet := g_pDD7.CreateSurface(@ddsd2, @g_pDDSOverlay7, 0);

            if(FAILED(hRet)) then
                CxbxKrnlCleanup('Could not create overlay surface');

            hRet := g_pDD7.CreateClipper(0, @g_pDDClipper, 0);

            if(FAILED(hRet)) then
                CxbxKrnlCleanup('Could not create overlay clipper');

            hRet := g_pDDClipper.SetHWnd(0, g_hEmuWindow);
         end;*)
    end;

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_UpdateOverlay

procedure XTL_EmuIDirect3DDevice8_UpdateOverlay;
(*(
    X_D3DSurface *pSurface,
    CONST TRect   *SrcRect,
    CONST TRect   *DstRect,
    BOOL          EnableColorKey,
    D3DCOLOR      ColorKey
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_UpdateOverlay'
           #13#10'('
           #13#10'   pSurface            : 0x%.08X'
           #13#10'   SrcRect             : 0x%.08X'
           #13#10'   DstRect             : 0x%.08X'
           #13#10'   EnableColorKey      : 0x%.08X'
           #13#10'   ColorKey            : 0x%.08X'
           #13#10');',
           pSurface, SrcRect, DstRect, EnableColorKey, ColorKey);

    // manually copy data over to overlay
    if(g_bSupportsYUY2) then
    begin
        DDSURFACEDESC2  ddsd2;

        ZeroMemory(@ddsd2, SizeOf(ddsd2));

        ddsd2.dwSize := SizeOf(ddsd2);

        g_pDDSOverlay7.Lock(0, @ddsd2, DDLOCK_SURFACEMEMORYPTR or DDLOCK_WAIT, 0);

        // copy data
        begin
            Char *pDest := (Char)ddsd2.lpSurface;
            Char *pSour := (Char)pSurface.Lock;

            integer w := g_dwOverlayW;
            integer h := g_dwOverlayH;

            // TODO: sucker the game into rendering directly to the overlay (speed boost)
            if( (ddsd2.lPitch = w*2) and ((integer)g_dwOverlayP = w*2) ) then
                memcpy(pDest, pSour, h*w*2);
            else
            begin
                for(integer y:=0;y<h;y++)
                begin
                    memcpy(pDest, pSour, w*2);

                    pDest:= pDest + ddsd2.lPitch;
                    pSour:= pSour + g_dwOverlayP;
                 end;
             end;
         end;

        g_pDDSOverlay7.Unlock(0);
     end;

    // update overlay!
    if(g_bSupportsYUY2) then
    begin
        TRect SourRect := (0, 0, g_dwOverlayW, g_dwOverlayH), DestRect;
        MONITORINFO MonitorInfo := (0);

        integer nTitleHeight  := 0;//GetSystemMetrics(SM_CYCAPTION);
        integer nBorderWidth  := 0;//GetSystemMetrics(SM_CXSIZEFRAME);
        integer nBorderHeight := 0;//GetSystemMetrics(SM_CYSIZEFRAME);

        MonitorInfo.cbSize := SizeOf(MONITORINFO);
        GetMonitorInfo(g_hMonitor, @MonitorInfo);

        GetWindowRect(g_hEmuWindow, @DestRect);

        DestRect.left  :=  + nBorderWidth;
        DestRect.right := DestRect.right - nBorderWidth;
        DestRect.top   :=  + nTitleHeight + nBorderHeight;
        DestRect.bottom:= DestRect.bottom - nBorderHeight;

        DestRect.left  :=  - MonitorInfo.rcMonitor.left;
        DestRect.right := DestRect.right - MonitorInfo.rcMonitor.left;
        DestRect.top   :=  - MonitorInfo.rcMonitor.top;
        DestRect.bottom:= DestRect.bottom - MonitorInfo.rcMonitor.top;

        DDOVERLAYFX ddofx;

        ZeroMemory(@ddofx, SizeOf(ddofx));

        ddofx.dwSize := SizeOf(DDOVERLAYFX);
        ddofx.dckDestColorkey.dwColorSpaceLowValue := 0;
        ddofx.dckDestColorkey.dwColorSpaceHighValue := 0;

        HRESULT hRet := g_pDDSOverlay7.UpdateOverlay(@SourRect, g_pDDSPrimary, @DestRect, (*DDOVER_KEYDESTOVERRIDE | *)(*DDOVER_SHOW, /*&ddofx*/0);
     end;
    else
    begin
        // TODO: dont assume X8R8G8B8 ?
        D3DLOCKED_RECT LockedRectDest;

        IDirect3DSurface8 *pBackBuffer:=0;

        HRESULT hRet := g_pD3DDevice8.GetBackBuffer(0, D3DBACKBUFFER_TYPE_MONO, @pBackBuffer);

        // if we obtained the backbuffer, manually translate the YUY2 into the backbuffer format
        if(hRet = D3D_OK and pBackBuffer.LockRect(@LockedRectDest, 0, 0) = D3D_OK) then
        begin
            uint08 *pCurByte := (uint08)pSurface.Lock;

            uint08 *pDest := (uint08)LockedRectDest.pBits;

            uint32 dx:=0, dy=0;

            uint32 dwImageSize := g_dwOverlayP*g_dwOverlayH;

            // grayscale
            if(False) then
            begin
                for(uint32 y:=0;y<g_dwOverlayH;y++)
                begin
                    uint32 stop := g_dwOverlayW*4;
                    for(uint32 x:=0;x<stop;x+=4)
                    begin
                        uint08 Y := *pCurByte;

                        pDest[x+0] := Y;
                        pDest[x+1] := Y;
                        pDest[x+2] := Y;
                        pDest[x+3] := $FF;

                        pCurByte+:=2;
                     end;

                    pDest:= pDest + LockedRectDest.Pitch;
                 end;
             end;
            // full color conversion (YUY2->XRGB)
            else
            begin
                for(uint32 v:=0;v<dwImageSize;v+=4)
                begin
                    Single Y[2], U, V;

                    Y[0] = *pCurByte:= *pCurByte + 1;
                    U    = *pCurByte:= *pCurByte + 1;
                    Y[1] = *pCurByte:= *pCurByte + 1;
                    V    = *pCurByte:= *pCurByte + 1;

                    integer a:=0;
                    for(integer x:=0;x<2;x++)
                    begin
                        Single R := Y[a] + 1.402f*(V-128);
                        Single G := Y[a] - 0.344f*(U-128) - 0.714f*(V-128);
                        Single B := Y[a] + 1.772f*(U-128);

                        R := (R < 0) ? 0 : ((R > 255) ? 255 : R);
                        G := (G < 0) ? 0 : ((G > 255) ? 255 : G);
                        B := (B < 0) ? 0 : ((B > 255) ? 255 : B);

                        uint32 i := (dy*LockedRectDest.Pitch+(dx+x)*4);

                        pDest[i+0] := (uint08)B;
                        pDest[i+1] := (uint08)G;
                        pDest[i+2] := (uint08)R;
                        pDest[i+3] := $FF;

                        a:= a + 1;
                     end;

                    dx+:=2;

                    if((dx%g_dwOverlayW) = 0) then
                    begin
                        dy:= dy + 1;
                        dx:=0;
                     end;

                 end;
             end;

            pBackBuffer.UnlockRect();
         end;
     end;

    EmuSwapFS();   // XBox FS

    Exit;     *)
end;

// func: EmuIDirect3DDevice8_GetOverlayUpdateStatus

function XTL_EmuIDirect3DDevice8_GetOverlayUpdateStatus(): LongBOOL;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetOverlayUpdateStatus();');

  EmuSwapFS(); // XBox FS

  // TODO: Actually check for update status
  Result := False;
end;

// func: EmuIDirect3DDevice8_BlockUntilVerticalBlank

procedure XTL_EmuIDirect3DDevice8_BlockUntilVerticalBlank;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_BlockUntilVerticalBlank();');

    // segaGT tends to freeze with this on
//    if(g_XBVideo.GetVSync())
{ TODO : Need to be translated to delphi }
(*        g_pDD7.WaitForVerticalBlank(DDWAITVB_BLOCKBEGIN, 0); *)

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetVerticalBlankCallback

procedure XTL_EmuIDirect3DDevice8_SetVerticalBlankCallback;
     (*pCallback : D3DVBLANKCALLBACK; *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVerticalBlankCallback'
           #13#10'('
           #13#10'   pCallback           : 0x%.08X'
           #13#10');',
           pCallback);

    g_pVBCallback := pCallback;

    EmuSwapFS();   // XBox FS

    Exit;  *)
end;

// func: EmuIDirect3DDevice8_SetTextureState_TexCoordIndex

procedure XTL_EmuIDirect3DDevice8_SetTextureState_TexCoordIndex(Stage: DWord; Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetTextureState_TexCoordIndex' +
    #13#10'(' +
    #13#10'   Stage               : 0x%.08X' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Stage, Value]);

  if (Value > $00030000) then
    CxbxKrnlCleanup(Format('EmuIDirect3DDevice8_SetTextureState_TexCoordIndex: Unknown TexCoordIndex Value (0x%.08X)', [Value]));

  g_pD3DDevice8.SetTextureStageState(Stage, D3DTSS_TEXCOORDINDEX, Value);

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetTextureState_TwoSidedLighting

procedure XTL_EmuIDirect3DDevice8_SetTextureState_TwoSidedLighting(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetTextureState_TwoSidedLighting' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('TwoSidedLighting is not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetTextureState_BackFillMode

procedure XTL_EmuIDirect3DDevice8_SetTextureState_BackFillMode(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetTextureState_BackFillMode' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('BackFillMode is not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetTextureState_BorderColor

procedure XTL_EmuIDirect3DDevice8_SetTextureState_BorderColor(Stage: DWord; Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetTextureState_BorderColor' +
    #13#10'(' +
    #13#10'   Stage               : 0x%.08X' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Stage, Value]);

  g_pD3DDevice8.SetTextureStageState(Stage, D3DTSS_BORDERCOLOR, Value);
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetTextureState_ColorKeyColor

procedure XTL_EmuIDirect3DDevice8_SetTextureState_ColorKeyColor(Stage: DWord; Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetTextureState_ColorKeyColor' +
    #13#10'(' +
    #13#10'   Stage               : 0x%.08X' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Stage, Value]);

  EmuWarning('SetTextureState_ColorKeyColor is not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetTextureState_BumpEnv

procedure XTL_EmuIDirect3DDevice8_SetTextureState_BumpEnv;
(*(
    DWORD                      Stage,
    X_D3DTEXTURESTAGESTATETYPE cType,
    DWORD                      Value
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetTextureState_BumpEnv'
           #13#10'('
           #13#10'   Stage               : 0x%.08X'
           #13#10'   cType                : 0x%.08X'
           #13#10'   Value               : 0x%.08X'
           #13#10');',
           Stage, cType, Value);

    case(cType) of
    begin
         22:    // X_D3DTSS_BUMPENVMAT00
            g_pD3DDevice8.SetTextureStageState(Stage, D3DTSS_BUMPENVMAT00, Value);
            break;
         23:    // X_D3DTSS_BUMPENVMAT01
            g_pD3DDevice8.SetTextureStageState(Stage, D3DTSS_BUMPENVMAT01, Value);
            break;
         24:    // X_D3DTSS_BUMPENVMAT11
            g_pD3DDevice8.SetTextureStageState(Stage, D3DTSS_BUMPENVMAT11, Value);
            break;
         25:    // X_D3DTSS_BUMPENVMAT10
            g_pD3DDevice8.SetTextureStageState(Stage, D3DTSS_BUMPENVMAT10, Value);
            break;
         26:    // X_D3DTSS_BUMPENVLSCALE
            g_pD3DDevice8.SetTextureStageState(Stage, D3DTSS_BUMPENVLSCALE, Value);
            break;
     end;

    EmuSwapFS();   // XBox FS

    Exit; *)
end;

// func: EmuIDirect3DDevice8_SetRenderState_FrontFace

procedure XTL_EmuIDirect3DDevice8_SetRenderState_FrontFace(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_FrontFace' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_FrontFace not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_LogicOp

procedure XTL_EmuIDirect3DDevice8_SetRenderState_LogicOp(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_LogicOp' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_LogicOp is not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_NormalizeNormals

procedure XTL_EmuIDirect3DDevice8_SetRenderState_NormalizeNormals(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_NormalizeNormals' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  g_pD3DDevice8.SetRenderState(D3DRS_NORMALIZENORMALS, Value);


  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_TextureFactor

procedure XTL_EmuIDirect3DDevice8_SetRenderState_TextureFactor(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_TextureFactor' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  g_pD3DDevice8.SetRenderState(D3DRS_TEXTUREFACTOR, Value);

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_ZBias

procedure XTL_EmuIDirect3DDevice8_SetRenderState_ZBias(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_ZBias' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  g_pD3DDevice8.SetRenderState(D3DRS_ZBIAS, Value);

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_EdgeAntiAlias

procedure XTL_EmuIDirect3DDevice8_SetRenderState_EdgeAntiAlias(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_EdgeAntiAlias' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  g_pD3DDevice8.SetRenderState(D3DRS_EDGEANTIALIAS, Value);

  EmuWarning('SetRenderState_EdgeAntiAlias not implemented!');
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_FillMode

procedure XTL_EmuIDirect3DDevice8_SetRenderState_FillMode(Value: DWord);
(*var
  dwFillMode: DWORD; *)
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_FillMode' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);


    { TODO : Need to be translated to delphi }
    (*
    if(g_iWireframe = 0) then
        dwFillMode := EmuXB2PC_D3DFILLMODE(Value);
    else if(g_iWireframe = 1) then
        dwFillMode := D3DFILL_WIREFRAME;
    else
        dwFillMode := D3DFILL_POINT;

    g_pD3DDevice8.SetRenderState(D3DRS_FILLMODE, dwFillMode);

  *)
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_FogColor

procedure XTL_EmuIDirect3DDevice8_SetRenderState_FogColor(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_FogColor' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  g_pD3DDevice8.SetRenderState(D3DRS_FOGCOLOR, Value);

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_Dxt1NoiseEnable

procedure XTL_EmuIDirect3DDevice8_SetRenderState_Dxt1NoiseEnable(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_Dxt1NoiseEnable' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_Dxt1NoiseEnable not implemented!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_Simple
(*VOID __fastcall XTL.EmuIDirect3DDevice8_SetRenderState_Simple
(
    DWORD Method,
    DWORD Value
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_Simple'
           #13#10'('
           #13#10'   Method              : 0x%.08X'
           #13#10'   Value               : 0x%.08X'
           #13#10');',
           Method, Value);

    integer State := -1;

    // Todo: make this faster and more elegant
    for(integer v:=0;v<174;v++)
    begin
        if(EmuD3DRenderStateSimpleEncoded[v] = Method) then
        begin
            State := v;
            break;
         end;
     end;

    if(State = -1) then
        EmuWarning('RenderState_Simple(0x%.08X, 0x%.08X) is unsupported!', Method, Value);
    else
    begin
        case(State) of
        begin
             D3DRS_COLORWRITEENABLE:
            begin
                DWORD OrigValue := Value;

                Value := 0;

                if(OrigValue and (1L shl 16)) then
                    Value:= Value or D3DCOLORWRITEENABLE_RED;
                if(OrigValue and (1L shl 8)) then
                    Value:= Value or D3DCOLORWRITEENABLE_GREEN;
                if(OrigValue and (1L shl 0)) then
                    Value:= Value or D3DCOLORWRITEENABLE_BLUE;
                if(OrigValue and (1L shl 24)) then
                    Value:= Value or D3DCOLORWRITEENABLE_ALPHA;

                DbgPrintf('D3DRS_COLORWRITEENABLE := 0x%.08X', Value);
             end;
            break;

             D3DRS_SHADEMODE:
                Value := Value and $03;
                DbgPrintf('D3DRS_SHADEMODE := 0x%.08X', Value);
                break;

             D3DRS_BLENDOP:
                Value := EmuXB2PC_D3DBLENDOP(Value);
                DbgPrintf('D3DRS_BLENDOP := 0x%.08X', Value);
                break;

             D3DRS_SRCBLEND:
                Value := EmuXB2PC_D3DBLEND(Value);
                DbgPrintf('D3DRS_SRCBLEND := 0x%.08X', Value);
                break;

             D3DRS_DESTBLEND:
                Value := EmuXB2PC_D3DBLEND(Value);
                DbgPrintf('D3DRS_DESTBLEND := 0x%.08X', Value);
                break;

             D3DRS_ZFUNC:
                Value := EmuXB2PC_D3DCMPFUNC(Value);
                DbgPrintf('D3DRS_ZFUNC := 0x%.08X', Value);
                break;

             D3DRS_ALPHAFUNC:
                Value := EmuXB2PC_D3DCMPFUNC(Value);
                DbgPrintf('D3DRS_ALPHAFUNC := 0x%.08X', Value);
                break;

             D3DRS_ALPHATESTENABLE:
                DbgPrintf('D3DRS_ALPHATESTENABLE := 0x%.08X', Value);
                break;

             D3DRS_ALPHABLENDENABLE:
                DbgPrintf('D3DRS_ALPHABLENDENABLE := 0x%.08X', Value);
                break;

             D3DRS_ALPHAREF:
                DbgPrintf('D3DRS_ALPHAREF := %lf', DWtoF(Value));
                break;

             D3DRS_ZWRITEENABLE:
                DbgPrintf('D3DRS_ZWRITEENABLE := 0x%.08X', Value);
                break;

             D3DRS_DITHERENABLE:
                DbgPrintf('D3DRS_DITHERENABLE := 0x%.08X', Value);
                break;

            default:
                CxbxKrnlCleanup('Unsupported RenderState (0x%.08X)', State);
                break;
        );

        // TODO: verify these params as you add support for them!
        g_pD3DDevice8->SetRenderState((D3DRENDERSTATETYPE)State, Value);
     end;

    EmuSwapFS();   // XBox FS

    Exit;
 end; *)

// func: EmuIDirect3DDevice8_SetRenderState_VertexBlend

procedure XTL_EmuIDirect3DDevice8_SetRenderState_VertexBlend(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_VertexBlend' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

    // convert from Xbox direct3d to PC direct3d enumeration
  if (Value <= 1) then
    Value := Value
  else if (Value = 3) then
    Value := 2
  else if (Value = 5) then
    Value := 3
  else
    CxbxKrnlCleanup(DxbxFormat('Unsupported D3DVERTEXBLENDFLAGS (%d)', [Value]));

  g_pD3DDevice8.SetRenderState(D3DRS_VERTEXBLEND, Value);

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_PSTextureModes

procedure XTL_EmuIDirect3DDevice8_SetRenderState_PSTextureModes(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_PSTextureModes' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

    // TODO: do something..

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_CullMode

procedure XTL_EmuIDirect3DDevice8_SetRenderState_CullMode(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_CullMode' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

    // convert from Xbox D3D to PC D3D enumeration
    // TODO: XDK-Specific Tables? So far they are the same
  case (Value) of
    0:
      Value := D3DCULL_NONE;
    $900:
      Value := D3DCULL_CW;
    $901:
      Value := D3DCULL_CCW;
  else
    CxbxKrnlCleanup(DxbxFormat('EmuIDirect3DDevice8_SetRenderState_CullMode: Unknown Cullmode (%d)', [Value]));
  end;

  g_pD3DDevice8.SetRenderState(D3DRS_CULLMODE, Value);
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_LineWidth

procedure XTL_EmuIDirect3DDevice8_SetRenderState_LineWidth(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_LineWidth' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

    // TODO: Convert to PC format??
//    g_pD3DDevice8->SetRenderState(D3DRS_LINEPATTERN, Value);
  EmuWarning('SetRenderState_LineWidth is not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_StencilFail

procedure XTL_EmuIDirect3DDevice8_SetRenderState_StencilFail(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_StencilFail' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  g_pD3DDevice8.SetRenderState(D3DRS_STENCILFAIL, Value);
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_OcclusionCullEnable

procedure XTL_EmuIDirect3DDevice8_SetRenderState_OcclusionCullEnable(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_OcclusionCullEnable' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_OcclusionCullEnable not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_StencilCullEnable

procedure XTL_EmuIDirect3DDevice8_SetRenderState_StencilCullEnable(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_StencilCullEnable' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_StencilCullEnable not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_RopZCmpAlwaysRead

procedure XTL_EmuIDirect3DDevice8_SetRenderState_RopZCmpAlwaysRead(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_RopZCmpAlwaysRead' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_RopZCmpAlwaysRead not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_RopZRead

procedure XTL_EmuIDirect3DDevice8_SetRenderState_RopZRead(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_RopZRead' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_RopZRead not supported!');

  EmuSwapFS(); // XBox FS

  Exit;
end;

// func: EmuIDirect3DDevice8_SetRenderState_DoNotCullUncompressed

procedure XTL_EmuIDirect3DDevice8_SetRenderState_DoNotCullUncompressed(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_DoNotCullUncompressed' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_DoNotCullUncompressed not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_ZEnable

procedure XTL_EmuIDirect3DDevice8_SetRenderState_ZEnable(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_ZEnable' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);
  g_pD3DDevice8.SetRenderState(D3DRS_ZENABLE, Value);

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_StencilEnable

procedure XTL_EmuIDirect3DDevice8_SetRenderState_StencilEnable(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_StencilEnable' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  g_pD3DDevice8.SetRenderState(D3DRS_STENCILENABLE, Value);
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_MultiSampleAntiAlias

procedure XTL_EmuIDirect3DDevice8_SetRenderState_MultiSampleAntiAlias(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_MultiSampleAntiAlias' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  g_pD3DDevice8.SetRenderState(D3DRS_MULTISAMPLEANTIALIAS, Value);

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_MultiSampleMask

procedure XTL_EmuIDirect3DDevice8_SetRenderState_MultiSampleMask(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_MultiSampleMask' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  g_pD3DDevice8.SetRenderState(D3DRS_MULTISAMPLEMASK, Value);

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_MultiSampleMode

procedure XTL_EmuIDirect3DDevice8_SetRenderState_MultiSampleMode(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_MultiSampleMode' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_MultiSampleMode is not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_MultiSampleRenderTargetMode

procedure XTL_EmuIDirect3DDevice8_SetRenderState_MultiSampleRenderTargetMode(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_MultiSampleRenderTargetMode' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('SetRenderState_MultiSampleRenderTargetMode is not supported!');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_ShadowFunc

procedure XTL_EmuIDirect3DDevice8_SetRenderState_ShadowFunc(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_ShadowFunc' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning('ShadowFunc not implemented');

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetRenderState_YuvEnable

procedure XTL_EmuIDirect3DDevice8_SetRenderState_YuvEnable(Value: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderState_YuvEnable' +
    #13#10'(' +
    #13#10'   Value               : 0x%.08X' +
    #13#10');',
    [Value]);

  EmuWarning(DxbxFormat('YuvEnable not implemented (0x%.08X)', [Value]));

  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetTransform

function XTL_EmuIDirect3DDevice8_SetTransform(State: D3DTRANSFORMSTATETYPE;
  pMatrix: D3DMATRIX): HRESULT;
var
  hRet: HRESULT;
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetTransform' +
    #13#10'(' +
    #13#10'   State               : 0x%.08X' +
    #13#10'   pMatrix             : 0x%.08X' +
    #13#10');',
    [@State, @pMatrix]);

    { TODO : Need to be translated to delphi }
    (*
    printf('pMatrix (%d)', State);
    printf('begin ');
    printf('    %.08f,%.08f,%.08f,%.08f', pMatrix->_11, pMatrix->_12, pMatrix->_13, pMatrix->_14);
    printf('    %.08f,%.08f,%.08f,%.08f', pMatrix->_21, pMatrix->_22, pMatrix->_23, pMatrix->_24);
    printf('    %.08f,%.08f,%.08f,%.08f', pMatrix->_31, pMatrix->_32, pMatrix->_33, pMatrix->_34);
    printf('    %.08f,%.08f,%.08f,%.08f', pMatrix->_41, pMatrix->_42, pMatrix->_43, pMatrix->_44);
    printf(' end;');

    if(State = 6 and (pMatrix->_11 = 1.0f) and (pMatrix->_22 = 1.0f) and (pMatrix->_33 = 1.0f) and (pMatrix->_44 = 1.0f)) then
    begin
        g_bSkipPush := TRUE;
        printf('SkipPush ON');
     end;
    else
    begin
        g_bSkipPush := False;
        printf('SkipPush OFF');
     end;
 *)

(*    State := EmuXB2PC_D3DTS(State);

    HRESULT hRet := g_pD3DDevice8->SetTransform(State, pMatrix);
*)
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_GetTransform

function XTL_EmuIDirect3DDevice8_GetTransform(State: D3DTRANSFORMSTATETYPE; pMatrix: D3DMATRIX): HRESULT;
var
  hRet: HRESULT;
begin
  hret := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetTransform' +
    #13#10'(' +
    #13#10'   State               : 0x%.08X' +
    #13#10'   pMatrix             : 0x%.08X' +
    #13#10');',
    [@State, @pMatrix]);

    { TODO : Need to be translated to delphi }
    (*State := EmuXB2PC_D3DTS(State);

    HRESULT hRet := g_pD3DDevice8->GetTransform(State, pMatrix);
*)
  EmuSwapFS(); // XBox FS
  Result := hRet;
end;

// func: EmuIDirect3DVertexBuffer8_Lock

procedure XTL_EmuIDirect3DVertexBuffer8_Lock;
(*(
    X_D3DVertexBuffer  *ppVertexBuffer,
    UINT                OffsetToLock,
    UINT                SizeToLock,
    BYTE              **ppbData,
    DWORD               Flags
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DVertexBuffer8_Lock'
           #13#10'('
           #13#10'   ppVertexBuffer      : 0x%.08X'
           #13#10'   OffsetToLock        : 0x%.08X'
           #13#10'   SizeToLock          : 0x%.08X'
           #13#10'   ppbData             : 0x%.08X'
           #13#10'   Flags               : 0x%.08X'
           #13#10');',
           ppVertexBuffer, OffsetToLock, SizeToLock, ppbData, Flags);

    IDirect3DVertexBuffer8 *pVertexBuffer8 := ppVertexBuffer->EmuVertexBuffer8;

    HRESULT hRet := pVertexBuffer8->Lock(OffsetToLock, SizeToLock, ppbData, Flags);

    if(FAILED(hRet)) then
        EmuWarning('VertexBuffer Lock Failed!');

    EmuSwapFS();   // XBox FS

    Exit;    *)
end;

// func: EmuIDirect3DVertexBuffer8_Lock2
(*BYTE* WINAPI XTL.EmuIDirect3DVertexBuffer8_Lock2
(
    X_D3DVertexBuffer  *ppVertexBuffer,
    DWORD               Flags
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DVertexBuffer8_Lock2'
           #13#10'('
           #13#10'   ppVertexBuffer      : 0x%.08X'
           #13#10'   Flags               : 0x%.08X'
           #13#10');',
           ppVertexBuffer, Flags);

    IDirect3DVertexBuffer8 *pVertexBuffer8 := ppVertexBuffer->EmuVertexBuffer8;

    BYTE *pbData := 0;

    HRESULT hRet := pVertexBuffer8->Lock(0, 0, @pbData, EmuXB2PC_D3DLock(Flags));	// Fixed flags check, Battlestar Galactica now displays graphics correctly

    EmuSwapFS();   // XBox FS

    Result:= pbData;
 end;       *)

// func: EmuIDirect3DDevice8_GetStreamSource2
(*XTL.X_D3DVertexBuffer* WINAPI XTL.EmuIDirect3DDevice8_GetStreamSource2
(
    UINT  StreamNumber,
    UINT *pStride
)
begin
    EmuSwapFS();

    // debug trace
    DbgPrintf( 'EmuD3D8 (0x%.08X): EmuIDirect3DDevice8_GetStreamSource2'
               #13#10'('
               #13#10'   StreamNumber               : 0x%.08X'
               #13#10'   pStride                    : 0x%.08X'
               #13#10');',
               StreamNumber, pStride);

    EmuWarning('Not correctly implemented yet!');
    X_D3DVertexBuffer* pVertexBuffer;
    g_pD3DDevice8->GetStreamSource(StreamNumber, (struct XTL.IDirect3DVertexBuffer8 )@pVertexBuffer, pStride);

    EmuSwapFS();
    Result:= pVertexBuffer;
 end;                   *)

// func: EmuIDirect3DDevice8_SetStreamSource

function XTL_EmuIDirect3DDevice8_SetStreamSource: HRESULT;
var
  hRet: HRESULT;
    (*StreamNumber : UINT;
    pStreamData : X_D3DVertexBuffer;
    Stride : UINT; *)
begin
  hret := 0;

  EmuSwapFS(); // Win2k/XP FS

{ TODO : Need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetStreamSource'
           #13#10'('
           #13#10'   StreamNumber        : 0x%.08X'
           #13#10'   pStreamData         : 0x%.08X (0x%.08X)'
           #13#10'   Stride              : 0x%.08X'
           #13#10');',
           StreamNumber, pStreamData, (pStreamData <> 0) ? pStreamData->EmuVertexBuffer8 : 0, Stride);

    if(StreamNumber = 0) then
        g_pVertexBuffer := pStreamData;

    IDirect3DVertexBuffer8 *pVertexBuffer8 := 0;

    if(pStreamData <> 0) then
    begin
        EmuVerifyResourceIsRegistered(pStreamData);

        pVertexBuffer8 := pStreamData->EmuVertexBuffer8;
        pVertexBuffer8->Unlock();
     end;

    #ifdef _DEBUG_TRACK_VB
    if(pStreamData <> 0) then
    begin
        g_bVBSkipStream := g_VBTrackDisable.exists(pStreamData->EmuVertexBuffer8);
     end;
    //endif

    HRESULT hRet := g_pD3DDevice8->SetStreamSource(StreamNumber, pVertexBuffer8, Stride);

    if(FAILED(hRet)) then
        CxbxKrnlCleanup('SetStreamSource Failed!');
*)
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_SetVertexShader

function XTL_EmuIDirect3DDevice8_SetVertexShader(aHandle: DWord): HRESULT;
var
  hRet: HRESULT;
  RealHandle: DWORD;
begin
  RealHandle := 0;
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexShader' +
    #13#10'(' +
    #13#10'   Handle              : 0x%.08X' +
    #13#10');',
    [aHandle]);

{ TODO : need to be translated to delphi }
(*  hRet := D3D_OK; *)

  g_CurrentVertexShader := aHandle;

    { What have you been trying to do here?  --- CXBX COMMENTS
    XTL.D3DXVECTOR4 vOffset;
    XTL.D3DXVECTOR4 vScale;

    EmuSwapFS();
    EmuIDirect3DDevice8_GetViewportOffsetAndScale(@vOffset, @vScale);
    EmuSwapFS();
    }

  if (g_VertexShaderConstantMode <> X_VSCM_NONERESERVED) then
  begin
        //g_pD3DDevice8.SetVertexShaderConstant( 58, &vScale, 1 );   -- MARKED OUT IN CXBX
        //g_pD3DDevice8->SetVertexShaderConstant( 59, &vOffset, 1 );  -- MARKED OUT IN CXBX
  end;

  if (VshHandleIsVertexShader(aHandle)) then
  begin
    { TODO : Need to be translated to delphi }
    (*RealHandle := VshHandleGetVertexShader(Handle)) - > Handle) - > Handle; *)
  end
  else
  begin
    RealHandle := aHandle;
  end;
  hRet := g_pD3DDevice8.SetVertexShader(RealHandle);

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_DrawVertices

procedure XTL_EmuIDirect3DDevice8_DrawVertices;
(*(
    X_D3DPRIMITIVETYPE PrimitiveType,
    UINT               StartVertex,
    UINT               VertexCount
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_DrawVertices'
           #13#10'('
           #13#10'   PrimitiveType       : 0x%.08X'
           #13#10'   StartVertex         : 0x%.08X'
           #13#10'   VertexCount         : 0x%.08X'
           #13#10');',
           PrimitiveType, StartVertex, VertexCount);

    EmuUpdateDeferredStates();

    if( (PrimitiveType = X_D3DPT_QUADSTRIP) or (PrimitiveType = X_D3DPT_POLYGON) ) then
        EmuWarning('Unsupported PrimitiveType not  (%d)', (DWORD)PrimitiveType);

    UINT PrimitiveCount := EmuD3DVertex2PrimitiveCount(PrimitiveType, VertexCount);

    // Convert from Xbox to PC enumeration
    D3DPRIMITIVETYPE PCPrimitiveType := EmuPrimitiveType(PrimitiveType);

    VertexPatchDesc VPDesc;

    VPDesc.dwVertexCount := VertexCount;
    VPDesc.PrimitiveType := PrimitiveType;
    VPDesc.dwPrimitiveCount := PrimitiveCount;
    VPDesc.dwOffset := StartVertex;
    VPDesc.pVertexStreamZeroData := 0;
    VPDesc.uiVertexStreamZeroStride := 0;
    VPDesc.hVertexShader := g_CurrentVertexShader;

    VertexPatcher VertPatch;

    bool bPatched := VertPatch.Apply(@VPDesc);

    if(IsValidCurrentShader()) then
    begin
        #ifdef _DEBUG_TRACK_VB
        if(g_bVBSkipStream) then
        begin
            g_pD3DDevice8->DrawPrimitive
            (
                PCPrimitiveType,
                StartVertex,
                0
            );
         end;
        else
        begin
        //endif
            g_pD3DDevice8->DrawPrimitive
            (
                PCPrimitiveType,
                StartVertex,
                VPDesc.dwPrimitiveCount
            );
        #ifdef _DEBUG_TRACK_VB
         end;
        //endif
     end;

    VertPatch.Restore();

    EmuSwapFS();   // XBox FS

    Exit;        *)
end;

// func: EmuIDirect3DDevice8_DrawVerticesUP

procedure XTL_EmuIDirect3DDevice8_DrawVerticesUP;
(*(
    X_D3DPRIMITIVETYPE  PrimitiveType,
    UINT                VertexCount,
    CONST PVOID         pVertexStreamZeroData,
    UINT                VertexStreamZeroStride
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_DrawVerticesUP'
           #13#10'('
           #13#10'   PrimitiveType            : 0x%.08X'
           #13#10'   VertexCount              : 0x%.08X'
           #13#10'   pVertexStreamZeroData    : 0x%.08X'
           #13#10'   VertexStreamZeroStride   : 0x%.08X'
           #13#10');',
           PrimitiveType, VertexCount, pVertexStreamZeroData,
           VertexStreamZeroStride);

    EmuUpdateDeferredStates();

    if( (PrimitiveType = X_D3DPT_QUADSTRIP) or (PrimitiveType = X_D3DPT_POLYGON) ) then
        CxbxKrnlCleanup('Unsupported PrimitiveType not  (%d)', (DWORD)PrimitiveType);

    (*
    // DEBUG
    begin
         FLOAT fixer[] =
        begin
            0.0f, 0.0f, 1.0f,
            0.0f, 480.0f, 1.0f,
            640.0f, 0.0f, 1.0f,
            640.0f, 480.0f, 1.0f,
        );

        DWORD *pdwVB := (DWORD)pVertexStreamZeroData;

        for(uint r:=0;r<VertexCount;r++)
        begin
            pdwVB[0] := FtoDW(fixer[r*3+0]);
            pdwVB[1] := FtoDW(fixer[r*3+1]);
            pdwVB[2] := FtoDW(fixer[r*3+2]);
            pdwVB[5] := $FFFFFFFF;

            FLOAT px := DWtoF(pdwVB[0]);
            FLOAT py := DWtoF(pdwVB[1]);
            FLOAT pz := DWtoF(pdwVB[2]);
            FLOAT rhw := DWtoF(pdwVB[3]);
            DWORD dwDiffuse := pdwVB[5];
            DWORD dwSpecular := pdwVB[4];
            FLOAT tx := DWtoF(pdwVB[6]);
            FLOAT ty := DWtoF(pdwVB[7]);

            //D3DFVF_POSITION_MASK

            printf('%.02d XYZ        : begin %.08f, %.08f, %.08f end;', r, px, py, pz);
            printf('%.02d RHW        : %f', r, rhw);
            printf('%.02d dwDiffuse  : 0x%.08X', r, dwDiffuse);
            printf('%.02d dwSpecular : 0x%.08X', r, dwSpecular);
            printf('%.02d Tex1       : begin %.08f, %.08f end;', r, tx, ty);
            printf('');

            pdwVB:= pdwVB + (VertexStreamZeroStride/4);
         end;
     end;
    //*/

    (*
    IDirect3DBaseTexture8 *pTexture := 0;

    g_pD3DDevice8->GetTexture(0, @pTexture);

    if(pTexture <> 0) then
    begin
         integer dwDumpTexture := 0;

         szBuffer: array[0..255-1] of Char;

        StrFmt(szBuffer, 'C:\Aaron\Textures\Texture-Active%.03d.bmp', dwDumpTexture++);

        D3DXSaveTextureToFile(szBuffer, D3DXIFF_BMP, pTexture, 0);
     end;
    //*/

    UINT PrimitiveCount := EmuD3DVertex2PrimitiveCount(PrimitiveType, VertexCount);

    // Convert from Xbox to PC enumeration
    D3DPRIMITIVETYPE PCPrimitiveType := EmuPrimitiveType(PrimitiveType);

    VertexPatchDesc VPDesc;

    VPDesc.dwVertexCount := VertexCount;
    VPDesc.PrimitiveType := PrimitiveType;
    VPDesc.dwPrimitiveCount := PrimitiveCount;
    VPDesc.dwOffset := 0;
    VPDesc.pVertexStreamZeroData := pVertexStreamZeroData;
    VPDesc.uiVertexStreamZeroStride := VertexStreamZeroStride;
    VPDesc.hVertexShader := g_CurrentVertexShader;

    VertexPatcher VertPatch;

    bool bPatched := VertPatch.Apply(@VPDesc);

    if (IsValidCurrentShader()) then
    begin
        #ifdef _DEBUG_TRACK_VB
        if( not g_bVBSkipStream) then
        begin
        //endif

        g_pD3DDevice8->DrawPrimitiveUP
        (
            PCPrimitiveType,
            VPDesc.dwPrimitiveCount,
            VPDesc.pVertexStreamZeroData,
            VPDesc.uiVertexStreamZeroStride
        );

        #ifdef _DEBUG_TRACK_VB
         end;
        //endif
     end;

    VertPatch.Restore();

    EmuSwapFS();   // XBox FS

    Exit;                 *)
end;

// func: EmuIDirect3DDevice8_DrawIndexedVertices

function XTL_EmuIDirect3DDevice8_DrawIndexedVertices: HRESULT;
(*(
    X_D3DPRIMITIVETYPE  PrimitiveType,
    UINT                VertexCount,
    CONST PWORD         pIndexData
) *)
begin
  EmuSwapFS(); // Win2k/XP FS

{ TODO -oDxbx : need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_DrawIndexedVertices'
           #13#10'('
           #13#10'   PrimitiveType       : 0x%.08X'
           #13#10'   VertexCount         : 0x%.08X'
           #13#10'   pIndexData          : 0x%.08X'
           #13#10');',
           PrimitiveType, VertexCount, pIndexData);

    // update index buffer, if necessary
    if(g_pIndexBuffer <> 0 and g_pIndexBuffer->Lock = X_D3DRESOURCE_LOCK_FLAG_NOSIZE) then
    begin
        DWORD dwSize := VertexCount*2;   // 16-bit indices

        HRESULT hRet = g_pD3DDevice8->CreateIndexBuffer
        (
            dwSize, 0, D3DFMT_INDEX16, D3DPOOL_MANAGED,
            @g_pIndexBuffer->EmuIndexBuffer8
        );

        if(FAILED(hRet)) then
            CxbxKrnlCleanup('CreateIndexBuffer Failed!');

        BYTE *pData := 0;

        hRet := g_pIndexBuffer->EmuIndexBuffer8->Lock(0, dwSize, @pData, 0);

        if(FAILED(hRet)) then
            CxbxKrnlCleanup('IndexBuffer Lock Failed!');

        memcpy(pData, g_pIndexBuffer->Data, dwSize);

        g_pIndexBuffer->EmuIndexBuffer8->Unlock();

        g_pIndexBuffer->Data := (ULONG)pData;

        hRet := g_pD3DDevice8->SetIndices(g_pIndexBuffer->EmuIndexBuffer8, g_dwBaseVertexIndex);

        if(FAILED(hRet)) then
            CxbxKrnlCleanup('SetIndices Failed!');
     end;

    EmuUpdateDeferredStates();

    if( (PrimitiveType = X_D3DPT_QUADLIST) or (PrimitiveType = X_D3DPT_QUADSTRIP) or (PrimitiveType = X_D3DPT_POLYGON) ) then
        EmuWarning('Unsupported PrimitiveType not  (%d)', (DWORD)PrimitiveType);

    UINT PrimitiveCount := EmuD3DVertex2PrimitiveCount(PrimitiveType, VertexCount);

    // Convert from Xbox to PC enumeration
    D3DPRIMITIVETYPE PCPrimitiveType := EmuPrimitiveType(PrimitiveType);

    VertexPatchDesc VPDesc;

    VPDesc.dwVertexCount := VertexCount;
    VPDesc.PrimitiveType := PrimitiveType;
    VPDesc.dwPrimitiveCount := PrimitiveCount;
    VPDesc.dwOffset := 0;
    VPDesc.pVertexStreamZeroData := 0;
    VPDesc.uiVertexStreamZeroStride := 0;
    VPDesc.hVertexShader := g_CurrentVertexShader;

    VertexPatcher VertPatch;

    bool bPatched := VertPatch.Apply(@VPDesc);

    #ifdef _DEBUG_TRACK_VB
    if( not g_bVBSkipStream) then
    begin
    //endif

    bool bActiveIB := False;

    IDirect3DIndexBuffer8 *pIndexBuffer := 0;

    // check if there is an active index buffer
    begin
        UINT BaseIndex := 0;

        g_pD3DDevice8->GetIndices(@pIndexBuffer, @BaseIndex);

        if(pIndexBuffer <> 0) then
        begin
            bActiveIB := true;
            pIndexBuffer->Release();
         end;
     end;

    UINT uiNumVertices := 0;
    UINT uiStartIndex := 0;

    // TODO: caching (if it becomes noticably slow to recreate the buffer each time)
    if( not bActiveIB) then
    begin
        g_pD3DDevice8->CreateIndexBuffer(VertexCount*2, D3DUSAGE_WRITEONLY, D3DFMT_INDEX16, D3DPOOL_MANAGED, @pIndexBuffer);

        if(pIndexBuffer = 0) then
            CxbxKrnlCleanup('Could not create index buffer not  (%d bytes)', VertexCount*2);

        BYTE *pbData := 0;

        pIndexBuffer->Lock(0, 0, @pbData, 0);

        if(pbData = 0) then
            CxbxKrnlCleanup('Could not lock index buffer!');

        memcpy(pbData, pIndexData, VertexCount*2);

        pIndexBuffer->Unlock();

        g_pD3DDevice8->SetIndices(pIndexBuffer, 0);

        uiNumVertices := VertexCount;
        uiStartIndex := 0;
     end;
    else
    begin
        uiNumVertices := ((DWORD)pIndexData)/2 + VertexCount;
        uiStartIndex := ((DWORD)pIndexData)/2;
     end;

    if(IsValidCurrentShader()) then
    begin
        g_pD3DDevice8->DrawIndexedPrimitive
        (
            PCPrimitiveType, 0, uiNumVertices, uiStartIndex, VPDesc.dwPrimitiveCount
        );
     end;

    if( not bActiveIB) then
    begin
        g_pD3DDevice8->SetIndices(0, 0);
        pIndexBuffer->Release();
     end;

    #ifdef _DEBUG_TRACK_VB
     end;
    //endif

    VertPatch.Restore();
*)
  EmuSwapFS(); // XBox FS
  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_DrawIndexedVerticesUP

procedure XTL_EmuIDirect3DDevice8_DrawIndexedVerticesUP;
(*(
    X_D3DPRIMITIVETYPE  PrimitiveType,
    UINT                VertexCount,
    CONST PVOID         pIndexData,
    CONST PVOID         pVertexStreamZeroData,
    UINT                VertexStreamZeroStride
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_DrawIndexedVerticesUP'
           #13#10'('
           #13#10'   PrimitiveType            : 0x%.08X'
           #13#10'   VertexCount              : 0x%.08X'
           #13#10'   pIndexData               : 0x%.08X'
           #13#10'   pVertexStreamZeroData    : 0x%.08X'
           #13#10'   VertexStreamZeroStride   : 0x%.08X'
           #13#10');',
           PrimitiveType, VertexCount, pIndexData, pVertexStreamZeroData, VertexStreamZeroStride);

    // update index buffer, if necessary
    if(g_pIndexBuffer <> 0 and g_pIndexBuffer->Lock = X_D3DRESOURCE_LOCK_FLAG_NOSIZE) then
        CxbxKrnlCleanup('g_pIndexBuffer <> 0');

    EmuUpdateDeferredStates();

    if( (PrimitiveType = X_D3DPT_QUADLIST) or (PrimitiveType = X_D3DPT_QUADSTRIP) or (PrimitiveType = X_D3DPT_POLYGON) ) then
        EmuWarning('Unsupported PrimitiveType not  (%d)', (DWORD)PrimitiveType);

    UINT PrimitiveCount := EmuD3DVertex2PrimitiveCount(PrimitiveType, VertexCount);

    // Convert from Xbox to PC enumeration
    D3DPRIMITIVETYPE PCPrimitiveType := EmuPrimitiveType(PrimitiveType);

    VertexPatchDesc VPDesc;

    VPDesc.dwVertexCount := VertexCount;
    VPDesc.PrimitiveType := PrimitiveType;
    VPDesc.dwPrimitiveCount := PrimitiveCount;
    VPDesc.dwOffset := 0;
    VPDesc.pVertexStreamZeroData := pVertexStreamZeroData;
    VPDesc.uiVertexStreamZeroStride := VertexStreamZeroStride;
    VPDesc.hVertexShader := g_CurrentVertexShader;

    VertexPatcher VertPatch;

    bool bPatched := VertPatch.Apply(@VPDesc);

    #ifdef _DEBUG_TRACK_VB
    if( not g_bVBSkipStream) then
    begin
    //endif

    if (IsValidCurrentShader()) then
    begin
        g_pD3DDevice8->DrawIndexedPrimitiveUP
        (
            PCPrimitiveType, 0, VertexCount, VPDesc.dwPrimitiveCount, pIndexData, D3DFMT_INDEX16, VPDesc.pVertexStreamZeroData, VPDesc.uiVertexStreamZeroStride
        );
     end;

    #ifdef _DEBUG_TRACK_VB
     end;
    //endif

    VertPatch.Restore();

    EmuSwapFS();   // XBox FS

    Exit;               *)
end;

// func: EmuIDirect3DDevice8_SetLight

function XTL_EmuIDirect3DDevice8_SetLight(Index: DWORD; pLight: D3DLIGHT8): HRESULT;
var
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetLight' +
    #13#10'(' +
    #13#10'   Index               : 0x%.08X' +
    #13#10'   pLight              : 0x%.08X' +
    #13#10');',
    [Index, @pLight]);

  hRet := g_pD3DDevice8.SetLight(Index, pLight);
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_SetMaterial

function XTL_EmuIDirect3DDevice8_SetMaterial(pMaterial: D3DMATERIAL8): HRESULT;
var
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetMaterial' +
    #13#10'(' +
    #13#10'   pMaterial           : 0x%.08X' +
    #13#10');',
    [@pMaterial]);

  hRet := g_pD3DDevice8.SetMaterial(pMaterial);
  EmuSwapFS(); // XBox FS
  Result := hRet;
end;

// func: EmuIDirect3DDevice8_LightEnable

function XTL_EmuIDirect3DDevice8_LightEnable(Index: DWORD; bEnable: LongBool): HRESULT;
var
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_LightEnable' +
    #13#10'(' +
    #13#10'   Index               : 0x%.08X' +
    #13#10'   bEnable             : 0x%.08X' +
    #13#10');',
    [Index, bEnable]);

  hRet := g_pD3DDevice8.LightEnable(Index, bEnable);
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_BlockUntilVerticalBlank

procedure EmuIDirect3DDevice8_BlockUntilVerticalBlank;
begin
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_BlockUntilVerticalBlank();');
  Exit;
end;

// func: EmuIDirect3DDevice8_SetRenderTarget

function XTL_EmuIDirect3DDevice8_SetRenderTarget(pRenderTarget: X_D3DSurface;
  pNewZStencil: X_D3DSurface): HRESULT;
var
  hRet: HRESULT;
  pPCRenderTarget: IDirect3DSurface8;
  pPCNewZStencil: IDirect3DSurface8;
begin
  EmuSwapFS(); // Win2k/XP FS

  { TODO : Need to be translated to delphi }
   (* DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetRenderTarget' +
           #13#10'(' +
           #13#10'   pRenderTarget       : 0x%.08X (0x%.08X)' +
           #13#10'   pNewZStencil        : 0x%.08X (0x%.08X)' +
           #13#10');',
           pRenderTarget, (pRenderTarget <> 0) ? pRenderTarget->EmuSurface8 : 0, pNewZStencil,
           (pNewZStencil <> 0) ? pNewZStencil->EmuSurface8 : 0); *)

  pPCRenderTarget := nil;
  pPCNewZStencil := nil;

  if (pRenderTarget <> nil) then
  begin
        { TODO : need to be translated to delphi }
        (*
        EmuVerifyResourceIsRegistered(pRenderTarget);

        pPCRenderTarget := pRenderTarget.EmuSurface8; *)
  end;

  if (pNewZStencil <> nil) then
  begin
        { TODO : need to be translated to delphi }
        (*
        EmuVerifyResourceIsRegistered(pNewZStencil);
        pPCNewZStencil  := pNewZStencil.EmuSurface8; *)
  end;

  // TODO: Follow that stencil!
  hRet := g_pD3DDevice8.SetRenderTarget(pPCRenderTarget, pPCNewZStencil);

  if (FAILED(hRet)) then
    EmuWarning(Format('SetRenderTarget Failed not  (0x%.08X)', [hRet]));

  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3DDevice8_CreatePalette

function XTL_EmuIDirect3DDevice8_CreatePalette: HRESULT;
(*(
    X_D3DPALETTESIZE    Size,
    X_D3DPalette      **ppPalette
) *)
begin
{ TODO -oDxbx : need to be translated to delphi }
(*    *ppPalette := EmuIDirect3DDevice8_CreatePalette2(Size);
*)
  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_CreatePalette2
(*XTL.X_D3DPalette * WINAPI XTL.EmuIDirect3DDevice8_CreatePalette2
(
    X_D3DPALETTESIZE    Size
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_CreatePalette2'
           #13#10'('
           #13#10'   Size                : 0x%.08X'
           #13#10');',
           Size);

    X_D3DPalette *pPalette := new X_D3DPalette();
 
     integer lk[4] =
    begin
        256*SizeOf(D3DCOLOR),    // D3DPALETTE_256
        128*SizeOf(D3DCOLOR),    // D3DPALETTE_128
        64*SizeOf(D3DCOLOR),     // D3DPALETTE_64
        32*SizeOf(D3DCOLOR)      // D3DPALETTE_32
    );

    pPalette->Common := 0;
    pPalette->Lock := $8000BEEF; // emulated reference count for palettes
    pPalette->Data := (DWORD)new uint08[lk[Size]];

    EmuSwapFS();   // XBox FS

    Result:= pPalette;
 end;         *)

// func: EmuIDirect3DDevice8_SetPalette

function XTL_EmuIDirect3DDevice8_SetPalette: HRESULT;
(*(
    DWORD         Stage,
    X_D3DPalette *pPalette
) *)
begin
  EmuSwapFS(); // Win2k/XP FS

{ TODO -oDxbx : need to be translated to delphi }
(*    DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetPalette'
           #13#10'('
           #13#10'   Stage               : 0x%.08X'
           #13#10'   pPalette            : 0x%.08X'
           #13#10');',
           Stage, pPalette);

//    g_pD3DDevice8->SetPaletteEntries(0, (PALETTEENTRY*)(*pPalette->Data);
*)
  EmuWarning('Not setting palette');

  EmuSwapFS(); // XBox FS

  Result := D3D_OK;
end;

// func: EmuIDirect3DDevice8_SetFlickerFilter

procedure XTL_EmuIDirect3DDevice8_SetFlickerFilter(Filter: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetFlickerFilter' +
    #13#10'(' +
    #13#10'   Filter              : 0x%.08X' +
    #13#10');',
    [Filter]);

  EmuWarning('Not setting flicker filter');
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetSoftDisplayFilter

procedure XTL_EmuIDirect3DDevice8_SetSoftDisplayFilter(Enable: Boolean);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetSoftDisplayFilter' +
    #13#10'(' +
    #13#10'   Enable              : 0%10s' +
    #13#10');',
    [BoolToStr(Enable)]);

  EmuWarning('Not setting soft display filter');
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DPalette8_Lock

function XTL_EmuIDirect3DPalette8_Lock: HRESULT;
(*(
    X_D3DPalette   *pThis,
    D3DCOLOR      **ppColors,
    DWORD           Flags
) *)
begin
{ TODO -oDxbx : need to be translated to delphi }
(*    *ppColors := EmuIDirect3DPalette8_Lock2(pThis, Flags);
*)
  Result := D3D_OK;
end;

// func: EmuIDirect3DPalette8_Lock2
(*XTL.D3DCOLOR * WINAPI XTL.EmuIDirect3DPalette8_Lock2
(
    X_D3DPalette   *pThis,
    DWORD           Flags
)
begin
    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf('EmuD3D8 : EmuIDirect3DPalette8_Lock'
           #13#10'('
           #13#10'   pThis               : 0x%.08X'
           #13#10'   Flags               : 0x%.08X'
           #13#10');',
           Flags);

    D3DCOLOR *pColors := (D3DCOLOR)pThis->Data;

    EmuSwapFS();   // XBox FS

    Result:= pColors;
 end; *)

// func: EmuIDirect3DDevice8_GetVertexShaderSize

procedure XTL_EmuIDirect3DDevice8_GetVertexShaderSize;
(*(
    DWORD Handle,
    UINT* pSize
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    DbgPrintf( 'EmuD3D8 : EmuIDirect3DDevice8_GetVertexShaderSize'
               #13#10'('
               #13#10'   Handle               : 0x%.08X'
               #13#10'   pSize                : 0x%.08X'
               #13#10');',
               Handle, pSize);

    if(pSize  and VshHandleIsVertexShader(Handle)) then
    begin
        X_D3DVertexShader *pD3DVertexShader := (X_D3DVertexShader )(Handle and $7FFFFFFF);
        VERTEX_SHADER *pVertexShader := (VERTEX_SHADER )pD3DVertexShader->Handle;
        *pSize := pVertexShader->Size;
     end;
    else if(pSize) then
    begin
        *pSize := 0;
     end;

    EmuSwapFS();   // Xbox FS      *)
end;

// func: EmuIDirect3DDevice8_DeleteVertexShader

procedure XTL_EmuIDirect3DDevice8_DeleteVertexShader(Handle: DWord);
(*var
  RealHandle: DWORD;
  hRet: HRESULT; *)
begin
  EmuSwapFS();

  DbgPrintf('EmuD3D8 (0x%.08X): EmuIDirect3DDevice8_DeleteVertexShader' +
    #13#10'(' +
    #13#10'   Handle                : 0x%.08X' +
    #13#10');',
    [Handle]);

(*  RealHandle := 0;

{ TODO : Need to be translated to delphi }
(*    if(VshHandleIsVertexShader(Handle)) then
    begin
        X_D3DVertexShader *pD3DVertexShader := (X_D3DVertexShader )(Handle and $7FFFFFFF);
        VERTEX_SHADER *pVertexShader := (VERTEX_SHADER )pD3DVertexShader->Handle;

        RealHandle := pVertexShader->Handle;
        CxbxFree(pVertexShader->pDeclaration);

        if(pVertexShader->pFunction) then
        begin
            CxbxFree(pVertexShader->pFunction);
         end;

        FreeVertexDynamicPatch(pVertexShader);

        CxbxFree(pVertexShader);
        CxbxFree(pD3DVertexShader);
     end;

    HRESULT hRet := g_pD3DDevice8->DeleteVertexShader(RealHandle);
*)
  EmuSwapFS();
end;

// func: EmuIDirect3DDevice8_SelectVertexShaderDirect

procedure XTL_EmuIDirect3DDevice8_SelectVertexShaderDirect;
(*(
    X_VERTEXATTRIBUTEFORMAT *pVAF,
    DWORD                    Address
) *)
begin
  EmuSwapFS(); // Win2k/XP FS

    // debug trace
    (*DbgPrintf( 'EmuD3D8 : EmuIDirect3DDevice8_SelectVertexShaderDirect' +
               #13#10'(' +
               #13#10'   pVAF                : 0x%.08X' +
               #13#10'   Address             : 0x%.08X' +
               #13#10');',
               [pVAF,Address]); *)

  DbgPrintf('NOT YET IMPLEMENTED!');

  EmuSwapFS(); // Xbox FS
end;

// func: EmuIDirect3DDevice8_GetShaderConstantMode

procedure XTL_EmuIDirect3DDevice8_GetShaderConstantMode(pMode: DWORD);
begin
{$IFDEF _DEBUG_TRACE}
  EmuSwapFS(); // Win2k/XP FS
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetShaderConstantMode' +
    #13#10'(' +
    #13#10'   pMode               : 0x%.08X' +
    #13#10');',
    [pMode]);
  EmuSwapFS(); // Xbox FS
{$ENDIF}

  { TODO : Need to be translated to delphi }
  (*
    if(pMode) then
    begin
        *pMode := g_VertexShaderConstantMode;
     end;         *)
end;

// func: EmuIDirect3DDevice8_GetVertexShader

procedure XTL_EmuIDirect3DDevice8_GetVertexShader(pHandle: DWORD);
begin
  EmuSwapFS();

  // debug trace
  DbgPrintf('EmuD3D8 (0x%.08X): EmuIDirect3DDevice8_GetVertexShader' +
    #13#10'(' +
    #13#10'   pHandle               : 0x%.08X' +
    #13#10');',
    [pHandle]);

{ TODO : need to be translated to delphi }
(*    if(pHandle) then
    begin
        (pHandle) := g_CurrentVertexShader;
     end;              *)

  EmuSwapFS();
end;

// func: EmuIDirect3DDevice8_GetVertexShaderConstant

procedure XTL_EmuIDirect3DDevice8_GetVertexShaderConstant;
(*(
    INT   Register,
        procedure  *pConstantData,; DWORD ConstantCount
) *)
begin
(*    EmuSwapFS();   // Win2k/XP FS

    // debug trace
    DbgPrintf( 'EmuD3D8 : EmuIDirect3DDevice8_GetVertexShaderConstant'
               #13#10'('
               #13#10'   Register            : 0x%.08X'
               #13#10'   pConstantData       : 0x%.08X'
               #13#10'   ConstantCount       : 0x%.08X'
               #13#10');',
               Register, pConstantData, ConstantCount);

    HRESULT hRet = g_pD3DDevice8->GetVertexShaderConstant
    (
        Register + 96,
        pConstantData,
        ConstantCount
    );

    EmuSwapFS();   // XBox FS    *)
end;

// func: EmuIDirect3DDevice8_SetVertexShaderInputDirect

function XTL_EmuIDirect3DDevice8_SetVertexShaderInputDirect(pVAF: X_VERTEXATTRIBUTEFORMAT;
  StreamCount: UINT; pStreamInputs: X_STREAMINPUT): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  // debug trace
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SelectVertexShaderDirect' +
    #13#10'(' +
    #13#10'   pVAF                : 0x%.08X' +
    #13#10'   StreamCount         : 0x%.08X' +
    #13#10'   pStreamInputs       : 0x%.08X' +
    #13#10');',
    [@pVAF, StreamCount, @pStreamInputs]);

  DbgPrintf('NOT YET IMPLEMENTED!');
  EmuSwapFS(); // Xbox FS
  Result := 0;
end;

// func: EmuIDirect3DDevice8_GetVertexShaderInput

function XTL_EmuIDirect3DDevice8_GetVertexShaderInput(pHandle: DWORD;
  pStreamCount: UINT; pStreamInputs: X_STREAMINPUT): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  // debug trace
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetVertexShaderInput' +
    #13#10'(' +
    #13#10'   pHandle             : 0x%.08X' +
    #13#10'   pStreamCount        : 0x%.08X' +
    #13#10'   pStreamInputs       : 0x%.08X' +
    #13#10');',
    [pHandle, pStreamCount, @pStreamInputs]);

  DbgPrintf('NOT YET IMPLEMENTED!');

  EmuSwapFS(); // Xbox FS
  Result := 0;
end;

// func: EmuIDirect3DDevice8_SetVertexShaderInput

function XTL_EmuIDirect3DDevice8_SetVertexShaderInput(aHandle: DWORD;
  StreamCount: UINT; pStreamInputs: X_STREAMINPUT): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

    // debug trace
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetVertexShaderInput' +
    #13#10'(' +
    #13#10'   Handle              : 0x%.08X' +
    #13#10'   StreamCount         : 0x%.08X' +
    #13#10'   pStreamInputs       : 0x%.08X' +
    #13#10');',
    [aHandle, StreamCount, @pStreamInputs]);

  DbgPrintf('NOT YET IMPLEMENTED!');
  EmuSwapFS(); // Xbox FS
  Result := 0;
end;


// func: EmuIDirect3DDevice8_RunVertexStateShader

procedure XTL_EmuIDirect3DDevice8_RunVertexStateShader(Address: DWORD; pData: FLOAT);
begin
  EmuSwapFS(); // Win2k/XP FS

    // debug trace
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_RunVertexStateShader' +
    #13#10'(' +
    #13#10'   Address              : 0x%.08X' +
    #13#10'   pData                : 0x%.08X' +
    #13#10');',
    [Address, pData]);

  DbgPrintf('NOT YET IMPLEMENTED!');

  EmuSwapFS(); // Xbox FS
end;

// func: EmuIDirect3DDevice8_LoadVertexShaderProgram

procedure XTL_EmuIDirect3DDevice8_LoadVertexShaderProgram(pFunction: DWORD; Address: DWORD);
begin
  EmuSwapFS(); // Win2k/XP FS

    // debug trace
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_LoadVertexShaderProgram' +
    #13#10'(' +
    #13#10'   pFunction           : 0x%.08X' +
    #13#10'   Address             : 0x%.08X' +
    #13#10');',
    [pFunction, Address]);

  DbgPrintf('NOT YET IMPLEMENTED!');

  EmuSwapFS(); // Xbox FS
end;

// func: EmuIDirect3DDevice8_GetVertexShaderType

procedure XTL_EmuIDirect3DDevice8_GetVertexShaderType(aHandle: DWORD;
  pType: DWORD);
begin
  EmuSwapFS(); // Win2k/XP FS

    // debug trace
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetVertexShaderType' +
    #13#10'(' +
    #13#10'   Handle               : 0x%.08X' +
    #13#10'   pType                : 0x%.08X' +
    #13#10');',
    [aHandle, pType]);

    { TODO : need to be translated to delphi }
    (*if(pType and VshHandleIsVertexShader(Handle)) then
    begin
        *pType := ((VERTEX_SHADER )(VshHandleGetVertexShader(Handle))->Handle)->cType;
     end; *)

  EmuSwapFS(); // Xbox FS
end;

// func: EmuIDirect3DDevice8_GetVertexShaderDeclaration

function XTL_EmuIDirect3DDevice8_GetVertexShaderDeclaration(Handle: DWORD;
  pData: PVOID; pSizeOfData: DWORD): HRESULT;
var
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

    // debug trace
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetVertexShaderDeclaration' +
    #13#10'(' +
    #13#10'   Handle               : 0x%.08X' +
    #13#10'   pData                : 0x%.08X' +
    #13#10'   pSizeOfData          : 0x%.08X' +
    #13#10');',
    [Handle, pData, pSizeOfData]);

  hRet := D3DERR_INVALIDCALL;

(*
    if(pSizeOfData and VshHandleIsVertexShader(Handle)) then
    begin
        VERTEX_SHADER *pVertexShader := (VERTEX_SHADER )(VshHandleGetVertexShader(Handle))->Handle;
        if(pSizeOfData < pVertexShader->DeclarationSize or  not pData) then
        begin
            *pSizeOfData := pVertexShader->DeclarationSize;

            hRet :=  not pData ? D3D_OK : D3DERR_MOREDATA;
         end;
        else
        begin
            memcpy(pData, pVertexShader->pDeclaration, pVertexShader->DeclarationSize);
            hRet := D3D_OK;
         end;
     end;
*)

  EmuSwapFS(); // Xbox FS
  Result := hRet;
end;

// func: EmuIDirect3DDevice8_GetVertexShaderFunction

function XTL_EmuIDirect3DDevice8_GetVertexShaderFunction(Handle: DWORD; pData: PVOID; pSizeOfData: DWORD): HRESULT;
var
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  // debug trace
  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_GetVertexShaderFunction' +
    #13#10'(' +
    #13#10'   Handle               : 0x%.08X' +
    #13#10'   pData                : 0x%.08X' +
    #13#10'   pSizeOfData          : 0x%.08X' +
    #13#10');',
    [Handle, pData, pSizeOfData]);

  hRet := D3DERR_INVALIDCALL;

{ TODO : Need to be translated to delphi }
(*    if(pSizeOfData and VshHandleIsVertexShader(Handle)) then
    begin
        VERTEX_SHADER *pVertexShader := (VERTEX_SHADER )(VshHandleGetVertexShader(Handle))->Handle;
        if(pSizeOfData < pVertexShader->FunctionSize or  not pData) then
        begin
            *pSizeOfData := pVertexShader->FunctionSize;

            hRet :=  not pData ? D3D_OK : D3DERR_MOREDATA;
         end;
        else
        begin
            memcpy(pData, pVertexShader->pFunction, pVertexShader->FunctionSize);
            hRet := D3D_OK;
         end;
     end;
*)

  EmuSwapFS(); // Xbox FS
  Result := hRet;
end;

// func: EmuIDirect3D8_AllocContiguousMemory
(*PVOID WINAPI XTL.EmuIDirect3D8_AllocContiguousMemory
(
    SIZE_T dwSize,
    DWORD dwAllocAttributes
)
begin
    EmuSwapFS();   // Win2k/XP FS

    // debug trace
    DbgPrintf( 'EmuD3D8 : EmuIDirect3D8_AllocContiguousMemory'
               #13#10'('
               #13#10'   dwSize               : 0x%.08X'
               #13#10'   dwAllocAttributes    : 0x%.08X'
               #13#10');',
               dwSize,dwAllocAttributes);

 //
    // NOTE: Kludgey (but necessary) solution:
    //
    // Since this memory must be aligned on a page boundary, we must allocate an extra page
    // so that we can return a valid page aligned pointer
    //

    PVOID pRet := CxbxMalloc(dwSize + 0x1000);

    // align to page boundary
    begin
        DWORD dwRet := (DWORD)pRet;

        dwRet:= dwRet + 0x1000 - dwRet%0x1000;

        g_AlignCache.insert(dwRet, pRet);

        pRet := (PVOID)dwRet;
     end;

    DbgPrintf('EmuD3D8 : EmuIDirect3D8_AllocContiguousMemory returned 0x%.08X', pRet);

    EmuSwapFS();   // Xbox FS

    Result:= pRet;
 end;     *)

// func: EmuIDirect3DTexture8_GetLevelDesc

function XTL_EmuIDirect3DTexture8_GetLevelDesc(Level: UINT; pDesc: X_D3DSURFACE_DESC): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

    // debug trace
  DbgPrintf(Format('EmuD3D8 : EmuIDirect3DTexture8_GetLevelDesc' +
    #13#10'(' +
    #13#10'   Level                : 0x%.08%' +
    #13#10'   pDesc                : 0x%.08%' +
    #13#10');',
    [Level, @pDesc]));

  EmuSwapFS(); // Xbox FS
  Result := D3D_OK;
end;

// func: EmuIDirect3D8_CheckDeviceMultiSampleType

function XTL_EmuIDirect3D8_CheckDeviceMultiSampleType(Adapter: UINT;
  DeviceType: D3DDEVTYPE; SurfaceFormat: D3DFORMAT; Windowed: LongBool;
  MultiSampleType: D3DMULTISAMPLE_TYPE): HRESULT;
var
  hRet: HRESULT;
  (*PCSurfaceFormat: D3DFORMAT; *)
begin
  hRet := 0;

  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3D8_CheckDeviceMultiSampleType' +
    #13#10'(' +
    #13#10'   Adapter              : 0x%.08X' +
    #13#10'   DeviceType           : 0x%.08X' +
    #13#10'   SurfaceFormat        : 0x%.08X' +
    #13#10'   Windowed             : 0x%.08X' +
    #13#10'   MultiSampleType      : 0x%.08X' +
    #13#10');',
    [Adapter, @DeviceType, @SurfaceFormat, Windowed, @MultiSampleType]);

{ TODO : need to be translated to delphi }
(*  if (Adapter <> D3DADAPTER_DEFAULT) then
  begin
    EmuWarning('Adapter is not D3DADAPTER_DEFAULT, correcting!');
    Adapter := D3DADAPTER_DEFAULT;
  end;

(*  if (DeviceType = D3DDEVTYPE_FORCE_DWORD) then
    EmuWarning('DeviceType := D3DDEVTYPE_FORCE_DWORD');

  // Convert SurfaceFormat (Xbox->PC)
   PCSurfaceFormat := EmuXB2PC_D3DSurfaceFormat);

    // TODO: HACK: Devices that don't support this should somehow emulate it!
if (PCSurfaceFormat = D3DFMT_D16) then
begin
  EmuWarning('D3DFMT_16 is an unsupported texture format!');
  PCSurfaceFormat := D3DFMT_X8R8G8B8;
end
else if (PCSurfaceFormat = D3DFMT_P8) then
begin
  EmuWarning('D3DFMT_P8 is an unsupported texture format!');
  PCSurfaceFormat := D3DFMT_X8R8G8B8;
end
else if (PCSurfaceFormat = D3DFMT_D24S8) then
begin
  EmuWarning('D3DFMT_D24S8 is an unsupported texture format!');
  PCSurfaceFormat := D3DFMT_X8R8G8B8;
end;

if (Windowed <> False) then
  Windowed := False;

 // TODO: Convert from Xbox to PC!!
if (MultiSampleType = 0 x0011) then
  MultiSampleType := D3DMULTISAMPLE_NONE;
else
  CxbxKrnlCleanup('EmuIDirect3D8_CheckDeviceMultiSampleType Unknown MultiSampleType not  (%d)', MultiSampleType);

 // Now call the real CheckDeviceMultiSampleType with the corrected parameters.
  HRESULT hRet = g_pD3D8 - > CheckDeviceMultiSampleType
    (
    Adapter,
    DeviceType,
    SurfaceFormat,
    Windowed,
    MultiSampleType
    );
*)


  EmuSwapFS(); // Xbox FS

  Result := hRet;
end;

// func: EmuIDirect3D8_GetDeviceCaps

function XTL_EmuIDirect3D8_GetDeviceCaps(Adapter: UINT; DeviceType: D3DDEVTYPE; pCaps: D3DCAPS8): HRESULT;
var
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3D8_GetDeviceCaps' +
    #13#10'(' +
    #13#10'   Adapter                   : 0x%.08X' +
    #13#10'   DeviceType                : 0x%.08X' +
    #13#10'   pCaps                     : 0x%.08X' +
    #13#10');',
    [Adapter, @DeviceType, @pCaps]);

  hRet := g_pD3D8.GetDeviceCaps(Adapter, DeviceType, pCaps);
  EmuSwapFS(); // XBox FS

  Result := hRet;
end;

// func: EmuIDirect3D8_SetPushBufferSize

function XTL_EmuIDirect3D8_SetPushBufferSize(PushBufferSize: DWORD; KickOffSize: DWORD): HRESULT;
var
  hRet: HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3D8_SetPushBufferSize' +
    #13#10'(' +
    #13#10'   PushBufferSize            : 0x%.08X' +
    #13#10'   KickOffSize               : 0x%.08X' +
    #13#10');',
    [PushBufferSize, KickOffSize]);

  hRet := D3D_OK;

  // This is a Xbox extension, meaning there is no pc counterpart.
  EmuSwapFS(); // XBox FS
  Result := hRet;
end;

// func: EmuIDirect3DDevice8_InsertFence

function XTL_EmuIDirect3DDevice8_InsertFence: DWORD;
var
  dwRet: DWord;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_InsertFence();');

  // TODO: Actually implement this
  dwRet := $8000BEEF;
  EmuSwapFS(); // XBox FS
  Result := dwRet;
end;

// func: EmuIDirect3DDevice8_BlockOnFence

procedure XTL_EmuIDirect3DDevice8_BlockOnFence(Fence: DWord);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_BlockOnFence' +
    #13#10'(' +
    #13#10'   Fence                     : 0x%.08X' +
    #13#10');',
    [Fence]);

  // TODO: Implement
  EmuSwapFS(); // XBox FS*)
end;

// func: EmuIDirect3DResource8_BlockUntilNotBusy

procedure XTL_EmuIDirect3DResource8_BlockUntilNotBusy(pThis: X_D3DResource);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DResource8_BlockUntilNotBusy' +
    #13#10'(' +
    #13#10'   pThis                     : 0x%.08X' +
    #13#10');',
    [pThis]);

  // TODO: Implement
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DVertexBuffer8_GetDesc

procedure XTL_EmuIDirect3DVertexBuffer8_GetDesc(pThis: X_D3DVertexBuffer; pDesc: D3DVERTEXBUFFER_DESC);
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DVertexBuffer8_GetDesc' +
    #13#10'(' +
    #13#10'   pThis                     : 0x%.08X' +
    #13#10'   pDesc                     : 0x%.08X' +
    #13#10');',
    [pThis, @pDesc]);

  // TODO: Implement
  EmuSwapFS(); // XBox FS
end;

// func: EmuIDirect3DDevice8_SetScissors

function XTL_EmuIDirect3DDevice8_SetScissors(Count: DWORD;
  Exclusive: BOOL; const pRects: D3DRECT): HRESULT;
begin
  EmuSwapFS(); // Win2k/XP FS

  DbgPrintf('EmuD3D8 : EmuIDirect3DDevice8_SetScissors' +
    #13#10'(' +
    #13#10'   Count                     : 0x%.08X' +
    #13#10'   Exclusive                 : 0x%.08X' +
    #13#10'   pRects                    : 0x%.08X' +
    #13#10');',
    [Count, Exclusive, @pRects]);

  // TODO: Implement

  EmuSwapFS(); // XBox FS

  Result := D3D_OK;
end;

end.

