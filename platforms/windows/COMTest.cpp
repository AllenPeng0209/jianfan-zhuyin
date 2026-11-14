#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include "Guids.h"
#include "gtest/gtest.h"
#include "TestTextStore.h"
#include "ProfileRegistration.h"
#include <cstdio>
#include <chrono>
#include <thread>
#include <io.h>

namespace {
struct Registration {
  HMODULE module = nullptr;
  HRESULT (__stdcall *unregister)() = nullptr;
  HKL originalLayout = GetKeyboardLayout(0);
  ~Registration() {
    if (unregister) {
      ActivateKeyboardLayout(originalLayout,0);
      SetUserProfileEnabled(false); unregister();
    }
    if (module) { FreeLibrary(module); }
  }
};
struct Apartment { ~Apartment() { CoUninitialize(); } };
}

TEST(WindowsTIP, FactoryProvidesNativeTSFAndCandidateUIContracts) {
  using Microsoft::WRL::ComPtr;
  ASSERT_TRUE(SUCCEEDED(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED)));
  Apartment apartment;
  HMODULE module = LoadLibraryW(L"JianfanIMETest.dll");
  ASSERT_NE(module,nullptr);
  Registration registration; registration.module = module;
  auto install = reinterpret_cast<HRESULT (__stdcall *)()>(GetProcAddress(module,"DllRegisterServer"));
  registration.unregister = reinterpret_cast<HRESULT (__stdcall *)()>(GetProcAddress(module,"DllUnregisterServer"));
  ASSERT_NE(install,nullptr); ASSERT_NE(registration.unregister,nullptr);
  // The launcher registers before this process starts, so TSF caches are fresh.
  DWORD session = 0; ProcessIdToSessionId(GetCurrentProcessId(),&session);
  std::cout << "Windows test session: " << session << "\n";
  auto factoryFunction = reinterpret_cast<HRESULT (__stdcall *)(REFCLSID,REFIID,void**)>(GetProcAddress(module,"DllGetClassObject"));
  ASSERT_NE(factoryFunction,nullptr);
  ComPtr<IClassFactory> factory;
  ASSERT_EQ(factoryFunction(CLSID_Jianfan,IID_PPV_ARGS(&factory)),S_OK);
  ComPtr<ITfTextInputProcessorEx> processor;
  ASSERT_EQ(factory->CreateInstance(nullptr,IID_PPV_ARGS(&processor)),S_OK);
  ComPtr<ITfKeyEventSink> keys;
  EXPECT_EQ(processor.As(&keys),S_OK);
  ComPtr<ITfDisplayAttributeProvider> display;
  EXPECT_EQ(processor.As(&display),S_OK);
  keys.Reset(); display.Reset(); processor.Reset(); factory.Reset();
  ComPtr<ITfThreadMgr> manager;
  ASSERT_EQ(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&manager)),S_OK);
  TfClientId client = TF_CLIENTID_NULL;
  ASSERT_EQ(manager->Activate(&client),S_OK);
  ComPtr<TestTextStore> store;
  store.Attach(new TestTextStore());
  ComPtr<ITfDocumentMgr> document;
  ASSERT_EQ(manager->CreateDocumentMgr(&document),S_OK);
  ComPtr<ITfContext> context;
  TfEditCookie cookie;
  ASSERT_EQ(document->CreateContext(client,0,static_cast<ITextStoreACP*>(store.Get()),&context,&cookie),S_OK);
  ASSERT_EQ(document->Push(context.Get()),S_OK);
  ComPtr<ITfDocumentMgr> priorFocus;
  ASSERT_EQ(manager->AssociateFocus(store->nativeWindow(),document.Get(),&priorFocus),S_OK);
  ASSERT_EQ(manager->SetFocus(document.Get()),S_OK);
  ComPtr<ITfTextInputProcessorEx> registeredService;
  ASSERT_EQ(CoCreateInstance(CLSID_Jianfan,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&registeredService)),S_OK);
  registeredService.Reset();
  std::cout << "Current keyboard language: " << LOWORD(GetKeyboardLayout(0)) << "; test language: " << JianfanLanguage << "\n";
  ComPtr<ITfInputProcessorProfileMgr> profiles;
  ASSERT_EQ(CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles)),S_OK);
  HKL layout = LoadKeyboardLayoutW(L"00000404",KLF_NOTELLSHELL);
  std::cout << "Traditional Chinese keyboard layout: " << layout << "; error: " << GetLastError() << "\n";
  ASSERT_NE(layout,nullptr);
  ASSERT_NE(ActivateKeyboardLayout(layout,0),nullptr);
  MSG message;
  while (PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
  ASSERT_EQ(LOWORD(GetKeyboardLayout(0)),JianfanLanguage);
  SetFocus(store->nativeWindow());
  ASSERT_EQ(manager->SetFocus(document.Get()),S_OK);
  TF_INPUTPROCESSORPROFILE profile{};
  ComPtr<ITfInputProcessorProfiles> descriptionProvider;
  ASSERT_EQ(profiles.As(&descriptionProvider),S_OK);
  ASSERT_EQ(descriptionProvider->EnableLanguageProfile(CLSID_Jianfan,JianfanLanguage,GUID_JianfanProfile,TRUE),S_OK);
  BOOL enabled = FALSE;
  ASSERT_EQ(descriptionProvider->IsEnabledLanguageProfile(CLSID_Jianfan,JianfanLanguage,GUID_JianfanProfile,&enabled),S_OK);
  ASSERT_TRUE(enabled);
  BSTR description = nullptr;
  HRESULT described = descriptionProvider->GetLanguageProfileDescription(CLSID_Jianfan,JianfanLanguage,GUID_JianfanProfile,&description);
  std::cout << "Profile description status: " << described << "\n";
  if (description) { SysFreeString(description); }
  EXPECT_EQ(described,S_OK);
  ComPtr<ITfCategoryMgr> categories;
  ASSERT_EQ(CoCreateInstance(CLSID_TF_CategoryMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&categories)),S_OK);
  const GUID* kinds[] = {&GUID_TFCAT_TIP_KEYBOARD,&GUID_TFCAT_TIP_SPEECH,&GUID_TFCAT_TIP_HANDWRITING};
  GUID category{};
  HRESULT categorized = categories->FindClosestCategory(CLSID_Jianfan,&category,kinds,3);
  std::cout << "Category query: " << categorized << "; keyboard category: " << (category == GUID_TFCAT_TIP_KEYBOARD) << "\n";
  EXPECT_EQ(categorized,S_OK); EXPECT_EQ(category,GUID_TFCAT_TIP_KEYBOARD);
  HRESULT profileReady = E_FAIL;
  auto profileDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  do {
    while (PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
    profileReady = profiles->GetProfile(TF_PROFILETYPE_INPUTPROCESSOR,JianfanLanguage,CLSID_Jianfan,GUID_JianfanProfile,nullptr,&profile);
    if (SUCCEEDED(profileReady)) { break; }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  } while (std::chrono::steady_clock::now() < profileDeadline);
  ASSERT_EQ(profileReady,S_OK);
  std::cout << "Registered profile type: " << profile.dwProfileType << "; flags: " << profile.dwFlags << "\n";
  ASSERT_EQ(profiles->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,JianfanLanguage,CLSID_Jianfan,GUID_JianfanProfile,nullptr,TF_IPPMF_FORPROCESS | TF_IPPMF_ENABLEPROFILE),S_OK);
  ComPtr<ITfFunctionProvider> provider;
  ComPtr<ITfKeystrokeMgr> routing;
  ASSERT_EQ(manager.As(&routing),S_OK);
  HRESULT available = E_FAIL;
  auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  do {
    while (PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
    BOOL pendingKey = FALSE; routing->TestKeyDown('S',0,&pendingKey);
    available = manager->GetFunctionProvider(CLSID_Jianfan,&provider);
    if (SUCCEEDED(available)) { break; }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  } while (std::chrono::steady_clock::now() < deadline);
  ASSERT_EQ(available,S_OK);
  ASSERT_EQ(provider.As(&processor),S_OK);
  ASSERT_EQ(processor.As(&keys),S_OK);
  ULONG endedBeforeTyping = store->ended;
  EXPECT_TRUE(store->text.empty());
  for (WCHAR key : std::wstring(L"SU3CL3")) {
    BOOL eaten = FALSE;
    ASSERT_EQ(keys->OnTestKeyDown(context.Get(),key,0,&eaten),S_OK);
    ASSERT_TRUE(eaten);
    ASSERT_EQ(keys->OnKeyDown(context.Get(),key,0,&eaten),S_OK);
    ASSERT_TRUE(eaten);
    std::cout << "Key " << static_cast<unsigned int>(key) << ": ended compositions " << store->ended << "\n";
  }
  EXPECT_EQ(store->text,L"你好");
  EXPECT_EQ(store->ended,endedBeforeTyping);
  BOOL opened = FALSE;
  ASSERT_EQ(keys->OnKeyDown(context.Get(),VK_DOWN,0,&opened),S_OK);
  ASSERT_TRUE(opened);
  ComPtr<ITfUIElementMgr> ui;
  ASSERT_EQ(manager.As(&ui),S_OK);
  ComPtr<IEnumTfUIElements> elements;
  ASSERT_EQ(ui->EnumUIElements(&elements),S_OK);
  ComPtr<ITfCandidateListUIElementBehavior> candidates;
  ULONG fetched = 0;
  ComPtr<ITfUIElement> element;
  while (elements->Next(1,element.ReleaseAndGetAddressOf(),&fetched) == S_OK && fetched) {
    GUID guid;
    if (SUCCEEDED(element->GetGUID(&guid)) && guid == GUID_JianfanCandidates) { element.As(&candidates); break; }
  }
  ASSERT_NE(candidates.Get(),nullptr);
  UINT count = 0; EXPECT_EQ(candidates->GetCount(&count),S_OK); EXPECT_GT(count,0u);
  EXPECT_EQ(candidates->Abort(),S_OK);
  candidates.Reset(); element.Reset(); elements.Reset(); ui.Reset();
  BOOL eaten = FALSE;
  ASSERT_EQ(keys->OnKeyDown(context.Get(),VK_RETURN,0,&eaten),S_OK);
  EXPECT_TRUE(eaten);
  EXPECT_EQ(store->text,L"你好");
  EXPECT_EQ(store->ended,endedBeforeTyping + 1);
  EXPECT_EQ(processor->Deactivate(),S_OK);
  profiles->DeactivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,JianfanLanguage,CLSID_Jianfan,GUID_JianfanProfile,nullptr,TF_IPPMF_FORPROCESS);
  provider.Reset(); profiles.Reset();
  manager->SetFocus(nullptr);
  manager->AssociateFocus(store->nativeWindow(),nullptr,&priorFocus);
  document->Pop(TF_POPF_ALL);
  context.Reset(); document.Reset(); store.Reset();
  priorFocus.Reset(); descriptionProvider.Reset(); categories.Reset();
  manager->Deactivate();
  routing.Reset(); manager.Reset(); keys.Reset(); display.Reset(); processor.Reset(); factory.Reset();
  auto canUnload = reinterpret_cast<HRESULT (__stdcall *)()>(GetProcAddress(module,"DllCanUnloadNow"));
  ASSERT_NE(canUnload,nullptr);
  HRESULT unloadable = S_FALSE;
  auto unloadDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
  do {
    while (PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
    CoFreeUnusedLibraries(); unloadable = canUnload();
    if (unloadable == S_OK) { break; }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  } while (std::chrono::steady_clock::now() < unloadDeadline);
  EXPECT_EQ(unloadable,S_OK);
}

int WINAPI wWinMain(HINSTANCE,HINSTANCE,PWSTR,int) {
  FILE* output = nullptr;
  freopen_s(&output,"windows-com.log","w",stdout);
  freopen_s(&output,"windows-com-error.log","w",stderr);
  SetStdHandle(STD_OUTPUT_HANDLE,reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(stdout))));
  SetStdHandle(STD_ERROR_HANDLE,reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(stderr))));
  setvbuf(stdout,nullptr,_IONBF,0); setvbuf(stderr,nullptr,_IONBF,0);
  int count = 1; char name[] = "WindowsCOMTest"; char* arguments[] = {name,nullptr};
  testing::InitGoogleTest(&count,arguments);
  return RUN_ALL_TESTS();
}
