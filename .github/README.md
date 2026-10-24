# leapgate-client

[English](#english) | [中文](#中文)

## English

The client of [Leapgate](https://github.com/Ogannesson/leapgate), a remote desktop built on RustDesk. This repository is a fork of [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk), starting from `bd92623`. Upstream releases will be brought in with `git merge`, not rebase, so the full upstream history is kept; none has been merged yet.

Leapgate has not been released and there is no installer to download. Only Windows 10 and later is supported for now. Builds are not code-signed.

### What is changed

- Leapgate's code lives in `libs/leapgate`: branding, default options, LAN address candidates for direct connections under a TUN-mode proxy, signed reports to the Leapgate API, and relay latency measurement. Upstream files only get short hooks marked `// leapgate:`.
- The app is renamed (`leapgate.exe`, `libleapgate.dll`, its own configuration directory) so that it can sit next to RustDesk on the same machine. The official update check is disabled.
- `libs/hbb_common` is the submodule [leapgate-cardo](https://github.com/Ogannesson/leapgate-cardo), branch `leapgate/client`. Default servers are injected at build time; a build without them never falls back to RustDesk's public servers.

### Building on Windows

The build scripts live in the [leapgate](https://github.com/Ogannesson/leapgate) repository under `scripts/windows/`, so clone that repository with its submodules. You need PowerShell 7, Visual Studio 2022 Build Tools (C++ and CMake), Developer Mode, long path support, rustup, Git for Windows, Python 3.10+, and 7-Zip or Bandizip.

```
git clone --recurse-submodules https://github.com/Ogannesson/leapgate.git
cd leapgate
pwsh -File scripts\windows\setup-toolchain.ps1
$env:LEAPGATE_RENDEZVOUS_SERVER = 'rendezvous.example.com'
$env:LEAPGATE_RS_PUB_KEY = '<server public key>'
pwsh -File scripts\windows\build-client.ps1 -Source client
```

- `setup-toolchain.ps1` installs pinned versions of Rust, LLVM, Flutter and vcpkg into `C:\leapgate-build`, or into `LEAPGATE_BUILD_ROOT` if set.
- `LEAPGATE_RENDEZVOUS_SERVER` and `LEAPGATE_RS_PUB_KEY` set the default server and its public key. `LEAPGATE_API_SERVER` is optional; without it the API address is derived from the rendezvous server. If no server is injected, the client waits for the user to enter one.
- `build-client.ps1` modifies tracked files in the source tree, so point `-Source` at a worktree used only for building if you plan to commit.
- The output is in `flutter\build\windows\x64\runner\Release\`.

### Documentation

`LEAPGATE.md` describes every change made on top of upstream, in Chinese. Upstream's original `README.md`, `AGENTS.md` and `CLAUDE.md` are kept unchanged at the repository root.

### License

AGPL-3.0, inherited from RustDesk. Leapgate is not affiliated with or endorsed by the RustDesk project; the RustDesk name belongs to its owners.

## 中文

[Leapgate（跃门）](https://github.com/Ogannesson/leapgate)的客户端。Leapgate 是基于 RustDesk 改进的远程桌面。本仓库是 [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk) 的 fork，起点是 `bd92623`。上游的正式版本以后用 `git merge` 合并进来（不用 rebase），保留上游的完整历史；目前还没有合并过。

Leapgate 还没有发布，没有可下载的安装包。目前只支持 Windows 10 及以上，构建产物没有代码签名。

### 改了什么

- Leapgate 的代码放在 `libs/leapgate`：品牌、默认选项、开 TUN 代理时用于局域网直连的候选地址、向 Leapgate API 签名上报、到各中继的延迟测量。上游文件里只加简短的挂钩，用 `// leapgate:` 标出。
- 程序改了名（`leapgate.exe`、`libleapgate.dll`、独立的配置目录），目的是能和 RustDesk 装在同一台机器上。官方的更新检查已关闭。
- `libs/hbb_common` 是子模块 [leapgate-cardo](https://github.com/Ogannesson/leapgate-cardo) 的 `leapgate/client` 分支。默认服务器在构建时注入，没有注入的构建不会退回到 RustDesk 的公共服务器。

### 在 Windows 上构建

构建脚本在 [leapgate](https://github.com/Ogannesson/leapgate) 仓库的 `scripts/windows/` 下，所以要连同子模块克隆那个仓库。需要 PowerShell 7、Visual Studio 2022 Build Tools（C++ 和 CMake 组件）、开发者模式、长路径支持、rustup、Git for Windows、Python 3.10 及以上，以及 7-Zip 或 Bandizip。命令见上方英文部分。

- `setup-toolchain.ps1` 把钉住版本的 Rust、LLVM、Flutter 和 vcpkg 装到 `C:\leapgate-build`；设置了 `LEAPGATE_BUILD_ROOT` 时装到它指定的目录。
- `LEAPGATE_RENDEZVOUS_SERVER` 和 `LEAPGATE_RS_PUB_KEY` 指定默认服务器和它的公钥。`LEAPGATE_API_SERVER` 可选，不设时由会合服务器地址推出 API 地址。没有注入服务器时，客户端会等用户填好再连接。
- `build-client.ps1` 会改动源码目录里被跟踪的文件，打算提交代码的话，`-Source` 应指向专门用来构建的 worktree。
- 产物在 `flutter\build\windows\x64\runner\Release\` 下。

### 文档

`LEAPGATE.md` 说明了在上游之上做的全部改动，只有中文。上游原来的 `README.md`、`AGENTS.md` 和 `CLAUDE.md` 原样保留在仓库根目录。

### 许可证

AGPL-3.0，继承自 RustDesk。Leapgate 与 RustDesk 项目没有关联，也未获其认可；RustDesk 这个名字归其所有者。
