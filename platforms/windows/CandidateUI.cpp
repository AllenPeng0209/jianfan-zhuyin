#include "CandidateUI.h"
#include <algorithm>

HRESULT CandidateUI::QueryInterface(REFIID iid,void** result) {
  if (!result) { return E_POINTER; } *result = nullptr;
  if (iid == IID_IUnknown || iid == IID_ITfUIElement || iid == IID_ITfCandidateListUIElement || iid == IID_ITfCandidateListUIElementBehavior) {
    *result = static_cast<ITfCandidateListUIElementBehavior*>(this);
  } else if (iid == __uuidof(IRawElementProviderSimple)) { *result = static_cast<IRawElementProviderSimple*>(this); }
  else { return E_NOINTERFACE; } AddRef(); return S_OK;
}
HRESULT CandidateUI::GetDescription(BSTR* result) { if (!result) { return E_POINTER; } *result = SysAllocString(L"簡繁注音候選字"); return *result ? S_OK : E_OUTOFMEMORY; }
HRESULT CandidateUI::GetGUID(GUID* result) { if (!result) { return E_POINTER; } *result = GUID_JianfanCandidates; return S_OK; }
HRESULT CandidateUI::Show(BOOL show) {
  shown_ = show != FALSE;
  if (window_) {
    ShowWindow(window_,show ? SW_SHOWNOACTIVATE : SW_HIDE);
    NotifyWinEvent(show ? EVENT_OBJECT_IME_SHOW : EVENT_OBJECT_IME_HIDE,window_,OBJID_CLIENT,CHILDID_SELF);
  }
  return S_OK;
}
HRESULT CandidateUI::IsShown(BOOL* result) { if (!result) { return E_POINTER; } *result = shown_; return S_OK; }
HRESULT CandidateUI::GetUpdatedFlags(DWORD* result) { if (!result) { return E_POINTER; } *result = TF_CLUIE_COUNT | TF_CLUIE_SELECTION | TF_CLUIE_STRING | TF_CLUIE_PAGEINDEX | TF_CLUIE_CURRENTPAGE; return S_OK; }
HRESULT CandidateUI::GetDocumentMgr(ITfDocumentMgr** result) { return document.CopyTo(result); }
HRESULT CandidateUI::GetCount(UINT* result) { if (!result) { return E_POINTER; } *result = static_cast<UINT>(values.size()); return S_OK; }
HRESULT CandidateUI::GetSelection(UINT* result) { if (!result) { return E_POINTER; } *result = selection_; return values.empty() ? S_FALSE : S_OK; }
HRESULT CandidateUI::GetString(UINT index,BSTR* result) {
  if (!result) { return E_POINTER; } *result = nullptr; if (index >= values.size()) { return E_INVALIDARG; }
  *result = SysAllocStringLen(values[index].data(),static_cast<UINT>(values[index].size())); return *result ? S_OK : E_OUTOFMEMORY;
}
HRESULT CandidateUI::GetPageIndex(UINT* indices,UINT capacity,UINT* count) {
  if (!count) { return E_POINTER; }
  UINT pages = pages_.empty() ? static_cast<UINT>((values.size() + 8) / 9) : static_cast<UINT>(pages_.size());
  *count = pages;
  if (indices) { for (UINT i = 0; i < std::min(capacity,pages); ++i) { indices[i] = pages_.empty() ? i * 9 : pages_[i]; } }
  return capacity >= pages ? S_OK : S_FALSE;
}
HRESULT CandidateUI::SetPageIndex(UINT* indices,UINT count) {
  if (!indices || !count || indices[0] != 0) { return E_INVALIDARG; }
  for (UINT i = 0; i < count; ++i) { if (indices[i] >= values.size() || (i && indices[i] <= indices[i-1])) { return E_INVALIDARG; } }
  pages_.assign(indices,indices + count); return S_OK;
}
HRESULT CandidateUI::GetCurrentPage(UINT* result) {
  if (!result) { return E_POINTER; } *result = 0;
  if (pages_.empty()) { *result = selection_ / 9; }
  else { auto end = std::upper_bound(pages_.begin(),pages_.end(),selection_); *result = static_cast<UINT>(std::distance(pages_.begin(),end) - 1); }
  return S_OK;
}
UINT CandidateUI::pageStart() const {
  if (pages_.empty()) { return selection_ / 9 * 9; }
  auto end = std::upper_bound(pages_.begin(),pages_.end(),selection_);
  return end == pages_.begin() ? 0 : *std::prev(end);
}
HRESULT CandidateUI::SetSelection(UINT index) { if (index >= values.size()) { return E_INVALIDARG; } selection_ = index; refresh(); return S_OK; }
HRESULT CandidateUI::Finalize() { if (selection_ >= values.size()) { return E_UNEXPECTED; } auto action = choose; if (action) { action(selection_); } return S_OK; }
HRESULT CandidateUI::Abort() { auto action = abort; if (action) { action(); } return S_OK; }
HRESULT CandidateUI::get_ProviderOptions(ProviderOptions* result) { if (!result) { return E_POINTER; } *result = ProviderOptions_ServerSideProvider; return S_OK; }
HRESULT CandidateUI::GetPatternProvider(PATTERNID,IUnknown** result) { if (!result) { return E_POINTER; } *result = nullptr; return S_OK; }
HRESULT CandidateUI::GetPropertyValue(PROPERTYID id,VARIANT* result) {
  if (!result) { return E_POINTER; } VariantInit(result);
  if (id == UIA_AutomationIdPropertyId || id == UIA_NamePropertyId) {
    std::wstring text = L"IME_Candidate_Window";
    if (id == UIA_NamePropertyId) { text = L"簡繁注音候選字"; for (const auto& value : values) { text += L" " + value; } }
    result->vt = VT_BSTR; result->bstrVal = SysAllocString(text.c_str());
  } else if (id == UIA_ControlTypePropertyId) { result->vt = VT_I4; result->lVal = UIA_ListControlTypeId; }
  else if (id == UIA_IsEnabledPropertyId) { result->vt = VT_BOOL; result->boolVal = VARIANT_TRUE; }
  return S_OK;
}
HRESULT CandidateUI::get_HostRawElementProvider(IRawElementProviderSimple** result) { return UiaHostProviderFromHwnd(window_,result); }
void CandidateUI::updateFont() {
  if (font_) { DeleteObject(font_); }
  UINT dpi = window_ ? GetDpiForWindow(window_) : 96;
  rowHeight_ = MulDiv(34,dpi,96);
  font_ = CreateFontW(-MulDiv(18,dpi,96),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Microsoft JhengHei UI");
}
void CandidateUI::position(HWND owner,RECT caret) {
  if (!window_) {
    WNDCLASSEXW cls{sizeof(cls)}; cls.lpfnWndProc = windowProc; cls.hInstance = gModule;
    cls.hCursor = LoadCursorW(nullptr,IDC_ARROW); cls.lpszClassName = L"Jianfan_IME_Candidate_Window";
    RegisterClassExW(&cls);
    window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,cls.lpszClassName,L"簡繁注音候選字",
                             WS_POPUP | WS_BORDER,0,0,100,100,owner,nullptr,gModule,this);
    updateFont();
  }
  if (!window_) { return; }
  UINT dpi = GetDpiForWindow(window_);
  int width = MulDiv(280,dpi,96), height = rowHeight_ * static_cast<int>(std::min(size_t(9),values.size())) + 2;
  MONITORINFO monitor{sizeof(monitor)}; GetMonitorInfoW(MonitorFromRect(&caret,MONITOR_DEFAULTTONEAREST),&monitor);
  int x = std::clamp(caret.left,monitor.rcWork.left,std::max(monitor.rcWork.left,monitor.rcWork.right - width));
  int y = caret.bottom + height <= monitor.rcWork.bottom ? caret.bottom : caret.top - height;
  y = std::max(y,monitor.rcWork.top);
  SetWindowPos(window_,HWND_TOPMOST,x,y,width,height,SWP_NOACTIVATE);
  refresh();
}
void CandidateUI::refresh() {
  if (!window_) { return; }
  InvalidateRect(window_,nullptr,TRUE);
  NotifyWinEvent(EVENT_OBJECT_IME_CHANGE,window_,OBJID_CLIENT,CHILDID_SELF);
  UiaRaiseAutomationEvent(static_cast<IRawElementProviderSimple*>(this),UIA_SelectionItem_ElementSelectedEventId);
}
LRESULT CALLBACK CandidateUI::windowProc(HWND window,UINT message,WPARAM wParam,LPARAM lParam) {
  auto self = reinterpret_cast<CandidateUI*>(GetWindowLongPtrW(window,GWLP_USERDATA));
  if (message == WM_NCCREATE) { self = static_cast<CandidateUI*>(reinterpret_cast<CREATESTRUCTW*>(lParam)->lpCreateParams); SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self)); }
  if (!self) { return DefWindowProcW(window,message,wParam,lParam); }
  if (message == WM_MOUSEACTIVATE) { return MA_NOACTIVATE; }
  if (message == WM_GETOBJECT && static_cast<LONG>(lParam) == UiaRootObjectId) { return UiaReturnRawElementProvider(window,wParam,lParam,static_cast<IRawElementProviderSimple*>(self)); }
  if (message == WM_DPICHANGED) { self->updateFont(); auto rect = reinterpret_cast<RECT*>(lParam); SetWindowPos(window,nullptr,rect->left,rect->top,rect->right-rect->left,rect->bottom-rect->top,SWP_NOACTIVATE | SWP_NOZORDER); return 0; }
  if (message == WM_LBUTTONUP) {
    UINT index = self->pageStart() + static_cast<UINT>(HIWORD(lParam) / self->rowHeight_);
    self->AddRef(); if (index < self->values.size()) { self->SetSelection(index); self->Finalize(); } self->Release(); return 0;
  }
  if (message == WM_PAINT) {
    PAINTSTRUCT paint; HDC dc = BeginPaint(window,&paint); RECT bounds; GetClientRect(window,&bounds);
    FillRect(dc,&bounds,GetSysColorBrush(COLOR_WINDOW)); SelectObject(dc,self->font_); SetBkMode(dc,TRANSPARENT);
    UINT start = self->pageStart();
    for (UINT i = start; i < std::min(static_cast<UINT>(self->values.size()),start + 9); ++i) {
      RECT row{0,static_cast<LONG>((i-start)*self->rowHeight_),bounds.right,static_cast<LONG>((i-start+1)*self->rowHeight_)};
      if (i == self->selection_) { FillRect(dc,&row,GetSysColorBrush(COLOR_HIGHLIGHT)); }
      SetTextColor(dc,GetSysColor(i == self->selection_ ? COLOR_HIGHLIGHTTEXT : COLOR_WINDOWTEXT));
      std::wstring text = std::to_wstring(i-start+1) + L"  " + self->values[i]; row.left += 10;
      DrawTextW(dc,text.c_str(),static_cast<int>(text.size()),&row,DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);
    }
    EndPaint(window,&paint); return 0;
  }
  return DefWindowProcW(window,message,wParam,lParam);
}
