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

unit uXBController;

interface

{$INCLUDE Dxbx.inc}

uses
  Windows
  , SysUtils
  // 3rd party
  , DirectInput
  , XInput
  // Dxbx
  , uLog
  , uError;

type
   // Xbox Controller Object IDs
  XBCtrlObject = (
    // Analog Axis
    XBCTRL_OBJECT_LTHUMBPOSX = 0,
    XBCTRL_OBJECT_LTHUMBNEGX,
    XBCTRL_OBJECT_LTHUMBPOSY,
    XBCTRL_OBJECT_LTHUMBNEGY,
    XBCTRL_OBJECT_RTHUMBPOSX,
    XBCTRL_OBJECT_RTHUMBNEGX,
    XBCTRL_OBJECT_RTHUMBPOSY,
    XBCTRL_OBJECT_RTHUMBNEGY,
    // Analog Buttons
    XBCTRL_OBJECT_A,
    XBCTRL_OBJECT_B,
    XBCTRL_OBJECT_X,
    XBCTRL_OBJECT_Y,
    XBCTRL_OBJECT_BLACK,
    XBCTRL_OBJECT_WHITE,
    XBCTRL_OBJECT_LTRIGGER,
    XBCTRL_OBJECT_RTRIGGER,
    // Digital Buttons
    XBCTRL_OBJECT_DPADUP,
    XBCTRL_OBJECT_DPADDOWN,
    XBCTRL_OBJECT_DPADLEFT,
    XBCTRL_OBJECT_DPADRIGHT,
    XBCTRL_OBJECT_BACK,
    XBCTRL_OBJECT_START,
    XBCTRL_OBJECT_LTHUMB,
    XBCTRL_OBJECT_RTHUMB);

const
  // Total number of components
  XBCTRL_OBJECT_COUNT = (Ord(High(XBCtrlObject)) - Ord(Low(XBCtrlObject)) + 1);
  XBCTRL_MAX_DEVICES = XBCTRL_OBJECT_COUNT;

