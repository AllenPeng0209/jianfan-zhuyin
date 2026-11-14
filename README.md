# 簡繁注音

使用標準注音大千鍵盤的中文輸入法，預設輸出簡體，可切換繁體。基於 McBopomofo 與 OpenCC 客製，注音解析、詞庫、選字記憶與聯想排序均在本機運作，無需帳戶或伺服器。

目前 Mac 本機試用版為 **0.2.0，構建號 3**。Windows、iOS、GitHub 開源與公開發行依序開發；此安裝包供本機試用，使用本地 ad hoc 簽名。

## 0.2 新增

- **長期選字記憶**：記住明確選用的候選，保存次數、時間及短語上下文；重啟後還原。排序兼顧使用頻率與最近使用情況。
- **個人詞庫管理**：搜尋、新增、改讀音、刪除、JSON 匯入匯出與自動讀音。保留原文字詞庫的註解與既有資料，存檔後立即載入引擎。
- **聯想排序**：已選用的聯想詞逐步提前，未學習的候選保留原有順序；仍使用本地詞庫提供的候選。
- **學習控制**：管理視窗可暫停使用及記錄偏好，也可清除選字與聯想記憶。個人詞庫與學習記憶分開管理。

## 安裝與更新

1. 開啟 `dist/JianfanZhuyin-0.2.0-arm64.dmg`。
2. 開啟其中的「安裝簡繁注音」，依畫面安裝或更新。
3. 若 macOS 顯示輸入法啟用提示，確認加入；從選單列選用「簡繁注音」。
4. 若安裝器顯示「已安裝，請啟用輸入法」，使用「開啟鍵盤設定」繼續加入。

程式位於目前使用者的 `~/Library/Input Methods/JianfanZhuyin.app`。本機資料位於 `~/Library/Application Support/JianfanZhuyin/`，更新時分開保留。

## 詞庫與學習

從輸入法選單開啟「管理詞庫與學習」，或在偏好設定的詞庫分頁開啟管理視窗。

選擇「新增詞語」，填入詞語，再按「自動讀音」。多音字可手動修改，以空格或連字號分隔音節。每條讀音最多 8 個音節，也可用較短讀音對應較長的名稱。按「加入詞庫」或「儲存變更」後即可輸入。

JSON 匯入會先檢查整批資料，再合併及去重；錯誤資料不會部分寫入。匯出包含一般詞語及讀音。需要完整備份原始文字詞庫、額外設定與學習記憶時，可備份整個本機資料夾。

選字記憶位於 `learning-v1.json`，另有本機復原備份。輸入法不記錄逐鍵日誌或完整對話，不會上傳詞庫或學習記憶。

## 常用按鍵

| 操作 | 按鍵 |
| --- | --- |
| 輸入音節 | 標準注音，以聲調結束；一聲按空白鍵 |
| 開啟候選 | 音節完成後按向下鍵或空白鍵 |
| 選字 | 數字 1 至 9，或方向鍵移動後按 Enter |
| 上屏組字 | 候選關閉時按 Enter，本次 Enter 不繼續觸發應用程式送出 |
| 切換簡繁 | Control 加 Command 加 G |
| 詞組聯想 | Shift 加 Enter；可從輸入法選單啟用自動聯想 |
| 取消聯想／候選 | Esc，保留目前組字 |
| 英文、數字、網址 | 使用系統快捷鍵切到 ABC，Caps Lock 依系統設定 |

可逐鍵輸入 `su3cl3` 驗證「你好」，`gj bj4` 驗證「输入」。鍵碼不可透過貼上驗證輸入法。

## 開發與驗證

使用 Xcode 27 與 Apple Silicon；依賴已鎖定並放在 `Vendor`，構建不需要線上解析 Swift 套件。

```bash
bash scripts/test-macos.sh
swift test --package-path Vendor/McBopomofo/Packages/JianfanUserData --scratch-path build/UserDataTests
cmake -S . -B build/EngineTests
cmake --build build/EngineTests --target McBopomofoLMLibTest --parallel 4
bash scripts/build-local.sh
```

Mac 測試使用獨立開發輸入源、IMK 連線及每次新建的測試資料夾，並以兩個不同程序驗證選字保存與還原，不修改日常輸入法的資料。紀錄位於 `build/logs/`。

公開分發仍需完成簽名、公證與各平台驗收。來源與授權見 [THIRD_PARTY.md](THIRD_PARTY.md)，完整產品需求見 [PRD.md](PRD.md)。
