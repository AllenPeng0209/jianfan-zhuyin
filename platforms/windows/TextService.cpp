#include "TextService.h"

HINSTANCE gModule = nullptr;
std::atomic<long> gObjects{0};
std::atomic<long> gLocks{0};

namespace {
class Factory final : public IClassFactory,public Counted {
 public:
  HRESULT __stdcall QueryInterface(REFIID iid,void** result) override {
    if (!result) { return E_POINTER; } *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_IClassFactory) { return E_NOINTERFACE; }
    *result = static_cast<IClassFactory*>(this); AddRef(); return S_OK;
  }
  JF_LIFETIME
  HRESULT __stdcall CreateInstance(IUnknown* outer,REFIID iid,void** result) override {
    if (!result) { return E_POINTER; } *result = nullptr;
    if (outer) { return CLASS_E_NOAGGREGATION; }
    auto service = new (std::nothrow) TextService(); if (!service) { return E_OUTOFMEMORY; }
    HRESULT outcome = service->QueryInterface(iid,result); service->Release(); return outcome;
  }
  HRESULT __stdcall LockServer(BOOL lock) override { if (lock) { ++gLocks; } else if (gLocks > 0) { --gLocks; } return S_OK; }
};
std::wstring guidString(REFGUID id) { wchar_t value[40]{}; StringFromGUID2(id,value,40); return value; }
std::wstring classKey() { return L"Software\\Classes\\CLSID\\" + guidString(CLSID_Jianfan); }
HRESULT writeRegistry(const std::wstring& key,const wchar_t* name,const std::wstring& value) {
  HKEY handle;
  LONG result = RegCreateKeyExW(HKEY_LOCAL_MACHINE,key.c_str(),0,nullptr,REG_OPTION_NON_VOLATILE,KEY_WRITE,nullptr,&handle,nullptr);
  if (result != ERROR_SUCCESS) { return HRESULT_FROM_WIN32(result); }
  result = RegSetValueExW(handle,name,0,REG_SZ,reinterpret_cast<const BYTE*>(value.c_str()),static_cast<DWORD>((value.size()+1)*sizeof(wchar_t)));
  RegCloseKey(handle); return HRESULT_FROM_WIN32(result);
}
const GUID categories[] = {GUID_TFCAT_TIP_KEYBOARD,GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,GUID_TFCAT_TIPCAP_UIELEMENTENABLED,GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT};
HRESULT registerProfile(bool install) {
  Ptr<ITfInputProcessorProfileMgr> profiles;
  HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles));
  if (FAILED(result)) { return result; }
  if (install) {
    std::wstring path(32768,L'\0'); DWORD length = GetModuleFileNameW(gModule,path.data(),static_cast<DWORD>(path.size()));
    if (!length || length >= path.size()) { return E_FAIL; } path.resize(length);
    const std::wstring description = L"簡繁注音";
#ifdef JIANFAN_TEST_PROFILE
    constexpr BOOL enabled = FALSE;
#else
    constexpr BOOL enabled = TRUE;
#endif
    Ptr<ITfInputProcessorProfiles> registration;
    result = profiles.As(&registration);
    if (FAILED(result)) { return result; }
    result = registration->Register(CLSID_Jianfan);
    if (FAILED(result)) { return result; }
    result = registration->AddLanguageProfile(CLSID_Jianfan,JianfanLanguage,GUID_JianfanProfile,
      description.c_str(),static_cast<ULONG>(description.size()),path.c_str(),length,0);
    if (SUCCEEDED(result)) { result = registration->EnableLanguageProfile(CLSID_Jianfan,JianfanLanguage,GUID_JianfanProfile,enabled); }
  } else { result = profiles->UnregisterProfile(CLSID_Jianfan,JianfanLanguage,GUID_JianfanProfile,0); }
  if (FAILED(result) && install) { return result; }
  Ptr<ITfCategoryMgr> category;
  HRESULT categoryResult = CoCreateInstance(CLSID_TF_CategoryMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&category));
  if (FAILED(categoryResult)) { return categoryResult; }
  for (const auto& id : categories) {
    categoryResult = install ? category->RegisterCategory(CLSID_Jianfan,id,CLSID_Jianfan) : category->UnregisterCategory(CLSID_Jianfan,id,CLSID_Jianfan);
    if (install && FAILED(categoryResult)) { return categoryResult; }
  }
  return S_OK;
}
}

BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) { gModule = instance; }
  return TRUE;
}
STDAPI DllGetClassObject(REFCLSID id,REFIID iid,void** result) {
  if (!result) { return E_POINTER; } *result = nullptr;
  if (id != CLSID_Jianfan) { return CLASS_E_CLASSNOTAVAILABLE; }
  auto factory = new (std::nothrow) Factory(); if (!factory) { return E_OUTOFMEMORY; }
  HRESULT outcome = factory->QueryInterface(iid,result); factory->Release(); return outcome;
}
STDAPI DllCanUnloadNow() { return gObjects == 0 && gLocks == 0 ? S_OK : S_FALSE; }
STDAPI DllRegisterServer() {
  HRESULT initialized = CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
  if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) { return initialized; }
  HRESULT result = E_FAIL;
  try {
    std::wstring path(32768,L'\0'); DWORD length = GetModuleFileNameW(gModule,path.data(),static_cast<DWORD>(path.size()));
    if (length && length < path.size()) {
      path.resize(length);
      result = writeRegistry(classKey(),nullptr,L"簡繁注音");
      if (SUCCEEDED(result)) { result = writeRegistry(classKey() + L"\\InprocServer32",nullptr,path); }
      if (SUCCEEDED(result)) { result = writeRegistry(classKey() + L"\\InprocServer32",L"ThreadingModel",L"Apartment"); }
      if (SUCCEEDED(result)) { result = registerProfile(true); }
      if (FAILED(result)) { registerProfile(false); RegDeleteTreeW(HKEY_LOCAL_MACHINE,classKey().c_str()); }
    }
  } catch (...) { result = E_FAIL; }
  if (SUCCEEDED(initialized)) { CoUninitialize(); } return result;
}
STDAPI DllUnregisterServer() {
  HRESULT initialized = CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
  if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) { return initialized; }
  HRESULT result = registerProfile(false);
  LONG removed = RegDeleteTreeW(HKEY_LOCAL_MACHINE,classKey().c_str());
  if (SUCCEEDED(initialized)) { CoUninitialize(); }
  return FAILED(result) ? result : (removed == ERROR_FILE_NOT_FOUND ? S_OK : HRESULT_FROM_WIN32(removed));
}
