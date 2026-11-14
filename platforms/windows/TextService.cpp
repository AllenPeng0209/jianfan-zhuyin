#include <windows.h>
#include <msctf.h>

STDAPI DllGetClassObject(REFCLSID,REFIID,void**) {
  return CLASS_E_CLASSNOTAVAILABLE;
}
STDAPI DllCanUnloadNow() { return S_OK; }
STDAPI DllRegisterServer() { return E_NOTIMPL; }
STDAPI DllUnregisterServer() { return E_NOTIMPL; }
