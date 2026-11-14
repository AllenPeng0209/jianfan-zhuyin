#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include "Guids.h"
#include "gtest/gtest.h"

TEST(WindowsTIP, FactoryProvidesNativeTSFAndCandidateUIContracts) {
  using Microsoft::WRL::ComPtr;
  ASSERT_TRUE(SUCCEEDED(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED)));
  HMODULE module = LoadLibraryW(L"JianfanIME.dll");
  ASSERT_NE(module,nullptr);
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
  ComPtr<ITfThreadMgr> manager;
  ASSERT_EQ(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&manager)),S_OK);
  TfClientId client = TF_CLIENTID_NULL;
  ASSERT_EQ(manager->Activate(&client),S_OK);
  EXPECT_EQ(processor->ActivateEx(manager.Get(),client,TF_TMAE_UIELEMENTENABLEDONLY),S_OK);
  EXPECT_EQ(processor->Deactivate(),S_OK);
  manager->Deactivate();
  manager.Reset(); keys.Reset(); display.Reset(); processor.Reset(); factory.Reset();
  auto canUnload = reinterpret_cast<HRESULT (__stdcall *)()>(GetProcAddress(module,"DllCanUnloadNow"));
  ASSERT_NE(canUnload,nullptr);
  EXPECT_EQ(canUnload(),S_OK);
  FreeLibrary(module);
  CoUninitialize();
}
