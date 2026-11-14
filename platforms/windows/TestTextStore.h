#pragma once
#include <windows.h>
#include <textstor.h>
#include <msctf.h>
#include <wrl/client.h>
#include <algorithm>
#include <string>

// A real TSF document for integration tests, isolated from other applications.
class TestTextStore final : public ITextStoreACP, public ITfContextOwnerCompositionSink {
 public:
  std::wstring text;
  ULONG ended = 0;
  HWND nativeWindow() const { return window_; }
  TestTextStore() {
    WNDCLASSEXW cls{sizeof(cls)}; cls.lpfnWndProc = DefWindowProcW; cls.hInstance = GetModuleHandleW(nullptr);
    cls.lpszClassName = L"Jianfan.TSFTest.Document"; RegisterClassExW(&cls);
    window_ = CreateWindowExW(0,cls.lpszClassName,L"Jianfan test document",WS_OVERLAPPEDWINDOW | WS_VISIBLE,0,0,500,400,nullptr,nullptr,cls.hInstance,nullptr);
    SetForegroundWindow(window_); SetFocus(window_);
  }
  ~TestTextStore() { if (window_) { DestroyWindow(window_); } UnregisterClassW(L"Jianfan.TSFTest.Document",GetModuleHandleW(nullptr)); }
  HRESULT __stdcall QueryInterface(REFIID iid,void** result) override {
    if (!result) { return E_POINTER; } *result = nullptr;
    if (iid == IID_IUnknown || iid == IID_ITextStoreACP) { *result = static_cast<ITextStoreACP*>(this); }
    else if (iid == IID_ITfContextOwnerCompositionSink) { *result = static_cast<ITfContextOwnerCompositionSink*>(this); }
    else { return E_NOINTERFACE; } AddRef(); return S_OK;
  }
  ULONG __stdcall AddRef() override { return ++references_; }
  ULONG __stdcall Release() override { ULONG count = --references_; if (!count) { delete this; } return count; }
  HRESULT __stdcall AdviseSink(REFIID iid,IUnknown* object,DWORD) override {
    if (iid != IID_ITextStoreACPSink) { return E_INVALIDARG; }
    return object->QueryInterface(IID_PPV_ARGS(&sink_));
  }
  HRESULT __stdcall UnadviseSink(IUnknown*) override { sink_.Reset(); return S_OK; }
  HRESULT __stdcall RequestLock(DWORD flags,HRESULT* result) override {
    if (!result) { return E_POINTER; }
    if (locked_) { *result = TS_E_SYNCHRONOUS; return S_OK; }
    if (!sink_) { return E_UNEXPECTED; }
    locked_ = true; *result = sink_->OnLockGranted(flags); locked_ = false; return S_OK;
  }
  HRESULT __stdcall GetStatus(TS_STATUS* status) override { if (!status) { return E_POINTER; } *status = {}; return S_OK; }
  HRESULT __stdcall QueryInsert(LONG start,LONG end,ULONG,LONG* resultStart,LONG* resultEnd) override {
    if (start < 0 || end < start || end > static_cast<LONG>(text.size())) { return TS_E_INVALIDPOS; }
    *resultStart = start; *resultEnd = end; return S_OK;
  }
  HRESULT __stdcall GetSelection(ULONG index,ULONG count,TS_SELECTION_ACP* selection,ULONG* fetched) override {
    *fetched = 0; if (index != 0 && index != TS_DEFAULT_SELECTION) { return TS_E_NOSELECTION; }
    if (count) { *selection = selection_; *fetched = 1; } return S_OK;
  }
  HRESULT __stdcall SetSelection(ULONG count,const TS_SELECTION_ACP* selection) override { if (count != 1) { return E_INVALIDARG; } selection_ = *selection; return S_OK; }
  HRESULT __stdcall GetText(LONG start,LONG end,WCHAR* plain,ULONG capacity,ULONG* written,TS_RUNINFO* runs,ULONG runCapacity,ULONG* runCount,LONG* next) override {
    if (end == -1) { end = static_cast<LONG>(text.size()); }
    if (start < 0 || end < start || end > static_cast<LONG>(text.size())) { return TS_E_INVALIDPOS; }
    ULONG count = std::min(capacity,static_cast<ULONG>(end - start));
    if (plain && count) { std::copy_n(text.data() + start,count,plain); }
    if (written) { *written = count; }
    if (runs && runCapacity) { runs[0] = {count,TS_RT_PLAIN}; }
    if (runCount) { *runCount = runCapacity && count ? 1 : 0; }
    if (next) { *next = start + count; } return S_OK;
  }
  HRESULT __stdcall SetText(DWORD,LONG start,LONG end,const WCHAR* value,ULONG count,TS_TEXTCHANGE* change) override {
    if (start < 0 || end < start || end > static_cast<LONG>(text.size())) { return TS_E_INVALIDPOS; }
    text.replace(start,end - start,value,count);
    if (change) { *change = {start,end,start + static_cast<LONG>(count)}; }
    selection_.acpStart = selection_.acpEnd = start + count; return S_OK;
  }
  HRESULT __stdcall GetFormattedText(LONG,LONG,IDataObject**) override { return E_NOTIMPL; }
  HRESULT __stdcall GetEmbedded(LONG,REFGUID,REFIID,IUnknown**) override { return E_NOTIMPL; }
  HRESULT __stdcall QueryInsertEmbedded(const GUID*,const FORMATETC*,BOOL* supported) override { *supported = FALSE; return S_OK; }
  HRESULT __stdcall InsertEmbedded(DWORD,LONG,LONG,IDataObject*,TS_TEXTCHANGE*) override { return E_NOTIMPL; }
  HRESULT __stdcall InsertTextAtSelection(DWORD flags,const WCHAR* value,ULONG count,LONG* start,LONG* end,TS_TEXTCHANGE* change) override {
    LONG a = selection_.acpStart, b = selection_.acpEnd;
    if (start) { *start = a; } if (end) { *end = (flags & TS_IAS_QUERYONLY) ? b : a + count; }
    if (flags & TS_IAS_QUERYONLY) { return S_OK; } return SetText(0,a,b,value,count,change);
  }
  HRESULT __stdcall InsertEmbeddedAtSelection(DWORD,IDataObject*,LONG*,LONG*,TS_TEXTCHANGE*) override { return E_NOTIMPL; }
  HRESULT __stdcall RequestSupportedAttrs(DWORD,ULONG,const TS_ATTRID*) override { return S_OK; }
  HRESULT __stdcall RequestAttrsAtPosition(LONG,ULONG,const TS_ATTRID*,DWORD) override { return S_OK; }
  HRESULT __stdcall RequestAttrsTransitioningAtPosition(LONG,ULONG,const TS_ATTRID*,DWORD) override { return S_OK; }
  HRESULT __stdcall FindNextAttrTransition(LONG,LONG halt,ULONG,const TS_ATTRID*,DWORD,LONG* next,BOOL* found,LONG* offset) override { *next = halt; *found = FALSE; *offset = 0; return S_OK; }
  HRESULT __stdcall RetrieveRequestedAttrs(ULONG,TS_ATTRVAL*,ULONG* fetched) override { *fetched = 0; return S_OK; }
  HRESULT __stdcall GetEndACP(LONG* end) override { *end = static_cast<LONG>(text.size()); return S_OK; }
  HRESULT __stdcall GetActiveView(TsViewCookie* cookie) override { *cookie = 1; return S_OK; }
  HRESULT __stdcall GetACPFromPoint(TsViewCookie,const POINT*,DWORD,LONG* position) override { *position = selection_.acpStart; return S_OK; }
  HRESULT __stdcall GetTextExt(TsViewCookie,LONG,LONG,RECT* rect,BOOL* clipped) override { *rect = {20,20,200,50}; *clipped = FALSE; return S_OK; }
  HRESULT __stdcall GetScreenExt(TsViewCookie,RECT* rect) override { *rect = {0,0,500,400}; return S_OK; }
  HRESULT __stdcall GetWnd(TsViewCookie,HWND* window) override { *window = window_; return S_OK; }
  HRESULT __stdcall OnStartComposition(ITfCompositionView*,BOOL* accepted) override { *accepted = TRUE; return S_OK; }
  HRESULT __stdcall OnUpdateComposition(ITfCompositionView*,ITfRange*) override { return S_OK; }
  HRESULT __stdcall OnEndComposition(ITfCompositionView*) override { ++ended; return S_OK; }
 private:
  ULONG references_ = 1;
  HWND window_ = nullptr;
  bool locked_ = false;
  TS_SELECTION_ACP selection_{0,0,{TS_AE_END,FALSE}};
  Microsoft::WRL::ComPtr<ITextStoreACPSink> sink_;
};
