#pragma once
#include <windows.h>
#include <shlobj.h>
#include <shellapi.h>
#include <wrl/client.h>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include "Guids.h"
#include "Session.h"
#include "../../Vendor/nlohmann/json.hpp"

extern HINSTANCE gModule;
extern std::atomic<long> gObjects;
extern std::atomic<long> gLocks;
template<class T> using Ptr = Microsoft::WRL::ComPtr<T>;

class Counted {
 public:
  Counted() { ++gObjects; }
  virtual ~Counted() { --gObjects; }
 protected:
  std::atomic<ULONG> references_{1};
};
#define JF_LIFETIME \
  ULONG __stdcall AddRef() override { return ++references_; } \
  ULONG __stdcall Release() override { ULONG count = --references_; if (!count) { delete this; } return count; }

inline std::wstring Wide(const std::string& text) {
  if (text.empty()) { return {}; }
  int count = MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),nullptr,0);
  if (!count) { throw std::runtime_error("Invalid UTF-8 text."); }
  std::wstring result(count,L'\0');
  MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),result.data(),count); return result;
}
inline std::string UTF8(const std::wstring& text) {
  if (text.empty()) { return {}; }
  int count = WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),nullptr,0,nullptr,nullptr);
  if (!count) { throw std::runtime_error("Invalid Unicode text."); }
  std::string result(count,'\0');
  WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),result.data(),count,nullptr,nullptr); return result;
}
inline std::string UTF8Path(const std::filesystem::path& path) { auto text = path.u8string(); return {text.begin(),text.end()}; }
inline std::filesystem::path ModuleDirectory() {
  std::wstring path(32768,L'\0');
  DWORD count = GetModuleFileNameW(gModule,path.data(),static_cast<DWORD>(path.size()));
  if (!count || count >= path.size()) { throw std::runtime_error("Application path is unavailable."); }
  path.resize(count); return std::filesystem::path(path).parent_path();
}
inline std::filesystem::path DataDirectory() {
  auto directory = ModuleDirectory();
  if (std::filesystem::exists(directory / L"Data" / L"data.txt")) { return directory / L"Data"; }
  return directory.parent_path() / L"Data";
}
inline std::filesystem::path UserDirectory() {
#ifdef JIANFAN_TEST_PROFILE
  wchar_t buffer[MAX_PATH];
  if (!GetTempPathW(MAX_PATH,buffer)) { throw std::runtime_error("Test folder is unavailable."); }
  return std::filesystem::path(buffer) / (L"Jianfan-Windows-Tests-" + std::to_wstring(GetCurrentProcessId()));
#else
  PWSTR path = nullptr;
  HRESULT result = SHGetKnownFolderPath(FOLDERID_LocalAppData,KF_FLAG_DEFAULT,nullptr,&path);
  if (FAILED(result)) { throw std::runtime_error("Personal data is unavailable in this application."); }
  std::filesystem::path directory(path); CoTaskMemFree(path); return directory / L"JianfanZhuyin";
#endif
}
inline Jianfan::Config EngineConfig() {
  auto directory = DataDirectory();
  return {UTF8Path(directory / L"data.txt"),UTF8Path(directory / L"associated-phrases-v2.txt"),UTF8Path(directory),"","",true};
}
inline double Now() { return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count(); }
struct LocalSettings {
  bool simplified = true;
  bool learning = true;
  std::string resetToken;
  static LocalSettings read(const std::filesystem::path& directory) {
    auto path = directory / L"settings-v1.json";
    if (!std::filesystem::exists(path)) { return {}; }
    if (std::filesystem::file_size(path) > 65536) { throw std::runtime_error("Invalid settings file."); }
    std::ifstream stream(path,std::ios::binary);
    auto data = nlohmann::json::parse(stream);
    if (data.value("schemaVersion",0) != 1) { throw std::runtime_error("Settings require a newer version."); }
    return {data.value("simplified",true),data.value("learningEnabled",true),data.value("resetToken",std::string())};
  }
  void write(const std::filesystem::path& directory) const {
    std::filesystem::create_directories(directory);
    auto path = directory / L"settings-v1.json", temporary = directory / L"settings-v1.json.tmp";
    auto data = nlohmann::json{{"schemaVersion",1},{"simplified",simplified},{"learningEnabled",learning},{"resetToken",resetToken}}.dump();
    { std::ofstream stream(temporary,std::ios::binary | std::ios::trunc);
      if (!stream.write(data.data(),data.size()) || !stream.flush()) { throw std::runtime_error("Cannot save local settings."); }
    }
    if (!MoveFileExW(temporary.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) { throw std::runtime_error("Cannot replace local settings."); }
  }
};
inline HRESULT OpenSettings(HWND parent) {
  try {
    auto path = ModuleDirectory() / L"JianfanSettings.exe";
    if (!std::filesystem::exists(path)) { path = ModuleDirectory().parent_path() / L"JianfanSettings.exe"; }
    auto result = reinterpret_cast<INT_PTR>(ShellExecuteW(parent,L"open",path.c_str(),nullptr,nullptr,SW_SHOWNORMAL));
    return result > 32 ? S_OK : E_FAIL;
  } catch (...) { return E_FAIL; }
}
