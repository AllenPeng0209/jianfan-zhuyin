# Windows 版本

Windows 原生版本使用 TSF，標準大千注音、簡繁輸出、候選、長期選字記憶、個人詞庫與聯想排序均離線運作。目前以 Windows 11 x64 為建置目標，同時提供 x86 輸入服務供 32 位元應用使用。ARM64 原生版本尚未列入此安裝包。

[Windows 0.3.0 公開下載](https://github.com/AllenPeng0209/jianfan-zhuyin/releases/tag/v0.3.0)。原生輸入、候選、元件釋放、詞庫管理介面及安裝／移除的資料保留已在 Windows 雲端環境以 x64 與 x86 驗證。安裝程式尚未使用商業程式碼簽章。

## 安裝後使用

執行安裝程式後，用 Win + Space 選用「簡繁注音」。安裝程式會註冊輸入法，不變更預設鍵盤。若應用程式正在使用舊版輸入服務，更新可能需要登出或重新啟動才能套用。

| 操作 | 按鍵 |
| --- | --- |
| 完成音節 | 聲調鍵；一聲按空白鍵 |
| 開啟候選 | 向下鍵 |
| 選字 | 數字 1–9，或方向鍵後按 Enter |
| 確認組字 | Enter 或空白鍵 |
| 聯想續詞 | Shift + Enter |
| 簡繁切換 | Ctrl + Shift + F |
| 開啟詞庫管理 | Ctrl + Shift + D，或開始功能表中的詞庫管理程式 |
| 英文輸入 | Caps Lock，或 Win + Space 切換英文鍵盤 |

個人資料儲存在 `%LOCALAPPDATA%\JianfanZhuyin`。移除程式會保留個人詞庫與記憶；JSON 匯出包含詞語及讀音，可在 Mac、Windows 與 iOS 之間手動匯入。

受 Windows 沙盒限制的應用可能無法讀取使用者的 LocalAppData；在這類應用中，內建離線詞庫仍可使用，個人化功能視該應用允許的檔案存取範圍而定。

## 從原始碼建置

需要 Visual Studio C++ 桌面開發工具、Windows SDK、CMake、Python 3 及 Inno Setup 6。相依原始碼已隨專案提供。

```powershell
powershell -File scripts/build-windows.ps1
```

輸出位於 `dist`。TSF 整合測試使用獨立的測試 CLSID、輸入設定與暫存資料夾，測試結束會取消註冊；測試註冊需要管理員權限。
