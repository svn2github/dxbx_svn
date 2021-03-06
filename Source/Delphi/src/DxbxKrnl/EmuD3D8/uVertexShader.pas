﻿(*
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

unit uVertexShader;

{$INCLUDE Dxbx.inc}

{$MINENUMSIZE 4} // Enums in this unit need to be 4 bytes !

interface

uses
  // Delphi
  Windows
  , SysUtils // strlen
  // Jedi Win32API
  , JwaWinType
  // DirectX
{$IFDEF DXBX_USE_D3D9}
  , Direct3D9
  , D3DX9
{$ELSE}
  , Direct3D8
  , D3DX8
{$ENDIF}
  // Dxbx
  , uTypes
  , uDxbxUtils // iif
  , uDxbxKrnlUtils
  , uState // for g_BuildVersion
  , uEmuD3D8Types
  , uEmuD3D8Utils
  , uEmuAlloc
  , uEmu;


// Types from VertexShader.h :

{$IFDEF DXBX_USE_D3D9}
  {.$DEFINE DXBX_USE_VS30} // Separate the port to Vertex Shader model 3.0 from the port to Direct3D9
{$ENDIF}

const
  VSH_XBOX_MAX_A_REGISTER_COUNT = 1;
  VSH_XBOX_MAX_C_REGISTER_COUNT = 96;
  VSH_XBOX_MAX_R_REGISTER_COUNT = 12 + 1; // Use r12 to read back the current value of oPos, allows to treat oPos as a thirteenth temporary register.
  VSH_XBOX_MAX_V_REGISTER_COUNT = 16;

{$IFDEF DXBX_USE_VS30}
  VSH_NATIVE_MAX_R_REGISTER_COUNT = 32; // vs.3.0 has at least 32 registers
{$ELSE}
  VSH_NATIVE_MAX_R_REGISTER_COUNT = 12;
{$ENDIF}

// nv2a microcode header
type _VSH_SHADER_HEADER = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    Type_: uint08;
    Version: uint08;
    NumInst: uint08;
    Unknown0: uint08;
  end; // size = 4 (as in Cxbx)
  VSH_SHADER_HEADER = _VSH_SHADER_HEADER;
  PVSH_SHADER_HEADER = ^VSH_SHADER_HEADER;

const VSH_INSTRUCTION_SIZE = 4;
const VSH_INSTRUCTION_SIZE_BYTES = VSH_INSTRUCTION_SIZE * sizeof(DWORD);

// Types from VertexShader.cpp :

// ****************************************************************************
// * Vertex shader function recompiler
// ****************************************************************************

// Local macros
const VERSION_VS =                      $F0;  // vs.1.1, not an official value (Dxbx extension : 3.0)
const VERSION_XVS =                     $20;  // Xbox vertex shader
const VERSION_XVSS =                    $73;  // Xbox vertex state shader
const VERSION_XVSW =                    $77;  // Xbox vertex read/write shader

const VSH_XBOX_MAX_INSTRUCTION_COUNT =  136;  // The maximum Xbox shader instruction count
const VSH_MAX_INTERMEDIATE_COUNT =      1024; // The maximum number of intermediate format slots

type _VSH_SWIZZLE =
(
    SWIZZLE_X = 0,
    SWIZZLE_Y,
    SWIZZLE_Z,
    SWIZZLE_W
);
VSH_SWIZZLE = _VSH_SWIZZLE;

type DxbxSwizzles = array [0..4-1] of VSH_SWIZZLE;

type DxbxMask = DWORD;
  PDxbxMask = ^DxbxMask;

const
  MASK_X = $001;
  MASK_Y = $002;
  MASK_Z = $004;
  MASK_W = $008;
  MASK_XYZ = MASK_X or MASK_Y or MASK_Z;
  MASK_XYZW = MASK_X or MASK_Y or MASK_Z or MASK_W;

// Local types
type _VSH_FIELD_NAME =
(
    FLD_ILU = 0,
    FLD_MAC,
    FLD_CONST,
    FLD_V,
    // Input A
    FLD_A_NEG,
    FLD_A_SWZ_X,
    FLD_A_SWZ_Y,
    FLD_A_SWZ_Z,
    FLD_A_SWZ_W,
    FLD_A_R,
    FLD_A_MUX,
    // Input B
    FLD_B_NEG,
    FLD_B_SWZ_X,
    FLD_B_SWZ_Y,
    FLD_B_SWZ_Z,
    FLD_B_SWZ_W,
    FLD_B_R,
    FLD_B_MUX,
    // Input C
    FLD_C_NEG,
    FLD_C_SWZ_X,
    FLD_C_SWZ_Y,
    FLD_C_SWZ_Z,
    FLD_C_SWZ_W,
    FLD_C_R_HIGH,
    FLD_C_R_LOW,
    FLD_C_MUX,
    // Output
    FLD_OUT_MAC_MASK_X,
    FLD_OUT_MAC_MASK_Y,
    FLD_OUT_MAC_MASK_Z,
    FLD_OUT_MAC_MASK_W,
    FLD_OUT_R,
    FLD_OUT_ILU_MASK_X,
    FLD_OUT_ILU_MASK_Y,
    FLD_OUT_ILU_MASK_Z,
    FLD_OUT_ILU_MASK_W,
    FLD_OUT_O_MASK_X,
    FLD_OUT_O_MASK_Y,
    FLD_OUT_O_MASK_Z,
    FLD_OUT_O_MASK_W,
    FLD_OUT_ORB,
    FLD_OUT_ADDRESS,
    FLD_OUT_MUX,
    // Relative addressing
    FLD_A0X,
    // Final instruction
    FLD_FINAL
);
VSH_FIELD_NAME = _VSH_FIELD_NAME;

type _VSH_OREG_NAME =
(
    OREG_OPOS,    //  0
    OREG_UNUSED1, //  1
    OREG_UNUSED2, //  2
    OREG_OD0,     //  3
    OREG_OD1,     //  4
    OREG_OFOG,    //  5
    OREG_OPTS,    //  6
    OREG_OB0,     //  7
    OREG_OB1,     //  8
    OREG_OT0,     //  9
    OREG_OT1,     // 10
    OREG_OT2,     // 11
    OREG_OT3,     // 12
    OREG_UNUSED3, // 13
    OREG_UNUSED4, // 14
    OREG_A0X      // 15 - all values of the 4 bits are used
);
VSH_OREG_NAME = _VSH_OREG_NAME;

{$IFDEF DXBX_USE_VS30}
const OREG_MAPPING: array [VSH_OREG_NAME] of Integer = (
     0, // OREG_OPOS
    -1, // OREG_UNUSED1
    -1, // OREG_UNUSED2
     1, // OREG_OD0
     2, // OREG_OD1
     3, // OREG_OFOG
     4, // OREG_OPTS
     5, // OREG_OB0
     6, // OREG_OB1
     7, // OREG_OT0
     8, // OREG_OT1
     9, // OREG_OT2
    10, // OREG_OT3
    -1, // OREG_UNUSED3
    -1, // OREG_UNUSED4
    11  // OREG_A0X
  );

  VSH_XBOX_MAX_O_REGISTER_COUNT = Ord(High(VSH_OREG_NAME));
{$ENDIF DXBX_USE_VS30}

type _VSH_OUTPUT_TYPE =
(
    OUTPUT_C = 0,
    OUTPUT_O
);
VSH_OUTPUT_TYPE = _VSH_OUTPUT_TYPE;

type VSH_ARGUMENT_TYPE =
(
    PARAM_UNKNOWN = 0,
    PARAM_R,          // Temporary registers
    PARAM_V,          // Vertex registers
    PARAM_C,          // Constant registers, set by SetVertexShaderConstant
    PARAM_O
);
VSH_PARAMETER_TYPE = VSH_ARGUMENT_TYPE; // Alias, to indicate difference between a parameter and a generic argument

type _VSH_OUTPUT_MUX =
(
    OMUX_MAC = 0,
    OMUX_ILU
);
VSH_OUTPUT_MUX = _VSH_OUTPUT_MUX;

type _VSH_IMD_OUTPUT_TYPE =
(
    IMD_OUTPUT_C,
    IMD_OUTPUT_R,
    IMD_OUTPUT_O,
    IMD_OUTPUT_A0X
);
VSH_IMD_OUTPUT_TYPE = _VSH_IMD_OUTPUT_TYPE;

// Dxbx note : ILU stands for 'Inverse Logic Unit' opcodes
type _VSH_ILU =
(
    ILU_NOP = 0,
    ILU_MOV,
    ILU_RCP,
    ILU_RCC,
    ILU_RSQ,
    ILU_EXP,
    ILU_LOG,
    ILU_LIT // = 7 - all values of the 3 bits are used
);
VSH_ILU = _VSH_ILU;

// Dxbx note : MAC stands for 'Multiply And Accumulate' opcodes
type _VSH_MAC =
(
    MAC_NOP,
    MAC_MOV,
    MAC_MUL,
    MAC_ADD,
    MAC_MAD,
    MAC_DP3,
    MAC_DPH,
    MAC_DP4,
    MAC_DST,
    MAC_MIN,
    MAC_MAX,
    MAC_SLT,
    MAC_SGE,
    MAC_ARL
    // ??? 14
    // ??? 15 - 2 values of the 4 bits are undefined
);
VSH_MAC = _VSH_MAC;

type _VSH_OPCODE_PARAMS = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
// Dxbx Note : Since we split up g_OpCodeParams into g_OpCodeParams_ILU and g_OpCodeParams_MAC
// the following two members aren't needed anymore :
//    ILU: VSH_ILU;
//    MAC: VSH_MAC;
    A: boolean;
    B: boolean;
    C: boolean;
  end; // size = 12 (as in Cxbx)
  VSH_OPCODE_PARAMS = _VSH_OPCODE_PARAMS;
  PVSH_OPCODE_PARAMS = ^VSH_OPCODE_PARAMS;

type _VSH_IMD_OUTPUT = object
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    Type_: VSH_IMD_OUTPUT_TYPE;
    Mask: DxbxMask;
    Address: int16;
    function IsRegister(aRegType: VSH_IMD_OUTPUT_TYPE; aAddress: int16): Boolean;
  end; // size = 12 (as in Cxbx)
  VSH_IMD_OUTPUT = _VSH_IMD_OUTPUT;
  PVSH_IMD_OUTPUT = ^VSH_IMD_OUTPUT;

type _VSH_PARAMETER = object
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    Neg: boolean;                    // TRUE if negated, FALSE if not
    Type_: VSH_ARGUMENT_TYPE;        // Argument type; R, V or C for parameters, C or O for output
    Address: int16;                  // Register address
    Mask: DxbxMask;                  // Read channels, to ease up comparisions (swizzle is still leading!)
    Swizzle: DxbxSwizzles;           // The four swizzles
    function IsRegister(aRegType: VSH_ARGUMENT_TYPE; aAddress: int16): Boolean;
  end; // size = 28 (as in Cxbx)
  VSH_PARAMETER = _VSH_PARAMETER;
  PVSH_PARAMETER = ^VSH_PARAMETER;

type _VSH_OUTPUT = object(VSH_PARAMETER)
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    // Output register
    OutputMux: VSH_OUTPUT_MUX;  // MAC or ILU used as output
    // MAC output R register
    MACRMask: DxbxMask;
    MACRAddress: int16;//boolean;
    // ILU output R register
    ILURMask: DxbxMask;
    ILURAddress: int16;//boolean;
  end; // size = 24 (as in Cxbx)
  VSH_OUTPUT = _VSH_OUTPUT;

// The raw, parsed shader instruction (can be many combined [paired] instructions)
type _VSH_SHADER_INSTRUCTION = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    ILU: VSH_ILU;
    MAC: VSH_MAC;
    Output: VSH_OUTPUT;
    A: VSH_PARAMETER;
    B: VSH_PARAMETER;
    C: VSH_PARAMETER;
    a0x: boolean;
  end; // size = 120 (as in Cxbx)
  VSH_SHADER_INSTRUCTION = _VSH_SHADER_INSTRUCTION;
  PVSH_SHADER_INSTRUCTION = ^VSH_SHADER_INSTRUCTION;

type _VSH_IMD_INSTRUCTION_TYPE =
(
    IMD_MAC,
    IMD_ILU
);
VSH_IMD_INSTRUCTION_TYPE = _VSH_IMD_INSTRUCTION_TYPE;

type _VSH_IMD_PARAMETER = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    Active: boolean;
    Parameter: VSH_PARAMETER;
    // There is only a single address register in Microsoft® DirectX® 8.0.
    // The address register, designated as a0.x, may be used as signed
    // integer offset in relative addressing into the constant register file.
    //     c[a0.x + n]
    IndexesWithA0_X: boolean;
  end; // size = 36 (as in Cxbx)
  VSH_IMD_PARAMETER = _VSH_IMD_PARAMETER;
  PVSH_IMD_PARAMETER = ^VSH_IMD_PARAMETER;

  TVSH_IMD_PARAMETERArray = array [0..(MaxInt div SizeOf(VSH_IMD_PARAMETER)) - 1] of VSH_IMD_PARAMETER;
  PVSH_IMD_PARAMETERs = ^TVSH_IMD_PARAMETERArray;

type _VSH_INTERMEDIATE_FORMAT = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    IsCombined: boolean;
    InstructionType: VSH_IMD_INSTRUCTION_TYPE;
    MAC: VSH_MAC;
    ILU: VSH_ILU;
    Output: VSH_IMD_OUTPUT;
    Parameters: array [0..3-1] of VSH_IMD_PARAMETER;
    function ReadsFromRegister(aRegType: VSH_ARGUMENT_TYPE; aAddress: Int16): Boolean;
    function WritesToRegister(aRegType: VSH_ARGUMENT_TYPE; aAddress: Int16): Boolean;
  end; // size = 136 (as in Cxbx)
  VSH_INTERMEDIATE_FORMAT = _VSH_INTERMEDIATE_FORMAT;
  PVSH_INTERMEDIATE_FORMAT = ^VSH_INTERMEDIATE_FORMAT;

// Used for xvu spec definition
type _VSH_FIELDMAPPING = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    // FieldName: VSH_FIELD_NAME;
    SubToken: uint08;
    StartBit: uint08;
    BitLength: uint08;
  end; // size = 8 (as in Cxbx)
  VSH_FIELDMAPPING = _VSH_FIELDMAPPING;
  PVSH_FIELDMAPPING = ^VSH_FIELDMAPPING;

type _VSH_XBOX_SHADER = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    ShaderHeader: VSH_SHADER_HEADER;
    IntermediateCount: uint16;
    Intermediate: array [0..VSH_MAX_INTERMEDIATE_COUNT -1] of VSH_INTERMEDIATE_FORMAT;
    function IsRegisterReadUntilNextWrite(aIndex: int; aRegType: VSH_ARGUMENT_TYPE; aAddress: Int16): Boolean;
  end; // size = 139272 (as in Cxbx)
  VSH_XBOX_SHADER = _VSH_XBOX_SHADER;
  PVSH_XBOX_SHADER = ^VSH_XBOX_SHADER;

{$IFDEF DXBX_USE_D3D9}
var // TODO -oDxbx : Make this threadsafe (not global) !
  RegVUsage: array [0..VSH_XBOX_MAX_V_REGISTER_COUNT-1] of Boolean; // Dxbx addition, to support D3D9
{$ENDIF}

{$IFDEF DXBX_USE_VS30}
var
  RegOUsage: array [0..VSH_XBOX_MAX_O_REGISTER_COUNT-1] of Boolean; // Dxbx addition, to support VS3.0
{$ENDIF}

// Local constants
const g_FieldMapping: array [VSH_FIELD_NAME] of VSH_FIELDMAPPING =
(
    //           Field Name             DWORD         BitPos           BitSize
    ( {FieldName:FLD_ILU;              }SubToken:1;   StartBit:25;     BitLength:3 ), // VSH_ILU
    ( {FieldName:FLD_MAC;              }SubToken:1;   StartBit:21;     BitLength:4 ), // VSH_MAC
    ( {FieldName:FLD_CONST;            }SubToken:1;   StartBit:13;     BitLength:8 ),
    ( {FieldName:FLD_V;                }SubToken:1;   StartBit: 9;     BitLength:4 ),
    // INPUT A
    ( {FieldName:FLD_A_NEG;            }SubToken:1;   StartBit: 8;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_A_SWZ_X;          }SubToken:1;   StartBit: 6;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_A_SWZ_Y;          }SubToken:1;   StartBit: 4;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_A_SWZ_Z;          }SubToken:1;   StartBit: 2;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_A_SWZ_W;          }SubToken:1;   StartBit: 0;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_A_R;              }SubToken:2;   StartBit:28;     BitLength:4 ),
    ( {FieldName:FLD_A_MUX;            }SubToken:2;   StartBit:26;     BitLength:2 ), // VSH_PARAMETER_TYPE
    // INPUT B
    ( {FieldName:FLD_B_NEG;            }SubToken:2;   StartBit:25;     BitLength:1 ),
    ( {FieldName:FLD_B_SWZ_X;          }SubToken:2;   StartBit:23;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_B_SWZ_Y;          }SubToken:2;   StartBit:21;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_B_SWZ_Z;          }SubToken:2;   StartBit:19;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_B_SWZ_W;          }SubToken:2;   StartBit:17;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_B_R;              }SubToken:2;   StartBit:13;     BitLength:4 ),
    ( {FieldName:FLD_B_MUX;            }SubToken:2;   StartBit:11;     BitLength:2 ), // VSH_PARAMETER_TYPE
    // INPUT C
    ( {FieldName:FLD_C_NEG;            }SubToken:2;   StartBit:10;     BitLength:1 ),
    ( {FieldName:FLD_C_SWZ_X;          }SubToken:2;   StartBit: 8;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_C_SWZ_Y;          }SubToken:2;   StartBit: 6;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_C_SWZ_Z;          }SubToken:2;   StartBit: 4;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_C_SWZ_W;          }SubToken:2;   StartBit: 2;     BitLength:2 ), // VSH_SWIZZLE
    ( {FieldName:FLD_C_R_HIGH;         }SubToken:2;   StartBit: 0;     BitLength:2 ), // Forms FLD_C_R together with
    ( {FieldName:FLD_C_R_LOW;          }SubToken:3;   StartBit:30;     BitLength:2 ), // this (to bridge a DWord). c0..c15
    ( {FieldName:FLD_C_MUX;            }SubToken:3;   StartBit:28;     BitLength:2 ), // VSH_PARAMETER_TYPE
    // Output
    ( {FieldName:FLD_OUT_MAC_MASK_X;   }SubToken:3;   StartBit:27;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_MAC_MASK_Y;   }SubToken:3;   StartBit:26;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_MAC_MASK_Z;   }SubToken:3;   StartBit:25;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_MAC_MASK_W;   }SubToken:3;   StartBit:24;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_R;            }SubToken:3;   StartBit:20;     BitLength:4 ), // Dxbx note : 4 bits to select r0..r15
    ( {FieldName:FLD_OUT_ILU_MASK_X;   }SubToken:3;   StartBit:19;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_ILU_MASK_Y;   }SubToken:3;   StartBit:18;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_ILU_MASK_Z;   }SubToken:3;   StartBit:17;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_ILU_MASK_W;   }SubToken:3;   StartBit:16;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_O_MASK_X;     }SubToken:3;   StartBit:15;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_O_MASK_Y;     }SubToken:3;   StartBit:14;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_O_MASK_Z;     }SubToken:3;   StartBit:13;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_O_MASK_W;     }SubToken:3;   StartBit:12;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_OUT_ORB;          }SubToken:3;   StartBit:11;     BitLength:1 ), // VSH_OUTPUT_TYPE
    ( {FieldName:FLD_OUT_ADDRESS;      }SubToken:3;   StartBit: 3;     BitLength:8 ),
    ( {FieldName:FLD_OUT_MUX;          }SubToken:3;   StartBit: 2;     BitLength:1 ), // VSH_OUTPUT_MUX
    // Other
    ( {FieldName:FLD_A0X;              }SubToken:3;   StartBit: 1;     BitLength:1 ), // Boolean
    ( {FieldName:FLD_FINAL;            }SubToken:3;   StartBit: 0;     BitLength:1 )  // Boolean
);

