# 第三方来源

本项目的输入法基于 McBopomofo 定制，保留上游版权及许可文件。

跨平台本機資料儲存使用 JSON for Modern C++ 3.12.0（MIT），完整聲明位於 [Vendor/nlohmann/LICENSE.MIT](Vendor/nlohmann/LICENSE.MIT)。

Windows 安裝程式使用 Inno Setup 6.7.1。授權文字保留於 [licenses/Inno-Setup-LICENSE.txt](licenses/Inno-Setup-LICENSE.txt)；中文安裝語系來自同一官方版本的 `Files/Languages/Unofficial`，保留檔案中的譯者資訊。

詞語對應資料另包含源自 libtabe tsi.src 的 BSD 授權衍生資料；完整聲明保留於 `licenses/libtabe-tsi-COPYING` 及 `licenses/libtabe-COPYING`。OpenCC 使用的 darts-clone 為 BSD 2-clause，聲明保留於 `licenses/darts-clone-COPYING.md`。這些聲明同時納入後續安裝包的 ThirdPartyNotices。

| 组件 | 锁定版本或修订 | 来源 | 许可 |
| --- | --- | --- | --- |
| McBopomofo | 3.1.1 | [官方仓库](https://github.com/openvanilla/McBopomofo/tree/3.1.1) | MIT，见 Vendor/McBopomofo/LICENSE.txt |
| SwiftyOpenCC | 1d8105a0f7199c90af722bff62728050c858e777 | [官方仓库](https://github.com/ddddxxx/SwiftyOpenCC) | MIT，见该目录 LICENSE |
| OpenCC | be3af873de7d9ca28c274b4a917d9fcd953345cf | [官方仓库](https://github.com/BYVoid/OpenCC) | Apache 2.0，见该目录 LICENSE |
| SQLite.swift | 392dd6058624d9f6c5b4c769d165ddd8c7293394 | [官方仓库](https://github.com/stephencelis/SQLite.swift) | MIT，见该目录 LICENSE.txt |

原始注音字词数据和搭配词来自 McBopomofo，本地构建生成语言模型。OpenCC 提供简繁转换和转换词典。各组件附带的第三方声明保留在对应源码目录。

SQLite.swift 在本项目中只面向 macOS 构建，使用系统 SQLite，移除了仅 Linux 与 Windows 使用的远程构建依赖。两个上游 Swift 包的依赖地址改为本地路径，使构建不依赖在线 Git 拉取。

本机试用版不使用上游的软件更新服务。新版本通过本项目的安装程序覆盖安装。
