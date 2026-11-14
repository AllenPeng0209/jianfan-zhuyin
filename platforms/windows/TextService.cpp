#include <windows.h>
#include <msctf.h>

extern "C" __declspec(dllexport) HRESULT __stdcall DllGetClassObject(REFCLSID,REFIID,void**) {
  return CLASS_E_CLASSNOTAVAILABLE;
}
extern "C" __declspec(dllexport) HRESULT __stdcall DllCanUnloadNow() { return S_OK; }
extern "C" __declspec(dllexport) HRESULT __stdcall DllRegisterServer() { return E_NOTIMPL; }
extern "C" __declspec(dllexport) HRESULT __stdcall DllUnregisterServer() { return E_NOTIMPL; }
