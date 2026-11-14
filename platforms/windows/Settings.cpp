#include "Common.h"
#include "OfflineStore.h"
#include "SettingsIds.h"
#include "ProfileRegistration.h"
#include <commctrl.h>
#include <commdlg.h>
#include <optional>
#include <vector>

HINSTANCE gModule = nullptr;
std::atomic<long> gObjects{0},gLocks{0};

namespace {
std::wstring text(HWND window) {
  int size = GetWindowTextLengthW(window); std::wstring value(size + 1,L'\0');
  GetWindowTextW(window,value.data(),size + 1); value.resize(size); return value;
}
std::string normalizedReading(const std::wstring& input) {
  std::vector<std::wstring> syllables; std::wstring current;
  auto append = [&] {
    if (current.empty()) { return; }
    if (current.front() == L'˙') { current.erase(current.begin()); current += L'˙'; }
    syllables.push_back(current); current.clear();
  };
  for (wchar_t c : input) {
    WORD type = 0; GetStringTypeW(CT_CTYPE1,&c,1,&type);
    if (c == L'-' || (type & C1_SPACE)) { append(); }
    else if (c != L'ˉ') { current += c; }
  }
  append(); std::wstring output;
  for (const auto& syllable : syllables) { if (!output.empty()) { output += L'-'; } output += syllable; }
  return UTF8(output);
}

class SettingsWindow {
 public:
  explicit SettingsWindow() : engine_(EngineConfig()),store_(UserDirectory()) { settings_ = LocalSettings::read(UserDirectory()); }
  HWND window = nullptr;
  static LRESULT CALLBACK procedure(HWND window,UINT message,WPARAM wParam,LPARAM lParam) {
    auto self = reinterpret_cast<SettingsWindow*>(GetWindowLongPtrW(window,GWLP_USERDATA));
    if (message == WM_NCCREATE) { self = static_cast<SettingsWindow*>(reinterpret_cast<CREATESTRUCTW*>(lParam)->lpCreateParams); self->window = window; SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self)); }
    if (!self) { return DefWindowProcW(window,message,wParam,lParam); }
    try { return self->handle(message,wParam,lParam); }
    catch (const std::exception& error) { MessageBoxW(window,Wide(error.what()).c_str(),L"無法完成操作",MB_OK | MB_ICONERROR); return 0; }
  }
 private:
  Jianfan::Session engine_;
  Jianfan::OfflineStore store_;
  LocalSettings settings_;
  std::vector<Jianfan::UserPhrase> rows_;
  std::optional<Jianfan::UserPhrase> original_;
  HFONT font_ = nullptr;
  HWND wordLabel_ = nullptr,readingLabel_ = nullptr,help_ = nullptr;
  bool loading_ = false,dirty_ = false;
  int scale(int value) const { return MulDiv(value,static_cast<int>(GetDpiForWindow(window)),96); }
  HWND control(int id,const wchar_t* cls,const wchar_t* label,DWORD style = 0) {
    auto result = CreateWindowExW(cls == std::wstring(L"EDIT") ? WS_EX_CLIENTEDGE : 0,cls,label,
      WS_CHILD | WS_VISIBLE | (cls == std::wstring(L"STATIC") ? 0 : WS_TABSTOP) | style,0,0,0,0,window,reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),gModule,nullptr);
    SendMessageW(result,WM_SETFONT,reinterpret_cast<WPARAM>(font_),TRUE); return result;
  }
  HWND item(int id) const { return GetDlgItem(window,id); }
  void move(HWND child,int x,int y,int width,int height) { MoveWindow(child,scale(x),scale(y),scale(width),scale(height),TRUE); }
  void layout() {
    RECT rect; GetClientRect(window,&rect);
    int width = MulDiv(rect.right,96,GetDpiForWindow(window)), height = MulDiv(rect.bottom,96,GetDpiForWindow(window));
    int split = width * 53 / 100, editor = split + 20, right = width - editor - 20;
    move(item(Search),20,18,split-20,32); move(item(WordList),20,62,split-20,height-194);
    move(wordLabel_,editor,20,right,24); move(item(Word),editor,48,right,36);
    move(readingLabel_,editor,100,right,24); move(item(Reading),editor,128,right,36);
    move(item(Suggest),editor,178,right,32);
    int button = (right-12)/2;
    move(item(Save),editor,224,button,36); move(item(NewWord),editor+button+12,224,button,36);
    move(item(DeleteWord),editor,272,right,34); move(help_,editor,322,right,92);
    move(item(ImportWords),20,height-118,100,34); move(item(ExportWords),132,height-118,100,34);
    move(item(Simplified),20,height-68,160,30); move(item(Learning),190,height-68,180,30);
    move(item(ClearLearning),width-180,height-68,160,30); move(item(Status),20,height-30,width-40,24);
    if (item(WordList)) { ListView_SetColumnWidth(item(WordList),0,scale(165)); ListView_SetColumnWidth(item(WordList),1,std::max(scale(160),scale(split-190))); }
  }
  void updateFont() {
    if (font_) { DeleteObject(font_); }
    font_ = CreateFontW(-scale(16),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Microsoft JhengHei UI");
    EnumChildWindows(window,[](HWND child,LPARAM value)->BOOL { SendMessageW(child,WM_SETFONT,static_cast<WPARAM>(value),TRUE); return TRUE; },reinterpret_cast<LPARAM>(font_));
  }
  bool discard() {
    if (!dirty_) { return true; }
    return MessageBoxW(window,L"放棄尚未儲存的修改？",L"詞庫",MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2) == IDYES;
  }
  void status() {
    std::wstring value = L"完全離線 · " + std::to_wstring(rows_.size()) + L" 個詞語";
    if (!store_.error().empty()) { value += L" · " + Wide(store_.error()); }
    SetWindowTextW(item(Status),value.c_str());
  }
  void reload() {
    auto entries = store_.phrases();
    std::wstring query = text(item(Search)); rows_.clear(); loading_ = true;
    ListView_DeleteAllItems(item(WordList));
    for (const auto& entry : entries) {
      auto word = Wide(entry.phrase), reading = Wide(entry.reading);
      if (!query.empty() && word.find(query) == std::wstring::npos && reading.find(query) == std::wstring::npos &&
          Wide(engine_.toSimplified(entry.phrase)).find(query) == std::wstring::npos) { continue; }
      int row = static_cast<int>(rows_.size()); rows_.push_back(entry);
      LVITEMW value{}; value.mask = LVIF_TEXT; value.iItem = row; value.pszText = word.data();
      ListView_InsertItem(item(WordList),&value); ListView_SetItemText(item(WordList),row,1,reading.data());
    }
    loading_ = false; status();
  }
  void draft(const std::optional<Jianfan::UserPhrase>& row) {
    loading_ = true; original_ = row;
    SetWindowTextW(item(Word),row ? Wide(row->phrase).c_str() : L"");
    SetWindowTextW(item(Reading),row ? Wide(row->reading).c_str() : L"");
    EnableWindow(item(DeleteWord),row.has_value()); loading_ = false; dirty_ = false;
  }
  void save() {
    Jianfan::UserPhrase row{engine_.toTraditional(UTF8(text(item(Word)))),normalizedReading(text(item(Reading)))};
    if (!engine_.supportsReading(row.reading)) { throw std::runtime_error("Enter valid Bopomofo, with spaces or hyphens between syllables (up to 8)."); }
    if (!store_.upsertPhrase(row,[&](const std::string& reading) { return engine_.supportsReading(reading); },original_)) { throw std::runtime_error(store_.error()); }
    draft(row); reload();
  }
  std::optional<std::filesystem::path> fileDialog(bool save) {
    std::wstring buffer(32768,L'\0'); if (save) { std::wstring name = L"Jianfan-phrases.json"; std::copy(name.begin(),name.end(),buffer.begin()); }
    OPENFILENAMEW data{sizeof(data)}; data.hwndOwner = window; data.lpstrFilter = L"詞庫備份 (*.json)\0*.json\0\0";
    data.lpstrFile = buffer.data(); data.nMaxFile = static_cast<DWORD>(buffer.size()); data.lpstrDefExt = L"json";
    data.Flags = OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST | (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
    if (!(save ? GetSaveFileNameW(&data) : GetOpenFileNameW(&data))) { return {}; } return std::filesystem::path(buffer.c_str());
  }
  void importWords() {
    if (!discard()) { return; }
    auto path = fileDialog(false); if (!path) { return; }
    if (std::filesystem::file_size(*path) > 4 * 1024 * 1024) { throw std::runtime_error("The dictionary file exceeds 4 MiB."); }
    std::ifstream stream(*path,std::ios::binary); auto doc = nlohmann::json::parse(stream);
    if (doc.contains("entries") && doc["entries"].is_array()) {
      for (auto& row : doc["entries"]) { if (row.contains("phrase") && row["phrase"].is_string()) { row["phrase"] = engine_.toTraditional(row["phrase"]); } }
    }
    if (!store_.importPhrases(doc.dump(),[&](const std::string& reading) { return engine_.supportsReading(reading); })) { throw std::runtime_error(store_.error()); }
    draft({}); reload();
  }
  void exportWords() {
    auto path = fileDialog(true); if (!path) { return; }
    auto temporary = *path; temporary += L".jianfan-" + std::to_wstring(GetCurrentProcessId()) + L".tmp";
    auto data = store_.exportPhrases();
    { std::ofstream stream(temporary,std::ios::binary | std::ios::trunc);
      if (!stream.write(data.data(),data.size()) || !stream.flush()) { throw std::runtime_error("Cannot write the dictionary backup."); }
    }
    if (!MoveFileExW(temporary.c_str(),path->c_str(),MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) { throw std::runtime_error("Cannot replace the dictionary backup."); }
  }
  LRESULT handle(UINT message,WPARAM wParam,LPARAM lParam) {
    if (message == WM_CTLCOLORSTATIC || message == WM_CTLCOLORBTN) {
      HDC dc = reinterpret_cast<HDC>(wParam); SetBkMode(dc,TRANSPARENT); SetTextColor(dc,GetSysColor(COLOR_WINDOWTEXT));
      return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
    }
    if (message == WM_CREATE) {
      updateFont();
      control(Search,L"EDIT",L"",ES_AUTOHSCROLL); SendMessageW(item(Search),EM_SETCUEBANNER,TRUE,reinterpret_cast<LPARAM>(L"搜尋詞語或注音"));
      control(WordList,WC_LISTVIEWW,L"",LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_BORDER);
      ListView_SetExtendedListViewStyle(item(WordList),LVS_EX_FULLROWSELECT | LVS_EX_LABELTIP | LVS_EX_DOUBLEBUFFER);
      LVCOLUMNW column{}; column.mask = LVCF_TEXT | LVCF_WIDTH; column.cx = scale(165); column.pszText = const_cast<wchar_t*>(L"詞語"); ListView_InsertColumn(item(WordList),0,&column);
      column.pszText = const_cast<wchar_t*>(L"注音"); column.cx = scale(260); ListView_InsertColumn(item(WordList),1,&column);
      wordLabel_ = control(0,L"STATIC",L"詞語"); readingLabel_ = control(0,L"STATIC",L"注音");
      control(Word,L"EDIT",L"",ES_AUTOHSCROLL); control(Reading,L"EDIT",L"",ES_AUTOHSCROLL);
      SendMessageW(item(Word),EM_SETLIMITTEXT,160,0); SendMessageW(item(Reading),EM_SETLIMITTEXT,160,0);
      control(Suggest,L"BUTTON",L"自動填入讀音"); control(Save,L"BUTTON",L"儲存",BS_DEFPUSHBUTTON); control(NewWord,L"BUTTON",L"新增詞語"); control(DeleteWord,L"BUTTON",L"刪除詞語");
      help_ = control(0,L"STATIC",L"以空格或 - 分隔音節，最多 8 個音節。\r\n\r\n多音字請確認讀音後儲存。詞庫與記憶都保存在本機。");
      control(ImportWords,L"BUTTON",L"匯入 JSON"); control(ExportWords,L"BUTTON",L"匯出 JSON");
      control(Simplified,L"BUTTON",L"預設簡體輸出",BS_AUTOCHECKBOX); control(Learning,L"BUTTON",L"長期選字記憶",BS_AUTOCHECKBOX); control(ClearLearning,L"BUTTON",L"清除記憶"); control(Status,L"STATIC",L"");
      SendMessageW(item(Simplified),BM_SETCHECK,settings_.simplified ? BST_CHECKED : BST_UNCHECKED,0);
      SendMessageW(item(Learning),BM_SETCHECK,settings_.learning ? BST_CHECKED : BST_UNCHECKED,0);
      draft({}); reload(); layout(); return 0;
    }
    if (message == WM_SIZE) { layout(); return 0; }
    if (message == WM_GETMINMAXINFO) { auto info = reinterpret_cast<MINMAXINFO*>(lParam); info->ptMinTrackSize = {scale(840),scale(580)}; return 0; }
    if (message == WM_DPICHANGED) { updateFont(); auto rect = reinterpret_cast<RECT*>(lParam); SetWindowPos(window,nullptr,rect->left,rect->top,rect->right-rect->left,rect->bottom-rect->top,SWP_NOZORDER | SWP_NOACTIVATE); layout(); return 0; }
    if (message == WM_NOTIFY) {
      auto header = reinterpret_cast<NMHDR*>(lParam);
      if (header->idFrom == WordList && header->code == LVN_ITEMCHANGING && !loading_) {
        auto value = reinterpret_cast<NMLISTVIEW*>(lParam);
        if ((value->uNewState & LVIS_SELECTED) && !(value->uOldState & LVIS_SELECTED) && !discard()) { return TRUE; }
      }
      if (header->idFrom == WordList && header->code == LVN_ITEMCHANGED && !loading_) {
        auto value = reinterpret_cast<NMLISTVIEW*>(lParam);
        if ((value->uNewState & LVIS_SELECTED) && value->iItem >= 0 && static_cast<size_t>(value->iItem) < rows_.size()) { draft(rows_[value->iItem]); }
      }
      return 0;
    }
    if (message == WM_COMMAND) {
      int id = LOWORD(wParam), event = HIWORD(wParam);
      if (id == Search && event == EN_CHANGE && !loading_) { reload(); return 0; }
      if ((id == Word || id == Reading) && event == EN_CHANGE && !loading_) { dirty_ = true; return 0; }
      if (event != BN_CLICKED) { return 0; }
      if (id == Save || id == IDOK) { save(); }
      else if (id == Suggest) { SetWindowTextW(item(Reading),Wide(engine_.suggestedReading(UTF8(text(item(Word))))).c_str()); }
      else if (id == NewWord) { if (discard()) { draft({}); SetFocus(item(Word)); } }
      else if (id == DeleteWord && original_ && MessageBoxW(window,L"刪除這個詞語？",L"詞庫",MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2) == IDYES) {
        if (!store_.removePhrase(*original_)) { throw std::runtime_error(store_.error()); } draft({}); reload();
      } else if (id == ImportWords) { importWords(); }
      else if (id == ExportWords) { exportWords(); }
      else if (id == Simplified || id == Learning) {
        auto latest = LocalSettings::read(UserDirectory());
        if (id == Simplified) { latest.simplified = SendMessageW(item(id),BM_GETCHECK,0,0) == BST_CHECKED; }
        else { latest.learning = SendMessageW(item(id),BM_GETCHECK,0,0) == BST_CHECKED; }
        latest.write(UserDirectory()); settings_ = latest;
      } else if (id == ClearLearning && MessageBoxW(window,L"清除選字與聯想記憶？個人詞庫會保留。",L"清除記憶",MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2) == IDYES) {
        if (!store_.clearLearning()) { throw std::runtime_error(store_.error()); }
        auto latest = LocalSettings::read(UserDirectory()); GUID id; CoCreateGuid(&id); wchar_t token[40]; StringFromGUID2(id,token,40);
        latest.resetToken = UTF8(token); latest.write(UserDirectory()); settings_ = latest; status();
      }
      return 0;
    }
    if (message == WM_CLOSE) { if (discard()) { DestroyWindow(window); } return 0; }
    if (message == WM_DESTROY) { if (font_) { DeleteObject(font_); font_ = nullptr; } PostQuitMessage(0); return 0; }
    return DefWindowProcW(window,message,wParam,lParam);
  }
};
}

int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR arguments,int show) {
  gModule = instance; CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
  if (std::wstring(arguments) == L"--enable" || std::wstring(arguments) == L"--disable") {
    bool enabled = std::wstring(arguments) == L"--enable";
    bool result = SetUserProfileEnabled(enabled); CoUninitialize(); return result ? 0 : 1;
  }
  INITCOMMONCONTROLSEX controls{sizeof(controls),ICC_LISTVIEW_CLASSES}; InitCommonControlsEx(&controls);
  int result = 1;
  try {
    SettingsWindow app;
    WNDCLASSEXW cls{sizeof(cls)}; cls.lpfnWndProc = SettingsWindow::procedure; cls.hInstance = instance; cls.lpszClassName = L"Jianfan.Settings.Window";
    cls.hCursor = LoadCursorW(nullptr,IDC_ARROW); cls.hbrBackground = GetSysColorBrush(COLOR_WINDOW); cls.hIcon = LoadIconW(instance,MAKEINTRESOURCEW(1)); RegisterClassExW(&cls);
    HWND window = CreateWindowExW(WS_EX_CONTROLPARENT,cls.lpszClassName,L"簡繁注音 · 詞庫與學習",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,1040,700,nullptr,nullptr,instance,&app);
    if (!window) { throw std::runtime_error("Cannot open the dictionary manager."); }
    ShowWindow(window,show); UpdateWindow(window);
    MSG message;
    while (GetMessageW(&message,nullptr,0,0) > 0) { if (!IsDialogMessageW(window,&message)) { TranslateMessage(&message); DispatchMessageW(&message); } }
    result = static_cast<int>(message.wParam);
  } catch (const std::exception& error) { MessageBoxW(nullptr,Wide(error.what()).c_str(),L"簡繁注音",MB_OK | MB_ICONERROR); }
  CoUninitialize(); return result;
}