const g_OpCodeParams_ILU: array [VSH_ILU] of VSH_OPCODE_PARAMS =
(
    //     ILU OP       MAC OP      ParamA   ParamB   ParamC
    ( {ILU:ILU_NOP; MAC:MAC_NOP;} a:FALSE; b:FALSE; c:FALSE ), // Dxbx note : Unused
    ( {ILU:ILU_MOV; MAC:MAC_NOP;} a:FALSE; b:FALSE; c:TRUE  ),
    ( {ILU:ILU_RCP; MAC:MAC_NOP;} a:FALSE; b:FALSE; c:TRUE  ),
    ( {ILU:ILU_RCC; MAC:MAC_NOP;} a:FALSE; b:FALSE; c:TRUE  ),
    ( {ILU:ILU_RSQ; MAC:MAC_NOP;} a:FALSE; b:FALSE; c:TRUE  ),
    ( {ILU:ILU_EXP; MAC:MAC_NOP;} a:FALSE; b:FALSE; c:TRUE  ),
    ( {ILU:ILU_LOG; MAC:MAC_NOP;} a:FALSE; b:FALSE; c:TRUE  ),
    ( {ILU:ILU_LIT; MAC:MAC_NOP;} a:FALSE; b:FALSE; c:TRUE  )
);

const g_OpCodeParams_MAC: array [VSH_MAC] of VSH_OPCODE_PARAMS =
(
    //     ILU OP       MAC OP      ParamA   ParamB   ParamC
    ( {ILU:ILU_NOP; MAC:MAC_NOP;} a:FALSE; b:FALSE; c:FALSE ), // Dxbx note : Unused
    ( {ILU:ILU_NOP; MAC:MAC_MOV;} a:TRUE;  b:FALSE; c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_MUL;} a:TRUE;  b:TRUE;  c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_ADD;} a:TRUE;  b:FALSE; c:TRUE  ),
    ( {ILU:ILU_NOP; MAC:MAC_MAD;} a:TRUE;  b:TRUE;  c:TRUE  ),
    ( {ILU:ILU_NOP; MAC:MAC_DP3;} a:TRUE;  b:TRUE;  c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_DPH;} a:TRUE;  b:TRUE;  c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_DP4;} a:TRUE;  b:TRUE;  c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_DST;} a:TRUE;  b:TRUE;  c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_MIN;} a:TRUE;  b:TRUE;  c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_MAX;} a:TRUE;  b:TRUE;  c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_SLT;} a:TRUE;  b:TRUE;  c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_SGE;} a:TRUE;  b:TRUE;  c:FALSE ),
    ( {ILU:ILU_NOP; MAC:MAC_ARL;} a:TRUE;  b:FALSE; c:FALSE )
);

const MAC_OpCode: array [VSH_MAC] of P_char =
(
    'nop',
    'mov',
    'mul',
    'add',
    'mad',
    'dp3',
    'dph',
    'dp4',
    'dst',
    'min',
    'max',
    'slt',
    'sge',
    'mov' // Cxbx says : really 'arl' - Dxbx note : Alias for 'mov a0.x'
);

const ILU_OpCode: array [VSH_ILU] of P_char =
(
    'nop',
    'mov',
    'rcp',
    'rcc',
    'rsq',
    'exp',
    'log',
    'lit'
);

const OReg_Name: array [VSH_OREG_NAME] of P_char =
(
    'oPos',
    '???',
    '???',
    'oD0',
    'oD1',
    'oFog',
    'oPts',
    'oB0',
    'oB1',
    'oT0',
    'oT1',
    'oT2',
    'oT3',
    '???',
    '???',
    'a0.x'
);

