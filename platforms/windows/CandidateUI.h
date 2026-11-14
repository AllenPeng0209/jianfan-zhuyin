#pragma once
#include "Common.h"
#include <msctf.h>
#include <UIAutomation.h>
#include <functional>
#include <vector>

class CandidateUI final : public ITfCandidateListUIElementBehavior,public IRawElementProviderSimple,public Counted {
 public:
  std::vector<std::wstring> values;
  std::function<void(UINT)> choose;
  std::function<void()> abort;
  Ptr<ITfDocumentMgr> document;
  CandidateUI() = default;
  ~CandidateUI() override { if (window_) { DestroyWindow(window_); } if (font_) { DeleteObject(font_); } UnregisterClassW(L"Jianfan_IME_Candidate_Window",gModule); }
  HRESULT __stdcall QueryInterface(REFIID iid,void** result) override;
  JF_LIFETIME
  HRESULT __stdcall GetDescription(BSTR* result) override;
  HRESULT __stdcall GetGUID(GUID* result) override;
  HRESULT __stdcall Show(BOOL show) override;
  HRESULT __stdcall IsShown(BOOL* result) override;
  HRESULT __stdcall GetUpdatedFlags(DWORD* result) override;
  HRESULT __stdcall GetDocumentMgr(ITfDocumentMgr** result) override;
  HRESULT __stdcall GetCount(UINT* result) override;
  HRESULT __stdcall GetSelection(UINT* result) override;
  HRESULT __stdcall GetString(UINT index,BSTR* result) override;
  HRESULT __stdcall GetPageIndex(UINT* indices,UINT capacity,UINT* count) override;
  HRESULT __stdcall SetPageIndex(UINT* indices,UINT count) override;
  HRESULT __stdcall GetCurrentPage(UINT* result) override;
  HRESULT __stdcall SetSelection(UINT index) override;
  HRESULT __stdcall Finalize() override;
  HRESULT __stdcall Abort() override;
  HRESULT __stdcall get_ProviderOptions(ProviderOptions* result) override;
  HRESULT __stdcall GetPatternProvider(PATTERNID id,IUnknown** result) override;
  HRESULT __stdcall GetPropertyValue(PROPERTYID id,VARIANT* result) override;
  HRESULT __stdcall get_HostRawElementProvider(IRawElementProviderSimple** result) override;
  void position(HWND owner,RECT caret);
  void refresh();
  UINT selection() const { return selection_; }
  UINT pageStart() const;
 private:
  HWND window_ = nullptr;
  HFONT font_ = nullptr;
  UINT selection_ = 0;
  bool shown_ = false;
  int rowHeight_ = 32;
  std::vector<UINT> pages_;
  void updateFont();
  static LRESULT CALLBACK windowProc(HWND,UINT,WPARAM,LPARAM);
};
