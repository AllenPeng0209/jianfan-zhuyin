#include "TextService.h"
#include <algorithm>
#include <cstdio>

namespace {
class Edit final : public ITfEditSession,public Counted {
 public:
  explicit Edit(std::function<HRESULT(TfEditCookie)> action) : action_(std::move(action)) {}
  HRESULT __stdcall QueryInterface(REFIID iid,void** result) override {
    if (!result) { return E_POINTER; } *result = nullptr;
    if (iid != IID_IUnknown && iid != IID_ITfEditSession) { return E_NOINTERFACE; }
    *result = static_cast<ITfEditSession*>(this); AddRef(); return S_OK;
  }
  JF_LIFETIME
  HRESULT __stdcall DoEditSession(TfEditCookie cookie) override { try { return action_(cookie); } catch (...) { return E_FAIL; } }
 private:
  std::function<HRESULT(TfEditCookie)> action_;
};
char physicalKey(WPARAM key) {
  if (key >= 'A' && key <= 'Z') { return static_cast<char>(key - 'A' + 'a'); }
  if (key >= '0' && key <= '9') { return static_cast<char>(key); }
  switch (key) {
    case VK_OEM_1: return ';'; case VK_OEM_PLUS: return '='; case VK_OEM_COMMA: return ',';
    case VK_OEM_MINUS: return '-'; case VK_OEM_PERIOD: return '.'; case VK_OEM_2: return '/';
    case VK_OEM_3: return '`'; case VK_OEM_4: return '['; case VK_OEM_5: return '\\';
    case VK_OEM_6: return ']'; case VK_OEM_7: return '\'';
    default: return 0;
  }
}
std::wstring punctuation(WPARAM key,bool shift) {
  if (shift) {
    switch (key) {
      case '1': return L"！"; case '9': return L"（"; case '0': return L"）";
      case VK_OEM_COMMA: return L"，"; case VK_OEM_PERIOD: return L"。"; case VK_OEM_2: return L"？";
      case VK_OEM_1: return L"："; case VK_OEM_4: return L"『"; case VK_OEM_6: return L"』";
      case VK_OEM_MINUS: return L"——"; case VK_OEM_PLUS: return L"＋";
      default: return {};
    }
  }
  switch (key) {
    case VK_OEM_4: return L"「"; case VK_OEM_6: return L"」"; case VK_OEM_5: return L"、";
    case VK_OEM_7: return L"’"; case VK_OEM_PLUS: return L"＝";
    default: return {};
  }
}
bool disabled(ITfContext* context) {
  if (!context) { return true; }
  Ptr<ITfCompartmentMgr> compartments;
  if (FAILED(context->QueryInterface(IID_PPV_ARGS(&compartments)))) { return false; }
  for (const auto& id : {GUID_COMPARTMENT_KEYBOARD_DISABLED,GUID_COMPARTMENT_EMPTYCONTEXT}) {
    Ptr<ITfCompartment> compartment;
    if (SUCCEEDED(compartments->GetCompartment(id,&compartment))) {
      VARIANT value; VariantInit(&value);
      HRESULT result = compartment->GetValue(&value);
      bool blocked = SUCCEEDED(result) && value.vt == VT_I4 && value.lVal != 0;
      VariantClear(&value); if (blocked) { return true; }
    }
  }
  return false;
}
}

