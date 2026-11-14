#pragma once
#include <windows.h>
#include <objbase.h>
#include <string>
#include "Guids.h"

inline bool SetUserProfileEnabled(bool enabled) {
  HMODULE input = LoadLibraryExW(L"input.dll",nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!input) { return false; }
  auto install = reinterpret_cast<BOOL (CALLBACK *)(LPCWSTR,DWORD)>(GetProcAddress(input,"InstallLayoutOrTip"));
  wchar_t clsid[40]{},profile[40]{},language[16]{};
  StringFromGUID2(CLSID_Jianfan,clsid,40); StringFromGUID2(GUID_JianfanProfile,profile,40);
  swprintf_s(language,L"0x%04X:",JianfanLanguage);
  std::wstring value = std::wstring(language) + clsid + profile;
  // Add or remove only this profile. Keep the user's default and other layouts.
  bool result = install && install(value.c_str(),enabled ? 0u : 1u);
  FreeLibrary(input); return result;
}
