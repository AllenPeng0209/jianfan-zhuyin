#pragma once
#include "CandidateUI.h"
#include "DisplayAttributes.h"
#include "OfflineStore.h"
#include <ctffunc.h>

class TextService final : public ITfTextInputProcessorEx,public ITfKeyEventSink,
    public ITfCompositionSink,public ITfThreadMgrEventSink,public ITfDisplayAttributeProvider,
    public ITfFunctionProvider,public ITfFnConfigure,public Counted {
 public:
  ~TextService() override;
  HRESULT __stdcall QueryInterface(REFIID,void**) override;
  JF_LIFETIME
  HRESULT __stdcall Activate(ITfThreadMgr*,TfClientId) override;
  HRESULT __stdcall ActivateEx(ITfThreadMgr*,TfClientId,DWORD) override;
  HRESULT __stdcall Deactivate() override;
  HRESULT __stdcall OnSetFocus(BOOL) override;
  HRESULT __stdcall OnTestKeyDown(ITfContext*,WPARAM,LPARAM,BOOL*) override;
  HRESULT __stdcall OnTestKeyUp(ITfContext*,WPARAM,LPARAM,BOOL*) override;
  HRESULT __stdcall OnKeyDown(ITfContext*,WPARAM,LPARAM,BOOL*) override;
  HRESULT __stdcall OnKeyUp(ITfContext*,WPARAM,LPARAM,BOOL*) override;
  HRESULT __stdcall OnPreservedKey(ITfContext*,REFGUID,BOOL*) override;
  HRESULT __stdcall OnCompositionTerminated(TfEditCookie,ITfComposition*) override;
  HRESULT __stdcall OnInitDocumentMgr(ITfDocumentMgr*) override;
  HRESULT __stdcall OnUninitDocumentMgr(ITfDocumentMgr*) override;
  HRESULT __stdcall OnSetFocus(ITfDocumentMgr*,ITfDocumentMgr*) override;
  HRESULT __stdcall OnPushContext(ITfContext*) override;
  HRESULT __stdcall OnPopContext(ITfContext*) override;
  HRESULT __stdcall EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo**) override;
  HRESULT __stdcall GetDisplayAttributeInfo(REFGUID,ITfDisplayAttributeInfo**) override;
  HRESULT __stdcall GetType(GUID*) override;
  HRESULT __stdcall GetDescription(BSTR*) override;
  HRESULT __stdcall GetFunction(REFGUID,REFIID,IUnknown**) override;
  HRESULT __stdcall GetDisplayName(BSTR*) override;
  HRESULT __stdcall Show(HWND,LANGID,REFGUID) override;
 private:
  Ptr<ITfThreadMgr> manager_;
  Ptr<ITfKeystrokeMgr> keys_;
  Ptr<ITfUIElementMgr> uiManager_;
  Ptr<ITfComposition> composition_;
  Ptr<ITfContext> context_;
  Ptr<CandidateUI> popup_;
  std::unique_ptr<Jianfan::Session> engine_;
  std::unique_ptr<Jianfan::OfflineStore> store_;
  LocalSettings settings_;
  TfClientId client_ = TF_CLIENTID_NULL;
  DWORD sinkCookie_ = TF_INVALID_COOKIE;
  DWORD uiId_ = 0;
  TfGuidAtom displayAtom_ = TF_INVALID_GUIDATOM;
  bool uiBegun_ = false;
  bool associations_ = false;
  bool finishing_ = false;
  HRESULT request(ITfContext*,std::function<HRESULT(TfEditCookie)>,bool allowAsync = false);
  HRESULT process(ITfContext*,TfEditCookie,WPARAM);
  HRESULT update(ITfContext*,TfEditCookie,const std::wstring&,bool commit);
  HRESULT finish(TfEditCookie);
  void finishCurrent();
  void loadPersonalData();
  void persist();
  void closeUI();
  void openUI(ITfContext*,TfEditCookie,bool associations);
  HRESULT choose(ITfContext*,TfEditCookie,UINT,bool commit);
  bool accepts(ITfContext*,WPARAM) const;
};
