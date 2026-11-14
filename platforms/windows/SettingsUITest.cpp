#include <windows.h>
#include <commctrl.h>
#include <gdiplus.h>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <functional>
#include <string>
#include <thread>
#include <vector>
#include "gtest/gtest.h"
#include "SettingsIds.h"

namespace {
bool until(const std::function<bool()>& check,int milliseconds = 5000) {
  auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(milliseconds);
  do { if (check()) { return true; } std::this_thread::sleep_for(std::chrono::milliseconds(20)); } while (std::chrono::steady_clock::now() < end);
  return false;
}
HWND findWindow(DWORD pid,const wchar_t* cls) {
  struct Search { DWORD pid; const wchar_t* cls; HWND result; } search{pid,cls,nullptr};
  EnumWindows([](HWND window,LPARAM parameter)->BOOL {
    auto data = reinterpret_cast<Search*>(parameter); DWORD pid; GetWindowThreadProcessId(window,&pid);
    wchar_t cls[128]; GetClassNameW(window,cls,128);
    if (pid == data->pid && std::wstring(cls) == data->cls) { data->result = window; return FALSE; } return TRUE;
  },reinterpret_cast<LPARAM>(&search)); return search.result;
}
std::wstring value(HWND control) {
  wchar_t buffer[512]{}; DWORD_PTR result;
  if (!SendMessageTimeoutW(control,WM_GETTEXT,512,reinterpret_cast<LPARAM>(buffer),SMTO_ABORTIFHUNG,2000,&result)) { return {}; }
  return buffer;
}
bool send(HWND control,UINT message,WPARAM wParam = 0,LPARAM lParam = 0) {
  DWORD_PTR result; return SendMessageTimeoutW(control,message,wParam,lParam,SMTO_ABORTIFHUNG,2000,&result) != 0;
}
void capture(HWND window) {
  Gdiplus::GdiplusStartupInput input; ULONG_PTR token;
  if (Gdiplus::GdiplusStartup(&token,&input,nullptr) != Gdiplus::Ok) { return; }
  RECT rect; GetWindowRect(window,&rect); int width = rect.right - rect.left, height = rect.bottom - rect.top;
  HDC dc = GetDC(window), memory = CreateCompatibleDC(dc); HBITMAP bitmap = CreateCompatibleBitmap(dc,width,height); HGDIOBJ previous = SelectObject(memory,bitmap);
  if (PrintWindow(window,memory,2)) {
    UINT count = 0,size = 0; Gdiplus::GetImageEncodersSize(&count,&size);
    std::vector<BYTE> bytes(size); auto encoders = reinterpret_cast<Gdiplus::ImageCodecInfo*>(bytes.data());
    if (Gdiplus::GetImageEncoders(count,size,encoders) == Gdiplus::Ok) {
      for (UINT i = 0; i < count; ++i) { if (std::wstring(encoders[i].MimeType) == L"image/png") { Gdiplus::Bitmap image(bitmap,nullptr); image.Save(L"windows-word-manager.png",&encoders[i].Clsid); break; } }
    }
  }
  SelectObject(memory,previous); DeleteObject(bitmap); DeleteDC(memory); ReleaseDC(window,dc); Gdiplus::GdiplusShutdown(token);
}
class ManagerProcess {
 public:
  PROCESS_INFORMATION process{};
  ~ManagerProcess() {
    if (!process.hProcess) { return; }
    if (auto window = findWindow(process.dwProcessId,L"Jianfan.Settings.Window")) { PostMessageW(window,WM_CLOSE,0,0); }
    if (WaitForSingleObject(process.hProcess,1000) != WAIT_OBJECT_0) { TerminateProcess(process.hProcess,1); WaitForSingleObject(process.hProcess,1000); }
    CloseHandle(process.hThread); CloseHandle(process.hProcess);
    wchar_t temp[MAX_PATH]; if (GetTempPathW(MAX_PATH,temp)) {
      auto folder = std::filesystem::path(temp) / (L"Jianfan-Windows-Tests-" + std::to_wstring(process.dwProcessId));
      std::error_code error; std::filesystem::remove_all(folder,error);
    }
  }
};
}

TEST(WindowsSettings, AddEditSearchAndDeleteThroughNativeControls) {
  wchar_t module[32768]; ASSERT_GT(GetModuleFileNameW(nullptr,module,32768),0u);
  auto application = std::filesystem::path(module).parent_path() / L"JianfanSettingsTest.exe";
  ManagerProcess child; STARTUPINFOW startup{sizeof(startup)};
  ASSERT_TRUE(CreateProcessW(application.c_str(),nullptr,nullptr,nullptr,FALSE,0,nullptr,nullptr,&startup,&child.process));
  WaitForInputIdle(child.process.hProcess,10000);
  HWND window = nullptr;
  ASSERT_TRUE(until([&] { window = findWindow(child.process.dwProcessId,L"Jianfan.Settings.Window"); return window != nullptr; }));
  ASSERT_TRUE(send(GetDlgItem(window,Word),WM_SETTEXT,0,reinterpret_cast<LPARAM>(L"星禾計畫")));
  ASSERT_TRUE(send(GetDlgItem(window,Suggest),BM_CLICK));
  EXPECT_EQ(value(GetDlgItem(window,Reading)),L"ㄒㄧㄥ-ㄏㄜˊ-ㄐㄧˋ-ㄏㄨㄚˋ");
  ASSERT_TRUE(send(GetDlgItem(window,Save),BM_CLICK));
  EXPECT_EQ(ListView_GetItemCount(GetDlgItem(window,WordList)),1);
  ASSERT_TRUE(send(GetDlgItem(window,Reading),WM_SETTEXT,0,reinterpret_cast<LPARAM>(L"ㄒㄧㄥ ㄏㄜˊ")));
  ASSERT_TRUE(send(GetDlgItem(window,Save),BM_CLICK));
  EXPECT_EQ(ListView_GetItemCount(GetDlgItem(window,WordList)),1);
  ASSERT_TRUE(send(GetDlgItem(window,Search),WM_SETTEXT,0,reinterpret_cast<LPARAM>(L"不存在")));
  EXPECT_EQ(ListView_GetItemCount(GetDlgItem(window,WordList)),0);
  ASSERT_TRUE(send(GetDlgItem(window,Search),WM_SETTEXT,0,reinterpret_cast<LPARAM>(L"星禾")));
  EXPECT_EQ(ListView_GetItemCount(GetDlgItem(window,WordList)),1);
  capture(window);
  PostMessageW(GetDlgItem(window,DeleteWord),BM_CLICK,0,0);
  HWND dialog = nullptr;
  ASSERT_TRUE(until([&] { dialog = findWindow(child.process.dwProcessId,L"#32770"); return dialog != nullptr; }));
  ASSERT_TRUE(send(GetDlgItem(dialog,IDYES),BM_CLICK));
  ASSERT_TRUE(until([&] { return ListView_GetItemCount(GetDlgItem(window,WordList)) == 0; }));
  PostMessageW(window,WM_CLOSE,0,0);
  EXPECT_EQ(WaitForSingleObject(child.process.hProcess,5000),WAIT_OBJECT_0);
}
