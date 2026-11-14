#pragma once
#include "Common.h"
#include <msctf.h>

class DisplayAttribute final : public ITfDisplayAttributeInfo,public Counted {
 public:
  HRESULT __stdcall QueryInterface(REFIID iid,void** result) override {
    if (!result) { return E_POINTER; } *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_ITfDisplayAttributeInfo) { return E_NOINTERFACE; }
    *result = static_cast<ITfDisplayAttributeInfo*>(this); AddRef(); return S_OK;
  }
  JF_LIFETIME
  HRESULT __stdcall GetGUID(GUID* value) override { if (!value) { return E_POINTER; } *value = GUID_JianfanDisplay; return S_OK; }
  HRESULT __stdcall GetDescription(BSTR* value) override { if (!value) { return E_POINTER; } *value = SysAllocString(L"簡繁注音組字"); return *value ? S_OK : E_OUTOFMEMORY; }
  HRESULT __stdcall GetAttributeInfo(TF_DISPLAYATTRIBUTE* value) override {
    if (!value) { return E_POINTER; } *value = {};
    value->crText.type = TF_CT_NONE; value->crBk.type = TF_CT_NONE;
    value->lsStyle = TF_LS_SOLID; value->fBoldLine = FALSE;
    value->crLine.type = TF_CT_COLORREF; value->crLine.cr = GetSysColor(COLOR_WINDOWTEXT);
    value->bAttr = TF_ATTR_INPUT; return S_OK;
  }
  HRESULT __stdcall SetAttributeInfo(const TF_DISPLAYATTRIBUTE*) override { return E_NOTIMPL; }
  HRESULT __stdcall Reset() override { return S_OK; }
};

class DisplayAttributes final : public IEnumTfDisplayAttributeInfo,public Counted {
 public:
  HRESULT __stdcall QueryInterface(REFIID iid,void** result) override {
    if (!result) { return E_POINTER; } *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_IEnumTfDisplayAttributeInfo) { return E_NOINTERFACE; }
    *result = static_cast<IEnumTfDisplayAttributeInfo*>(this); AddRef(); return S_OK;
  }
  JF_LIFETIME
  HRESULT __stdcall Clone(IEnumTfDisplayAttributeInfo** result) override {
    if (!result) { return E_POINTER; } auto clone = new DisplayAttributes(); clone->used_ = used_; *result = clone; return S_OK;
  }
  HRESULT __stdcall Next(ULONG count,ITfDisplayAttributeInfo** values,ULONG* fetched) override {
    if (!values || (!fetched && count != 1)) { return E_INVALIDARG; }
    ULONG actual = 0;
    if (count && !used_) { values[0] = new DisplayAttribute(); used_ = true; actual = 1; }
    if (fetched) { *fetched = actual; } return actual == count ? S_OK : S_FALSE;
  }
  HRESULT __stdcall Reset() override { used_ = false; return S_OK; }
  HRESULT __stdcall Skip(ULONG count) override { bool available = !used_; if (count) { used_ = true; } return !count || (available && count == 1) ? S_OK : S_FALSE; }
 private:
  bool used_ = false;
};