{///****************************************************************** }
{///* offsets into analog button array }
{///****************************************************************** }
const
  XINPUT_GAMEPAD_A = 0;
  XINPUT_GAMEPAD_B = 1;
  XINPUT_GAMEPAD_X = 2;
  XINPUT_GAMEPAD_Y = 3;
  XINPUT_GAMEPAD_BLACK = 4;
  XINPUT_GAMEPAD_WHITE = 5;
  XINPUT_GAMEPAD_LEFT_TRIGGER = 6;
  XINPUT_GAMEPAD_RIGHT_TRIGGER = 7;

{///****************************************************************** }
{///* masks for digital buttons }
{///****************************************************************** }
const
  XINPUT_GAMEPAD_DPAD_UP = $00000001;
  XINPUT_GAMEPAD_DPAD_DOWN = $00000002;
  XINPUT_GAMEPAD_DPAD_LEFT = $00000004;
  XINPUT_GAMEPAD_DPAD_RIGHT = $00000008;
  XINPUT_GAMEPAD_START = $00000010;
  XINPUT_GAMEPAD_BACK = $00000020;
  XINPUT_GAMEPAD_LEFT_THUMB = $00000040;
  XINPUT_GAMEPAD_RIGHT_THUMB = $00000080;



type
  // DirectInput Enumeration Types
  XBCtrlState = (
    XBCTRL_STATE_NONE = 0,
    XBCTRL_STATE_CONFIG,
    XBCTRL_STATE_LISTEN);

  XBCtrlObjectCfg = record
    dwDevice: Integer; // offset into m_InputDevice
    dwInfo: Integer; // extended information, depending on dwFlags
    dwFlags: Integer; // flags explaining the data format
  end;


// * XINPUT_GAMEPAD
  _XINPUT_GAMEPAD = record
    wButtons: WORD;
    bAnalogButtons: array[0..7] of BYTE;
    sThumbLX: SHORT;
    sThumbLY: SHORT;
    sThumbRX: SHORT;
    sThumbRY: SHORT;
  end;

  PXINPUT_GAMEPAD = _XINPUT_GAMEPAD;

  // XINPUT_STATE
  _XINPUT_STATE = record
    dwPacketNumber: DWORD;
    Gamepad: _XINPUT_GAMEPAD;
  end;

  PXINPUT_STATE = _XINPUT_STATE;

  { TODO : Need to be translated to delphi }
  InputDevice = record
    (*XTL_LPDIRECTINPUTDEVICE8 m_Device; *)
    m_Flags: integer;
  end;

  XBController = record
    private
      m_CurrentState: XBCtrlState;
    m_dwInputDeviceCount: Integer;
    m_dwCurObject: Integer;

    // Device Names
    m_DeviceName: array[0..XBCTRL_MAX_DEVICES] of array[0..260] of char;
    m_InputDevice: array[0..XBCTRL_MAX_DEVICES] of InputDevice;

    m_ObjectConfig: array[XBCtrlObject] of XBCtrlObjectCfg;

    lPrevMouseX, lPrevMouseY, lPrevMouseZ: LongInt;
    CurConfigObject: XBCtrlObject;

    public
  procedure Load(szRegistryKey: PChar);
procedure Save(szRegistryKey: PChar);
procedure ConfigBegin(ahwnd: THandle; aObject: XBCtrlObject);
procedure ConfigEnd;
procedure ListenPoll(var Controller: XINPUT_STATE);

procedure ListenBegin(ahwnd: THandle);
procedure ListenEnd;
procedure DInputInit(ahwnd: THandle);
procedure DInputCleanup;
procedure Map(aobject: XBCtrlObject; szDeviceName: PChar; dwInfo: Integer; dwFlags: Integer);
procedure ReorderObjects(szDeviceName: PChar; aPos: Integer);

function DeviceIsUsed(szDeviceName: PChar): Longbool;
function Insert(szDeviceName: PChar): Integer;
function ConfigPoll(szStatus: PChar): Longbool;
  end;


implementation

// ******************************************************************
// * func: XBController::XBController
// ******************************************************************
(*XBController::XBController()
{
    m_CurrentState = XBCTRL_STATE_NONE;

    int v=0;

    for(v=0;v<XBCTRL_MAX_DEVICES;v++)
    {
        m_DeviceName[v][0] = '\0';

        m_InputDevice[v].m_Device = NULL;
        m_InputDevice[v].m_Flags  = 0;
    }

    for(v=0;v<XBCTRL_OBJECT_COUNT;v++)
    {
        m_ObjectConfig[v].dwDevice = -1;
        m_ObjectConfig[v].dwInfo   = -1;
        m_ObjectConfig[v].dwFlags  = 0;
    }

    m_pDirectInput8 = NULL;

    m_dwInputDeviceCount = 0;
}    *)



{ TODO : Need to be added to XBController }
// ******************************************************************
// * func: XBController::~XBController
// ******************************************************************
(*XBController.~XBController()
begin
    if(m_CurrentState = XBCTRL_STATE_CONFIG) then
        ConfigEnd();
    else if(m_CurrentState = XBCTRL_STATE_LISTEN) then
        ListenEnd();
 end;

{ TODO : Need to be added to XBController }
// ******************************************************************
// * func: XBController::EnumObjectsCallback
// ******************************************************************
function XBController.EnumObjectsCallback(lpddoi: XTL.LPCDIDEVICEOBJECTINSTANCE): BOOL;
begin
    if(lpddoi^.dwType and DIDFT_AXIS) then
    begin
        XTL.DIPROPRANGE diprg;

        diprg.diph.dwSize       := SizeOf(XTL.DIPROPRANGE);
        diprg.diph.dwHeaderSize := SizeOf(XTL.DIPROPHEADER);
        diprg.diph.dwHow        := DIPH_BYID;
        diprg.diph.dwObj        := lpddoi^.dwType;
        diprg.lMin              := 0 - 32768;
        diprg.lMax              := 0 + 32767;

        HRESULT hRet := m_InputDevice[m_dwCurObject].m_Device^.SetProperty(DIPROP_RANGE, @diprg.diph);

        if(FAILED(hRet)) then
        begin
            if(hRet = E_NOTIMPL) then
                Result:= DIENUM_CONTINUE;
            else
                Result:= DIENUM_STOP;
         end;
     end;
    else if(lpddoi^.dwType and DIDFT_BUTTON) then
    begin
        XTL.DIPROPRANGE diprg;

        diprg.diph.dwSize       := SizeOf(XTL.DIPROPRANGE);
        diprg.diph.dwHeaderSize := SizeOf(XTL.DIPROPHEADER);
        diprg.diph.dwHow        := DIPH_BYID;
        diprg.diph.dwObj        := lpddoi^.dwType;
        diprg.lMin              := 0;
        diprg.lMax              := 255;

        HRESULT hRet := m_InputDevice[m_dwCurObject].m_Device^.SetProperty(DIPROP_RANGE, @diprg.diph);

        if(FAILED(hRet)) then
        begin
            if(hRet = E_NOTIMPL) then
                Result:= DIENUM_CONTINUE;
            else
                Result:= DIENUM_STOP;
         end;
     end;

    Result:= DIENUM_CONTINUE;
 end;

 { TODO : Need to be added to XBController }
// ******************************************************************
// * func: WrapEnumGameCtrlCallback
// ******************************************************************
function CALLBACK WrapEnumGameCtrlCallback(lpddi: XTL.LPCDIDEVICEINSTANCE; pvRef: Pointer): BOOL;
begin
    XBController *context := (XBController)pvRef;

    Result:= context^.EnumGameCtrlCallback(lpddi);
 end;

{ TODO : Need to be added to XBController }
// ******************************************************************
// * func: WrapEnumObjectsCallback
// ******************************************************************
function CALLBACK WrapEnumObjectsCallback(lpddoi: XTL.LPCDIDEVICEOBJECTINSTANCE; pvRef: Pointer): BOOL;
begin
    XBController *context := (XBController)pvRef;

    Result:= context^.EnumObjectsCallback(lpddoi);
 end;

{ TODO : Need to be added to XBController }
// ******************************************************************
// * Input Device Name Lookup Table
// ******************************************************************
 Char *XBController.m_DeviceNameLookup[XBCTRL_OBJECT_COUNT] =
begin
    // ******************************************************************
    // * Analog Axis
    // ******************************************************************
    'LThumbPosX', 'LThumbNegX', 'LThumbPosY', 'LThumbNegY',
    'RThumbPosX', 'RThumbNegX', 'RThumbPosY', 'RThumbNegY',

    // ******************************************************************
    // * Analog Buttons
    // ******************************************************************
    'X', 'Y', 'A', 'B', 'White', 'Black', 'LTrigger', 'RTrigger',

    // ******************************************************************
    // * Digital Buttons
    // ******************************************************************
    'DPadUp', 'DPadDown', 'DPadLeft', 'DPadRight',
    'Back', 'Start', 'LThumb', 'RThumb',
);


{ TODO : Need to be added to XBController }
// ******************************************************************
// * func: XBController::EnumGameCtrlCallback
// ******************************************************************
function XBController.EnumGameCtrlCallback(lpddi: XTL.LPCDIDEVICEINSTANCE): BOOL;
begin
    if(m_CurrentState = XBCTRL_STATE_LISTEN and  not DeviceIsUsed(lpddi^.tszInstanceName)) then
        Result:= DIENUM_CONTINUE;

    HRESULT hRet := m_pDirectInput8^.CreateDevice(lpddi^.guidInstance, @m_InputDevice[m_dwInputDeviceCount].m_Device, 0);

    if( not FAILED(hRet)) then
    begin
        m_InputDevice[m_dwInputDeviceCount].m_Flags := DEVICE_FLAG_JOYSTICK;

        m_InputDevice[m_dwInputDeviceCount++].m_Device^.SetDataFormat(@XTL.c_dfDIJoystick);

        if(m_CurrentState = XBCTRL_STATE_LISTEN) then
            ReorderObjects(lpddi^.tszInstanceName, m_dwInputDeviceCount - 1);
     end;

    Result:= DIENUM_CONTINUE;
 end;       *)

{ XBController }


// func: XBController::ListenPoll

procedure XBController.ListenPoll(var Controller: XINPUT_STATE);
(*var
  hRet: HRESULT;
  v: Integer;

  dwDevice: Integer;
  dwFlags: Integer;
  dwInfo: Integer;

  wValue: SmallInt; *)
begin
  (*if (Controller = Nil) then
    Exit;

    { TODO : Need to be translated to delphi }
    XTL.LPDIRECTINPUTDEVICE8 pDevice:=0;

  hRet := 0;
  dwFlags := 0;

    // Default values necessary for axis
  Controller.Gamepad.sThumbLX := 0;
  Controller.Gamepad.sThumbLY := 0;
  Controller.Gamepad.sThumbRX := 0;
  Controller.Gamepad.sThumbRY := 0;

    // Poll all devices

  for v := 0 to XBCTRL_OBJECT_COUNT - 1 do
  begin
    dwDevice := m_ObjectConfig[v].dwDevice;
    dwFlags := m_ObjectConfig[v].dwFlags;
    dwInfo := m_ObjectConfig[v].dwInfo;

    if (dwDevice = -1) then
      continue;

        pDevice := m_InputDevice[dwDevice].m_Device;

        hRet := pDevice^.Poll();

        if(FAILED(hRet)) then
        begin
            hRet := pDevice^.Acquire();

            while(hRet = DIERR_INPUTLOST)
                hRet := pDevice^.Acquire();
         end;

    wValue := 0;

        // Interpret PC Joystick Input
        (*if(dwFlags and DEVICE_FLAG_JOYSTICK) then
        begin
            XTL.DIJOYSTATE JoyState := (0);

            if(pDevice^.GetDeviceState(SizeOf(JoyState), @JoyState) <> DI_OK) then
                continue;

            if(dwFlags and DEVICE_FLAG_AXIS) then
            begin
                LongInt *pdwAxis := (LongInt)((uint32)@JoyState + dwInfo);
                wValue := (SmallInt)(pdwAxis);

                if(dwFlags and DEVICE_FLAG_NEGATIVE) then
                begin
                    if(wValue < 0) then
                        wValue := abs(wValue+1);
                    else
                        wValue := 0;
                 end;
                else if(dwFlags and DEVICE_FLAG_POSITIVE) then
                begin
                    if(wValue < 0) then
                        wValue := 0;
                 end;
             end;
            else if(dwFlags and DEVICE_FLAG_BUTTON) then
            begin
                BYTE *pbButton := (BYTE)((uint32)@JoyState + dwInfo);

                if(pbButton and $80) then
                    wValue := 32767;
                else
                    wValue := 0;
             end;
         end
        // Interpret PC KeyBoard Input
        else if(dwFlags and DEVICE_FLAG_KEYBOARD) then
        begin
            BYTE KeyboardState[256] := (0);

            if(pDevice^.GetDeviceState(SizeOf(KeyboardState), @KeyboardState) <> DI_OK) then
                continue;

            BYTE bKey := KeyboardState[dwInfo];

            if(bKey and $80) then
                wValue := 32767;
            else
                wValue := 0;
         end
        // Interpret PC Mouse Input
        else if(dwFlags and DEVICE_FLAG_MOUSE) then
        begin
            XTL.DIMOUSESTATE2 MouseState := (0);

            if(pDevice^.GetDeviceState(SizeOf(MouseState), @MouseState) <> DI_OK) then
                continue;

            if(dwFlags and DEVICE_FLAG_MOUSE_CLICK) then
            begin
                if(MouseState.rgbButtons[dwInfo] and $80) then
                    wValue := 32767;
                else
                    wValue := 0;
             end;
            else if(dwFlags and DEVICE_FLAG_AXIS) then
            begin
                 LongInt lAccumX := 0;
                 LongInt lAccumY := 0;
                 LongInt lAccumZ := 0;

                lAccumX:= lAccumX + MouseState.lX * 300;
                lAccumY:= lAccumY + MouseState.lY * 300;
                lAccumZ:= lAccumZ + MouseState.lZ * 300;

                if(lAccumX > 32767) then
                    lAccumX := 32767;
                else if(lAccumX < -32768) then
                    lAccumX := -32768;

                if(lAccumY > 32767) then
                    lAccumY := 32767;
                else if(lAccumY < -32768) then
                    lAccumY := -32768;

                if(lAccumZ > 32767) then
                    lAccumZ := 32767;
                else if(lAccumZ < -32768) then
                    lAccumZ := -32768;

                if(dwInfo = FIELD_OFFSET(XTL.DIMOUSESTATE, lX)) then
                    wValue := (WORD)lAccumX;
                else if(dwInfo = FIELD_OFFSET(XTL.DIMOUSESTATE, lY)) then
                    wValue := (WORD)lAccumY;
                else if(dwInfo = FIELD_OFFSET(XTL.DIMOUSESTATE, lZ)) then
                    wValue := (WORD)lAccumZ;

                if(dwFlags and DEVICE_FLAG_NEGATIVE) then
                begin
                    if(wValue < 0) then
                        wValue := abs(wValue+1);
                    else
                        wValue := 0;
                 end;
                else if(dwFlags and DEVICE_FLAG_POSITIVE) then
                begin
                    if(wValue < 0) then
                        wValue := 0;
                 end;
             end;
         end;

        // ******************************************************************
        // * Map Xbox Joystick Input
        // ******************************************************************
    if (v >= XBCTRL_OBJECT_LTHUMBPOSX) and (v <= XBCTRL_OBJECT_RTHUMB) then
    begin
      case (v) of
        XBCTRL_OBJECT_LTHUMBPOSY:
          Controller.Gamepad.sThumbLY := Controller.Gamepad.sThumbLY + wValue;
        XBCTRL_OBJECT_LTHUMBNEGY:
          Controller.Gamepad.sThumbLY := Controller.Gamepad.sThumbLY - wValue;
        XBCTRL_OBJECT_RTHUMBPOSY:
          Controller.Gamepad.sThumbRY := Controller.Gamepad.sThumbRY + wValue;
        XBCTRL_OBJECT_RTHUMBNEGY:
          Controller.Gamepad.sThumbRY := Controller.Gamepad.sThumbRY - wValue;
        XBCTRL_OBJECT_LTHUMBPOSX:
          Controller.Gamepad.sThumbLX := Controller.Gamepad.sThumbLX + wValue;
        XBCTRL_OBJECT_LTHUMBNEGX:
          Controller.Gamepad.sThumbLX := Controller.Gamepad.sThumbLX - wValue;
        XBCTRL_OBJECT_RTHUMBPOSX:
          Controller.Gamepad.sThumbRX := Controller.Gamepad.sThumbRX + wValue;
        XBCTRL_OBJECT_RTHUMBNEGX:
          Controller.Gamepad.sThumbRX := Controller.Gamepad.sThumbRX - wValue;
        XBCTRL_OBJECT_A:
          Controller.Gamepad.bAnalogButtons[XINPUT_GAMEPAD_A] := (wValue / 128);
        XBCTRL_OBJECT_B:
          Controller.Gamepad.bAnalogButtons[XINPUT_GAMEPAD_B] := (wValue / 128);
        XBCTRL_OBJECT_X:
          Controller.Gamepad.bAnalogButtons[XINPUT_GAMEPAD_X] := (wValue / 128);
        XBCTRL_OBJECT_Y:
          Controller.Gamepad.bAnalogButtons[XINPUT_GAMEPAD_Y] := (wValue / 128);
        XBCTRL_OBJECT_WHITE:
          Controller.Gamepad.bAnalogButtons[XINPUT_GAMEPAD_WHITE] := (wValue / 128);
        XBCTRL_OBJECT_BLACK:
          Controller.Gamepad.bAnalogButtons[XINPUT_GAMEPAD_BLACK] := (wValue / 128);
        XBCTRL_OBJECT_LTRIGGER:
          Controller.Gamepad.bAnalogButtons[XINPUT_GAMEPAD_LEFT_TRIGGER] := (wValue / 128);
        XBCTRL_OBJECT_RTRIGGER:
          Controller.Gamepad.bAnalogButtons[XINPUT_GAMEPAD_RIGHT_TRIGGER] := (wValue / 128);
        XBCTRL_OBJECT_DPADUP: begin
            if (wValue > 0) then
              Controller.Gamepad.wButtons := Controller.Gamepad.wButtons or XINPUT_GAMEPAD_DPAD_UP
            else
              Controller.Gamepad.wButtons := Controller.Gamepad.wButtons and XINPUT_GAMEPAD_DPAD_UP;
          end;
        XBCTRL_OBJECT_DPADDOWN:
          if (wValue > 0) then
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons or XINPUT_GAMEPAD_DPAD_DOWN
          else
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons and XINPUT_GAMEPAD_DPAD_DOWN;
        XBCTRL_OBJECT_DPADLEFT:
          if (wValue > 0) then
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons or XINPUT_GAMEPAD_DPAD_LEFT
          else
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons and XINPUT_GAMEPAD_DPAD_LEFT;
        XBCTRL_OBJECT_DPADRIGHT:
          if (wValue > 0) then
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons or XINPUT_GAMEPAD_DPAD_RIGHT
          else
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons and XINPUT_GAMEPAD_DPAD_RIGHT;
        XBCTRL_OBJECT_BACK:
          if (wValue > 0) then
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons or XINPUT_GAMEPAD_BACK
          else
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons and XINPUT_GAMEPAD_BACK;
        XBCTRL_OBJECT_START:
          if (wValue > 0) then
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons or XINPUT_GAMEPAD_START
          else
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons and XINPUT_GAMEPAD_START;
        XBCTRL_OBJECT_LTHUMB:
          if (wValue > 0) then
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons or XINPUT_GAMEPAD_LEFT_THUMB
          else
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons and XINPUT_GAMEPAD_LEFT_THUMB;
        XBCTRL_OBJECT_RTHUMB:
          if (wValue > 0) then
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons or XINPUT_GAMEPAD_RIGHT_THUMB
          else
            Controller.Gamepad.wButtons := Controller.Gamepad.wButtons and XINPUT_GAMEPAD_RIGHT_THUMB;
      end;
    end;
  end;    *)
end;

procedure XBController.ConfigBegin(ahwnd: THandle; aObject: XBCtrlObject);
begin
  if m_CurrentState <> XBCTRL_STATE_NONE then
  begin
    Error_SetError('Invalid State', False);
    Exit;
  end;

  m_CurrentState := XBCTRL_STATE_CONFIG;

  DInputInit(ahwnd);

  if Error_GetError <> '' then
    Exit;

  lPrevMouseX := -1;
  lPrevMouseY := -1;
  lPrevMouseZ := -1;

  CurConfigObject := aobject;
end;

procedure XBController.ConfigEnd;
begin
  if m_CurrentState <> XBCTRL_STATE_CONFIG then
  begin
    Error_SetError('Invalid State', False);
    Exit;
  end;

  DInputCleanup();
  m_CurrentState := XBCTRL_STATE_NONE;
end;

function XBController.ConfigPoll(szStatus: PChar): Longbool;
(*var
  v: Integer;
  hRet: HRESULT;
  dwHow: DWORD;
  dwFlags: DWORD; *)
begin
  Result := False;

  if m_CurrentState <> XBCTRL_STATE_CONFIG then
  begin
    Error_SetError('Invalid State', False);
    Result := False;
  end;

    { TODO : Need to be translated to delphi }
    (*XTL.DIDEVICEINSTANCE        DeviceInstance;
    XTL.DIDEVICEOBJECTINSTANCE  ObjectInstance;

    DeviceInstance.dwSize := SizeOf(XTL.DIDEVICEINSTANCE);
    ObjectInstance.dwSize := SizeOf(XTL.DIDEVICEOBJECTINSTANCE);

  // Monitor for significant device state changes
  for v := m_dwInputDeviceCount downto 0 do
  begin
    // Poll the current device
    begin
             { TODO : Need to be translated to delphi }
            (*hRet := m_InputDevice[v].m_Device^.Poll();

            if(FAILED(hRet)) then
            begin
                hRet := m_InputDevice[v].m_Device^.Acquire();

                while(hRet = DIERR_INPUTLOST)
                    hRet := m_InputDevice[v].m_Device^.Acquire();
             end;
    end;

    dwHow := -1;
    dwFlags = m_InputDevice[v].m_Flags;

    // Detect Joystick Input

    if (m_InputDevice[v].m_Flags and DEVICE_FLAG_JOYSTICK) then
    begin
      XTL.DIJOYSTATE JoyState;

            // ******************************************************************
            // * Get Joystick State
            // ******************************************************************
      begin
        HRESULT hRet := m_InputDevice[v].m_Device^.GetDeviceState(SizeOf(XTL.DIJOYSTATE), @JoyState);

        if (FAILED(hRet)) then
          continue;
      end;

      dwFlags := DEVICE_FLAG_JOYSTICK;

      if (abs(JoyState.lX) > DETECT_SENSITIVITY_JOYSTICK) then
      begin
        dwHow := FIELD_OFFSET(XTL.DIJOYSTATE, lX);
        dwFlags := dwFlags or (JoyState.lX > 0)?(DEVICE_FLAG_AXIS or DEVICE_FLAG_POSITIVE): (DEVICE_FLAG_AXIS or DEVICE_FLAG_NEGATIVE);
      end
    else if (abs(JoyState.lY) > DETECT_SENSITIVITY_JOYSTICK) then
    begin
      dwHow := FIELD_OFFSET(XTL.DIJOYSTATE, lY);
      dwFlags := dwFlags or (JoyState.lY > 0)?(DEVICE_FLAG_AXIS or DEVICE_FLAG_POSITIVE): (DEVICE_FLAG_AXIS or DEVICE_FLAG_NEGATIVE);
    end;
else if (abs(JoyState.lZ) > DETECT_SENSITIVITY_JOYSTICK) then
begin
  dwHow := FIELD_OFFSET(XTL.DIJOYSTATE, lZ);
  dwFlags := dwFlags or (JoyState.lZ > 0)?(DEVICE_FLAG_AXIS or DEVICE_FLAG_POSITIVE): (DEVICE_FLAG_AXIS or DEVICE_FLAG_NEGATIVE);
end;
else if (abs(JoyState.lRx) > DETECT_SENSITIVITY_JOYSTICK) then
begin
  dwHow := FIELD_OFFSET(XTL.DIJOYSTATE, lRx);
  dwFlags := dwFlags or (JoyState.lRx > 0)?(DEVICE_FLAG_AXIS or DEVICE_FLAG_POSITIVE): (DEVICE_FLAG_AXIS or DEVICE_FLAG_NEGATIVE);
end;
else if (abs(JoyState.lRy) > DETECT_SENSITIVITY_JOYSTICK) then
begin
  dwHow := FIELD_OFFSET(XTL.DIJOYSTATE, lRy);
  dwFlags := dwFlags or (JoyState.lRy > 0)?(DEVICE_FLAG_AXIS or DEVICE_FLAG_POSITIVE): (DEVICE_FLAG_AXIS or DEVICE_FLAG_NEGATIVE);
end;
else if (abs(JoyState.lRz) > DETECT_SENSITIVITY_JOYSTICK) then
begin
  dwHow := FIELD_OFFSET(XTL.DIJOYSTATE, lRz);
  dwFlags := dwFlags or (JoyState.lRz > 0)?(DEVICE_FLAG_AXIS or DEVICE_FLAG_POSITIVE): (DEVICE_FLAG_AXIS or DEVICE_FLAG_NEGATIVE);
end;
else
  begin
    for (Integer b := 0; b < 2; b + +)
    begin
      if (abs(JoyState.rglSlider[b]) > DETECT_SENSITIVITY_JOYSTICK) then
      begin
        dwHow := FIELD_OFFSET(XTL.DIJOYSTATE, rglSlider[b]);
        dwFlags := dwFlags or (JoyState.rglSlider[b] > 0)?(DEVICE_FLAG_AXIS or DEVICE_FLAG_POSITIVE): (DEVICE_FLAG_AXIS or DEVICE_FLAG_NEGATIVE);
      end;
    end;
  end;

            (* temporarily disabled
            if(dwHow = -1) then
            begin
                for(Integer b:=0;b<4;b++)
                begin
                    if(abs(JoyState.rgdwPOV[b]) > DETECT_SENSITIVITY_POV) then
                    begin
                        dwHow := FIELD_OFFSET(XTL.DIJOYSTATE, rgdwPOV[b]);
                     end;
                 end;
             end;
            //*/

            if(dwHow = -1) then
            begin
                for(Integer b:=0;b<32;b++)
                begin
                    if(JoyState.rgbButtons[b] > DETECT_SENSITIVITY_BUTTON) then
                    begin
                        dwHow := FIELD_OFFSET(XTL.DIJOYSTATE, rgbButtons[b]);
                        dwFlags:= dwFlags or DEVICE_FLAG_BUTTON;
                     end;
                 end;
             end;

            // ******************************************************************
            // * Retrieve Object Info
            // ******************************************************************
            if(dwHow <> -1) then
            begin
                Char *szDirection := (dwFlags and DEVICE_FLAG_AXIS) ? (dwFlags and DEVICE_FLAG_POSITIVE) ? 'Positive ' : 'Negative ' : '';

                m_InputDevice[v].m_Device^.GetDeviceInfo(@DeviceInstance);

                m_InputDevice[v].m_Device^.GetObjectInfo(@ObjectInstance, dwHow, DIPH_BYOFFSET);

                Map(CurConfigObject, DeviceInstance.tszInstanceName, dwHow, dwFlags);

                printf('Cxbx: Detected %s%s on %s', szDirection, ObjectInstance.tszName, DeviceInstance.tszInstanceName, ObjectInstance.dwType);

                StrFmt(szStatus, 'Success: %s Mapped to '%s%s' on '%s'!', m_DeviceNameLookup[CurConfigObject], szDirection, ObjectInstance.tszName, DeviceInstance.tszInstanceName);

                Result:= true;
             end;
         end;
        // ******************************************************************
        // * Detect Keyboard Input
        // ******************************************************************
        else if(m_InputDevice[v].m_Flags and DEVICE_FLAG_KEYBOARD) then
        begin
             KeyState: array[0..256-1] of BYTE;

            m_InputDevice[v].m_Device^.GetDeviceState(256, KeyState);

            dwFlags := DEVICE_FLAG_KEYBOARD;

            // ******************************************************************
            // * Check for Keyboard State Change
            // ******************************************************************
            for(Integer r:=0;r<256;r++)
            begin
                if(KeyState[r] <> 0) then
                begin
                    dwHow := r;
                    break;
                 end;
             end;

            // ******************************************************************
            // * Check for Success
            // ******************************************************************
            if(dwHow <> -1) then
            begin
                Map(CurConfigObject, 'SysKeyboard', dwHow, dwFlags);

                printf('Cxbx: Detected Key %d on SysKeyboard', dwHow);

                StrFmt(szStatus, 'Success: %s Mapped to Key %d on SysKeyboard', m_DeviceNameLookup[CurConfigObject], dwHow);

                Result:= true;
             end;
         end;
        // ******************************************************************
        // * Detect Mouse Input
        // ******************************************************************
        else if(m_InputDevice[v].m_Flags and DEVICE_FLAG_MOUSE) then
        begin
            XTL.DIMOUSESTATE2 MouseState;

            m_InputDevice[v].m_Device^.GetDeviceState(SizeOf(MouseState), @MouseState);

            dwFlags := DEVICE_FLAG_MOUSE;

            // ******************************************************************
            // * Detect Button State Change
            // ******************************************************************
            for(Integer r:=0;r<4;r++)
            begin
                // 0x80 is the mask for button push
                if(MouseState.rgbButtons[r] and $80) then
                begin
                    dwHow := r;
                    dwFlags:= dwFlags or DEVICE_FLAG_MOUSE_CLICK;
                    break;
                 end;
             end;
            // ******************************************************************
            // * Check for Success
            // ******************************************************************
            if(dwHow <> -1) then
            begin
                Map(CurConfigObject, 'SysMouse', dwHow, dwFlags);

                printf('Cxbx: Detected Button %d on SysMouse', dwHow);

                StrFmt(szStatus, 'Success: %s Mapped to Button %d on SysMouse', m_DeviceNameLookup[CurConfigObject], dwHow);

                Result:= true;
             end;
            // ******************************************************************
            // * Check for Mouse Movement
            // ******************************************************************
            else
            begin
                LongInt lAbsDeltaX:=0, lAbsDeltaY=0, lAbsDeltaZ=0;
                LongInt lDeltaX:=0, lDeltaY=0, lDeltaZ=0;

                if(lPrevMouseX = -1 or lPrevMouseY = -1 or lPrevMouseZ = -1) then
                    lDeltaX := lDeltaY = lDeltaZ = 0;
                else
                begin
                    lDeltaX := MouseState.lX - lPrevMouseX;
                    lDeltaY := MouseState.lY - lPrevMouseY;
                    lDeltaZ := MouseState.lZ - lPrevMouseZ;

                    lAbsDeltaX := abs(lDeltaX);
                    lAbsDeltaY := abs(lDeltaY);
                    lAbsDeltaZ := abs(lDeltaZ);
                 end;

                LongInt lMax := (lAbsDeltaX > lAbsDeltaY) ? lAbsDeltaX : lAbsDeltaY;

                if(lAbsDeltaZ > lMax) then
                    lMax := lAbsDeltaZ;

                lPrevMouseX := MouseState.lX;
                lPrevMouseY := MouseState.lY;
                lPrevMouseZ := MouseState.lZ;

                if(lMax > DETECT_SENSITIVITY_MOUSE) then
                begin
                    dwFlags:= dwFlags or DEVICE_FLAG_AXIS;

                    if(lMax = lAbsDeltaX) then
                    begin
                        dwHow := FIELD_OFFSET(XTL.DIMOUSESTATE, lX);
                        dwFlags:= dwFlags or (lDeltaX > 0) ? DEVICE_FLAG_POSITIVE : DEVICE_FLAG_NEGATIVE;
                     end;
                    else if(lMax = lAbsDeltaY) then
                    begin
                        dwHow := FIELD_OFFSET(XTL.DIMOUSESTATE, lY);
                        dwFlags:= dwFlags or (lDeltaY > 0) ? DEVICE_FLAG_POSITIVE : DEVICE_FLAG_NEGATIVE;
                     end;
                    else if(lMax = lAbsDeltaZ) then
                    begin
                        dwHow := FIELD_OFFSET(XTL.DIMOUSESTATE, lZ);
                        dwFlags:= dwFlags or (lDeltaZ > 0) ? DEVICE_FLAG_POSITIVE : DEVICE_FLAG_NEGATIVE;
                     end;
                 end;

                // ******************************************************************
                // * Check for Success
                // ******************************************************************
                if(dwHow <> -1) then
                begin
                    Char *szDirection := (dwFlags and DEVICE_FLAG_POSITIVE) ? 'Positive' : 'Negative';
                    Char *szObjName := 'Unknown';

                    ObjectInstance.dwSize := SizeOf(ObjectInstance);

                    if(m_InputDevice[v].m_Device^.GetObjectInfo(@ObjectInstance, dwHow, DIPH_BYOFFSET) = DI_OK) then
                        szObjName := ObjectInstance.tszName;

                    Map(CurConfigObject, 'SysMouse', dwHow, dwFlags);

                    printf('Cxbx: Detected Movement on the %s%s on SysMouse', szDirection, szObjName);

                    StrFmt(szStatus, 'Success: %s Mapped to %s%s on SysMouse', m_DeviceNameLookup[CurConfigObject], szDirection, szObjName);

                    Result:= true;
                 end;
             end;
         end;
     end;

    Result:= False;*)
end;


function XBController.DeviceIsUsed(szDeviceName: PChar): Longbool;
var
  v: Integer;
begin
  Result := False;
  for v := 0 to XBCTRL_MAX_DEVICES - 1 do begin
    if (m_DeviceName[v][0] <> #0) then
    begin
      { TODO : Need to be translated to delphi }
      (*
      if (strncmp(m_DeviceName[v], szDeviceName, 255) = 0) then
        Result := true;   *)
    end;
  end;
end;

procedure XBController.DInputCleanup;
var
  v: Integer;
begin
  for v := m_dwInputDeviceCount downto 0 do
  begin
    { TODO : Need to be translated to delphi }
    (*
    m_InputDevice[v].m_Device^.Unacquire();
    m_InputDevice[v].m_Device^.Release();
    m_InputDevice[v].m_Device := 0;
    *)
  end;

  m_dwInputDeviceCount := 0;
    { TODO : Need to be translated to delphi }
    (*if(m_pDirectInput8 <> 0) then
    begin
        m_pDirectInput8^.Release();
        m_pDirectInput8 := 0;
     end; *)
end;

procedure XBController.DInputInit(ahwnd: THandle);
(*var
  hRet: HResult; *)
begin
  m_dwInputDeviceCount := 0;
        (*
    // Create DirectInput Object
    begin
        hRet = DirectInput8Create
        (
            GetModuleHandle(0),
            DIRECTINPUT_VERSION,
            XTL.IID_IDirectInput8,
            @m_pDirectInput8,
            0
        );

        if(FAILED(hRet)) then
        begin
            SetError('Could not initialized DirectInput8', true);
            Exit;
         end;
     end;

    // ******************************************************************
    // * Create all the devices available (well...most of them)
    // ******************************************************************
    if(m_pDirectInput8 <> 0) then
    begin
        HRESULT hRet = m_pDirectInput8^.EnumDevices
        (
            DI8DEVCLASS_GAMECTRL,
            WrapEnumGameCtrlCallback,
            this,
            DIEDFL_ATTACHEDONLY
        );

        if(m_CurrentState = XBCTRL_STATE_CONFIG or DeviceIsUsed('SysKeyboard')) then
        begin
            hRet := m_pDirectInput8^.CreateDevice(XTL.GUID_SysKeyboard, @m_InputDevice[m_dwInputDeviceCount].m_Device, 0);

            if( not FAILED(hRet)) then
            begin
                m_InputDevice[m_dwInputDeviceCount].m_Flags := DEVICE_FLAG_KEYBOARD;

                m_InputDevice[m_dwInputDeviceCount++].m_Device^.SetDataFormat(@XTL.c_dfDIKeyboard);
             end;

            if(m_CurrentState = XBCTRL_STATE_LISTEN) then
                ReorderObjects('SysKeyboard', m_dwInputDeviceCount - 1);
         end;

        if(m_CurrentState = XBCTRL_STATE_CONFIG or DeviceIsUsed('SysMouse')) then
        begin
            hRet := m_pDirectInput8^.CreateDevice(XTL.GUID_SysMouse, @m_InputDevice[m_dwInputDeviceCount].m_Device, 0);

            if( not FAILED(hRet)) then
            begin
                m_InputDevice[m_dwInputDeviceCount].m_Flags := DEVICE_FLAG_MOUSE;

                m_InputDevice[m_dwInputDeviceCount++].m_Device^.SetDataFormat(@XTL.c_dfDIMouse2);
             end;

            if(m_CurrentState = XBCTRL_STATE_LISTEN) then
                ReorderObjects('SysMouse', m_dwInputDeviceCount - 1);
         end;
     end;

    // ******************************************************************
    // * Enumerate Controller objects
    // ******************************************************************
    for(m_dwCurObject:=0;m_dwCurObject<m_dwInputDeviceCount;m_dwCurObject++)
        m_InputDevice[m_dwCurObject].m_Device^.EnumObjects(WrapEnumObjectsCallback, this, DIDFT_ALL);

    // ******************************************************************
    // * Set cooperative level and acquire
    // ******************************************************************
    begin
        for(Integer v:=m_dwInputDeviceCount-1;v>=0;v--)
        begin
            m_InputDevice[v].m_Device^.SetCooperativeLevel(hwnd, DISCL_NONEXCLUSIVE or DISCL_FOREGROUND);
            m_InputDevice[v].m_Device^.Acquire();

            HRESULT hRet := m_InputDevice[v].m_Device^.Poll();

            if(FAILED(hRet)) then
            begin
                hRet := m_InputDevice[v].m_Device^.Acquire();

                while(hRet = DIERR_INPUTLOST)
                    hRet := m_InputDevice[v].m_Device^.Acquire();

                if(hRet <> DIERR_INPUTLOST) then
                    break;
             end;
         end;
     end;*)
end;

function XBController.Insert(szDeviceName: PChar): Integer;
var
  v: Integer;
begin
  Result := 0;

  for v := 0 to XBCTRL_MAX_DEVICES - 1 do
    if (StrComp(m_DeviceName[v], szDeviceName) = 0) then
      Result := v;

  for v := 0 to XBCTRL_MAX_DEVICES - 1 do
  begin
    if (m_DeviceName[v][0] = #0) then
    begin
      { TODO : Need to be translated to delphi }
      (*m_DeviceName[v] := szDeviceName; *)
      Result := v;
    end;
  end;

  MessageBox(0, 'Unexpected Circumstance (Too Many Controller Devices)! Please contact caustik!', 'Cxbx', MB_OK or MB_ICONEXCLAMATION);

  ExitProcess(1);
end;

procedure XBController.ListenBegin(ahwnd: THandle);
var
  v: Integer;
begin
  if m_CurrentState <> XBCTRL_STATE_NONE then
  begin
    Error_SetError('Invalid State', False);
    Exit;
  end;

  m_CurrentState := XBCTRL_STATE_LISTEN;

  DInputInit(ahwnd);

  for v := XBCTRL_MAX_DEVICES downto m_dwInputDeviceCount do
    m_DeviceName[v][0] := #0;

  for v := 0 to XBCTRL_OBJECT_COUNT - 1 do
  begin
    { TODO : Need to be translated to delphi }
    (*if m_ObjectConfig[v].dwDevice >= m_dwInputDeviceCount then
    begin
      DbgPrintf(Format ('Warning: Device Mapped to %s was not found!', m_DeviceNameLookup[v]);
      m_ObjectConfig[v].dwDevice := -1;
    end;                                                                                      *)
  end;
end;

procedure XBController.ListenEnd;
begin
  if m_CurrentState <> XBCTRL_STATE_LISTEN then
  begin
    Error_SetError('Invalid State', False);
    Exit;
  end;

  DInputCleanup();
  m_CurrentState := XBCTRL_STATE_NONE;
end;

procedure XBController.Load(szRegistryKey: PChar);
var
  (*dwType, dwSize: DWORD; *)
  dwDisposition: DWORD;
  ahKey: HKEY;
  v: Integer;
  szValueName: array[0..64 - 1] of Char;
begin
  if m_CurrentState <> XBCTRL_STATE_NONE then
  begin
    Error_SetError('Invalid State', False);
    Exit;
  end;

  // Load Configuration from Registry
  if (RegCreateKeyEx(HKEY_CURRENT_USER, szRegistryKey, 0, nil, REG_OPTION_NON_VOLATILE, KEY_QUERY_VALUE, nil, ahKey, @dwDisposition) = ERROR_SUCCESS) then
  begin
    // Load Device Names
    for v := 0 to XBCTRL_MAX_DEVICES - 1 do begin
      // default is a null string
      m_DeviceName[v][0] := #0;
      StrFmt(szValueName, 'DeviceName $%.02X', [v]);
      { TODO : Need to be translated to delphi }
      (*
      dwType := REG_SZ;
      dwSize := 260;
      RegQueryValueEx(ahKey, szValueName, 0, @dwType, m_DeviceName[v], @dwSize); *)
    end;

    { TODO : Need to be translated to delphi }
    // Load Object Configuration
    (*for v := 0 to XBCTRL_OBJECT_COUNT - 1 do begin
      // default object configuration
      m_ObjectConfig[v].dwDevice := -1;
      m_ObjectConfig[v].dwInfo := -1;
      m_ObjectConfig[v].dwFlags := 0;

        { TODO : Need to be translated to delphi }
        (*StrFmt(szValueName, 'Object : %s', m_DeviceNameLookup[v]);

      dwType := REG_BINARY;
      dwSize := SizeOf(XBCtrlObjectCfg);
        { TODO : Need to be translated to delphi }
        (*RegQueryValueEx(hKey, szValueName, 0, @dwType, (PBYTE)@m_ObjectConfig[v], @dwSize);
    end; *)

    RegCloseKey(ahKey);
  end;
end;

procedure XBController.Map(aobject: XBCtrlObject; szDeviceName: PChar; dwInfo, dwFlags: Integer);
var
  v: Integer;
  r: XBCtrlObject;
  InUse: Boolean;
begin
  // Initialize InputMapping instance
  m_ObjectConfig[aobject].dwDevice := Insert(szDeviceName);
  m_ObjectConfig[aobject].dwInfo := dwInfo;
  m_ObjectConfig[aobject].dwFlags := dwFlags;

  // Purge unused device slots
  for v := 0 to XBCTRL_MAX_DEVICES - 1 do
  begin
    InUse := False;

    for r := Low(XBCtrlObject) to High(XBCtrlObject) do
      if m_ObjectConfig[r].dwDevice = v then
        InUse := True;

    if not InUse then
      m_DeviceName[v][0] := #0;
  end;
end;

procedure XBController.ReorderObjects(szDeviceName: PChar; aPos: Integer);
var
  Old: Integer;
  v: integer;
begin
  Old := -1;

  // locate Old device name position
  for v := 0 to XBCTRL_MAX_DEVICES - 1 do
  begin
    if (StrComp(m_DeviceName[v], szDeviceName) = 0) then
    begin
      Old := v;
      break;
    end;
  end;

  // Swap names, if necessary
  if Old <> aPos then
  begin
    StrCopy(m_DeviceName[Old], m_DeviceName[aPos]);
    StrCopy(m_DeviceName[aPos], szDeviceName);
  end;

  // Update all Old values
  for v := 0 to XBCTRL_OBJECT_COUNT - 1 do
  begin
    { TODO : Need to be translated to delphi }
    (*if m_ObjectConfig[v].dwDevice = Old then
      m_ObjectConfig[v].dwDevice := aPos
    else
      if m_ObjectConfig[v].dwDevice = aPos then
        m_ObjectConfig[v].dwDevice := Old; *)
  end;
end;

procedure XBController.Save(szRegistryKey: PChar);
var
  (*dwType, dwSize: DWORD; *)
  dwDisposition : DWORD;
  ahKey: HKEY;
  v: Integer;
  szValueName: array[0..64 - 1] of Char;
begin
  if (m_CurrentState <> XBCTRL_STATE_NONE) then
  begin
    Error_SetError('Invalid State', False);
    Exit;
  end;

  // Save Configuration to Registry
  if (RegCreateKeyEx(HKEY_CURRENT_USER, szRegistryKey, 0, Nil, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, Nil, ahKey, @dwDisposition) = ERROR_SUCCESS) then
  begin
    // Save Device Names
    for v := 0 to XBCTRL_MAX_DEVICES - 1 do begin
      StrFmt(szValueName, 'DeviceName $%.02X', [v]);

      { TODO : Need to be translated to delphi }
      (*dwType := REG_SZ;
      dwSize := 260;

      if (m_DeviceName[v][0] = #0) then
        RegDeleteValue(ahKey, szValueName)
      else
        RegSetValueEx(ahKey, szValueName, 0, dwType, m_DeviceName[v], dwSize); *)
    end;

        { TODO : need to be translated to delphi }
    // Save Object Configuration
    (*for v := 0 to XBCTRL_OBJECT_COUNT - 1 do begin
    StrFmt(szValueName, 'Object : %s', m_DeviceNameLookup[v]);

      dwType := REG_BINARY;
      dwSize := SizeOf(XBCtrlObjectCfg);

        if (m_ObjectConfig[v].dwDevice <> -1) then
          RegSetValueEx(hKey, szValueName, 0, dwType, (PBYTE)@m_ObjectConfig[v], dwSize);
    end; *)

    RegCloseKey(ahKey);
  end;
end;

end.

