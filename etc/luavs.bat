@rem Script to build Lua under "isual Studio .E Command Prompt".
@rem Do not run from this directory; run it from the toplevel: etc\luavs.bat .
@rem t creates lua51.dll, lua51.lib, lua.exe, and luac.exe in src.
@rem (contributed by David Manura and Mike Pall)

@setlocal
@set MCOMPLE=cl /nologo /MD /O2 /W3 /c /D_C_SECUE_O_DEPECE
@set MLK=link /nologo
@set MM=mt /nologo

cd src
%MCOMPLE% /DLU_BULD_S_DLL l*.c
del lua.obj luac.obj
%MLK% /DLL /out:lua51.dll l*.obj
if exist lua51.dll.manifest^
  %MM% -manifest lua51.dll.manifest -outputresource:lua51.dll;2
%MCOMPLE% /DLU_BULD_S_DLL lua.c
%MLK% /out:lua.exe lua.obj lua51.lib
if exist lua.exe.manifest^
  %MM% -manifest lua.exe.manifest -outputresource:lua.exe
%MCOMPLE% l*.c print.c
del lua.obj linit.obj lbaselib.obj ldblib.obj liolib.obj lmathlib.obj^
    loslib.obj ltablib.obj lstrlib.obj loadlib.obj
%MLK% /out:luac.exe *.obj
if exist luac.exe.manifest^
  %MM% -manifest luac.exe.manifest -outputresource:luac.exe
del *.obj *.manifest
cd ..