type
  // We use this record to read the various bit-fields in binary vertex shader instructions by name :
  PVSH_ENTRY_Bits = ^VSH_ENTRY_Bits;
  VSH_ENTRY_Bits = packed record
  private
    Data: array[0..3] of DWORD;
    function GetBits(const aIndex: Integer): DWORD;
  public
    property ILU                 : DWORD index ((((1* 32) + 25) shl 8) + 3) read GetBits; // VSH_ILU
    property MAC                 : DWORD index ((((1* 32) + 21) shl 8) + 4) read GetBits; // VSH_MAC
    property ConstantAddress     : DWORD index ((((1* 32) + 13) shl 8) + 8) read GetBits; // C0..C191
    property VRegAddress         : DWORD index ((((1* 32) +  9) shl 8) + 4) read GetBits; // V0..V15
    // INPUT A
    property A_NEG               : DWORD index ((((1* 32) +  8) shl 8) + 1) read GetBits; // Boolean
    property A_SWZ_X             : DWORD index ((((1* 32) +  6) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property A_SWZ_Y             : DWORD index ((((1* 32) +  4) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property A_SWZ_Z             : DWORD index ((((1* 32) +  2) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property A_SWZ_W             : DWORD index ((((1* 32) +  0) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property A_R                 : DWORD index ((((2* 32) + 28) shl 8) + 4) read GetBits;
    property A_MUX               : DWORD index ((((2* 32) + 26) shl 8) + 2) read GetBits; // VSH_PARAMETER_TYPE
    // INPUT B
    property B_NEG               : DWORD index ((((2* 32) + 25) shl 8) + 1) read GetBits;
    property B_SWZ_X             : DWORD index ((((2* 32) + 23) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property B_SWZ_Y             : DWORD index ((((2* 32) + 21) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property B_SWZ_Z             : DWORD index ((((2* 32) + 19) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property B_SWZ_W             : DWORD index ((((2* 32) + 17) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property B_R                 : DWORD index ((((2* 32) + 13) shl 8) + 4) read GetBits;
    property B_MUX               : DWORD index ((((2* 32) + 11) shl 8) + 2) read GetBits; // VSH_PARAMETER_TYPE
    // INPUT C
    property C_NEG               : DWORD index ((((2* 32) + 10) shl 8) + 1) read GetBits;
    property C_SWZ_X             : DWORD index ((((2* 32) +  8) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property C_SWZ_Y             : DWORD index ((((2* 32) +  6) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property C_SWZ_Z             : DWORD index ((((2* 32) +  4) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property C_SWZ_W             : DWORD index ((((2* 32) +  2) shl 8) + 2) read GetBits; // VSH_SWIZZLE
    property C_R_HIGH            : DWORD index ((((2* 32) +  0) shl 8) + 2) read GetBits; // Forms C_R together with
    property C_R_LOW             : DWORD index ((((3* 32) + 30) shl 8) + 2) read GetBits; // this (to bridge a DWord). c0..c15
    property C_MUX               : DWORD index ((((3* 32) + 28) shl 8) + 2) read GetBits; // VSH_PARAMETER_TYPE
    // Output
    property OutputMACWriteMask  : DWORD index ((((3* 32) + 24) shl 8) + 4) read GetBits;
    property OutputRegister      : DWORD index ((((3* 32) + 20) shl 8) + 4) read GetBits; // Dxbx note : 4 bits to select r0..r15
    property OutputILUWriteMask  : DWORD index ((((3* 32) + 16) shl 8) + 4) read GetBits;
    property OutputWriteMask     : DWORD index ((((3* 32) + 12) shl 8) + 4) read GetBits;
    property OutputWriteType     : DWORD index ((((3* 32) + 11) shl 8) + 1) read GetBits; // VSH_OUTPUT_TYPE
    property OutputWriteAddress  : DWORD index ((((3* 32) +  3) shl 8) + 8) read GetBits;
    property OutputMultiplexer   : DWORD index ((((3* 32) +  2) shl 8) + 1) read GetBits; // VSH_OUTPUT_MUX
    // Other
    property A0X                 : DWORD index ((((3* 32) +  1) shl 8) + 1) read GetBits; // Boolean
    property EndOfShader         : DWORD index ((((3* 32) +  0) shl 8) + 1) read GetBits; // Boolean
  end;

const
  NV2A_VertexShaderMaskStr: array [0..15] of string =  (
            // xyzw xyzw
    '',     // 0000 ____
    '.w',   // 0001 ___w
    '.z',   // 0010 __z_
    '.zw',  // 0011 __zw
    '.y',   // 0100 _y__
    '.yw',  // 0101 _y_w
    '.yz',  // 0110 _yz_
    '.yzw', // 0111 _yzw
    '.x',   // 1000 x___
    '.xw',  // 1001 x__w
    '.xz',  // 1010 x_z_
    '.xzw', // 1011 x_zw
    '.xy',  // 1100 xy__
    '.xyw', // 1101 xy_w
    '.xyz', // 1110 xyz_
    ''//.xyzw  1111 xyzw
    );

  // Note : OpenGL seems to be case-sensitive, and requires upper-case opcodes!
  NV2A_MAC_OpCode: array [VSH_MAC] of string = (
    'NOP',
    'MOV',
    'MUL',
    'ADD',
    'MAD',
    'DP3',
    'DPH',
    'DP4',
    'DST',
    'MIN',
    'MAX',
    'SLT',
    'SGE',
    'ARL A0.x' // Dxbx note : Alias for 'mov a0.x'
  );

  NV2A_ILU_OpCode: array [VSH_ILU] of string = (
    'NOP',
    'MOV',
    'RCP',
    'RCP', // Was RCC
    'RSQ',
    'EXP',
    'LOG',
    'LIT'
  );

  NV2A_OReg_Name: array [VSH_OREG_NAME] of string = (
    'R12', // 'oPos',
    '???',
    '???',
    'oD0',
    'oD1',
    'oFog',
    'oPts',
    'oB0',
    'oB1',
    'oT0',
    'oT1',
    'oT2',
    'oT3',
    '???',
    '???',
    'A0.x'
    );

// Dxbx forward declarations :

function VshHandleIsFVF(aHandle: DWORD): boolean; // inline
function VshHandleIsVertexShader(aHandle: DWORD): boolean; inline; // forward
function VshHandleGetVertexShader(aHandle: DWORD): PX_D3DVertexShader; inline; // forward
function VshHandleGetRealHandle(aHandle: DWORD): DWORD; // forward
procedure VshSetSwizzle(pParameter: PVSH_PARAMETER;
                        x: VSH_SWIZZLE;
                        y: VSH_SWIZZLE;
                        z: VSH_SWIZZLE;
                        w: VSH_SWIZZLE); inline;
procedure VshSetMask(pMASK: PDxbxMask;
                           MaskX: boolean;
                           MaskY: boolean;
                           MaskZ: boolean;
                           MaskW: boolean); inline;

function XTL_EmuRecompileVshDeclaration(
  pDeclaration: PDWORD;
  ppRecompiledDeclaration: PPVertexShaderDeclaration;
  pDeclarationSize: PDWORD;
  IsFixedFunction: boolean;
  pVertexDynamicPatch: PVERTEX_DYNAMIC_PATCH
): DWORD; // forward
function XTL_EmuRecompileVshFunction(
    pFunction: PDWORD;
    pRecompiledDeclaration: PVertexShaderDeclaration;
    ppRecompiled: XTL_PLPD3DXBUFFER;
    pOriginalSize: PDWORD;
    bNoReservedConstants: boolean
) : HRESULT; // forward
procedure XTL_FreeVertexDynamicPatch(pVertexShader: PVERTEX_SHADER); // forward
function IsValidCurrentShader(): boolean; // forward
function VshHandleIsValidShader(aHandle: DWORD): boolean; // forward
function VshGetVertexDynamicPatch(Handle: DWORD): PVERTEX_DYNAMIC_PATCH; // forward
function VshGetField(pShaderToken: Puint32;
                     FieldName: VSH_FIELD_NAME): uint08;

implementation

uses
  // Dxbx
    uLog
  , uEmuFS
  , uEmuD3D8;

{$DEFINE _DEBUG_TRACK_VS}

const lfUnit = lfCxbx or lfDxbx or lfVertexShader;

// VSH_ENTRY_Bits :

function VSH_ENTRY_Bits.GetBits(const aIndex: Integer): DWORD;
const DWORD_MASK_BITS = 5 + 8;
begin
  Result := aIndex and ((1 shl DWORD_MASK_BITS) - 1);
  Result := GetDWordBits(Data[aIndex shr DWORD_MASK_BITS], Result);
end;

// VertexShader.h

function VSH_IMD_OUTPUT.IsRegister(aRegType: VSH_IMD_OUTPUT_TYPE; aAddress: int16): Boolean;
begin
  Result := (Type_ = aRegType)
        and (Address = aAddress);
end;

function VSH_PARAMETER.IsRegister(aRegType: VSH_ARGUMENT_TYPE; aAddress: int16): Boolean;
begin
  Result := (Type_ = aRegType)
        and (Address = aAddress);
end;

function VSH_INTERMEDIATE_FORMAT.ReadsFromRegister(aRegType: VSH_ARGUMENT_TYPE; aAddress: Int16): Boolean;
var
  i: int;
begin
  // Check all parameters :
  for i := 0 to 3-1 do
  begin
    if not Parameters[i].Active then
      Continue;

    // Check if one of them reads from the given register :
    Result := Parameters[i].Parameter.IsRegister(aRegType, aAddress);
    if Result then
      Exit;
  end;

  Result := False;
end;

function VSH_INTERMEDIATE_FORMAT.WritesToRegister(aRegType: VSH_ARGUMENT_TYPE; aAddress: Int16): Boolean;
begin
  // Check the output :
  case aRegType of
//    PARAM_UNKNOWN: Result := False;
    PARAM_R: Result := Output.IsRegister(IMD_OUTPUT_R, aAddress);
    PARAM_C: Result := Output.IsRegister(IMD_OUTPUT_C, aAddress);
    PARAM_O: Result := Output.IsRegister(IMD_OUTPUT_O, aAddress);
//    IMD_OUTPUT_A0X ??
  else
    Result := False;
  end;
end;

// Return at what index the given register is written to (and if any reads take place in between).
function VSH_XBOX_SHADER.IsRegisterReadUntilNextWrite(aIndex: int; aRegType: VSH_ARGUMENT_TYPE; aAddress: Int16): Boolean;
var
  i: int;
  Cur: PVSH_INTERMEDIATE_FORMAT;
begin
  Result := False;
  for i := aIndex to IntermediateCount - 1 do
  begin
    Cur := @(Intermediate[i]);
    if Cur.WritesToRegister(aRegType, aAddress) then
      Exit;

    if Cur.ReadsFromRegister(aRegType, aAddress) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure DbgVshPrintf(aStr: string); overload;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
{$ifdef _DEBUG_TRACK_VS}
  if MayLog(lfUnit) then
    printf(aStr);
{$endif}
end;

procedure DbgVshPrintf(aStr: string; Args: array of const); overload;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
{$ifdef _DEBUG_TRACK_VS}
  if MayLog(lfUnit) then
    printf(aStr, Args);
{$endif}
end;

function VshHandleIsFVF(aHandle: DWORD): boolean; // inline
// Branch:Dxbx  Translator:PatrickvL  Done:100
begin
  // Dxbx note : On Xbox, a FVF is recognizable when the handle <= 0x0000FFFF
  // (as all values above are allocated addresses). But since we patch all
  // not-FVF handles (which are actual vertex shaders) bu setting their sign bit
  // we can suffice by testing that :
  Result := IntPtr(aHandle) >= 0; // A test on the sign bit is faster like this
//  Result := (aHandle and $80000000) = 0; // this was the previous (slower) test
end;

function VshHandleIsVertexShader(aHandle: DWORD): boolean; // inline
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := IntPtr(aHandle) < 0; // A test on the sign bit is faster like this
//  Result := (aHandle and $80000000) <> 0; // this was the previous (slower) test
end;

function VshHandleGetVertexShader(aHandle: DWORD): PX_D3DVertexShader; // inline
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := PX_D3DVertexShader(aHandle and $7FFFFFFF); // Mask out the sign bit
end;

// Dxbx note : This tooling function is never used, but clearly illustrates the relation
// between vertex shader's being passed around, and the actual handle value used on PC.
function VshHandleGetRealHandle(aHandle: DWORD): DWORD;
// Branch:Dxbx  Translator:PatrickvL  Done:100
var
  pD3DVertexShader: PX_D3DVertexShader;
  pVertexShader: PVERTEX_SHADER;
begin
  if VshHandleIsVertexShader(aHandle) then
  begin
    pD3DVertexShader := VshHandleGetVertexShader(aHandle);
    Assert(Assigned(pD3DVertexShader));

    pVertexShader := PVERTEX_SHADER(pD3DVertexShader.Handle);
    Assert(Assigned(pVertexShader));

    Result := pVertexShader.Handle;
  end
  else
    Result := aHandle;
end;

// VertexShader.cpp

function IsInUse(const aMask: DxbxMask): boolean; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := (aMask > 0);
end;

function HasMACR(pInstruction: PVSH_SHADER_INSTRUCTION): boolean; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := IsInUse(pInstruction.Output.MACRMask) and (pInstruction.MAC <> MAC_NOP);
end;

function HasMACO(pInstruction: PVSH_SHADER_INSTRUCTION): boolean; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := IsInUse(pInstruction.Output.Mask) and
            (pInstruction.Output.OutputMux = OMUX_MAC) and
            (pInstruction.MAC <> MAC_NOP);
end;

function HasMACARL(pInstruction: PVSH_SHADER_INSTRUCTION): boolean; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := (* Cxbx : (not IsInUse(pInstruction.Output.Mask)) and
            (pInstruction.Output.OutputMux = OMUX_MAC) and*)
            (pInstruction.MAC = MAC_ARL);
end;

function HasILUR(pInstruction: PVSH_SHADER_INSTRUCTION): boolean; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := IsInUse(pInstruction.Output.ILURMask) and (pInstruction.ILU <> ILU_NOP);
end;

function HasILUO(pInstruction: PVSH_SHADER_INSTRUCTION): boolean; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := IsInUse(pInstruction.Output.Mask) and
            (pInstruction.Output.OutputMux = OMUX_ILU) and
            (pInstruction.ILU <> ILU_NOP);
end;

// Retrieves a number of bits in the instruction token
function VshGetFromToken(pShaderToken: Puint32;
                         SubToken: uint08;
                         StartBit: uint08;
                         BitLength: uint08): int; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := (PDWORDs(pShaderToken)[SubToken] shr StartBit) and (not ($FFFFFFFF shl BitLength));
end;

// Converts the C register address to disassembly format
function ConvertCRegister(const CReg: int16): int16; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := ((((CReg shr 5) and 7) - 3) * 32) + (CReg and 31);
end;

function VshGetField(pShaderToken: Puint32;
                     FieldName: VSH_FIELD_NAME): uint08;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := uint08(VshGetFromToken(pShaderToken,
                                   g_FieldMapping[FieldName].SubToken,
                                   g_FieldMapping[FieldName].StartBit,
                                   g_FieldMapping[FieldName].BitLength));
end;

function VshGetOpCodeParams(ILU: VSH_ILU;
                            MAC: VSH_MAC): PVSH_OPCODE_PARAMS;
// Branch:Dxbx  Translator:PatrickvL  Done:100
begin
  if ILU in [ILU_MOV..ILU_LIT] then
    Result := PVSH_OPCODE_PARAMS(@g_OpCodeParams_ILU[ILU])
  else
    if MAC in [MAC_MOV..MAC_ARL] then
      Result := PVSH_OPCODE_PARAMS(@g_OpCodeParams_MAC[MAC])
    else
      Result := nil;
end;

procedure VshParseInstruction(pShaderToken: Puint32;
                              pInstruction: PVSH_SHADER_INSTRUCTION);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  // First get the instruction(s).
  pInstruction.ILU := VSH_ILU(VshGetField(pShaderToken, FLD_ILU));
  pInstruction.MAC := VSH_MAC(VshGetField(pShaderToken, FLD_MAC));

  // Get parameter A
  pInstruction.A.Neg := Boolean(VshGetField(pShaderToken, FLD_A_NEG) > 0);
  pInstruction.A.Type_ := VSH_PARAMETER_TYPE(VshGetField(pShaderToken, FLD_A_MUX));
  case pInstruction.A.Type_ of
    PARAM_R:
      pInstruction.A.Address := VshGetField(pShaderToken, FLD_A_R);

    PARAM_V:
      pInstruction.A.Address := VshGetField(pShaderToken, FLD_V);

    PARAM_C:
      pInstruction.A.Address := ConvertCRegister(VshGetField(pShaderToken, FLD_CONST));

  else
    DbgVshPrintf('Invalid instruction, parameter A type unknown %d'#13#10, [Ord(pInstruction.A.Type_)]);
    Exit;
  end;

  VshSetSwizzle(@pInstruction.A,
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_A_SWZ_X)),
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_A_SWZ_Y)),
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_A_SWZ_Z)),
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_A_SWZ_W)));

  // Get parameter B
  pInstruction.B.Neg := Boolean(VshGetField(pShaderToken, FLD_B_NEG) > 0);
  pInstruction.B.Type_ := VSH_PARAMETER_TYPE(VshGetField(pShaderToken, FLD_B_MUX));
  case pInstruction.B.Type_ of
    PARAM_R:
      pInstruction.B.Address := VshGetField(pShaderToken, FLD_B_R);

    PARAM_V:
      pInstruction.B.Address := VshGetField(pShaderToken, FLD_V);

    PARAM_C:
      pInstruction.B.Address := ConvertCRegister(VshGetField(pShaderToken, FLD_CONST));

  else
    DbgVshPrintf('Invalid instruction, parameter B type unknown %d'#13#10, [Ord(pInstruction.B.Type_)]);
    Exit;
  end;

  VshSetSwizzle(@pInstruction.B,
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_B_SWZ_X)),
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_B_SWZ_Y)),
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_B_SWZ_Z)),
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_B_SWZ_W)));

  // Get parameter C
  pInstruction.C.Neg := Boolean(VshGetField(pShaderToken, FLD_C_NEG) > 0);
  pInstruction.C.Type_ := VSH_PARAMETER_TYPE(VshGetField(pShaderToken, FLD_C_MUX));
  case pInstruction.C.Type_ of
    PARAM_R:
      pInstruction.C.Address := (VshGetField(pShaderToken, FLD_C_R_HIGH) shl 2) or
                                   VshGetField(pShaderToken, FLD_C_R_LOW);
    PARAM_V:
      pInstruction.C.Address := VshGetField(pShaderToken, FLD_V);

    PARAM_C:
      pInstruction.C.Address := ConvertCRegister(VshGetField(pShaderToken, FLD_CONST));

  else
    DbgVshPrintf('Invalid instruction, parameter C type unknown %d'#13#10, [Ord(pInstruction.C.Type_)]);
    Exit;
  end;

  VshSetSwizzle(@pInstruction.C,
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_C_SWZ_X)),
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_C_SWZ_Y)),
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_C_SWZ_Z)),
    VSH_SWIZZLE(VshGetField(pShaderToken, FLD_C_SWZ_W)));

  // Get output

  // Output register
  case VSH_OUTPUT_TYPE(VshGetField(pShaderToken, FLD_OUT_ORB)) of
    OUTPUT_C:
    begin
      pInstruction.Output.Type_ := PARAM_C;
      pInstruction.Output.Address := ConvertCRegister(VshGetField(pShaderToken, FLD_OUT_ADDRESS));
    end;

    OUTPUT_O:
    begin
      pInstruction.Output.Type_ := PARAM_O;
      pInstruction.Output.Address := VshGetField(pShaderToken, FLD_OUT_ADDRESS) and $F;
    end;
  end;

  pInstruction.Output.OutputMux := VSH_OUTPUT_MUX(VshGetField(pShaderToken, FLD_OUT_MUX));
  VshSetMask(@pInstruction.Output.Mask,
    Boolean(VshGetField(pShaderToken, FLD_OUT_O_MASK_X) > 0),
    Boolean(VshGetField(pShaderToken, FLD_OUT_O_MASK_Y) > 0),
    Boolean(VshGetField(pShaderToken, FLD_OUT_O_MASK_Z) > 0),
    Boolean(VshGetField(pShaderToken, FLD_OUT_O_MASK_W) > 0));

  // MAC output
  VshSetMask(@pInstruction.Output.MACRMask,
    Boolean(VshGetField(pShaderToken, FLD_OUT_MAC_MASK_X) > 0),
    Boolean(VshGetField(pShaderToken, FLD_OUT_MAC_MASK_Y) > 0),
    Boolean(VshGetField(pShaderToken, FLD_OUT_MAC_MASK_Z) > 0),
    Boolean(VshGetField(pShaderToken, FLD_OUT_MAC_MASK_W) > 0));
  pInstruction.Output.MACRAddress := VshGetField(pShaderToken, FLD_OUT_R);

  // ILU output
  VshSetMask(@pInstruction.Output.ILURMask,
    Boolean(VshGetField(pShaderToken, FLD_OUT_ILU_MASK_X) > 0),
    Boolean(VshGetField(pShaderToken, FLD_OUT_ILU_MASK_Y) > 0),
    Boolean(VshGetField(pShaderToken, FLD_OUT_ILU_MASK_Z) > 0),
    Boolean(VshGetField(pShaderToken, FLD_OUT_ILU_MASK_W) > 0));
  pInstruction.Output.ILURAddress := VshGetField(pShaderToken, FLD_OUT_R);

  // Finally, get a0.x indirect constant addressing
  pInstruction.a0x := Boolean(VshGetField(pShaderToken, FLD_A0X) > 0);
end; // VshParseInstruction

// Print functions
function VshGetRegisterName(aArgumentType: VSH_PARAMETER_TYPE): string;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  case (aArgumentType) of
    PARAM_R:
      Result := 'r';
    PARAM_V:
      Result := 'v';
    PARAM_C:
      Result := 'c';
    PARAM_O:
      Result := 'oPos';
  else
    Result := '?';
  end;
end;

procedure VshWriteOutputMask(const Mask: DxbxMask;
                             pDisassembly: P_char;
                             pDisassemblyPos: Puint32);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
const
  _x: array [Boolean] of AnsiString = ('', 'x');
  _y: array [Boolean] of AnsiString = ('', 'y');
  _z: array [Boolean] of AnsiString = ('', 'z');
  _w: array [Boolean] of AnsiString = ('', 'w');
begin
  if (Mask and MASK_XYZW) = MASK_XYZW then
  begin
    // All components are there, no need to print the mask
    Exit;
  end;

  Inc(pDisassemblyPos^, sprintf(pDisassembly + pDisassemblyPos^, '.%s%s%s%s', [
    _x[(Mask and MASK_X) > 0],
    _y[(Mask and MASK_Y) > 0],
    _z[(Mask and MASK_Z) > 0],
    _w[(Mask and MASK_W) > 0]]));
end;

procedure VshWriteParameter(pParameter: PVSH_IMD_PARAMETER;
                            pDisassembly: P_char;
                            pDisassemblyPos: Puint32);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
const
  _neg: array [Boolean] of AnsiString = ('', '-');
var
  i: int;
  j: int;
  Swizzle: _char;
begin
  Inc(pDisassemblyPos^, sprintf(pDisassembly + pDisassemblyPos^, ', %s%s', [
                _neg[pParameter.Parameter.Neg],
                VshGetRegisterName(pParameter.Parameter.Type_)]));
  if (pParameter.Parameter.Type_ = PARAM_C) and (pParameter.IndexesWithA0_X) then
  begin
    // Only display the offset if it's not 0.
    if (pParameter.Parameter.Address) > 0 then
    begin
      Inc(pDisassemblyPos^, sprintf(pDisassembly + pDisassemblyPos^, '[a0.x+%d]', [pParameter.Parameter.Address]));
    end
    else
    begin
      Inc(pDisassemblyPos^, sprintf(pDisassembly + pDisassemblyPos^, '[a0.x]'));
    end;
  end
  else
  begin
    Inc(pDisassemblyPos^, sprintf(pDisassembly + pDisassemblyPos^, '%d', [pParameter.Parameter.Address]));
  end;
  // Only bother printing the swizzle if it is not .xyzw
  if not ((pParameter.Parameter.Swizzle[0] = SWIZZLE_X) and
          (pParameter.Parameter.Swizzle[1] = SWIZZLE_Y) and
          (pParameter.Parameter.Swizzle[2] = SWIZZLE_Z) and
          (pParameter.Parameter.Swizzle[3] = SWIZZLE_W)) then
  begin
    Inc(pDisassemblyPos^, sprintf(pDisassembly + pDisassemblyPos^, '.'));
    for i := 0 to 4-1 do
    begin
      Swizzle := '?';
      case (pParameter.Parameter.Swizzle[i]) of
        SWIZZLE_X:
          Swizzle := 'x';
        SWIZZLE_Y:
          Swizzle := 'y';
        SWIZZLE_Z:
          Swizzle := 'z';
        SWIZZLE_W:
          Swizzle := 'w';
      end;
      Inc(pDisassemblyPos^, sprintf(pDisassembly + pDisassemblyPos^, '%s', [Swizzle]));
      // TODO -oDxbx : Shouldn't we do this for i=0 only? :
      j := i;
      while j < 4 do
      begin
        if (pParameter.Parameter.Swizzle[i] <> pParameter.Parameter.Swizzle[j]) then
        begin
          break;
        end;
        Inc(j);
      end; // while
      if (j = 4) then
      begin
        break;
      end;
    end;
  end;
end; // VshWriteParameter

procedure VshWriteShader(pShader: PVSH_XBOX_SHADER;
                         pRecompiledDeclaration: PVertexShaderDeclaration;
                         pDisassembly: P_char;
                         IsConverted: boolean);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  DisassemblyPos: uint32;
  i, j: int;
  pIntermediate: PVSH_INTERMEDIATE_FORMAT;
  pParameter: PVSH_IMD_PARAMETER;
{$IFDEF DXBX_USE_D3D9}
  DclStr: AnsiString;
{$ENDIF}
begin
  DisassemblyPos := 0;
  case pShader.ShaderHeader.Version of
    VERSION_VS:
    begin
{$IFDEF DXBX_USE_VS30}
      Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, 'vs.3.0'#13#10));
{$ELSE}
      Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, 'vs.1.1'#13#10));
{$ENDIF}
    end;
    VERSION_XVS:
      Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, 'xvs.1.1'#13#10));
    VERSION_XVSS:
      Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, 'xvss.1.1'#13#10));
    VERSION_XVSW:
      Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, 'xvsw.1.1'#13#10));
  end;

{$IFDEF DXBX_USE_D3D9}
  if IsConverted then
  begin
    Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '; Input usage declarations :'#13#10));
    // TODO -oDxbx : We have a bit of a problem here, as there's no reliable way
    // to determine what usage the input vertex registers have exactly (some cases
    // might be logical, like a single use to fill a color output register, the
    // input is probably a color register too then). Another method to determine
    // the type of input register usage, is to look at the D3DVSD_REG / D3DVSDT_*
    // registration. (How to get that here?)
    i := 0;
    while (pRecompiledDeclaration.Stream < $FF) and (i < VSH_XBOX_MAX_V_REGISTER_COUNT) do
    begin
      if RegVUsage[i] then
      begin
        case pRecompiledDeclaration.Usage of
          D3DDECLUSAGE_POSITION: DclStr := 'dcl_position';
          D3DDECLUSAGE_BLENDWEIGHT: DclStr := 'dcl_blendweight';
          D3DDECLUSAGE_NORMAL: DclStr := 'dcl_normal';
          D3DDECLUSAGE_COLOR: DclStr := 'dcl_color' + AnsiString(IntToStr(pRecompiledDeclaration.UsageIndex));
          D3DDECLUSAGE_FOG: DclStr := 'dcl_fog';
          D3DDECLUSAGE_TEXCOORD: DclStr := 'dcl_texcoord' + AnsiString(IntToStr(pRecompiledDeclaration.UsageIndex));
        else
          DclStr := '; dcl_unknown';
        end;

        Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '%s v%d'#13#10, [DclStr, i]));
        Inc(pRecompiledDeclaration);
      end;

      Inc(i);
    end;

{$IFDEF DXBX_USE_VS30}
    Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '; Output usage declarations :'#13#10));
    for i := 0 to VSH_XBOX_MAX_O_REGISTER_COUNT - 1 do
    begin
      // Test if this Output-register is actually used :
      if RegOUsage[i] then
      begin
        case VSH_OREG_NAME(i) of
          OREG_OPOS: DclStr := 'dcl_position o%d.xyzw'#13#10;
          OREG_OD0: DclStr := 'dcl_color0 o%d.xyzw'#13#10;
          OREG_OD1: DclStr := 'dcl_color1 o%d.xyzw'#13#10;
          OREG_OFOG: DclStr := 'dcl_fog o%d'#13#10; // .w ?
          OREG_OPTS: DclStr := 'dcl_psize o%d'#13#10;
          OREG_OB0: DclStr := 'dcl_color2 o%d.xyzw'#13#10;
          OREG_OB1: DclStr := 'dcl_color3 o%d.xyzw'#13#10;
          OREG_OT0: DclStr := 'dcl_texcoord0 o%d.xyzw'#13#10;
          OREG_OT1: DclStr := 'dcl_texcoord1 o%d.xyzw'#13#10;
          OREG_OT2: DclStr := 'dcl_texcoord2 o%d.xyzw'#13#10;
          OREG_OT3: DclStr := 'dcl_texcoord3 o%d.xyzw'#13#10;
        else
          DclStr := '; dcl_unknown o%d'#13#10;
        end;
        Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, DclStr, [OREG_MAPPING[VSH_OREG_NAME(i)]]));
      end;
    end;
{$ENDIF DXBX_USE_VS30}

    Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '; Recompiled opcodes :'#13#10));
  end;
{$ENDIF DXBX_USE_D3D9}

  // Dxbx note : Translated 'for' to 'while', because loop condition is a complex expression :
  i := 0; while (i < pShader.IntermediateCount) and ((i < 128) or (not IsConverted)) do
  begin
    pIntermediate := @(pShader.Intermediate[i]);

    if (i = 128) then
    begin
      Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '; -- Passing the truncation limit --'#13#10));
    end;

    // Writing combining sign if necessary
    if (pIntermediate.IsCombined) then
    begin
      Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '+'));
    end;

    // Print the op code
    if (pIntermediate.InstructionType = IMD_MAC) then
    begin
      // Dxbx addition : Safeguard against incorrect MAC opcodes :
      if (Ord(pIntermediate.MAC) > Ord(HIGH(VSH_MAC))) then
        Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '??? '))
      else
        Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '%s ', [MAC_OpCode[pIntermediate.MAC]]))
    end
    else // IMD_ILU
    begin
      // Dxbx addition : Safeguard against incorrect ILU opcodes :
      if (Ord(pIntermediate.ILU) > Ord(HIGH(VSH_ILU))) then
        Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '??? '))
      else
        Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '%s ', [ILU_OpCode[pIntermediate.ILU]]));
    end;

    // Print the output parameter
    if (pIntermediate.Output.Type_ = IMD_OUTPUT_A0X) then
    begin
      Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, 'a0.x'))
    end
    else
    begin
      case (pIntermediate.Output.Type_) of
        IMD_OUTPUT_C:
          Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, 'c%d', [pIntermediate.Output.Address]));
        IMD_OUTPUT_R:
          Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, 'r%d', [pIntermediate.Output.Address]));
        IMD_OUTPUT_O:
          // Dxbx addition : Safeguard against incorrect VSH_OREG_NAME values :
          if (Integer(pIntermediate.Output.Address) > Ord(HIGH(VSH_OREG_NAME))) then
            // don't add anything
          else
          begin
{$IFDEF DXBX_USE_VS30}
            if IsConverted then
              Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, 'o%d', [OREG_MAPPING[VSH_OREG_NAME(pIntermediate.Output.Address)]]))
            else
{$ENDIF}
              Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, '%s', [OReg_Name[VSH_OREG_NAME(pIntermediate.Output.Address)]]));
          end;
      else
        DxbxKrnlCleanup('Invalid output register in vertex shader!');
      end;
      VshWriteOutputMask(pIntermediate.Output.Mask, pDisassembly, @DisassemblyPos);
    end;

    // Print the parameters
    for j := 0 to 3-1 do
    begin
      pParameter := @(pIntermediate.Parameters[j]);
      if (pParameter.Active) then
      begin
        VshWriteParameter(pParameter, pDisassembly, @DisassemblyPos);
      end;
    end;

    Inc(DisassemblyPos, sprintf(pDisassembly + DisassemblyPos, #13#10));
    Inc(i);
  end;
  pDisassembly[DisassemblyPos] := #0;
end; // VshWriteShader

procedure VshAddParameter(pParameter: PVSH_PARAMETER;
                          a0x: boolean;
                          pIntermediateParameter: PVSH_IMD_PARAMETER);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  pIntermediateParameter.Parameter := pParameter^;
  pIntermediateParameter.Active := TRUE;
  pIntermediateParameter.IndexesWithA0_X := a0x;
end;

procedure VshAddParameters(pInstruction: PVSH_SHADER_INSTRUCTION;
                           ILU: VSH_ILU;
                           MAC: VSH_MAC;
                           pParameters: PVSH_IMD_PARAMETERs);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  ParamCount: uint08;
  pParams: PVSH_OPCODE_PARAMS;
begin
  ParamCount := 0;
  pParams := VshGetOpCodeParams(ILU, MAC);

  // param A
  if (pParams.A) then
  begin
    VshAddParameter(@pInstruction.A, pInstruction.a0x, @pParameters[ParamCount]);
    Inc(ParamCount);
  end;

  // param B
  if (pParams.B) then
  begin
    VshAddParameter(@pInstruction.B, pInstruction.a0x, @pParameters[ParamCount]);
    Inc(ParamCount);
  end;

  // param C
  if (pParams.C) then
  begin
    VshAddParameter(@pInstruction.C, pInstruction.a0x, @pParameters[ParamCount]);
    // Inc(ParamCount);
  end;
end; // VshAddParameters

procedure VshVerifyBufferBounds(pShader: PVSH_XBOX_SHADER);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  if (pShader.IntermediateCount = VSH_MAX_INTERMEDIATE_COUNT) then
  begin
    DxbxKrnlCleanup('Shader exceeds conversion buffer!');
  end;
end;

function VshNewIntermediate(pShader: PVSH_XBOX_SHADER): PVSH_INTERMEDIATE_FORMAT;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  VshVerifyBufferBounds(pShader);

  ZeroMemory(@pShader.Intermediate[pShader.IntermediateCount], sizeof(VSH_INTERMEDIATE_FORMAT));

  Result := @pShader.Intermediate[pShader.IntermediateCount];
  Inc(pShader.IntermediateCount);
end;

procedure VshInsertIntermediate(pShader: PVSH_XBOX_SHADER;
                                pIntermediate: PVSH_INTERMEDIATE_FORMAT;
                                Pos: uint16);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  i: int;
begin
  VshVerifyBufferBounds(pShader);

  for i := pShader.IntermediateCount downto Pos do
  begin
    pShader.Intermediate[i + 1] := pShader.Intermediate[i];
  end;
  pShader.Intermediate[Pos] := pIntermediate^;
  Inc(pShader.IntermediateCount);
end;

procedure VshDeleteIntermediate(pShader: PVSH_XBOX_SHADER;
                                Pos: uint16);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  i: int;
begin
  if pShader.IntermediateCount > 1 then // Dxbx addition, to prevent underflow
  for i := Pos to (pShader.IntermediateCount - 1) - 1 do
  begin
    pShader.Intermediate[i] := pShader.Intermediate[i + 1];
  end;
  Dec(pShader.IntermediateCount);
end;

function VshAddInstructionMAC_R(pInstruction: PVSH_SHADER_INSTRUCTION;
                                pShader: PVSH_XBOX_SHADER;
                                IsCombined: boolean): boolean;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  pIntermediate: PVSH_INTERMEDIATE_FORMAT;
begin
  if (not HasMACR(pInstruction)) then
  begin
    Result := FALSE;
    Exit;
  end;

  pIntermediate := VshNewIntermediate(pShader);
  pIntermediate.IsCombined := IsCombined;

  // Opcode
  pIntermediate.InstructionType := IMD_MAC;
  pIntermediate.MAC := pInstruction.MAC;

  // Output param
  pIntermediate.Output.Type_ := IMD_OUTPUT_R;
  pIntermediate.Output.Address := Word(pInstruction.Output.MACRAddress);
  pIntermediate.Output.Mask := pInstruction.Output.MACRMask;

  // Other parameters
  VshAddParameters(pInstruction, ILU_NOP, pInstruction.MAC, @pIntermediate.Parameters[0]);

  Result := TRUE;
end; // VshAddInstructionMAC_R

function VshAddInstructionMAC_O(pInstruction: PVSH_SHADER_INSTRUCTION;
                                pShader: PVSH_XBOX_SHADER;
                                IsCombined: boolean): boolean;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  pIntermediate: PVSH_INTERMEDIATE_FORMAT;
begin
  if (not HasMACO(pInstruction)) then
  begin
    Result := FALSE;
    Exit;
  end;

  pIntermediate := VshNewIntermediate(pShader);
  pIntermediate.IsCombined := IsCombined;

  // Opcode
  pIntermediate.InstructionType := IMD_MAC;
  pIntermediate.MAC := pInstruction.MAC;

  // Output param
  if pInstruction.Output.Type_ = PARAM_C then
    pIntermediate.Output.Type_ := IMD_OUTPUT_C
  else
    pIntermediate.Output.Type_ := IMD_OUTPUT_O;
  pIntermediate.Output.Address := pInstruction.Output.Address;
  pIntermediate.Output.Mask := pInstruction.Output.Mask;

  // Other parameters
  VshAddParameters(pInstruction, ILU_NOP, pInstruction.MAC, @pIntermediate.Parameters[0]);

  Result := TRUE;
end; // VshAddInstructionMAC_O

function VshAddInstructionMAC_ARL(pInstruction: PVSH_SHADER_INSTRUCTION;
                                  pShader: PVSH_XBOX_SHADER;
                                  IsCombined: boolean): boolean;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  pIntermediate: PVSH_INTERMEDIATE_FORMAT;
begin
  if (not HasMACARL(pInstruction)) then
  begin
    Result := FALSE;
    Exit;
  end;

  pIntermediate := VshNewIntermediate(pShader);
  pIntermediate.IsCombined := IsCombined;

  // Opcode
  pIntermediate.InstructionType := IMD_MAC;
  pIntermediate.MAC := pInstruction.MAC;

  // Output param
  pIntermediate.Output.Type_ := IMD_OUTPUT_A0X;
  pIntermediate.Output.Address := pInstruction.Output.Address;

  // Other parameters
  VshAddParameters(pInstruction, ILU_NOP, pInstruction.MAC, @pIntermediate.Parameters[0]);

  Result := TRUE;
end; // VshAddInstructionMAC_ARL

// Dxbx addition : Scalar instructions reading from W should read from X instead
function DxbxFixupScalarParameter(pInstruction: PVSH_SHADER_INSTRUCTION;
                                  pShader: PVSH_XBOX_SHADER;
                                  pParameter: PVSH_PARAMETER): Boolean;
var
  i: int;
  WIsWritten: Boolean;
begin
  // The DirectX vertex shader language specifies that the exp, log, rcc, rcp, and rsq instructions
  // all operate on the "w" component of the input. But the microcode versions of these instructions
  // actually operate on the "x" component of the input.
  Result := False;

  // Test if this is a scalar instruction :
  if pInstruction.ILU in [ILU_RCP, ILU_RCC, ILU_RSQ, ILU_EXP, ILU_LOG] then
  begin
    // Test if this parameter reads all components, including W (TODO : Or should we fixup any W reading swizzle?) :
    if  (pParameter.Swizzle[0] = SWIZZLE_X)
    and (pParameter.Swizzle[1] = SWIZZLE_Y)
    and (pParameter.Swizzle[2] = SWIZZLE_Z)
    and (pParameter.Swizzle[3] = SWIZZLE_W) then
    begin
      // Also test that the .W component is never written to before:
      WIsWritten := False;
      for i := 0 to pShader.IntermediateCount - 1 do
      begin
        // Stop when we reached this instruction :
        if @(pShader.Intermediate[i]) = pInstruction then
          Break;

        // Check if this instruction writes to the .W component of the same input parameter :
        if ((pShader.Intermediate[i].Output.Type_ = IMD_OUTPUT_C) and (pParameter.Type_ = PARAM_C))
        or ((pShader.Intermediate[i].Output.Type_ = IMD_OUTPUT_R) and (pParameter.Type_ = PARAM_R)) then
        begin
          WIsWritten := (pShader.Intermediate[i].Output.Address = pParameter.Address)
                    and ((pShader.Intermediate[i].Output.Mask and MASK_W) > 0);
          if WIsWritten then
            Break;
        end;
      end;

      if not WIsWritten then
      begin
        // Change the read from W into a read from X (this fixes the XDK VolumeLight sample) :
        VshSetSwizzle(pParameter, SWIZZLE_X, SWIZZLE_X, SWIZZLE_X, SWIZZLE_X);
        DbgVshPrintf('Dxbx fixup on scalar instruction applied; Changed read of uninitialized W into a read of X!'#13#10);
        Result := True;
      end;
    end;
  end;
end;

function VshAddInstructionILU_R(pInstruction: PVSH_SHADER_INSTRUCTION;
                                pShader: PVSH_XBOX_SHADER;
                                IsCombined: boolean): boolean;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  pIntermediate: PVSH_INTERMEDIATE_FORMAT;
begin
  if (not HasILUR(pInstruction)) then
  begin
    Result := FALSE;
    Exit;
  end;

  // Dxbx note : Scalar instructions read from C, but use X instead of W, fix that :
  DxbxFixupScalarParameter(pInstruction, pShader, @pInstruction.C);

  pIntermediate := VshNewIntermediate(pShader);
  pIntermediate.IsCombined := IsCombined;

  // Opcode
  pIntermediate.InstructionType := IMD_ILU;
  pIntermediate.ILU := pInstruction.ILU;

  // Output param
  pIntermediate.Output.Type_ := IMD_OUTPUT_R;
  // If this is a combined instruction, only r1 is allowed (R address should not be used)
  if IsCombined then
    pIntermediate.Output.Address := 1
  else
    pIntermediate.Output.Address := Word(pInstruction.Output.ILURAddress);
  pIntermediate.Output.Mask := pInstruction.Output.ILURMask;

  // Other parameters
  VshAddParameters(pInstruction, pInstruction.ILU, MAC_NOP, @pIntermediate.Parameters[0]);

  Result := TRUE;
end; // VshAddInstructionILU_R

function VshAddInstructionILU_O(pInstruction: PVSH_SHADER_INSTRUCTION;
                                pShader: PVSH_XBOX_SHADER;
                                IsCombined: boolean): boolean;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  pIntermediate: PVSH_INTERMEDIATE_FORMAT;
begin
  if (not HasILUO(pInstruction)) then
  begin
    Result := FALSE;
    Exit;
  end;

  pIntermediate := VshNewIntermediate(pShader);
  pIntermediate.IsCombined := IsCombined;

  // Opcode
  pIntermediate.InstructionType := IMD_ILU;
  pIntermediate.ILU := pInstruction.ILU;

  // Output param
  if pInstruction.Output.Type_ = PARAM_C then
    pIntermediate.Output.Type_ := IMD_OUTPUT_C
  else
    pIntermediate.Output.Type_ := IMD_OUTPUT_O;

  pIntermediate.Output.Address := pInstruction.Output.Address;
  pIntermediate.Output.Mask := pInstruction.Output.Mask;

  // Other parameters
  VshAddParameters(pInstruction, pInstruction.ILU, MAC_NOP, @pIntermediate.Parameters[0]);
  Result := TRUE;
end; // VshAddInstructionILU_O

procedure VshConvertToIntermediate(pInstruction: PVSH_SHADER_INSTRUCTION;
                                   pShader: PVSH_XBOX_SHADER);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  IsCombined: boolean;
begin
  // Five types of instructions:
  //   MAC
  //
  //   ILU
  //
  //   MAC
  //   +ILU
  //
  //   MAC
  //   +MAC
  //   +ILU
  //
  //   MAC
  //   +ILU
  //   +ILU
  IsCombined := FALSE;

  if (VshAddInstructionMAC_R(pInstruction, pShader, IsCombined)) then
  begin
    if (HasMACO(pInstruction) or
        HasILUR(pInstruction) or
        HasILUO(pInstruction)) then
    begin
      IsCombined := TRUE;
    end;
  end;

  if (VshAddInstructionMAC_O(pInstruction, pShader, IsCombined)) then
  begin
    if (HasILUR(pInstruction) or
        HasILUO(pInstruction)) then
    begin
      IsCombined := TRUE;
    end;
  end;

  // Special case, arl (mov a0.x, ...)
  if (VshAddInstructionMAC_ARL(pInstruction, pShader, IsCombined)) then
  begin
    if (HasILUR(pInstruction) or
        HasILUO(pInstruction)) then
    begin
      IsCombined := TRUE;
    end;
  end;

  if (VshAddInstructionILU_R(pInstruction, pShader, IsCombined)) then
  begin
    if (HasILUO(pInstruction)) then
    begin
      IsCombined := TRUE;
    end;
  end;

  {ignore}VshAddInstructionILU_O(pInstruction, pShader, IsCombined);
end; // VshConvertToIntermediate

procedure VshSetSwizzle(pParameter: PVSH_PARAMETER;
                        x: VSH_SWIZZLE;
                        y: VSH_SWIZZLE;
                        z: VSH_SWIZZLE;
                        w: VSH_SWIZZLE); inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  pParameter.Swizzle[0] := x;
  pParameter.Swizzle[1] := y;
  pParameter.Swizzle[2] := z;
  pParameter.Swizzle[3] := w;

  if (x = y) and (y = z) and (z = w) then
  begin
    if x = SWIZZLE_X then
      pParameter.Mask := MASK_X
    else
    if x = SWIZZLE_Y then
      pParameter.Mask := MASK_Y
    else
    if x = SWIZZLE_Z then
      pParameter.Mask := MASK_Z
    else
      pParameter.Mask := MASK_W;
  end
  else
    pParameter.Mask := MASK_XYZW;
end;

procedure VshSetMask(pMask: PDxbxMask;
                           MaskX: boolean;
                           MaskY: boolean;
                           MaskZ: boolean;
                           MaskW: boolean); inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  pMask^ := 0;
  if MaskX then pMask^ := pMask^ or MASK_X;
  if MaskY then pMask^ := pMask^ or MASK_Y;
  if MaskZ then pMask^ := pMask^ or MASK_Z;
  if MaskW then pMask^ := pMask^ or MASK_W;
end;

(*
    mul oPos.xyz, r12, c-38
    +rcc r1.x, r12.w

    mad oPos.xyz, r12, r1.x, c-37
*)
procedure VshRemoveScreenSpaceInstructions(pShader: PVSH_XBOX_SHADER);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  RccOutputRegAddress: int;
  deleted: int;
  i: int;
  pIntermediate: PVSH_INTERMEDIATE_FORMAT;
  MulIntermediate: VSH_INTERMEDIATE_FORMAT;
  AddIntermediate: VSH_INTERMEDIATE_FORMAT;
begin
  deleted := 0;
  RccOutputRegAddress := -1;

  // Dxbx note : Run backwards, so we don't need to consider index-differences because of deletions
  // and because this scan actually needs to see "mad oPos.xyz, r12, r#.x, c-37" first to determine '#' :
  i := pShader.IntermediateCount; while i > 0 do
  begin
    Dec(i);
    pIntermediate := @pShader.Intermediate[i];

{$IFDEF DXBX_REMOVE_V9_FOR_COMPRESSEDVERTICES}
    // The faulty instruction reads "mov oT0, V9", just check for V9 :
    // TODO : This must become a generic fix (either remove or declare/guess undeclared vertex registers).
    if pIntermediate.Parameters[0].Parameter.IsRegister(PARAM_V, 9) then
    begin
      VshDeleteIntermediate(pShader, i);
      DbgVshPrintf('Removed v9 access'#13#10);
    end else
{$ENDIF}
    // The two special instructions (both MAC opcodes) should only be tested on the 3rd parameter (when it's not indexed) :
    if  (pIntermediate.InstructionType = IMD_MAC)
    and (not pIntermediate.Parameters[2].IndexesWithA0_X) then
    begin
      // Check for "mad oPos.xyz, r12, r#.x, c-37"
      if (pIntermediate.MAC = MAC_MAD)
      and (pIntermediate.Parameters[2].Parameter.IsRegister(PARAM_C, X_D3DSCM_RESERVED_CONSTANT2{=-37}))
      and (pIntermediate.Parameters[1].Active)
      and (pIntermediate.Parameters[1].Parameter.Type_ = PARAM_R) then
      begin
        // Found the instruction, so remove it (but remember the '#' part) :
        RccOutputRegAddress := pIntermediate.Parameters[1].Parameter.Address;
        VshDeleteIntermediate(pShader, i);
        DbgVshPrintf('Deleted mad oPos.xyz, r12, r#.x, c-37'#13#10);
        Inc(deleted);
        Continue;
      end;

      // Check for "mul oPos.xyz, r12, c-38"
      if  (pIntermediate.MAC = MAC_MUL)
      and (pIntermediate.Output.IsRegister(IMD_OUTPUT_O, ORD(OREG_OPOS)))
      and (pIntermediate.Parameters[0].Parameter.IsRegister(PARAM_R, 12))
      and (pIntermediate.Parameters[1].Parameter.IsRegister(PARAM_C, X_D3DSCM_RESERVED_CONSTANT1{=-38})) then
      begin
        // Found the instruction, so remove it :
        VshDeleteIntermediate(pShader, i);
        DbgVshPrintf('Deleted mul oPos.xyz, r12, c-38'#13#10);
        Inc(deleted);
        Continue;
      end;
    end;

    // Check for "+rcc r#.x, r12.w" (once we know what register to search for) :
    if  (RccOutputRegAddress >= 0)
    and (pIntermediate.InstructionType = IMD_ILU)
    and (pIntermediate.ILU = ILU_RCC)
    and (pIntermediate.Output.IsRegister(IMD_OUTPUT_R, RccOutputRegAddress)) then
    begin
      // Dxbx addition : Check that this output register is not read (until being written to) again.
      // (Note, that the "mad oPos.xyz, r12, r#.x, c-37" instruction is already removed, since we
      // execute this search backwards, so that won't give us a false positive here) :
      if not pShader.IsRegisterReadUntilNextWrite(i+1, PARAM_R, RccOutputRegAddress) then
      begin
        DbgVshPrintf('Deleted (+)rcc r#.x, r12.w'#13#10);
        VshDeleteIntermediate(pShader, i);
        // Don't count this deletion (it might not happen and is not relevant for the following code)
      end;
    end;

  end; // while instructions

  // If we couldn't find the generic screen space transformation we're
  // assuming that the shader writes direct screen coordinates that must be
  // normalized. This hack will fail if (a) the shader uses custom screen
  // space transformation, (b) reads r10 or r11 after we have written to
  // them, or (c) doesn't reserve c-38 and c-37 for scale and offset.
  if (deleted <> 2) then
  begin
    EmuWarning('Applying screen space vertex shader patching hack!');
    // Dxbx note : Translated 'for' to 'while', because counter is incremented twice :
    i := 0; while i < pShader.IntermediateCount do
    begin
      pIntermediate := @pShader.Intermediate[i];

      // Find instructions outputting to oPos.
      // (?opcode? oPos.[mask], ...)
      if pIntermediate.Output.IsRegister(IMD_OUTPUT_O, Ord(OREG_OPOS)) then
      begin
        // Redirect output to r11. (?opcode? r11.[mask], ...)
        pIntermediate.Output.Type_    := IMD_OUTPUT_R;
        pIntermediate.Output.Address  := 11;

        // Scale r11 to r10. (mul r10.[mask], r11, c58)   r10 = r11 * c58
        MulIntermediate.IsCombined        := FALSE;
        MulIntermediate.InstructionType   := IMD_MAC;
        MulIntermediate.MAC               := MAC_MUL;
        MulIntermediate.Output.Type_      := IMD_OUTPUT_R;
        MulIntermediate.Output.Address    := 10;
        MulIntermediate.Output.Mask       := pIntermediate.Output.Mask;
        // Set first parameter :
        MulIntermediate.Parameters[0].Active                  := TRUE;
        MulIntermediate.Parameters[0].IndexesWithA0_X         := FALSE;
        MulIntermediate.Parameters[0].Parameter.Type_ := PARAM_R;
        MulIntermediate.Parameters[0].Parameter.Address       := 11;
        MulIntermediate.Parameters[0].Parameter.Neg           := FALSE;
        VshSetSwizzle(@MulIntermediate.Parameters[0].Parameter, SWIZZLE_X, SWIZZLE_Y, SWIZZLE_Z, SWIZZLE_W);
        // Set second parameter :
        MulIntermediate.Parameters[1].Active                  := TRUE;
        MulIntermediate.Parameters[1].IndexesWithA0_X         := FALSE;
        MulIntermediate.Parameters[1].Parameter.Type_ := PARAM_C;
        // Dxbx note : Cxbx calls ConvertCRegister(58) here, but doing a conversion seems incorrect.
        // That, and the constant address is also corrected afterwards, so use the original :
        MulIntermediate.Parameters[1].Parameter.Address       := X_D3DSCM_RESERVED_CONSTANT1{=-38};

        MulIntermediate.Parameters[1].Parameter.Neg           := FALSE;
        VshSetSwizzle(@MulIntermediate.Parameters[1].Parameter, SWIZZLE_X, SWIZZLE_Y, SWIZZLE_Z, SWIZZLE_W);
        // Disable third parameter :
        MulIntermediate.Parameters[2].Active                  := FALSE;
        // Insert this instruction :
        Inc(i); VshInsertIntermediate(pShader, @MulIntermediate, i);

        // Add offset with r10 to oPos (add oPos.[mask], r10, c59)
        // Start with a copy of the previous multiplication :
        AddIntermediate := MulIntermediate;
        AddIntermediate.MAC               := MAC_ADD;
        AddIntermediate.Output.Type_      := IMD_OUTPUT_O;
        AddIntermediate.Output.Address    := Ord(OREG_OPOS);
        AddIntermediate.Parameters[0].Parameter.Address       := 10;
        // Dxbx note : Cxbx calls ConvertCRegister(59) here, but doing a conversion seems incorrect.
        // That, and the constant address is also corrected afterwards, so use the original :
        AddIntermediate.Parameters[1].Parameter.Address       := X_D3DSCM_RESERVED_CONSTANT2{=-37};
        // Insert this instruction :
        Inc(i); VshInsertIntermediate(pShader, @AddIntermediate, i);
      end;

      Inc(i);
    end; // while
  end;
end; // VshRemoveScreenSpaceInstructions

function VshRemoveBacksideInstructions(pShader: PVSH_XBOX_SHADER): int;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  i: int;
  pIntermediate: PVSH_INTERMEDIATE_FORMAT;
begin
  Result := 0;
  // Dxbx note : Translated 'for' to 'while', because counter is incremented twice :
  i := 0; while i < pShader.IntermediateCount do
  begin
    pIntermediate := @pShader.Intermediate[i];

    if  (pIntermediate.Output.Type_ = IMD_OUTPUT_O)
    and (   (pIntermediate.Output.Address = Ord(OREG_OB0))
         or (pIntermediate.Output.Address = Ord(OREG_OB1))) then
    begin
      VshDeleteIntermediate(pShader, i);
      Inc(Result);
    end
    else
      Inc(i);
  end; // while

  if Result > 0 then
    EmuWarning('Removed %d backside lighting register assignments!', [Result]);
end; // VshRemoveBacksideInstructions

// Converts the intermediate format vertex shader to DirectX 8 format
function VshConvertShader(pShader: PVSH_XBOX_SHADER;
                          bNoReservedConstants: boolean): boolean;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  RUsage: array [0..VSH_NATIVE_MAX_R_REGISTER_COUNT] of int; // Not -1, to get 1 extra (at least 13: r0-r12)
  i: int;
  j: int;
  k: int;
  pIntermediate: PVSH_INTERMEDIATE_FORMAT;
  TmpIntermediate: VSH_INTERMEDIATE_FORMAT;
  R12Replacement: int;
  pOPosWriteBack: PVSH_INTERMEDIATE_FORMAT;
  DPHReplacement: int;

  function _WritesRegister(pIntermediate: PVSH_INTERMEDIATE_FORMAT; RegisterAddress: int): boolean;
  begin
    if (RegisterAddress = 12) then
      Result := (pIntermediate.Output.Type_ = IMD_OUTPUT_O)
    else
      Result := (pIntermediate.Output.IsRegister(IMD_OUTPUT_R, RegisterAddress));
  end;

  function _ReadsRegister(pIntermediate: PVSH_INTERMEDIATE_FORMAT; RegisterAddress: int): int;
  begin
    Result := 2;
    while Result >= 0 do
    begin
      if  (pIntermediate.Parameters[Result].Active)
      and (pIntermediate.Parameters[Result].Parameter.Type_ = PARAM_R)
      and (pIntermediate.Parameters[Result].Parameter.Address = RegisterAddress) then
        Exit;

      Dec(Result);
    end;
  end;

  function _RegisterIsWrittenBeforeRead(RangeStart, RangeEnd, RegisterAddress: int): boolean;
  var
    i: int;
    WrittenMask: DxbxMask;
    pIntermediate: PVSH_INTERMEDIATE_FORMAT;
    j: int;
  begin
    WrittenMask := 0;
    for i := RangeStart to RangeEnd do
    begin
      pIntermediate := @pShader.Intermediate[i];

      // Check that the only reads on this register happen on channels that are written to in this range :
      for j := 0 to 2 do
        if  (pIntermediate.Parameters[j].Active)
        and (pIntermediate.Parameters[j].Parameter.Type_ = PARAM_R)
        and (pIntermediate.Parameters[j].Parameter.Address = RegisterAddress) then
          if ((pIntermediate.Parameters[j].Parameter.Mask and (not WrittenMask)) > 0) then
          begin
            Result := False;
            Exit;
          end;

      // Collect all channels that are written to :
      if _WritesRegister(pIntermediate, RegisterAddress) then
      begin
        WrittenMask := WrittenMask or pIntermediate.Output.Mask;
        // Mask won't grow any further, we're done :
        if WrittenMask = MASK_XYZW then
          Break;
      end;
    end;

    // No failures, this register is only read when written to!
    Result := True;
  end; // _RegisterIsWrittenBeforeRead

  function _DetermineRegisterUsageInRange(RangeStart, RangeEnd, RegisterAddress: int; out FirstWrite, LastRead: int): boolean;
  var
    i: int;
    pIntermediate: PVSH_INTERMEDIATE_FORMAT;
  begin
    Result := False;
    {out}FirstWrite := -1;
    {out}LastRead := 0;
    // Determine the linespan in which the given register is used :
    for i := RangeStart to RangeEnd do
    begin
      pIntermediate := @pShader.Intermediate[i];

      if {out}FirstWrite < 0 then
      begin
        if _WritesRegister(pIntermediate, RegisterAddress) then
        begin
          // Remember where this register was first written to :
          {out}FirstWrite := i;
          Result := True;
        end;
      end;

      if _ReadsRegister(pIntermediate, RegisterAddress) >= 0 then
      begin
        {out}LastRead := i;
        Result := True;
      end;
    end; // for
  end; // _DetermineRegisterUsageInRange

  function _FindFreeRegister(out FreeRegister: int): boolean;
  var
    i: int;
    LeastUsed: int;
    LeastUsed_FirstWrite, LeastUsed_LastRead: int;
    pIntermediate: PVSH_INTERMEDIATE_FORMAT;
  begin
    // First, try to find an unused register (and determine which one was least used for the later fallback) :
    LeastUsed := 0;
    for i := VSH_NATIVE_MAX_R_REGISTER_COUNT-1 downto 0 do
    begin
      if (RUsage[i] = 0) then
      begin
        {out}FreeRegister := i;
        Result := True;
        Exit;
      end;

      if RUsage[LeastUsed] > RUsage[i] then
        LeastUsed := i;
    end;

    // Try to free up the least used register;
    {out}FreeRegister := -1;

    // Determine the linespan in which that register is used :
    _DetermineRegisterUsageInRange(0, pShader.IntermediateCount-1, {Register=}LeastUsed, {out}LeastUsed_FirstWrite, {out}LeastUsed_LastRead);

    // Loop over all registers (except 12) :
    for i := 0 to 12 - 1 do
    begin
      // Skip the register we're trying to free up :
      if i = LeastUsed then
        Continue;

      // Now find a register that's not persisted across the usage-range of the LeastUsed register :
      if _RegisterIsWrittenBeforeRead(LeastUsed_FirstWrite+1, pShader.IntermediateCount-1, {Register=}i) then
      begin
        // Remember this ReplacementRegister in the FreeRegister :
        {out}FreeRegister := i;
        Break;
      end;
    end;

    if FreeRegister < 0 then
    begin
      // We couldn't free up a register :
      Result := False;
      Exit;
    end;

    // Change the usage of the LeastUsed register into the ReplacementRegister :
    for i := LeastUsed_FirstWrite to LeastUsed_LastRead do
    begin
      pIntermediate := @pShader.Intermediate[i];
      if _WritesRegister(pIntermediate, LeastUsed) then
        pIntermediate.Output.Address := FreeRegister;

      if _ReadsRegister(pIntermediate, LeastUsed) = 2 then
        pIntermediate.Parameters[2].Parameter.Address := FreeRegister;
      if _ReadsRegister(pIntermediate, LeastUsed) = 1 then
        pIntermediate.Parameters[1].Parameter.Address := FreeRegister;
      if _ReadsRegister(pIntermediate, LeastUsed) = 0 then
        pIntermediate.Parameters[0].Parameter.Address := FreeRegister;
    end;

    // Now that the LeastUsedRegister is gone, return that as a free register :
    DbgVshPrintf('Freed up register r%d by replacing it with r%d in lines %d-%d'#13#10,
      [LeastUsed, FreeRegister, LeastUsed_FirstWrite, LeastUsed_LastRead]);
    {out}FreeRegister := LeastUsed;
    Result := True;
  end; // _FindFreeRegister

begin
  DPHReplacement := -1;
  for i := 0 to VSH_NATIVE_MAX_R_REGISTER_COUNT do // Not -1, to get 1 extra (at least r12)
    RUsage[i] := 0;

{$IFDEF DXBX_USE_D3D9}
  for i := 0 to VSH_XBOX_MAX_V_REGISTER_COUNT - 1 do
    RegVUsage[i] := FALSE;
{$ENDIF}

{$IFDEF DXBX_USE_VS30}
  for i := 0 to VSH_XBOX_MAX_O_REGISTER_COUNT - 1 do
    RegOUsage[i] := FALSE;
{$ENDIF}

  // TODO -oDxbx : Xbox can write to OREG_OD0 and OREG_OD1, while Direct3D8 marks these as read-only; How to fix that?

  // TODO -oCXBX: What about state shaders and such?
  pShader.ShaderHeader.Version := VERSION_VS;

  // Search for the screen space instructions, and remove them
  if (not bNoReservedConstants) then
  begin
    VshRemoveScreenSpaceInstructions(pShader);
  end;

  // Search & remove opcodes that write to the (unsupported) backside color registers (oB0 and oB1) :
  VshRemoveBacksideInstructions(pShader);

  // Dxbx note : Translated 'for' to 'while', because counter is incremented twice :
  i := 0; while i < pShader.IntermediateCount do
  begin
    pIntermediate := @pShader.Intermediate[i];
    // Combining not supported in vs.1.1
    pIntermediate.IsCombined := FALSE;

    (* MARKED OUT CXBX
    if (pIntermediate.Output.Type = IMD_OUTPUT_O) and (pIntermediate.Output.Address = OREG_OFOG) then
    begin
        // The PC shader assembler doesn't like masks on scalar registers
        VshSetMask(@pIntermediate.Output.Mask, TRUE, TRUE, TRUE, TRUE);
    end;
    *)

    if (pIntermediate.InstructionType = IMD_ILU) and (pIntermediate.ILU = ILU_RCC) then
    begin
      // Convert rcc to rcp
      DbgVshPrintf('Converted rcc to rcp'#13#10);
      pIntermediate.ILU := ILU_RCP;
    end;

    if (pIntermediate.Output.Type_ = IMD_OUTPUT_R) then
    begin
      Inc(RUsage[pIntermediate.Output.Address]);
    end;

    // Make constant registers range from 0 to 191 instead of -96 to 95
    if (pIntermediate.Output.Type_ = IMD_OUTPUT_C) then
    begin
      // Dxbx note : This should NOT be done version-dependantly!
      Inc(pIntermediate.Output.Address, X_D3DSCM_CORRECTION);
    end;

{$IFDEF DXBX_USE_VS30}
    if (pIntermediate.Output.Type_ = IMD_OUTPUT_O) then
      RegOUsage[pIntermediate.Output.Address] := TRUE;
{$ENDIF}

    for j := 0 to 3-1 do
    begin
      if (pIntermediate.Parameters[j].Parameter.Type_ = PARAM_R) then
      begin
        // Dxbx fix : Here, Active does seem to apply :
        if (pIntermediate.Parameters[j].Active) then
          Inc(RUsage[pIntermediate.Parameters[j].Parameter.Address]);
      end else
      if (pIntermediate.Parameters[j].Parameter.Type_ = PARAM_C) then
      begin
        // Dxbx fix : PARAM_C correction shouldn't depend on Active!

        // Make constant registers range from 0 to 191 instead of -96 to 95 :
        // Dxbx note : This should NOT be done version-dependantly!
        // Dxbx note 2 : Turok shows c[a0.x] indexes must also be corrected
        // TODO -oDxbx : Find out why MatrixPaletteSkinning is flickering so much
        Inc(pIntermediate.Parameters[j].Parameter.Address, X_D3DSCM_CORRECTION);
      end else
      if (pIntermediate.Parameters[j].Parameter.Type_ = PARAM_V) then
      begin
{$IFDEF DXBX_USE_D3D9}
        if (pIntermediate.Parameters[j].Active) then
          RegVUsage[pIntermediate.Parameters[j].Parameter.Address] := TRUE;
{$ENDIF}
      end;
    end;

    if (pIntermediate.InstructionType = IMD_MAC) and (pIntermediate.MAC = MAC_DPH) then
    begin
      // 2010/01/12 - revel8n - attempt to alleviate conversion issues relate to the dph instruction

      // Replace dph with dp3 and add
      if (pIntermediate.Output.Type_ <> IMD_OUTPUT_R) then
      begin
        // attempt to find unused register...
        if DPHReplacement = -1 then
        begin
          // return failure if there are no available registers
          if not _FindFreeRegister({out}DPHReplacement) then
          begin
            EmuWarning('Vertex shader uses all r registers, dph impossible to convert!');
            Result := FALSE;
            Exit;
          end;
        end;

        TmpIntermediate := pIntermediate^;

        // modify the instructions
        pIntermediate.MAC := MAC_DP3;
        pIntermediate.Output.Type_ := IMD_OUTPUT_R;
        pIntermediate.Output.Address := DPHReplacement;
        VshSetMask(@pIntermediate.Output.Mask, TRUE, TRUE, TRUE, TRUE);

        TmpIntermediate.MAC := MAC_ADD;
        TmpIntermediate.Parameters[0].IndexesWithA0_X := FALSE;
        TmpIntermediate.Parameters[0].Parameter.Type_ := PARAM_R;
        TmpIntermediate.Parameters[0].Parameter.Address := DPHReplacement;
        TmpIntermediate.Parameters[0].Parameter.Neg := FALSE;
        // VshSetSwizzle(@TmpIntermediate.Parameters[0].Parameter, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W);
        VshSetSwizzle(@TmpIntermediate.Parameters[1].Parameter, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W);
        //VshSetMask(@TmpIntermediate.Output.Mask, FALSE, FALSE, FALSE, TRUE);
        VshInsertIntermediate(pShader, @TmpIntermediate, i + 1);

        Inc(RUsage[DPHReplacement], 2); // 1 write, 1 read

        DbgVshPrintf('Replaced dph with dp3+add (via r%d)'#13#10, [TmpIntermediate.Parameters[0].Parameter.Address]);
      end
      else
      begin
        TmpIntermediate := pIntermediate^;
        pIntermediate.MAC := MAC_DP3;
        TmpIntermediate.MAC := MAC_ADD;
        TmpIntermediate.Parameters[0].IndexesWithA0_X := FALSE;
        TmpIntermediate.Parameters[0].Parameter.Type_ := PARAM_R;
        TmpIntermediate.Parameters[0].Parameter.Address := TmpIntermediate.Output.Address;
        TmpIntermediate.Parameters[0].Parameter.Neg := FALSE;

        case (TmpIntermediate.Output.Mask) of
          MASK_X: begin
            VshSetSwizzle(@TmpIntermediate.Parameters[0].Parameter, SWIZZLE_X, SWIZZLE_X, SWIZZLE_X, SWIZZLE_X);
          end;
          MASK_Y: begin
            VshSetSwizzle(@TmpIntermediate.Parameters[0].Parameter, SWIZZLE_Y, SWIZZLE_Y, SWIZZLE_Y, SWIZZLE_Y);
          end;
          MASK_Z: begin
            VshSetSwizzle(@TmpIntermediate.Parameters[0].Parameter, SWIZZLE_Z, SWIZZLE_Z, SWIZZLE_Z, SWIZZLE_Z);
          end;
          MASK_W: begin
            VshSetSwizzle(@TmpIntermediate.Parameters[0].Parameter, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W);
          end;
        // 15: begin
        else // default:
          VshSetSwizzle(@TmpIntermediate.Parameters[0].Parameter, SWIZZLE_X, SWIZZLE_Y, SWIZZLE_Z, SWIZZLE_W);
          break;
        end;
        //VshSetSwizzle(@TmpIntermediate.Parameters[0].Parameter, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W);
        VshSetSwizzle(@TmpIntermediate.Parameters[1].Parameter, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W);
        //VshSetMask(@TmpIntermediate.Output.Mask, FALSE, FALSE, FALSE, TRUE);
        VshInsertIntermediate(pShader, @TmpIntermediate, i + 1);

        DbgVshPrintf('Replaced dph with dp3+add'#13#10);
      end;

      Inc(i);
    end; // if

    Inc(i);
  end; // while

  // r12 is a special thirteenth register that can be use to read back the current value of oPos.
  // r12 can only be used as an input register and oPos can only be used as an output register.
  if (RUsage[12] > 0) then
  begin
    // Sigh, they absolutely had to use r12, didn't they?
    if not _FindFreeRegister({out}R12Replacement) then
    begin
      EmuWarning('Vertex shader uses all r registers; impossible to use another register instead of r12!');
      Result := FALSE;
      Exit;
    end;

    DbgVshPrintf('Replacing r12 with r%d'#13#10, [R12Replacement]);

    if pShader.IntermediateCount > 0 then // Dxbx addition, to prevent underflow
    for j := 0 to pShader.IntermediateCount - 1 do
    begin
      pIntermediate := @pShader.Intermediate[j];
      if (pIntermediate.Output.IsRegister(IMD_OUTPUT_O, Ord(OREG_OPOS))) then
      begin
        // Found instruction writing to oPos
        pIntermediate.Output.Type_ := IMD_OUTPUT_R;
        pIntermediate.Output.Address := R12Replacement;
        Inc(RUsage[R12Replacement]);
      end;

      for k := 0 to 3-1 do
      begin
        if (pIntermediate.Parameters[k].Active) then
        begin
          if (pIntermediate.Parameters[k].Parameter.Type_ = PARAM_R) and
             (pIntermediate.Parameters[k].Parameter.Address = 12) then
          begin
            // Found a r12 used as a parameter; replace
            pIntermediate.Parameters[k].Parameter.Address := R12Replacement;
            Inc(RUsage[R12Replacement]);
          end
// Dxbx fix : C-38 is readily available to us!
//          else if (pIntermediate.Parameters[k].Parameter.Type_ = PARAM_C) and
//                  (pIntermediate.Parameters[k].Parameter.Address = ({58=}X_D3DSCM_RESERVED_CONSTANT1{=-38}+X_D3DSCM_CORRECTION{=96})) and
//                  (not pIntermediate.Parameters[k].IndexesWithA0_X) then
// if (not bNoReservedConstants) then
//          begin
//            // Found c-38, replace it with r12.w
//            pIntermediate.Parameters[k].Parameter.Type_ := PARAM_R;
//            pIntermediate.Parameters[k].Parameter.Address := R12Replacement;
//            Inc(RUsage[R12Replacement]);
//            VshSetSwizzle(@pIntermediate.Parameters[k].Parameter, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W, SWIZZLE_W);
//          end;
        end;
      end;
    end;

    // Append (mov oPos, r##) at the end
    pOPosWriteBack := VshNewIntermediate(pShader);
    pOPosWriteBack.InstructionType := IMD_ILU;
    pOPosWriteBack.ILU := ILU_MOV;
    pOPosWriteBack.MAC := MAC_NOP;
    pOPosWriteBack.Output.Type_ := IMD_OUTPUT_O;
    pOPosWriteBack.Output.Address := Ord(OREG_OPOS);
    VshSetMask(@pOPosWriteBack.Output.Mask, TRUE, TRUE, TRUE, TRUE);
    pOPosWriteBack.Parameters[0].Active := TRUE;
    pOPosWriteBack.Parameters[0].Parameter.Type_ := PARAM_R;
    pOPosWriteBack.Parameters[0].Parameter.Address := R12Replacement;
    Inc(RUsage[R12Replacement]);
    VshSetSwizzle(@pOPosWriteBack.Parameters[0].Parameter, SWIZZLE_X, SWIZZLE_Y, SWIZZLE_Z, SWIZZLE_W);
  end;

  Result := TRUE;
end; // VshConvertShader

// ****************************************************************************
// * Vertex shader declaration recompiler
// ****************************************************************************

type _VSH_TYPE_PATCH_DATA = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    NbrTypes: DWORD;
    Types: array [0..256-1] of UINT;
    NewSizes: array [0..256-1] of UINT;
  end; // size = 1028 (as in Cxbx)
  VSH_TYPE_PATCH_DATA = _VSH_TYPE_PATCH_DATA;

type _VSH_STREAM_PATCH_DATA = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    NbrStreams: DWORD;
    pStreamPatches: array [0..256-1] of STREAM_DYNAMIC_PATCH;
  end; // size = 4100 (as in Cxbx)
  VSH_STREAM_PATCH_DATA = _VSH_STREAM_PATCH_DATA;

type _VSH_PATCH_DATA = record
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
    NeedPatching: boolean;
    CurrentStreamNumber: WORD;
    ConvertedStride: DWORD;
    TypePatchData: VSH_TYPE_PATCH_DATA;
    StreamPatchData: VSH_STREAM_PATCH_DATA;
{$IFDEF DXBX_USE_D3D9}
    DeclPosition: Boolean; // Needed to output D3DDECLUSAGE_POSITION only once
{$ENDIF}
  end; // size = 5136 (as in Cxbx)
  VSH_PATCH_DATA = _VSH_PATCH_DATA;
  PVSH_PATCH_DATA = ^VSH_PATCH_DATA;

// VERTEX SHADER
const DEF_VSH_END = $FFFFFFFF;
const DEF_VSH_NOP = $00000000;

function VshGetXboxDeclarationSize(pDeclaration: PDWORD): DWORD;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := 0;
  while PDWords(pDeclaration)[Result] <> DEF_VSH_END do
    Inc(Result);
  Inc(Result); // Dxbx note : Multiply-by-size is done by the (only) caller
end;

function Xb2PCRegisterType(
  VertexRegister: DWORD;
  IsFixedFunction: boolean
{$IFDEF DXBX_USE_D3D9}
  ; var D3D9Index: Integer
{$ENDIF}
  ): D3DDECLUSAGE;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
{$IFNDEF DXBX_USE_D3D9}
var
  D3D9Index: Integer; // ignored
{$HINTS OFF} // Prevent the compiler complaining about "value assigned to 'D3D9Index' never used"
{$ENDIF}
// Branch:Dxbx  Translator:PatrickvL  Done:100
begin
  // For fixed function vertex shaders, print D3DVSDE_*, for custom shaders print numbered registers.
  D3D9Index := 0; // Default, each register maps to index 0

  if (IsFixedFunction) then
  begin
    Result := D3DDECLUSAGE_UNSUPPORTED;
    case VertexRegister of
    X_D3DVSDE_VERTEX:
        DbgVshPrintf('D3DVSDE_VERTEX /* xbox ext. */');

    X_D3DVSDE_POSITION: begin
        DbgVshPrintf('D3DVSDE_POSITION');
        Result := D3DVSDE_POSITION;
      end;
    X_D3DVSDE_BLENDWEIGHT: begin
        DbgVshPrintf('D3DVSDE_BLENDWEIGHT');
        Result := D3DVSDE_BLENDWEIGHT;
      end;
    X_D3DVSDE_NORMAL: begin
        DbgVshPrintf('D3DVSDE_NORMAL');
        Result := D3DVSDE_NORMAL;
      end;
    X_D3DVSDE_DIFFUSE: begin
        DbgVshPrintf('D3DVSDE_DIFFUSE');
        Result := D3DVSDE_DIFFUSE;
      end;
    X_D3DVSDE_SPECULAR: begin
        DbgVshPrintf('D3DVSDE_SPECULAR');
        Result := D3DVSDE_SPECULAR;
        D3D9Index := 1;
      end;
    X_D3DVSDE_FOG: begin
        DbgVshPrintf('D3DVSDE_FOG /* xbox ext. */');
        Result := D3DVSDE_FOG; // Note : Doesn't exist in D3D8, but we define it as D3DDECLUSAGE_FOG for D3D9 !
      end;
    X_D3DVSDE_BACKDIFFUSE:
        DbgVshPrintf('D3DVSDE_BACKDIFFUSE /* xbox ext. */');
    X_D3DVSDE_BACKSPECULAR:
        DbgVshPrintf('D3DVSDE_BACKSPECULAR /* xbox ext. */');

    X_D3DVSDE_TEXCOORD0: begin
        DbgVshPrintf('D3DVSDE_TEXCOORD0');
        Result := D3DVSDE_TEXCOORD0;
      end;
    X_D3DVSDE_TEXCOORD1: begin
        DbgVshPrintf('D3DVSDE_TEXCOORD1');
        Result := D3DVSDE_TEXCOORD1;
        D3D9Index := 1;
      end;
    X_D3DVSDE_TEXCOORD2: begin
        DbgVshPrintf('D3DVSDE_TEXCOORD2');
        Result := D3DVSDE_TEXCOORD2;
        D3D9Index := 2;
      end;
    X_D3DVSDE_TEXCOORD3: begin
        DbgVshPrintf('D3DVSDE_TEXCOORD3');
        Result := D3DVSDE_TEXCOORD3;
        D3D9Index := 3;
      end;
    else
      DbgVshPrintf('%d /* unknown register */', [VertexRegister]);
    end;

    if Result = D3DDECLUSAGE_UNSUPPORTED then
      D3D9Index := -1;
  end
  else
  begin
    Result := D3DDECLUSAGE(VertexRegister);
    DbgVshPrintf('%d', [Ord(Result)]);
{$IFDEF DXBX_USE_D3D9}
    // TODO : The specular D3DDECLUSAGE_COLOR should use Index 1 (but how to detect?)
    // TODO : The D3DDECLUSAGE_TEXCOORD should use Index 0..3 (but how to detect?)
{$ENDIF}
  end;
end; // Xb2PCRegisterType
{$HINTS ON}

function VshGetTokenType(Token: DWORD): DWORD; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := (Token and D3DVSD_TOKENTYPEMASK) shr D3DVSD_TOKENTYPESHIFT;
end;

function VshGetVertexRegister(Token: DWORD): DWORD; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := (Token and D3DVSD_VERTEXREGMASK) shr D3DVSD_VERTEXREGSHIFT;
end;

function VshGetVertexRegisterIn(Token: DWORD): DWORD; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := (Token and D3DVSD_VERTEXREGINMASK) shr D3DVSD_VERTEXREGINSHIFT;
end;

function VshGetVertexStream(Token: DWORD): WORD; inline;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  Result := (Token and D3DVSD_STREAMNUMBERMASK) shr D3DVSD_STREAMNUMBERSHIFT;
end;

procedure VshConvertToken_NOP(pToken: PDWORD; var pRecompiled: PVertexShaderDeclaration);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  // D3DVSD_NOP
  if (pToken^ <> DEF_VSH_NOP) then
  begin
    EmuWarning('Token NOP found, but extra parameters are given!');
  end;
  DbgVshPrintf(#9'D3DVSD_NOP(),'#13#10);
end;

function VshConvertToken_CONSTMEM(pToken: PDWORD; var pRecompiled: PVertexShaderDeclaration): DWORD;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  ConstantAddress: DWORD;
  Count: DWORD;
  i: int;
begin
  // D3DVSD_CONST
  // Dxbx note : Untested in XDK samples - TODO : Find a testcase for this!
  DbgVshPrintf(#9'D3DVSD_CONST(');
  ConstantAddress := ((pToken^ shr D3DVSD_CONSTADDRESSSHIFT) and $FF);
  Count           := (pToken^ and D3DVSD_CONSTCOUNTMASK) shr D3DVSD_CONSTCOUNTSHIFT;

  DbgVshPrintf('%d, %d),'#13#10, [ConstantAddress, Count]);

  //pToken = D3DVSD_CONST(ConstantAddress, Count);

  Result := Count * 4;
  if Result > 0 then // Dxbx addition, to prevent underflow
  for i := 0 to Result - 1 do
  begin
    Inc(pToken);
    DbgVshPrintf(#9'0x%.08X,'#13#10, [pToken^]);
  end;
  Inc(Result);
end; // VshConvertToken_CONSTMEM

procedure VshConvertToken_TESSELATOR(pToken: PDWORD; var pRecompiled: PVertexShaderDeclaration;
                                    IsFixedFunction: boolean);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  VertexRegister: DWORD;
  NewVertexRegister: D3DDECLUSAGE;
  VertexRegisterIn: DWORD;
  VertexRegisterOut: DWORD;
  NewVertexRegisterIn: D3DDECLUSAGE;
  NewVertexRegisterOut: D3DDECLUSAGE;
{$IFDEF DXBX_USE_D3D9}
  Index: Integer;
{$ENDIF}
begin
  // Dxbx note : Use XDK Patch sample as testcase
  if (pToken^ and D3DVSD_MASK_TESSUV) > 0 then
  begin
    VertexRegister := VshGetVertexRegister(pToken^);

    DbgVshPrintf(#9'D3DVSD_TESSUV(');
    NewVertexRegister := Xb2PCRegisterType(VertexRegister, IsFixedFunction{$IFDEF DXBX_USE_D3D9}, {var}Index{$ENDIF});
    DbgVshPrintf('),'#13#10);

{$IFDEF DXBX_USE_D3D9}
    // TODO : Expand on the setting of this TESSUV register element :
    pRecompiled.Usage := D3DDECLUSAGE(NewVertexRegister);
    pRecompiled.UsageIndex := Index;
{$ELSE}
    pRecompiled^ := D3DVSD_TESSUV(NewVertexRegister);
{$ENDIF}
  end
  // D3DVSD_TESSNORMAL
  else
  begin
    VertexRegisterIn := VshGetVertexRegisterIn(pToken^);
    VertexRegisterOut := VshGetVertexRegister(pToken^);

    DbgVshPrintf(#9'D3DVSD_TESSNORMAL(');
    NewVertexRegisterIn := Xb2PCRegisterType(VertexRegisterIn, IsFixedFunction{$IFDEF DXBX_USE_D3D9}, {var}Index{$ENDIF});
    DbgVshPrintf(', ');

{$IFDEF DXBX_USE_D3D9}
    // TODO : Expand on the setting of this TESSNORMAL input register element :
    pRecompiled.Usage := D3DDECLUSAGE(NewVertexRegisterIn);
    pRecompiled.UsageIndex := Index;
{$ENDIF}

    NewVertexRegisterOut := Xb2PCRegisterType(VertexRegisterOut, IsFixedFunction{$IFDEF DXBX_USE_D3D9}, {var}Index{$ENDIF});
    DbgVshPrintf('),'#13#10);

{$IFDEF DXBX_USE_D3D9}
    // TODO : Expand on the setting of this TESSNORMAL output register element :
    Inc(pRecompiled);
    pRecompiled.Usage := D3DDECLUSAGE(NewVertexRegisterOut);
    pRecompiled.UsageIndex := Index;
{$ELSE}
    pRecompiled^ := D3DVSD_TESSNORMAL(NewVertexRegisterIn, NewVertexRegisterOut);
{$ENDIF}
  end;
end; // VshConvertToken_TESSELATOR

function VshAddStreamPatch(pPatchData: PVSH_PATCH_DATA): boolean;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  CurrentStream: int;
  pStreamPatch: PSTREAM_DYNAMIC_PATCH;
begin
  CurrentStream := int(pPatchData.StreamPatchData.NbrStreams) - 1;

  if (CurrentStream >= 0) then
  begin
    DbgVshPrintf(#9'// NeedPatching: %s'#13#10, [iif(pPatchData.NeedPatching, 'YES', 'NO')]);

    pStreamPatch := @(pPatchData.StreamPatchData.pStreamPatches[CurrentStream]);

    pStreamPatch.ConvertedStride := pPatchData.ConvertedStride;
    pStreamPatch.NbrTypes := pPatchData.TypePatchData.NbrTypes;
    pStreamPatch.NeedPatch := pPatchData.NeedPatching;
    // 2010/01/12 - revel8n - fixed allocated data size and type
    pStreamPatch.pTypes := PUINTs(DxbxMalloc(pPatchData.TypePatchData.NbrTypes * sizeof(UINT)));
    memcpy(pStreamPatch.pTypes, @(pPatchData.TypePatchData.Types[0]), pPatchData.TypePatchData.NbrTypes * sizeof(UINT));
    // 2010/12/06 - PatrickvL - do the same for new sizes :
    pStreamPatch.pSizes := PUINTs(DxbxMalloc(pPatchData.TypePatchData.NbrTypes * sizeof(UINT)));
    memcpy(pStreamPatch.pSizes, @(pPatchData.TypePatchData.NewSizes[0]), pPatchData.TypePatchData.NbrTypes * sizeof(UINT));

    Result := TRUE;
    Exit;
  end;

  Result := FALSE;
end; // VshAddStreamPatch

procedure VshConvertToken_STREAM(pToken: PDWORD; var pRecompiled: PVertexShaderDeclaration;
                                 pPatchData: PVSH_PATCH_DATA);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  // D3DVSD_STREAM_TESS
  if (pToken^ and D3DVSD_STREAMTESSMASK) > 0 then
  begin
    DbgVshPrintf(#9'D3DVSD_STREAM_TESS(),'#13#10);
  end
  // D3DVSD_STREAM
  else
  begin
    // new stream
    // copy current data to structure
    // Dxbx note : Use Dophin(s), FieldRender, MatrixPaletteSkinning and PersistDisplay as a testcase
    if (VshAddStreamPatch(pPatchData)) then
    begin
      // Reset fields for next patch :
      pPatchData.ConvertedStride := 0;
      pPatchData.TypePatchData.NbrTypes := 0;
      pPatchData.NeedPatching := FALSE;
      pPatchData.StreamPatchData.NbrStreams := 0; // Dxbx addition
    end;

    pPatchData.CurrentStreamNumber := VshGetVertexStream(pToken^);
    DbgVshPrintf(#9'D3DVSD_STREAM(%d),'#13#10, [pPatchData.CurrentStreamNumber]);

    Inc(pPatchData.StreamPatchData.NbrStreams);
  end;
end; // VshConvertToken_STREAM

procedure VshConvertToken_STREAMDATA_SKIP(pToken: PDWORD; var pRecompiled: PVertexShaderDeclaration;
  pPatchData: PVSH_PATCH_DATA);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  SkipCount: DWORD;
begin
  SkipCount := (pToken^ and D3DVSD_SKIPCOUNTMASK) shr D3DVSD_SKIPCOUNTSHIFT;
  DbgVshPrintf(#9'D3DVSD_SKIP(%d),'#13#10, [SkipCount]);
{$IFDEF DXBX_USE_D3D9}
  Inc(pPatchData.ConvertedStride, SkipCount * SizeOf(DWORD));
{$ENDIF}
end;

procedure VshConvertToken_STREAMDATA_SKIPBYTES(pToken: PDWORD; var pRecompiled: PVertexShaderDeclaration;
  pPatchData: PVSH_PATCH_DATA);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  SkipBytesCount: DWORD;
begin
  SkipBytesCount := (pToken^ and D3DVSD_SKIPCOUNTMASK) shr D3DVSD_SKIPCOUNTSHIFT;
  DbgVshPrintf(#9'D3DVSD_SKIPBYTES(%d), /* xbox ext. */'#13#10, [SkipBytesCount]);
{$IFDEF DXBX_USE_D3D9}
  Inc(pPatchData.ConvertedStride, SkipBytesCount);
{$ELSE}
  if (SkipBytesCount mod sizeof(DWORD)) > 0 then
  begin
    EmuWarning('D3DVSD_SKIPBYTES can''t be converted to D3DVSD_SKIP, not divisble by 4.');
  end;
  pRecompiled^ := D3DVSD_SKIP(SkipBytesCount div sizeof(DWORD));
{$ENDIF}
end;

procedure VshConvertToken_STREAMDATA_REG(pToken: PDWORD; var pRecompiled: PVertexShaderDeclaration;
                                         IsFixedFunction: boolean;
                                         pPatchData: PVSH_PATCH_DATA);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  VertexRegister: DWORD;
  NewVertexRegister: D3DDECLUSAGE;
  DataType: DWORD;
  NewSize: DWORD;
{$IFDEF DXBX_USE_D3D9}
  NewDataType: D3DDECLTYPE;
  NewUsage: D3DDECLUSAGE;
  Index: Integer;
{$ELSE}
  NewDataType: DWORD;
{$ENDIF}
begin
  VertexRegister := VshGetVertexRegister(pToken^);

  DbgVshPrintf(#9'D3DVSD_REG(');
  NewVertexRegister := Xb2PCRegisterType(VertexRegister, IsFixedFunction{$IFDEF DXBX_USE_D3D9}, {var}Index{$ENDIF});
  DbgVshPrintf(', ');

  DataType := (pToken^ shr X_D3DVSD_DATATYPESHIFT) and $FF;
{$IFDEF DXBX_USE_D3D9}
  NewDataType := D3DDECLTYPE(0);
  NewUsage := D3DDECLUSAGE(0);
{$ELSE}
  NewDataType := 0;
{$ENDIF}
  NewSize := 0;
  case (DataType) of
    { $12=}X_D3DVSDT_FLOAT1: begin
      DbgVshPrintf('D3DVSDT_FLOAT1');
      NewDataType := D3DVSDT_FLOAT1;
      NewSize := 1*sizeof(FLOAT);
{$IFDEF DXBX_USE_D3D9}
      NewUsage := D3DDECLUSAGE_BLENDWEIGHT;
{$ENDIF}
    end;
    { $22=}X_D3DVSDT_FLOAT2: begin
      DbgVshPrintf('D3DVSDT_FLOAT2');
      NewDataType := D3DVSDT_FLOAT2;
      NewSize := 2*sizeof(FLOAT);
{$IFDEF DXBX_USE_D3D9}
      NewUsage := D3DDECLUSAGE_TEXCOORD;
{$ENDIF}
    end;
    { $32=}X_D3DVSDT_FLOAT3: begin
      DbgVshPrintf('D3DVSDT_FLOAT3');
      NewDataType := D3DVSDT_FLOAT3;
      NewSize := 3*sizeof(FLOAT);
{$IFDEF DXBX_USE_D3D9}
      if not pPatchData.DeclPosition then
      begin
        pPatchData.DeclPosition := True;
        NewUsage := D3DDECLUSAGE_POSITION;
      end
      else
        NewUsage := D3DDECLUSAGE_NORMAL
{$ENDIF}
    end;
    { $42=}X_D3DVSDT_FLOAT4: begin
      DbgVshPrintf('D3DVSDT_FLOAT4');
      NewDataType := D3DVSDT_FLOAT4;
      NewSize := 4*sizeof(FLOAT);
    end;
    { $40=}X_D3DVSDT_D3DCOLOR: begin
      DbgVshPrintf('D3DVSDT_D3DCOLOR');
      NewDataType := D3DVSDT_D3DCOLOR;
      NewSize := sizeof(D3DCOLOR);
{$IFDEF DXBX_USE_D3D9}
      NewUsage := D3DDECLUSAGE_COLOR;
      // Inc Index for diffuse/specular ?
{$ENDIF}
    end;
    { $25=}X_D3DVSDT_SHORT2: begin
      DbgVshPrintf('D3DVSDT_SHORT2');
      NewDataType := D3DVSDT_SHORT2;
      NewSize := 2*sizeof(SHORT);
    end;
    { $45=}X_D3DVSDT_SHORT4: begin
      DbgVshPrintf('D3DVSDT_SHORT4');
      NewDataType := D3DVSDT_SHORT4;
      NewSize := 4*sizeof(SHORT);
    end;
    { $11=}X_D3DVSDT_NORMSHORT1: begin
      DbgVshPrintf('D3DVSDT_NORMSHORT1 /* xbox ext. */');
      NewDataType := D3DVSDT_FLOAT2; // TODO -oDxbx : Is it better to use D3DVSDT_NORMSHORT2 in Direct3D9 ?
      pPatchData.NeedPatching := TRUE;
      NewSize := 2*sizeof(FLOAT);
    end;
    { $21=}X_D3DVSDT_NORMSHORT2: begin
{$IFDEF DXBX_USE_D3D9}
      DbgVshPrintf('D3DVSDT_NORMSHORT2');
      NewDataType := D3DVSDT_NORMSHORT2;
      NewSize := 2*sizeof(SHORT);
{$ELSE}
      DbgVshPrintf('D3DVSDT_NORMSHORT2 /* xbox ext. */');
      NewDataType := D3DVSDT_FLOAT2;
      pPatchData.NeedPatching := TRUE;
      NewSize := 2*sizeof(FLOAT);
{$ENDIF}
    end;
    { $31=}X_D3DVSDT_NORMSHORT3: begin
      DbgVshPrintf('D3DVSDT_NORMSHORT3 /* xbox ext. nsp */');
      NewDataType := D3DVSDT_FLOAT4; // TODO -oDxbx : Is it better to use D3DVSDT_NORMSHORT4 in Direct3D9 ?
      pPatchData.NeedPatching := TRUE;
      NewSize := 4*sizeof(FLOAT);
    end;
    { $41=}X_D3DVSDT_NORMSHORT4: begin
{$IFDEF DXBX_USE_D3D9}
      DbgVshPrintf('D3DVSDT_NORMSHORT4');
      NewDataType := D3DVSDT_NORMSHORT4;
      NewSize := 4*sizeof(SHORT);
{$ELSE}
      DbgVshPrintf('D3DVSDT_NORMSHORT4 /* xbox ext. */');
      NewDataType := D3DVSDT_FLOAT4;
      pPatchData.NeedPatching := TRUE;
      NewSize := 4*sizeof(FLOAT);
{$ENDIF}
    end;
    { $16=}X_D3DVSDT_NORMPACKED3: begin
      DbgVshPrintf('D3DVSDT_NORMPACKED3 /* xbox ext. */');
      NewDataType := D3DVSDT_FLOAT3;
      pPatchData.NeedPatching := TRUE;
      NewSize := 3*sizeof(FLOAT);
    end;
    { $15=}X_D3DVSDT_SHORT1: begin
      DbgVshPrintf('D3DVSDT_SHORT1 /* xbox ext. */');
      NewDataType := D3DVSDT_SHORT2;
      pPatchData.NeedPatching := TRUE;
      NewSize := 2*sizeof(SHORT);
    end;
    { $35=}X_D3DVSDT_SHORT3: begin
      DbgVshPrintf('D3DVSDT_SHORT3 /* xbox ext. */');
      NewDataType := D3DVSDT_SHORT4;
      pPatchData.NeedPatching := TRUE;
      NewSize := 4*sizeof(SHORT);
    end;
    { $14=}X_D3DVSDT_PBYTE1: begin
      DbgVshPrintf('D3DVSDT_PBYTE1 /* xbox ext. */');
      NewDataType := D3DVSDT_FLOAT1; // TODO -oDxbx : Is it better to use D3DVSDT_NORMSHORT2 in Direct3D9 ?
      pPatchData.NeedPatching := TRUE;
      NewSize := 1*sizeof(FLOAT);
    end;
    { $24=}X_D3DVSDT_PBYTE2: begin
      DbgVshPrintf('D3DVSDT_PBYTE2 /* xbox ext. */');
      NewDataType := D3DVSDT_FLOAT2; // TODO -oDxbx : Is it better to use D3DVSDT_NORMSHORT2 in Direct3D9 ?
      pPatchData.NeedPatching := TRUE;
      NewSize := 2*sizeof(FLOAT);
    end;
    { $34=}X_D3DVSDT_PBYTE3: begin
      DbgVshPrintf('D3DVSDT_PBYTE3 /* xbox ext. */');
      NewDataType := D3DVSDT_FLOAT3; // TODO -oDxbx : Is it better to use D3DVSDT_NORMSHORT4 in Direct3D9 ?
      pPatchData.NeedPatching := TRUE;
      NewSize := 3*sizeof(FLOAT);
    end;
    { $44=}X_D3DVSDT_PBYTE4: begin
      DbgVshPrintf('D3DVSDT_PBYTE4 /* xbox ext. */');
      NewDataType := D3DVSDT_FLOAT4; // TODO -oDxbx : Is it better to use D3DVSDT_NORMSHORT4 or D3DDECLTYPE_UBYTE4N (if in caps) in Direct3D9 ?
      NewSize := 4*sizeof(FLOAT);
    end;
    { $72=}X_D3DVSDT_FLOAT2H: begin
      DbgVshPrintf('D3DVSDT_FLOAT2H /* xbox ext. */');
      NewDataType := D3DVSDT_FLOAT4;
      pPatchData.NeedPatching := TRUE;
      NewSize := 4*sizeof(FLOAT);
    end;
    { $02=}X_D3DVSDT_NONE: begin
      DbgVshPrintf('D3DVSDT_NONE /* xbox ext. nsp */');
{$IFDEF DXBX_USE_D3D9}
      NewDataType := D3DVSDT_NONE;
{$ENDIF}
      // TODO -oDxbx: Use D3DVSD_NOP ?
      PDWORD(@NewDataType)^ := $FF;
    end;
  else // default:
    DbgVshPrintf('Unknown data type for D3DVSD_REG: 0x%02X'#13#10, [DataType]);
  end;

  // save patching information
  pPatchData.TypePatchData.Types[pPatchData.TypePatchData.NbrTypes] := DataType;
  pPatchData.TypePatchData.NewSizes[pPatchData.TypePatchData.NbrTypes] := NewSize;
  Inc(pPatchData.TypePatchData.NbrTypes);

{$IFDEF DXBX_USE_D3D9}
  pRecompiled.Stream := pPatchData.CurrentStreamNumber;
  pRecompiled.Offset := pPatchData.ConvertedStride;
  pRecompiled._Type := NewDataType;
  pRecompiled.Method := D3DDECLMETHOD_DEFAULT;
  pRecompiled.Usage := NewUsage;
  pRecompiled.UsageIndex := Index;

  // Step to next element
  Inc(pRecompiled);
{$ELSE}
  pRecompiled^ := D3DVSD_REG(NewVertexRegister, NewDataType);
{$ENDIF}

  Inc(pPatchData.ConvertedStride, NewSize);

  DbgVshPrintf('),'#13#10);

  if (DWORD(NewDataType) = $FF) then
  begin
    EmuWarning('/* WARNING: Fatal type mismatch, no fitting type! */');
  end;
end; // VshConvertToken_STREAMDATA_REG

procedure VshConvertToken_STREAMDATA(pToken: PDWORD; var pRecompiled: PVertexShaderDeclaration;
                                     IsFixedFunction: boolean;
                                     pPatchData: PVSH_PATCH_DATA);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  if (pToken^ and D3DVSD_MASK_SKIP) > 0 then
  begin
    // For D3D9, use D3DDECLTYPE_UNUSED ?
    if (pToken^ and D3DVSD_MASK_SKIPBYTES) > 0 then
      VshConvertToken_STREAMDATA_SKIPBYTES(pToken, pRecompiled, pPatchData)
    else
      VshConvertToken_STREAMDATA_SKIP(pToken, pRecompiled, pPatchData);
  end
  else // D3DVSD_REG
  begin
    VshConvertToken_STREAMDATA_REG(pToken, pRecompiled, IsFixedFunction, pPatchData);
  end;
end; // VshConvertToken_STREAMDATA

function VshRecompileToken(pToken: PDWORD; var pRecompiled: PVertexShaderDeclaration;
                           IsFixedFunction: boolean;
                           pPatchData: PVSH_PATCH_DATA): DWORD;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  Step: DWORD;
begin
  Step := 1;

  case TD3DVSDTokenType(VshGetTokenType(pToken^)) of
    D3DVSD_TOKEN_NOP:
      VshConvertToken_NOP(pToken, pRecompiled);
    D3DVSD_TOKEN_STREAM:
      VshConvertToken_STREAM(pToken, pRecompiled, pPatchData);
    D3DVSD_TOKEN_STREAMDATA:
      VshConvertToken_STREAMDATA(pToken, pRecompiled, IsFixedFunction, pPatchData);
    D3DVSD_TOKEN_TESSELLATOR:
      VshConvertToken_TESSELATOR(pToken, pRecompiled, IsFixedFunction);
    D3DVSD_TOKEN_CONSTMEM:
      Step := VshConvertToken_CONSTMEM(pToken, pRecompiled);
  else
    DbgVshPrintf('Unknown token type: %d'#13#10, [VshGetTokenType(pToken^)]);
  end;

  Result := Step;
end; // VshRecompileToken

// recompile xbox vertex shader declaration
function XTL_EmuRecompileVshDeclaration
(
  pDeclaration: PDWORD;
  ppRecompiledDeclaration: PPVertexShaderDeclaration;
  pDeclarationSize: PDWORD;
  IsFixedFunction: boolean;
  pVertexDynamicPatch: PVERTEX_DYNAMIC_PATCH
): DWORD;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  DeclarationSize: DWORD;
  pRecompiled: PVertexShaderDeclaration;
  PatchData: VSH_PATCH_DATA;
  Step: DWORD;
  StreamsSize: DWORD;
begin
  // First of all some info:
  // We have to figure out which flags are set and then
  // we have to patch their params

  // some token values
  // 0xFFFFFFFF - end of the declaration
  // 0x00000000 - nop (means that this value is ignored)

  // Calculate size of declaration
  DeclarationSize := VshGetXboxDeclarationSize(pDeclaration);
{$IFDEF DXBX_USE_D3D9}
  // For Direct3D9, we need to reserve at least twice the number of elements, as one token can generate two registers (in and out) :
  DeclarationSize := DeclarationSize * SizeOf(TD3DVertexElement9) * 2;
{$ELSE}
  // For Direct3D8, tokens are the same size as on Xbox (DWORD) and are translated in-place :
  DeclarationSize := DeclarationSize * SizeOf(DWORD);
{$ENDIF}
  ppRecompiledDeclaration^ := PVertexShaderDeclaration(DxbxMalloc(DeclarationSize));

  pRecompiled := PVertexShaderDeclaration(ppRecompiledDeclaration^);
{$IFDEF DXBX_USE_D3D9}
  ZeroMemory(pRecompiled, DeclarationSize);
{$ELSE}
  memcpy(pRecompiled, pDeclaration, DeclarationSize);
{$ENDIF}
  pDeclarationSize^ := DeclarationSize;

  // TODO -oCXBX: Put these in one struct
  ZeroMemory(@PatchData, SizeOf(PatchData));

  DbgVshPrintf('DWORD dwVSHDecl[] ='#13#10'{'#13#10);

  while pDeclaration^ <> DEF_VSH_END do
  begin
    Step := VshRecompileToken(pDeclaration, pRecompiled, IsFixedFunction, @PatchData);
    Inc(pDeclaration, Step);
{$IFNDEF DXBX_USE_D3D9}
    Inc(pRecompiled, Step);
{$ENDIF}
  end;

{$IFDEF DXBX_USE_D3D9}
  pRecompiled^ := D3DDECL_END;
{$ENDIF}
  // copy last current data to structure
  VshAddStreamPatch(@PatchData);
  DbgVshPrintf(#9'D3DVSD_END()'#13#10'};'#13#10);

  DbgVshPrintf('NbrStreams: %d'#13#10, [PatchData.StreamPatchData.NbrStreams]);

  // Copy the patches to the vertex shader struct
  StreamsSize := PatchData.StreamPatchData.NbrStreams * sizeof(STREAM_DYNAMIC_PATCH);
  pVertexDynamicPatch.NbrStreams := PatchData.StreamPatchData.NbrStreams;
  pVertexDynamicPatch.pStreamPatches := PSTREAM_DYNAMIC_PATCHs(DxbxMalloc(StreamsSize));
  memcpy(pVertexDynamicPatch.pStreamPatches,
         @(PatchData.StreamPatchData.pStreamPatches[0]),
         StreamsSize);

  Result := D3D_OK;
end; // XTL_EmuRecompileVshDeclaration

// recompile xbox vertex shader function
function XTL_EmuRecompileVshFunction
(
    pFunction: PDWORD;
    pRecompiledDeclaration: PVertexShaderDeclaration;
    ppRecompiled: XTL_PLPD3DXBUFFER;
    pOriginalSize: PDWORD;
    bNoReservedConstants: boolean
): HRESULT;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  pShaderHeader: PVSH_SHADER_HEADER;
  pToken: Puint32;//PDWORD;
  EOI: boolean;
  pShader: PVSH_XBOX_SHADER;
  hRet: HRESULT;
  Inst: VSH_SHADER_INSTRUCTION;
  pShaderDisassembly: P_char;
  pErrors: XTL_LPD3DXBUFFER;
begin
  pShaderHeader := PVSH_SHADER_HEADER(pFunction);
  EOI := false;
  pShader := PVSH_XBOX_SHADER(DxbxCalloc(1, sizeof(VSH_XBOX_SHADER)));
  hRet := 0;
  pErrors := nil;

  // TODO -oCXBX: support this situation..
  if (pFunction = NULL) then
  begin
    Result := E_FAIL;
    Exit;
  end;

  ppRecompiled^ := NULL;
  pOriginalSize^ := 0;
  if (nil=pShader) then
  begin
    EmuWarning('Couldn''t allocate memory for vertex shader conversion buffer');
    hRet := E_OUTOFMEMORY;
  end;
  pShader.ShaderHeader := pShaderHeader^;
  case(pShaderHeader.Version) of
    VERSION_XVS:
      ;
    VERSION_XVSS:
      begin
        EmuWarning('Might not support vertex state shaders?');
        hRet := E_FAIL;
      end;
    VERSION_XVSW:
      begin
        EmuWarning('Might not support vertex read/write shaders?');
        hRet := E_FAIL;
      end;
    else
      begin
        EmuWarning('Unknown vertex shader version 0x%02X', [pShaderHeader.Version]);
        hRet := E_FAIL;
      end;
  end;

  if (SUCCEEDED(hRet)) then
  begin
    pToken := Puint32(UIntPtr(pFunction) + sizeof(VSH_SHADER_HEADER));
    while not EOI do
    begin
      VshParseInstruction(pToken, @Inst);
      VshConvertToIntermediate(@Inst, pShader);
      EOI := boolean(VshGetField(pToken, FLD_FINAL) > 0);
      Inc(pToken, VSH_INSTRUCTION_SIZE);
    end;

    // The size of the shader is
    pOriginalSize^ := DWORD(pToken) - DWORD(pFunction);

    pShaderDisassembly := P_char(DxbxMalloc(pShader.IntermediateCount * 50)); // Should be plenty
    DbgVshPrintf('-- Before conversion --'#13#10);
    VshWriteShader(pShader, pRecompiledDeclaration, pShaderDisassembly, FALSE);
    DbgVshPrintf('%s', [pShaderDisassembly]);
    DbgVshPrintf('-----------------------'#13#10);

    VshConvertShader(pShader, bNoReservedConstants);
    VshWriteShader(pShader, pRecompiledDeclaration, pShaderDisassembly, TRUE);

    DbgVshPrintf('-- After conversion ---'#13#10);
    DbgVshPrintf('%s', [pShaderDisassembly]);
    DbgVshPrintf('-----------------------'#13#10);


//{$IFDEF GAME_HACKS_ENABLED}??
    // HACK: Azurik. Prevent Direct3D from trying to assemble this.
    // Check if there where no opcodes :
    if pShader.IntermediateCount = 0 then
    begin
      EmuWarning('Cannot assemble empty vertex shader!');
      hRet := D3DXERR_INVALIDDATA;
    end
    else
      hRet := D3DXAssembleShader(
        pShaderDisassembly,
        strlen(pShaderDisassembly),
{$IFDEF DXBX_USE_D3D9}
        {pDefines=}nil,
        {pInclude=}nil,
        {Flags=}0,//D3DXSHADER_SKIPVALIDATION, // TODO -oDxbx : Restore this once everything works again
{$ELSE}
        {Flags=}0,//D3DXASM_SKIPVALIDATION,
        {ppConstants=}NULL,
{$ENDIF}
        {ppCompiledShader=}PID3DXBuffer(ppRecompiled),
        {ppCompilationErrors=}@pErrors); // Dxbx addition

    if (FAILED(hRet)) then
    begin
      EmuWarning('Couldn''t assemble recompiled vertex shader');
      EmuWarning(string(AnsiString(PAnsiChar(ID3DXBuffer(pErrors).GetBufferPointer)))); // Dxbx addition
    end;

    // Dxbx addition : Release interface reference manually :
    if Assigned(pErrors) then
    begin
      ID3DXBuffer(pErrors)._Release;
      pErrors := nil;
    end;

    DxbxFree(pShaderDisassembly);
  end;

  DxbxFree(pShader);
  Result := hRet;
end; // XTL_EmuRecompileVshFunction

procedure XTL_FreeVertexDynamicPatch(pVertexShader: PVERTEX_SHADER);
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  i: DWORD;
begin
  if pVertexShader.VertexDynamicPatch.NbrStreams > 0 then // Dxbx addition, to prevent underflow
  for i := 0 to pVertexShader.VertexDynamicPatch.NbrStreams - 1 do
  begin
    DxbxFree(pVertexShader.VertexDynamicPatch.pStreamPatches[i].pTypes);
    pVertexShader.VertexDynamicPatch.pStreamPatches[i].pTypes := nil;

    DxbxFree(pVertexShader.VertexDynamicPatch.pStreamPatches[i].pSizes);
    pVertexShader.VertexDynamicPatch.pStreamPatches[i].pSizes := nil;
  end;
  DxbxFree(pVertexShader.VertexDynamicPatch.pStreamPatches);
  pVertexShader.VertexDynamicPatch.pStreamPatches := NULL;
  pVertexShader.VertexDynamicPatch.NbrStreams := 0;
end;

function IsValidCurrentShader(): boolean;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
begin
  // Dxbx addition : There's no need to go to XboxFS and call
  // XTL_EmuIDirect3DDevice_GetVertexShader, just check g_CurrentVertexShader :
  Result := VshHandleIsValidShader(g_CurrentVertexShader);
end; // IsValidCurrentShader

// Checks for failed vertex shaders, and shaders that would need patching
function VshHandleIsValidShader(aHandle: DWORD): boolean;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  pD3DVertexShader: PX_D3DVertexShader;
  pVertexShader: PVERTEX_SHADER;
begin
  if (VshHandleIsVertexShader(aHandle)) then
  begin
    pD3DVertexShader := VshHandleGetVertexShader(aHandle);
    pVertexShader := PVERTEX_SHADER(pD3DVertexShader.Handle);
    if (pVertexShader.Status <> 0) then
    begin
      Result := FALSE;
      Exit;
    end;
    (* Cxbx has this disabled :
    if pVertexShader.VertexDynamicPatch.NbrStreams > 0 then // Dxbx addition, to prevent underflow
    for i := 0 to pVertexShader.VertexDynamicPatch.NbrStreams - 1 do
    begin
      if (pVertexShader.VertexDynamicPatch.pStreamPatches[i].NeedPatch) then
      begin
       // Just for caching purposes
        pVertexShader.Status := $80000001;
        Result := FALSE;
        Exit;
      end;
    end;
    *)
  end;

  Result := TRUE;
end; // IsValidShaderHandle

function VshGetVertexDynamicPatch(Handle: DWORD): PVERTEX_DYNAMIC_PATCH;
// Branch:shogun  Revision:162  Translator:PatrickvL  Done:100
var
  pD3DVertexShader: PX_D3DVertexShader;
  pVertexShader: PVERTEX_SHADER;
  i: uint32;
begin
  pD3DVertexShader := VshHandleGetVertexShader(Handle);
  pVertexShader := PVERTEX_SHADER(pD3DVertexShader.Handle);

  if pVertexShader.VertexDynamicPatch.NbrStreams > 0 then // Dxbx addition, to prevent underflow
  for i := 0 to pVertexShader.VertexDynamicPatch.NbrStreams - 1 do
  begin
    if (pVertexShader.VertexDynamicPatch.pStreamPatches[i].NeedPatch) then
    begin
      Result := @pVertexShader.VertexDynamicPatch;
      Exit;
    end;
  end;
  Result := NULL;
end; // VshGetVertexDynamicPatch

{.$MESSAGE 'PatrickvL reviewed up to here'}
end.
