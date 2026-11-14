#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include "Guids.h"
#include "gtest/gtest.h"
#include "TestTextStore.h"

TEST(WindowsTIP, FactoryProvidesNativeTSFAndCandidateUIContracts) {
  using Microsoft::WRL::ComPtr;
  ASSERT_TRUE(SUCCEEDED(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED)));
  HMODULE module = LoadLibraryW(L"JianfanIMETest.dll");
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
  ComPtr<TestTextStore> store;
  store.Attach(new TestTextStore());
  ComPtr<ITfDocumentMgr> document;
  ASSERT_EQ(manager->CreateDocumentMgr(&document),S_OK);
  ComPtr<ITfContext> context;
  TfEditCookie cookie;
  ASSERT_EQ(document->CreateContext(client,0,static_cast<ITextStoreACP*>(store.Get()),&context,&cookie),S_OK);
  ASSERT_EQ(document->Push(context.Get()),S_OK);
  ASSERT_EQ(manager->SetFocus(document.Get()),S_OK);
  for (WCHAR key : std::wstring(L"SU3CL3")) {
    BOOL eaten = FALSE;
    ASSERT_EQ(keys->OnTestKeyDown(context.Get(),key,0,&eaten),S_OK);
    ASSERT_TRUE(eaten);
    ASSERT_EQ(keys->OnKeyDown(context.Get(),key,0,&eaten),S_OK);
    ASSERT_TRUE(eaten);
  }
  EXPECT_EQ(store->text,L"你好");
  EXPECT_EQ(store->ended,0u);
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
  EXPECT_EQ(store->ended,1u);
  EXPECT_EQ(processor->Deactivate(),S_OK);
  manager->SetFocus(nullptr);
  document->Pop(TF_POPF_ALL);
  context.Reset(); document.Reset(); store.Reset();
  manager->Deactivate();
  manager.Reset(); keys.Reset(); display.Reset(); processor.Reset(); factory.Reset();
  auto canUnload = reinterpret_cast<HRESULT (__stdcall *)()>(GetProcAddress(module,"DllCanUnloadNow"));
  ASSERT_NE(canUnload,nullptr);
  EXPECT_EQ(canUnload(),S_OK);
  FreeLibrary(module);
  CoUninitialize();
}