TextService::~TextService() { Deactivate(); }
HRESULT TextService::QueryInterface(REFIID iid,void** result) {
  if (!result) { return E_POINTER; } *result = nullptr;
  if (iid == IID_IUnknown || iid == IID_ITfTextInputProcessor || iid == IID_ITfTextInputProcessorEx) { *result = static_cast<ITfTextInputProcessorEx*>(this); }
  else if (iid == IID_ITfKeyEventSink) { *result = static_cast<ITfKeyEventSink*>(this); }
  else if (iid == IID_ITfCompositionSink) { *result = static_cast<ITfCompositionSink*>(this); }
  else if (iid == IID_ITfThreadMgrEventSink) { *result = static_cast<ITfThreadMgrEventSink*>(this); }
  else if (iid == IID_ITfDisplayAttributeProvider) { *result = static_cast<ITfDisplayAttributeProvider*>(this); }
  else if (iid == IID_ITfFunctionProvider) { *result = static_cast<ITfFunctionProvider*>(this); }
  else if (iid == IID_ITfFnConfigure || iid == IID_ITfFunction) { *result = static_cast<ITfFnConfigure*>(this); }
  else { return E_NOINTERFACE; } AddRef(); return S_OK;
}
HRESULT TextService::Activate(ITfThreadMgr* manager,TfClientId client) { return ActivateEx(manager,client,0); }
HRESULT TextService::ActivateEx(ITfThreadMgr* manager,TfClientId client,DWORD) {
  if (!manager || client == TF_CLIENTID_NULL || manager_) { return E_INVALIDARG; }
  try {
#ifdef JIANFAN_TEST_PROFILE
    std::fprintf(stderr,"Jianfan activation: creating engine\n");
#endif
    engine_ = std::make_unique<Jianfan::Session>(EngineConfig());
    if (!engine_->ready()) { return E_FAIL; }
    loadPersonalData();
    manager_ = manager; client_ = client;
    HRESULT result = manager_.As(&keys_);
    if (FAILED(result) || FAILED(result = keys_->AdviseKeyEventSink(client_,this,TRUE))) { Deactivate(); return result; }
#ifdef JIANFAN_TEST_PROFILE
    std::fprintf(stderr,"Jianfan activation: keyboard sink ready\n");
#endif
    manager_.As(&uiManager_);
    Ptr<ITfSource> source;
    if (SUCCEEDED(manager_.As(&source))) { source->AdviseSink(IID_ITfThreadMgrEventSink,static_cast<ITfThreadMgrEventSink*>(this),&sinkCookie_); }
    Ptr<ITfSourceSingle> functions;
    result = manager_.As(&functions);
    if (FAILED(result)) { Deactivate(); return result; }
    Ptr<IUnknown> identity;
    QueryInterface(IID_PPV_ARGS(&identity));
    result = functions->AdviseSingleSink(client_,IID_ITfFunctionProvider,identity.Get());
    if (FAILED(result)) { Deactivate(); return result; }
    Ptr<ITfCategoryMgr> category;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&category)))) { category->RegisterGUID(GUID_JianfanDisplay,&displayAtom_); }
    TF_PRESERVEDKEY script{'F',TF_MOD_CONTROL | TF_MOD_SHIFT};
    TF_PRESERVEDKEY settings{'D',TF_MOD_CONTROL | TF_MOD_SHIFT};
    keys_->PreserveKey(client_,GUID_JianfanToggleScript,&script,L"簡繁切換",4);
    keys_->PreserveKey(client_,GUID_JianfanConfigure,&settings,L"管理詞庫",4);
    return S_OK;
  } catch (const std::exception& error) {
#ifdef JIANFAN_TEST_PROFILE
    std::fprintf(stderr,"Jianfan activation exception: %s\n",error.what());
#endif
    Deactivate(); return E_FAIL;
  }
}
HRESULT TextService::Deactivate() {
  finishCurrent(); closeUI();
  if (keys_) {
    TF_PRESERVEDKEY script{'F',TF_MOD_CONTROL | TF_MOD_SHIFT},settings{'D',TF_MOD_CONTROL | TF_MOD_SHIFT};
    keys_->UnpreserveKey(GUID_JianfanToggleScript,&script); keys_->UnpreserveKey(GUID_JianfanConfigure,&settings);
    keys_->UnadviseKeyEventSink(client_);
  }
  if (manager_ && sinkCookie_ != TF_INVALID_COOKIE) {
    Ptr<ITfSource> source; if (SUCCEEDED(manager_.As(&source))) { source->UnadviseSink(sinkCookie_); }
  }
  if (manager_) { Ptr<ITfSourceSingle> functions; if (SUCCEEDED(manager_.As(&functions))) { functions->UnadviseSingleSink(client_,IID_ITfFunctionProvider); } }
  sinkCookie_ = TF_INVALID_COOKIE; keys_.Reset(); uiManager_.Reset(); manager_.Reset(); client_ = TF_CLIENTID_NULL;
  return S_OK;
}
void TextService::loadPersonalData() {
  if (!engine_) { return; }
  try {
    auto directory = UserDirectory(); settings_ = LocalSettings::read(directory);
    if (!store_) { store_ = std::make_unique<Jianfan::OfflineStore>(directory); }
    engine_->setSimplified(settings_.simplified); engine_->setLearningEnabled(settings_.learning);
    engine_->restoreChoices(store_->choices());
    engine_->reloadUserPhrases(UTF8Path(store_->phrasesPath()),"");
  } catch (...) {
    // A restricted host may deny LocalAppData. Stock offline input still works.
    store_.reset();
  }
}
void TextService::persist() { if (store_ && settings_.learning) { store_->saveChoices(engine_->learnedChoices()); } }
HRESULT TextService::request(ITfContext* context,std::function<HRESULT(TfEditCookie)> action,bool allowAsync) {
  if (!context || client_ == TF_CLIENTID_NULL) { return E_INVALIDARG; }
  Ptr<Edit> session; session.Attach(new Edit(std::move(action)));
  HRESULT outcome = E_FAIL;
  HRESULT result = context->RequestEditSession(client_,session.Get(),TF_ES_SYNC | TF_ES_READWRITE,&outcome);
  if (allowAsync && (FAILED(result) || FAILED(outcome))) {
    result = context->RequestEditSession(client_,session.Get(),TF_ES_ASYNC | TF_ES_READWRITE,&outcome);
  }
  return FAILED(result) ? result : outcome;
}
void TextService::finishCurrent() {
  if (!composition_ || !context_ || client_ == TF_CLIENTID_NULL) { return; }
  Ptr<ITfTextInputProcessorEx> lifetime(this); auto context = context_;
  request(context.Get(),[this,lifetime,context](TfEditCookie cookie) {
    if (!engine_) { return E_UNEXPECTED; }
    return update(context.Get(),cookie,Wide(engine_->commit()),true);
  },true);
}
HRESULT TextService::finish(TfEditCookie cookie) {
  if (!composition_) { return S_OK; }
  auto composition = composition_;
  Ptr<ITfRange> range; composition->GetRange(&range);
  Ptr<ITfProperty> property;
  if (context_ && range && SUCCEEDED(context_->GetProperty(GUID_PROP_ATTRIBUTE,&property))) { property->Clear(cookie,range.Get()); }
  finishing_ = true;
  HRESULT result = composition->EndComposition(cookie);
  finishing_ = false; composition_.Reset(); context_.Reset(); closeUI();
  return result;
}
HRESULT TextService::update(ITfContext* context,TfEditCookie cookie,const std::wstring& value,bool commit) {
  Ptr<ITfRange> range;
  HRESULT result;
  if (composition_) {
    if (context != context_.Get()) { return E_UNEXPECTED; }
    if (FAILED(result = composition_->GetRange(&range))) { return result; }
    if (FAILED(result = range->SetText(cookie,0,value.data(),static_cast<LONG>(value.size())))) { return result; }
  } else {
    if (value.empty()) { return S_OK; }
    Ptr<ITfInsertAtSelection> insertion;
    if (FAILED(result = context->QueryInterface(IID_PPV_ARGS(&insertion)))) { return result; }
    if (FAILED(result = insertion->InsertTextAtSelection(cookie,0,value.data(),static_cast<LONG>(value.size()),&range))) { return result; }
    if (!commit) {
      Ptr<ITfContextComposition> compositions;
      if (FAILED(result = context->QueryInterface(IID_PPV_ARGS(&compositions)))) { return result; }
      result = compositions->StartComposition(cookie,range.Get(),this,&composition_);
      if (FAILED(result) || !composition_) { range->SetText(cookie,0,L"",0); engine_->commit(); return E_FAIL; }
      context_ = context;
    }
  }
  Ptr<ITfRange> selection;
  if (SUCCEEDED(range->Clone(&selection))) {
    selection->Collapse(cookie,TF_ANCHOR_START);
    LONG moved = 0;
    selection->ShiftEnd(cookie,static_cast<LONG>(commit ? value.size() : engine_->cursorUtf16()),&moved,nullptr);
    selection->Collapse(cookie,TF_ANCHOR_END);
    TF_SELECTION item{selection.Get(),{TF_AE_NONE,FALSE}}; context->SetSelection(cookie,1,&item);
  }
  if (composition_ && !commit && !value.empty() && displayAtom_ != TF_INVALID_GUIDATOM) {
    Ptr<ITfProperty> property;
    if (SUCCEEDED(context->GetProperty(GUID_PROP_ATTRIBUTE,&property))) {
      VARIANT attribute; VariantInit(&attribute); attribute.vt = VT_I4; attribute.lVal = displayAtom_;
      property->SetValue(cookie,range.Get(),&attribute);
    }
  }
  if (commit || value.empty()) { return finish(cookie); }
  return S_OK;
}
bool TextService::accepts(ITfContext* context,WPARAM key) const {
  if (!engine_ || disabled(context)) { return false; }
  if (GetKeyState(VK_CONTROL) < 0 || GetKeyState(VK_MENU) < 0 || GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0) { return false; }
  bool composing = !engine_->composition().empty();
  if (key == VK_CAPITAL || key == VK_TAB) { return composing; }
  if (GetKeyState(VK_CAPITAL) & 1) { return false; }
  if (composing && (key == VK_RETURN || key == VK_ESCAPE || key == VK_BACK || key == VK_LEFT || key == VK_RIGHT || key == VK_UP || key == VK_DOWN || key == VK_HOME || key == VK_END || key == VK_PRIOR || key == VK_NEXT || key == VK_SPACE)) { return true; }
  char ascii = physicalKey(key);
  return (ascii && std::string("1234567890-qwertyuiopasdfghjkl;zxcvbnm,./").find(ascii) != std::string::npos) || !punctuation(key,GetKeyState(VK_SHIFT) < 0).empty();
}
HRESULT TextService::OnTestKeyDown(ITfContext* context,WPARAM key,LPARAM,BOOL* eaten) { if (!eaten) { return E_POINTER; } *eaten = accepts(context,key); return S_OK; }
HRESULT TextService::OnTestKeyUp(ITfContext*,WPARAM,LPARAM,BOOL* eaten) { if (!eaten) { return E_POINTER; } *eaten = FALSE; return S_OK; }
HRESULT TextService::OnKeyUp(ITfContext*,WPARAM,LPARAM,BOOL* eaten) { if (!eaten) { return E_POINTER; } *eaten = FALSE; return S_OK; }
HRESULT TextService::OnKeyDown(ITfContext* context,WPARAM key,LPARAM,BOOL* eaten) {
  if (!eaten) { return E_POINTER; } *eaten = FALSE;
  if (!accepts(context,key)) { return S_OK; }
  Ptr<ITfTextInputProcessorEx> lifetime(this); Ptr<ITfContext> owned(context);
  HRESULT result = request(context,[this,lifetime,owned,key](TfEditCookie cookie) { return process(owned.Get(),cookie,key); });
  *eaten = SUCCEEDED(result) && key != VK_TAB && key != VK_CAPITAL;
  return S_OK;
}
HRESULT TextService::process(ITfContext* context,TfEditCookie cookie,WPARAM key) {
  if (engine_->composition().empty()) { loadPersonalData(); }
  if (key == VK_TAB || key == VK_CAPITAL) { return update(context,cookie,Wide(engine_->commit()),true); }
  if (popup_) {
    UINT selection = popup_->selection(), count = static_cast<UINT>(popup_->values.size());
    if (key >= '1' && key <= '9') { return choose(context,cookie,popup_->pageStart() + static_cast<UINT>(key-'1'),false); }
    if (key == VK_RETURN || key == VK_SPACE) { return choose(context,cookie,selection,key == VK_RETURN); }
    if (key == VK_DOWN || key == VK_UP || key == VK_PRIOR || key == VK_NEXT) {
      int delta = key == VK_DOWN ? 1 : key == VK_UP ? -1 : key == VK_PRIOR ? -9 : 9;
      UINT next = static_cast<UINT>(std::clamp(static_cast<int>(selection) + delta,0,static_cast<int>(count)-1));
      popup_->SetSelection(next); if (uiBegun_) { uiManager_->UpdateUIElement(uiId_); } return S_OK;
    }
    if (key == VK_ESCAPE) { engine_->cancel(); closeUI(); return S_OK; }
    engine_->cancel(); closeUI();
  }
  if (key == VK_RETURN && GetKeyState(VK_SHIFT) < 0) { openUI(context,cookie,true); return S_OK; }
  if (key == VK_RETURN || (key == VK_SPACE && engine_->phonetic().empty())) { return update(context,cookie,Wide(engine_->commit()),true); }
  if (key == VK_DOWN || key == VK_UP) { openUI(context,cookie,false); return S_OK; }
  if (key == VK_BACK) { engine_->backspace(); }
  else if (key == VK_ESCAPE) { engine_->cancel(); }
  else if (key == VK_LEFT || key == VK_RIGHT || key == VK_HOME || key == VK_END) { engine_->moveCursor(key == VK_LEFT ? -1 : key == VK_RIGHT ? 1 : key == VK_HOME ? -100000 : 100000); }
  else {
    auto literal = punctuation(key,GetKeyState(VK_SHIFT) < 0);
    if (!literal.empty()) { return update(context,cookie,Wide(engine_->commit()) + literal,true); }
    char ascii = key == VK_SPACE ? ' ' : physicalKey(key);
    if (!ascii || !engine_->key(ascii,Now())) { return S_FALSE; }
  }
  return update(context,cookie,Wide(engine_->composition()),false);
}
void TextService::closeUI() {
  if (popup_) { popup_->choose = {}; popup_->abort = {}; popup_->Show(FALSE); }
  if (uiBegun_ && uiManager_) { uiManager_->EndUIElement(uiId_); }
  uiBegun_ = false; popup_.Reset(); associations_ = false;
}
void TextService::openUI(ITfContext* context,TfEditCookie cookie,bool associations) {
  closeUI();
  if (!uiManager_) { return; }
  if (associations) {
    engine_->openAssociations();
    if (store_ && settings_.learning) { engine_->rankAssociations(store_->rankAssociations(engine_->associationPrefix(),engine_->associations(),Now())); }
  } else { engine_->openCandidates(); }
  const auto& rows = associations ? engine_->associations() : engine_->candidates();
  if (rows.empty()) { return; }
  popup_.Attach(new CandidateUI()); associations_ = associations;
  for (const auto& row : rows) { popup_->values.push_back(Wide(row.value)); }
  context->GetDocumentMgr(&popup_->document);
  popup_->choose = [this](UINT index) {
    if (!context_) { return; } Ptr<ITfTextInputProcessorEx> lifetime(this); auto context = context_;
    request(context.Get(),[this,lifetime,context,index](TfEditCookie cookie) { return choose(context.Get(),cookie,index,false); },true);
  };
  popup_->abort = [this] { if (engine_) { engine_->cancel(); } closeUI(); };
  BOOL show = TRUE;
  if (FAILED(uiManager_->BeginUIElement(popup_.Get(),&show,&uiId_))) { closeUI(); return; }
  uiBegun_ = true;
  if (show) {
    Ptr<ITfContextView> view; HWND owner = nullptr; RECT rect{20,20,200,50}; BOOL clipped = FALSE;
    if (SUCCEEDED(context->GetActiveView(&view))) {
      view->GetWnd(&owner); Ptr<ITfRange> range;
      if (composition_ && SUCCEEDED(composition_->GetRange(&range))) { view->GetTextExt(cookie,range.Get(),&rect,&clipped); }
    }
    popup_->position(owner,rect);
  }
  popup_->Show(show);
}
HRESULT TextService::choose(ITfContext* context,TfEditCookie cookie,UINT index,bool commit) {
  double now = Now(); bool selected = false;
  if (associations_) {
    if (index >= engine_->associations().size()) { return E_INVALIDARG; }
    auto prefix = engine_->associationPrefix(); auto candidate = engine_->associations()[index];
    selected = engine_->selectAssociation(index,now);
    if (selected && store_ && settings_.learning) { store_->recordAssociation(prefix,candidate,now); }
  } else { selected = engine_->selectCandidate(index,now); }
  if (!selected) { return E_INVALIDARG; }
  persist(); closeUI();
  return update(context,cookie,Wide(commit ? engine_->commit() : engine_->composition()),commit);
}
HRESULT TextService::OnPreservedKey(ITfContext* context,REFGUID id,BOOL* eaten) {
  if (!eaten) { return E_POINTER; } *eaten = FALSE;
  if (id == GUID_JianfanConfigure) { *eaten = SUCCEEDED(OpenSettings(nullptr)); return S_OK; }
  if (id != GUID_JianfanToggleScript || !engine_) { return S_OK; }
  auto toggle = [this] {
    settings_.simplified = !settings_.simplified; engine_->setSimplified(settings_.simplified);
    try { settings_.write(UserDirectory()); } catch (...) {} closeUI();
  };
  if (!context) { toggle(); *eaten = TRUE; return S_OK; }
  Ptr<ITfTextInputProcessorEx> lifetime(this); Ptr<ITfContext> owned(context);
  *eaten = SUCCEEDED(request(context,[this,lifetime,owned,toggle](TfEditCookie cookie) {
    toggle(); return update(owned.Get(),cookie,Wide(engine_->composition()),false);
  })); return S_OK;
}
HRESULT TextService::OnCompositionTerminated(TfEditCookie,ITfComposition*) {
  if (!finishing_) { if (engine_) { engine_->commit(); } composition_.Reset(); context_.Reset(); closeUI(); }
  return S_OK;
}
HRESULT TextService::OnSetFocus(BOOL foreground) { if (!foreground) { finishCurrent(); } else if (engine_ && engine_->composition().empty()) { loadPersonalData(); } return S_OK; }
HRESULT TextService::OnInitDocumentMgr(ITfDocumentMgr*) { return S_OK; }
HRESULT TextService::OnUninitDocumentMgr(ITfDocumentMgr*) { finishCurrent(); return S_OK; }
HRESULT TextService::OnSetFocus(ITfDocumentMgr*,ITfDocumentMgr*) { finishCurrent(); return S_OK; }
HRESULT TextService::OnPushContext(ITfContext*) { finishCurrent(); return S_OK; }
HRESULT TextService::OnPopContext(ITfContext*) { finishCurrent(); return S_OK; }
HRESULT TextService::EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** result) { if (!result) { return E_POINTER; } *result = new DisplayAttributes(); return S_OK; }
HRESULT TextService::GetDisplayAttributeInfo(REFGUID id,ITfDisplayAttributeInfo** result) { if (!result) { return E_POINTER; } *result = nullptr; if (id != GUID_JianfanDisplay) { return E_INVALIDARG; } *result = new DisplayAttribute(); return S_OK; }
HRESULT TextService::GetType(GUID* result) { if (!result) { return E_POINTER; } *result = CLSID_Jianfan; return S_OK; }
HRESULT TextService::GetDescription(BSTR* result) { if (!result) { return E_POINTER; } *result = SysAllocString(L"簡繁注音"); return *result ? S_OK : E_OUTOFMEMORY; }
HRESULT TextService::GetDisplayName(BSTR* result) { return GetDescription(result); }
HRESULT TextService::GetFunction(REFGUID id,REFIID iid,IUnknown** result) { if (!result) { return E_POINTER; } *result = nullptr; if (id != GUID_NULL || iid != IID_ITfFnConfigure) { return E_NOINTERFACE; } *result = static_cast<ITfFnConfigure*>(this); AddRef(); return S_OK; }
HRESULT TextService::Show(HWND parent,LANGID,REFGUID) { return OpenSettings(parent); }
