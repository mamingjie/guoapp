# 开发指南

## 环境

Flutter `3.47.9`、Dart `3.12+`、Go `1.24.1+`、Python `3.10+`。

- Android：JDK 17、SDK 36、NDK `28.2.13676358`
- Windows：Visual Studio C++ 桌面组件、MinGW-w64 x64、Inno Setup 6.5+（`winget install JRSoftware.InnoSetup`）
- iOS：macOS、完整 Xcode、CocoaPods
- macOS：完整 Xcode、CocoaPods，打 dmg 需 `pip install dmgbuild Pillow`；`xcode-select` 指向 Command Line Tools 时 `build_macos.py` 会自动改用 `/Applications/Xcode*.app`，也可以在系统层面执行 `sudo xcode-select -s`
- 鸿蒙：DevEco Studio 26（内含 SDK API 26、Ohpm、hvigor、Node）、带 `enable-ohos` 的 OHOS 版 Flutter SDK、`OpenHarmony-SIG/ohos_golang_go` 的 Go fork（见[鸿蒙](#鸿蒙harmonyos)）

构建脚本对子进程默认设置 `GOPROXY=https://goproxy.cn,direct`、`GOSUMDB=off`，同名环境变量可覆盖。

## 调试运行

官方站源不在本仓库，放在单独的私有站源仓库里（Go 模块 `guoapp/sources`）。编译 Go 核心时用 `--sources <站源仓库路径>` 接入站源，可以多次指定以同时接入多个站源模块；脚本会在 `native/` 下生成不入库的 `go.work` 与 `bridge/sources_gen.go`，之后可以省略。从未接入过站源时自动使用 `native/sources_example` 的示例站源，它只返回假数据、不访问网络、不能播放，用来在没有站源仓库时调试界面；想换回示例站源，传 `--sources native/sources_example`。所有出包脚本都接受同一个参数。站源模块的写法见[站源开发约定](#站源开发约定)。

Flutter 运行前必须先编译对应平台 / 架构的 Go 核心：

~~~sh
python3 scripts/build_native.py --platform android --abi arm64-v8a --sources ../guoapp-sources
flutter pub get --enforce-lockfile
flutter run
~~~

调试全站源版：`build_native.py` 加 `--all-sources`，再 `flutter run --dart-define=APP_FLAVOR=zhenguojian`；iOS 对应 `build_ios.py --core-only --all-sources`，macOS 用 `build_native.py --platform darwin --all-sources`。版本是编译期开关，Dart 常量和 Go 编译参数必须一致，应用启动时会校验，避免混装原生库。

## 出包

~~~sh
python3 scripts/build_android.py                 # 红果鉴
python3 scripts/build_android.py --all-sources   # 全站源版
python3 scripts/build_android.py --abi arm64-v8a
python scripts/build_windows.py [--all-sources]
python3 scripts/build_ios.py [--all-sources]
python3 scripts/build_macos.py [--all-sources]
python3 scripts/build_ios.py --core-only [--simulator]
python3 scripts/build_ios.py --export-options /path/to/ExportOptions.plist
~~~

产物在 `dist/android`、`dist/windows`、`dist/ios`、`dist/macos`，红果鉴以 `hongguojian-` 开头，全站源版以 `zhenguojian-` 开头。Windows 同时出便携 zip 和 Inno Setup 安装包（`windows/installer/setup.iss`，简体中文语言文件取自 Inno Setup 官方仓库），安装包以包名为 AppId，两个版本可同时安装，默认装到 `%LOCALAPPDATA%\Programs\<包名>`，安装时可提权改为所有用户，卸载窗口先显示「卸载选项」页（插在卸载进度窗口里），勾选「同时清除本地数据」才删除 `%APPDATA%\<包名>`（含默认下载目录），默认保留；静默卸载不删。macOS 出 arm64 + x86_64 通用 dmg；dmg 的安装窗口（背景图、图标位置、隐藏工具栏）由 `dmgbuild` 写入 `.DS_Store`，打包机需要 `pip install dmgbuild Pillow`，没装时会退回普通镜像并提示。默认 ad-hoc 签名，从网络下载的 dmg 在其他 Mac 上首次打开会被 Gatekeeper 拦一次（右键「打开」，或执行 `xattr -dr com.apple.quarantine /Applications/红果鉴.app`）。有 Developer ID 时用 `package_release.py --platform macos --identity "Developer ID Application: ..."` 重新打包并公证，才能免掉这一步。本机 Android 签名：红果鉴用 `android/key.properties`，全站源版用 `android/key-all-sources.properties`（均不入库）。

其他脚本：`generate_brand_assets.py` 从 `brand_icon.svg` 生成各平台图标；`clear_app_data.py`、`clear_catalog_cache.py` 清理 Windows 上的应用数据和剧库缓存。

## 鸿蒙（HarmonyOS）

鸿蒙版以 `ohos/` 的 ArkTS 工程作宿主，Flutter 走 OHOS 版 Flutter SDK 的 embedding（`@ohos/flutter_ohos`）。`ohos/entry/src/main/module.json5` 同时声明 `phone`、`tablet`、`2in1`，平板由 `lib/ui/app_scope.dart` 的 `shortestSide >= 600` 判成 `FormFactor.pad`，复用平板分栏布局，不需要单独的平板界面代码。

~~~sh
python3 scripts/build_ohos.py --abi arm64-v8a               # 真机（手机 / 平板）
python3 scripts/build_ohos.py --abi arm64-v8a --install     # 打完自动 hdc install
python3 scripts/build_ohos.py --abi x86_64 --install        # 模拟器，只能验界面
python3 scripts/build_ohos.py --abi arm64-v8a --no-native   # 只重打 HAP，不重编 Go 核心

python3 scripts/build_ohos.py --abi arm64-v8a --all-sources # 全站源版（真果鉴）
python3 scripts/build_ohos.py --abi arm64-v8a --all-sources --sources ~/sources/xxx  # 追加源
~~~

**站源必须显式接入，否则脚本直接拒绝出包。** 站源是编进核心库的 Go 模块，链接关系只写在构建脚本生成的 `native/go.work` 里（不入库）。不带 `--sources` 时 `app_build.link_sources` 会沿用上一次的 `go.work`，而它往往还指着 `native/sources_example`——示例站源只有假数据、不能播放，但构建全程不会报错，包也装得上，只是打开后站源列表里只有一个「示例」。`build_ohos.py` 因此在编译前和签名前各查一次链接结果，只有示例站源时直接失败；纯界面预览包加 `--allow-example` 放行。站源路径也可以写成环境变量 `GUOAPP_SOURCES`（多个用 `os.pathsep` 分隔），本地反复出包时省得每次敲 `--sources`。

不加参数打出来的是红果鉴，`--all-sources` 打的是真果鉴，这条命令把三处开关一起翻：Go 核心加 `-tags=zhenguojian`，Flutter 加 `--dart-define=APP_FLAVOR=zhenguojian`，`ohos/AppScope/app.json5` 的 `bundleName` 连同各处应用名（`AppScope` 与 `entry` 的 `base`、`zh_CN`，可选 `en_US`）改成 `com.guoapp.all` / 真果鉴。包名不同，两个版本可以同时装在一台机器上，互不覆盖数据。只改 `base` 不改 `zh_CN` 会出现「包名换了、桌面图标还是红果鉴」，所以按目录扫所有语言。改的是源文件，脚本在 `finally` 里还原，构建失败也不会留下改动。要覆盖包名 / 名字就用 `ZHENGUOJIAN_PACKAGE_NAME`、`ZHENGUOJIAN_DISPLAY_NAME`、`ZHENGUOJIAN_LATIN_NAME`（拉丁名只管英文资源）。

产物是 `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`，`scripts/sign_hap.py` 做本地自签名，输出 `.ohos-sign/<变体>-signed.hap`，最后复制一份到 `dist/ohos/<变体>-<abi>.hap` 备着。未配置调试签名时 `flutter build hap` 会以非零码退出，但 HAP 实际已经打好了，脚本按产物时间判断后继续签名；签名前还会开包核对 `libs/<abi>/libduanju_core.so` 在不在，避免打出只有 `libflutter.so` 的空壳包。`libs/<abi>/.flavor` 记录当前核心是哪个变体编的，`--no-native` 遇到变体不符会照旧重编，不会把上一个变体的核心混进新包。清 hvigor/ArkTS 缓存是 `--clean`，实现上是把目录挪到 `.tmp/ohos-cache-*` 而不是删——批量删除会撞上环境的 safe-delete 拦截直接让进程退出。

签名材料分两种模式，由 `OHOS_DEVICE_UDID` 决定：设了 UDID 用 `UnsgnedDebugProfileTemplate.json`（`development-certificate`，只能装到该 UDID 的设备，适合联调）；没设用 `UnsgnedReleasedProfileTemplate.json`（`distribution-certificate`，不绑设备，适合分发）。两个模板的证书字段名不一样，拿 debug 模板删掉 `debug-info` 冒充 release 会被 `11015001 Require cert in bundleInfo!` 拒掉。

**Go 核心有两种来源，默认从源码编。** 站源是编进核心库的 Go 模块，而真实站源所在的仓库是私有的（上游 CI 用 `SOURCES_DEPLOY_KEY` 拉取），从公开渠道拿不到源码。所以 `--release-core` 走另一条路：直接复用上游发布 APK 里已经编好的 `libduanju_core.so`，中间用一层 bionic→musl 兼容层抹平差异。

~~~sh
python3 scripts/build_ohos.py --abi arm64-v8a --all-sources --release-core
python3 scripts/build_ohos.py --abi x86_64 --all-sources --release-core --mode debug
~~~

发布目录默认 `source-releases/`（内含 `zhenguojian-<版本>-<abi>.apk`），也可以传别的路径。这条路径只适用于 `--all-sources`——上游发布包本身就是全站源版；站源已在 `.so` 里，所以脚本跳过 `check_sources` 检查。

**复用发布核心要过四关，缺一不可**（`scripts/build_ohos.py` 与 `ohos/entry/src/main/cpp/bionic_shim.c` 各承担一部分）：

1. **补依赖名**。核心库的 `DT_NEEDED` 写着 `liblog.so` / `libdl.so`，鸿蒙两个都没有（logcat 不存在，`dlopen` 直接在 libc 里）。`build_shims()` 按这两个名字各编一个 `.so` 放进 `libs/<abi>/`，其中 `liblog.so` 就是兼容层本体。
2. **改名抢符号**。musl 解析符号时先走全局作用域（主程序 + libc），再走被加载对象的依赖链，所以兼容层里导出 `sigaction` 一定会被 libc 的版本压过去。`rename_imports()` 反过来改核心库：把 `.dynstr` 里那一个 `sigaction` 字符串原地改成 `sig_ohos`（长度一致），全局作用域里没人叫这个名字，才会落到兼容层。这个改名不是可选优化——bionic 的 `struct sigaction` 是 32 字节、musl 的 152 字节，让 musl 直接处理那块内存会在写旧动作时冲掉调用者的栈帧，`dlopen` 阶段就 `SIGSEGV @0`。
3. **短路 `inittls`**。Go 的 `runtime/cgo/gcc_android.c` 里 `inittls()` 固定去拿 bionic 的 `TLS_SLOT_APP`（= `2*sizeof(void*)` = 16），拿不到 `android_get_device_api_level` 就走兜底分支，而兜底要扫 `*(void**)(%fs-16)`——musl 这一格是 0，扫描循环用 `r14=0` 当场 `SIGSEGV`。`patch_core_tls()` 通过 `dynsym` 里的 `x_cgo_inittls` 找到它（**注意 `.data` 里那个指针是 `R_*_RELATIVE` 重定位目标，文件里值是 0，真正的入口在 `r_addend` 里**），把入口改成 `ret`（arm64 是 `bti c; ret`）。
4. **改 `runtime.tls_g` 槽位**。`inittls` 短路后，`tls_g` 还是静态初值 16，而 16 是 bionic 的预留槽，musl 里 `%fs:16` 恰好是 `struct pthread` 的 `prev`/`next` 自指链表指针，非 0。`tls_g` 没导出，但读它的指令形态唯一（x86_64：`movq %fs:xx,%r64` 往回找 `movq tls_g(%rip)`；arm64：`MRS X0, TPIDR_EL0` + `ADRP X27` + `LDR X27,[X27,#imm]`），按 PC 相对目标反查并要求目标处当前 8 字节 == 16 来排除误匹配。改成的值见 `TLS_G_SLOTS`：

   | ABI | 偏移 | 依据 |
   | --- | --- | --- |
   | x86_64 | `+216` | 模拟器实测。`struct pthread` 的 `+208` 是 `signal_stack`，`+216` 是 `gwp_asan_tls`（头文件注释写明「musl 不支持 libc 用 tls，这里给 gwp_asan 预留了槽」）；未开插桩时恒 0，灌魔数跑完建线程/分配/stdio/socket/key 一整套压力后不被改写。 |
   | arm64-v8a | `-136` | 按头文件字段序推导。arm64 的结构体在 TP 下方，`hwasan_tls` 按编译器契约定在 `tp-144`，紧跟其后的 `tls_slots[0]` 就是 `tp-136`；`tls_slots[0..4]` 与 `[10..14]` 是给内核 ABI 增长预留的空位。**没有真机验证过。** |

   补丁是幂等的：入口已经是 `ret` 桩时只校验 `tls_g` 是否等于预期槽位，不重复改。

   arm64 那一格尚无真机可验，需要换槽位时用环境变量覆盖，不用改脚本：

   ```bash
   GUO_OHOS_TLS_SLOT_ARM64=-120 python3 scripts/build_ohos.py \
       --all-sources --release-core --abi arm64-v8a --install
   ```

   支持 `0x` 前缀。装到设备后用 `hdc shell hilog -T guoapp` 看启动那行日志，`slot=` 恒为 `0x0` 且反复进出页面不崩才算选对。

   出包后可以离线复核补丁有没有真的打进去（架构、`inittls` 桩、`tls_g` 值、兼容层导出）：

   ```bash
   python3 scripts/check_hap_patch.py dist/ohos/*.hap
   ```

**还有一处必须由调用方配合**：Go 的 `cgocallback` 用「TLS 里的 g 是否为 0」判断这个线程是不是第一次进 Go，而 `dropm`（负责把 g 清回 0）只在两个时机跑——C 线程主动调 `cgocallback(nil, ...)`，或 Go 注册的 pthread key 析构器。Flutter 的 `DartWorker` 是 pthread 建完、函数返回就退出的普通线程，两者都不会触发，于是它 `pthread` 结构体里的 g 槽带着旧值被 musl 回收；下一个 `DartWorker` 复用同一块内存，一进 `cgocallback` 就读到残留 g，跳过 `needm` 直接取 `m.curg`——那个 m 早已还回空闲池、`curg` 为 0，于是在 `56(%rsi)` 处 `SIGSEGV @0x38`（实测崩溃点固定在 `libduanju_core.so+0x31316d`，崩在 `DartWorker` 线程）。所以 `lib/core_bridge.dart` 在每次发起请求前调兼容层的 `guoapp_tls_enter()` 把槽清零、返回后 `guoapp_tls_leave()`，让每个线程都走 `needm` 这条正规路径。用 thread-local 深度计数兜住嵌套，避免内层把外层的 g 清掉。**这一步不能省**，否则界面用起来必崩——只是崩溃时机取决于线程复用，看起来像随机闪退。

兼容层还导出了 `guoapp_tls_state()`，把线程指针、加载时槽值、当前槽值、冲突标记写进 hilog，arm64 没有真机时靠这条日志确认偏移没撞上别人的字段（正常输出形如 `tls tp=0x... off=-136 slot=0x0`）。

**从源码编时的工具链要求**：必须用 `OpenHarmony-SIG/ohos_golang_go`（`release-branch.go1.24`）。鸿蒙的 libc 是 musl，主线 Go 在 arm64 上用 initial-exec 模型读 `runtime.tls_g`，产出 `R_AARCH64_TLS_TPREL64` 和 `STATIC_TLS` 标记，`dlopen` 时直接报 `initial-exec TLS resolves to dynamic definition`（golang/go#54805，`-tls=GD` 的 PR 还没合）。该 fork 增加 `GOOS=openharmony`，把 arm64 的 TLS 访问降到 General Dynamic / TLSDESC，musl 才肯加载。`build_native.py --platform ohos` 会自动切到 fork，没装时提示路径。fork 只实现 `openharmony/arm64`，所以 x86_64 只能用主线 Go 编 `linux/amd64`：模拟器里界面能跑，但 `libduanju_core.so` 会在 `dlopen` 阶段被 musl 拒掉，只适合验 UI。**要真跑核心就用 `--release-core`**，它绕开了这条限制。

`duanju/device` 通道在鸿蒙上由 `ohos/entry/src/main/ets/entryability/DeviceChannel.ets` 实现，在 `EntryAbility.configureFlutterEngine` 里注册，包含亮度、音量、横竖屏、电量、视频导出、文件保存与选择。平台差异：

- 没有 FFmpeg：`lib/media_pipeline.dart` 直接抛「暂不支持本地转码」，保留原始分片；合并视频改成先写临时文件再用系统保存界面导出。
- `flutter_foreground_task`、`window_manager`、`file_picker`、`dynamic_color` 都没有鸿蒙实现：后台下载和前台服务在鸿蒙上不启用，窗口相关调用靠 try/catch 降级，`file_picker` 的保存 / 选择统一走 `lib/platform_files.dart` → `duanju/device` 通道（ArkTS 侧用 `DocumentViewPicker`）。
- 下载目录迁移只在应用自己的目录里选（沙箱外不申请受限权限写不进去），和 Android 的做法一致。

## 检查与测试

~~~sh
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos lib test
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=APP_FLAVOR=zhenguojian
cd native
go test -race ./...
go test -race -tags=zhenguojian ./...
~~~

Flutter 测试一律带 `DISABLE_REMOTE_IMAGES=true`，避免加载站源图片。测试只覆盖数据兼容、权限和逻辑层，界面改动不写测试；公共假仓库在 `test/support/`。

## 架构

Flutter 界面 + Go 原生核心。站源请求、解析、签名、缓存、下载调度和播放代理都在 Go 里完成，Dart 只负责界面、播放器和本地用户数据。

- **FFI**：`native/bridge` 以 `-buildmode=c-shared` 只导出 `DuanjuRequest(json) -> json` 与 `DuanjuFree`。`lib/core_bridge.dart` 的 `NativeRepository` 把每次调用编码成 `{"action": ...}`，在 `Isolate.run` 中调用；Go 侧在 `native/core/app_runtime.go` 的 `NativeRequest` 里按 action 分派。新增能力两端都要改。Android 与 Windows 动态加载（`libduanju_core.so` / `duanju_core.dll`）；iOS 与 macOS 改成 `-buildmode=c-archive` 静态库（`ios/DuanjuCore`、`macos/DuanjuCore`）链进主程序，Dart 侧用 `DynamicLibrary.process()` 查符号，避免 dylib 的签名与库校验问题。
- **Go 核心**：`native/core` 是运行时，站源只经它导出的接口（`Provider`、`Host` 及各可选接口）访问。站源与各版本的站源名单放在站源模块里（官方站源模块是私有站源仓库，示例站源模块是 `native/sources_example`），只单向依赖 core，由构建脚本生成的 `native/bridge/sources_gen.go` 空白导入接入。core 里 `app_*.go` 运行时与业务（目录缓存、下载、弹幕、存储、设置），`network_*.go` HTTP 客户端、DNS、CDN、限流。`app_stream.go` 在本机起播放代理，重写 HLS playlist、透传 Range，并处理带密钥的媒体。
- **Flutter**：界面在 `lib/ui/`（按页面分子目录，入口 `lib/main.dart` → `lib/ui/app.dart`），逻辑层平铺在 `lib/`，状态管理只用 ChangeNotifier。
- **播放与下载**：播放器用 [media_kit](https://github.com/media-kit/media-kit) / libmpv；每集下载完由 [FFmpegKit min-gpl](https://github.com/sk3llo/ffmpeg_kit_flutter)（含 GPL 媒体组件）转成单个 mp4，只换封装、不重新编码，不参与正常播放。
- **本地数据**：存储格式须兼容旧版。本地快照遇到未知键会整体报错，新增设置若要兼容旧版须存为快照外的独立键。

## 目录结构

| 目录 | 内容 |
| --- | --- |
| `lib/ui` | 界面：主题、导航壳、各页面、播放器、公共组件 |
| `lib` | 逻辑层：FFI、站源目录、播放、下载、本地存储与用户 |
| `native/core`、`native/bridge` | Go 运行时（缓存、下载、播放代理）及 C ABI |
| `native/sources_example` | 示例站源模块（假数据，不访问网络） |
| `android`、`windows`、`ios`、`macos` | 平台工程与资源 |
| `packages/media_kit_libs_windows_video` | 本地覆盖的 Windows 媒体依赖插件 |
| `scripts` | 构建、图标生成与数据清理脚本 |
| `test` | 逻辑层测试 |

## 站源开发约定

站源是站源模块里的 Go 原生 provider，不是运行期加载的脚本。新增站源实现 `core.Provider`（按需实现可选接口），在 `init` 里用 `core.Register` 登记描述符和工厂，并加进所在模块 `flavor_*.go` 的版本名单；运行时与界面代码都不用改，界面的站源列表由核心在初始化时下发。

### 站源模块

- 站源模块是任意路径的 Go 模块，经构建脚本生成的 `go.work` 解析 `duanjuapp/native/core`，`go.mod` 不需要 `require` 它。构建脚本只空白导入模块根包，所有注册都要在根包的 `init` 里完成。新模块从复制 `native/sources_example` 开始，改掉 `go.mod` 的模块名和站源 ID。
- 按编译标签调用 `core.RegisterFlavor`：默认（`!zhenguojian`）注册 `hongguojian`，`zhenguojian` 标签下注册 `zhenguojian`，列出本模块要在该版本启用的站源 ID。没列进当前版本名单的站源在该版本不可用。多个模块注册的同名版本会合并站源名单。
- 版本名不一致或站源 ID 重复时原生库加载即 panic，不提供覆盖规则：编译期拼装的站源本来就该在出包时暴露冲突。别名不查重，撞上时后注册的生效，起别名时自己避开。
- 模块要声明它所适配的站源接口版本：`var _ core.SourceAPI1`。

### 接口版本

站源接口指 `native/core` 的全部导出标识符，包括下面列出的类型和站源常用的工具函数（`core.Truncate`、`core.FirstNonEmpty` 等）。core 对这些标识符做不兼容改动（删除、改名、改签名、改语义）时，把 `native/core/source_api.go` 的 `SourceAPI1` 改名为下一个版本号，并在 `CHANGELOG.md` 写明迁移办法。没跟上的模块会以 `undefined: core.SourceAPI1` 编译失败，而不是装到设备上才出错。只新增导出标识符、新增可选接口或给描述符加字段不升版本。

### 标识

- 站源 ID 用小写字母、数字和 `-`，不能含 `:`；`Aliases` 里的域名或旧 ID 也会解析到本站源。
- 剧的 ID 用 `core.ProviderDramaID(站源 ID, 站内 ID)`，分集 ID 用 `core.ProviderChapterID(站源 ID, 站内 ID, 分集键)`。这些 ID 会写进用户的追剧、记录和下载，发布后不能改格式。
- 分类 ID 由站源自定，空字符串表示「全部」；`ValidCategory` 必须放行站源自己返回的所有分类 ID，否则界面切换分类时会被拒绝。

### `SourceDescriptor`

| 字段 | 作用 |
| --- | --- |
| `ID`、`Name`、`Description` | 站源 ID、显示名、站源列表里的说明 |
| `Group`、`GroupName`、`EntryName` | 同组站源在界面里合并成一个入口时的分组 ID、分组名和组内名称 |
| `DefaultOff` | 新用户默认不启用 |
| `SkipVIPPrompt` | 不对 VIP 剧弹提示 |
| `Aliases`、`HostSuffixes`、`MatchesHost` | 把别名、域名后缀或任意判断函数匹配到的主机归到本站源，用于按地址识别站源 |
| `BaseURL` | 站点默认地址，`Host.BaseURL` 和域名轮换以它为准 |
| `NoHostRotation` | 请求失败时不在多个站点地址间轮换 |
| `AllowEmptyCatalog` | 目录第一页为空时不报错 |
| `ContinuousFeed` | 目录是不分页的信息流：运行时经 `ctx` 传入已知剧集（`core.LibraryKnownKey`）和是否加载更多（`core.LibraryMoreKey`），缓存合并也按信息流处理 |
| `KeepDetailEpisodes` | 详情的分集少于剧集信息里的总集数时，保留较大的总集数 |
| `BrowserFingerprint` | 本站源域名的请求改用浏览器 TLS 指纹 |
| `ValidCategory` | 校验分类 ID，见上 |
| `Rankings` | 榜单列表，配合 `Ranker` 使用 |

### `Provider` 与可选接口

`Provider` 必须实现：`Descriptor`、`Categories`（分类列表）、`CatalogPage`（按页取目录，返回本页剧集和是否还有下一页）、`Detail`（按站内 ID 取剧集信息和分集）、`ResolveMedia`（把分集解析成可播放的媒体）。

需要哪种能力就实现哪个接口，运行时用类型断言检测，界面上的对应入口随之出现：

| 接口 | 能力 |
| --- | --- |
| `Searcher`、`WarningSearcher` | 搜索；后者可以在有结果的同时附带一条提示 |
| `Suggester` | 搜索联想 |
| `Recommender` | 推荐流 |
| `Ranker` | 榜单分页 |
| `DanmakuProvider` | 弹幕 |
| `DeviceProvider`、`AccountProvider` | 站源设备注册、站源账号操作 |
| `CatalogStateful` | 目录翻页状态随剧库缓存一起保存和恢复 |
| `Sited`、`URLRotator` | 运行时决定的站点地址；同一地址的候选镜像 |
| `CoverResolver`、`CoverRepairer`、`CoverRefererProvider` | 按需解析封面地址；修复旧数据的封面；封面请求的 Referer |
| `MetadataEnricher` | 详情之外再补齐剧集元数据 |
| `SeasonProvider` | 同一部剧的各季，按季序返回；详情页显示季标签，本季播完自动接下一季 |
| `MediaAuthorizer` | 播放请求需要临时授权头时由站源签发，失效时被告知 |

返回 `core.SourceLoginError` 表示要先登录站源账号；`Categories` 同时返回已取到的分类和 `core.ErrCategoriesIncomplete` 表示分类不完整，本次照常显示但不写入缓存，下次重新获取。

### `Host`

工厂函数收到的 `core.Host` 是站源访问运行时的唯一入口。所有网络请求都走 `Fetch`、`FetchText`、`FetchPlaylist`，不要自建 `http.Client`，代理、限流、重试、DNS 和诊断日志都由运行时统一处理。

| 方法 | 作用 |
| --- | --- |
| `Fetch`、`FetchText` | 通用 HTTP 请求；取文本页面 |
| `FetchPlaylist` | 取 HLS 播放列表，可带媒体凭证 |
| `Reserve` | 先占用限流名额再请求，返回的票据填进 `HTTPRequest.Ticket` |
| `Retries`、`MaxPages` | 用户设置的重试次数、每个分类最多翻页数 |
| `BaseURL`、`PreferredSite`、`RememberSite` | 站点地址；上次可用的站点；记住可用站点 |
| `LoadState`、`SaveState` | 读写站源自己的状态文件。各站源共用一个目录，文件名只能是单个文件名，请带上站源 ID 前缀 |
| `PrepareWebMedia`、`FinishMedia` | 把网页或播放列表里取到的媒体整理成播放器可用的形式 |

## 发布

工作流 `.github/workflows/build.yml` 只能在 `main` 上手动触发，推送和 PR 不会自动运行。

1. 同时提升 `pubspec.yaml` 的版本号与构建号。
2. 在 `CHANGELOG.md` 新增同名一节（标题如 `## 1.0.1+101`），工作流会把它写入 Release 说明；未验证的改动标为开发快照。
3. 推送到 `main`，在 Actions 中手动运行 **Build app packages**。

工作流先检查版本：tag `app-v{version}`（`+` 替换为 `-`）或同名 Release 已存在时直接失败。随后四个平台各构建红果鉴、全站源版两版：

| 产物 | 内容 |
| --- | --- |
| `*-android` | 三种架构 APK，使用发布证书签名并通过指纹校验 |
| `*-windows` | Windows x64 安装包和便携 ZIP |
| `*-ios-unsigned` | arm64 iPhone 未签名 IPA |
| `*-macos` | arm64 + x86_64 通用 dmg，ad-hoc 签名、未公证 |

各平台出包任务用仓库 Secret `SOURCES_DEPLOY_KEY`（站源仓库只读 deploy key 的私钥）把站源仓库检出到 `guoapp-sources/`，再以 `--sources guoapp-sources` 构建，示例站源不会进入发布包。检查任务会对示例站源单独做编译检查。

格式、分析、测试不阻塞出包；Android、Windows、iOS、macOS 全部成功后才创建 tag 和 Release，任一平台失败就不发布，已有 Release 不会被覆盖。

Android 签名只用仓库 Secrets，两个版本各用一套：红果鉴为 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`，另需仓库变量 `ANDROID_CERT_SHA256`；全站源版把前缀 `ANDROID_` 换成 `ZHENGUOJIAN_`，证书变量为 `ZHENGUOJIAN_CERT_SHA256`（证书 SHA-256，冒号和大小写不限）。工作流按矩阵的 `signing` 前缀选取，缺任意一项都会失败。CI 通过环境变量把签名传给 Gradle；本机红果鉴读 `android/key.properties`，全站源版读 `android/key-all-sources.properties`（均不入库）。

全站源版的包名和显示名取环境变量（CI 取同名仓库变量），没设或为空时用默认值；红果鉴固定为 `com.guoapp.phoenix`、`红果鉴`、`HongGuoJian`：

| 变量 | 默认值 | 读取位置 |
| --- | --- | --- |
| `ZHENGUOJIAN_PACKAGE_NAME` | `com.guoapp.all` | Android `build.gradle.kts`、Windows `app_branding.cmake`、iOS / macOS `scripts/app_build.py` |
| `ZHENGUOJIAN_DISPLAY_NAME` | `真果鉴` | 由 `scripts/app_build.py` 作为 `--dart-define` 传入，Dart `appName`、Android `build.gradle.kts`、iOS「Thin Binary」构建阶段读取；Windows `app_branding.cmake` 直接读环境变量；macOS 由 `package_release.py` 写入 |
| `ZHENGUOJIAN_LATIN_NAME` | `ZhenGuoJian` | iOS「Thin Binary」构建阶段，作为英文 `CFBundleDisplayName` |

Windows 数据目录为 `%APPDATA%\<包名>`：`Runner.rc` 不设 CompanyName，ProductName 为包名，`path_provider` 据此拼出应用支持目录，两个版本数据互不共用。旧版数据在 `%APPDATA%\真果鉴\真果鉴`，`lib/windows_data_migration.dart` 在启动最早阶段检查：新目录为空且旧目录存在时整个改名移入，先启动的版本拿到旧数据；新目录已有内容或移动失败都不处理，失败写入日志。Android TV 横幅 `tv_banner_all_sources.png` 只有图标不带文字，改名不用重新生成。

关于页的重建版 GitHub、Telegram 交流群组和更新频道链接分别取环境变量 `PROJECT_URL`、`TELEGRAM_GROUP_URL`、`TELEGRAM_CHANNEL_URL`（CI 取同名仓库变量），由 `scripts/app_build.py` 作为 `--dart-define` 传给 Flutter；没设的链接在关于页不显示，直接 `flutter run` 时需自行加 `--dart-define`。`PROJECT_URL` 同时注入 Go 的 `nativeProjectURL`，检查更新只接受 `{PROJECT_URL}/releases/` 开头的发布页，没设时不提示更新。

## 检查更新与使用统计

接收端是 Cloudflare Worker `guoapp-update`（`worker/`，D1 数据库 `guoapp-stats`），地址在编译期由环境变量 `UPDATE_SERVER_URL` 经 `scripts/app_build.py` 注入 Go（CI 取仓库变量 `UPDATE_SERVER_URL`），没设时检查更新和使用统计都不发请求，fork 和本地构建默认不会连到这里。变量可填逗号分隔的多个地址，Go 按顺序尝试，前一个连不上或返回错误时换下一个；CI 里先填国内可直连的中转服务器，再填 Worker。Go 核心（`native/core/app_update.go`）的 `checkUpdate` 请求 `GET /v1/latest`，只读不写；`reportUsage` 请求 `POST /v1/ping`，按北京时间日期和随机编号在 `pings` 表里每天记一行。两者分别由设置里的「启动时检查更新」和「匿名使用统计」控制。各平台点「更新」都只打开发布页，应用内不下载安装包。Worker 每小时从 GitHub 读取最新 Release 写入 `meta` 表。改 Worker 后在 `worker/` 下运行 `npx wrangler deploy`。

在 `worker/` 下查询（`--remote` 查线上库）：

~~~sh
npx wrangler d1 execute guoapp-stats --remote --command "SELECT day, COUNT(*) AS users FROM pings GROUP BY day ORDER BY day DESC LIMIT 30"   # 日活
npx wrangler d1 execute guoapp-stats --remote --command "SELECT COUNT(DISTINCT id) FROM pings WHERE day >= date('now', '-30 days')"          # 近 30 天活跃
npx wrangler d1 execute guoapp-stats --remote --command "SELECT COUNT(DISTINCT id) FROM pings"                                               # 累计装机
npx wrangler d1 execute guoapp-stats --remote --command "SELECT platform, build, version, COUNT(*) FROM pings WHERE day = date('now', '+8 hours') GROUP BY 1, 2, 3 ORDER BY 4 DESC"  # 今日分布
~~~

应用显示名：Android 在 `android/app/build.gradle.kts`，Windows 在 `windows/runner/app_branding.cmake`，iOS 由 Xcode「Thin Binary」构建阶段按 `DART_DEFINES` 写入，macOS 由 `scripts/package_release.py` 打包时改 `CFBundleDisplayName` / `CFBundleName` / `CFBundleIdentifier` 后重新签名。iOS 的 `CFBundleDisplayName` 用英文名（红果鉴 `HongGuoJian`，真果鉴取 `ZHENGUOJIAN_LATIN_NAME`）以通过侧载工具的名称校验，中文名写在 `zh-Hans.lproj/InfoPlist.strings`。macOS 关闭了 App Sandbox，以便本地播放代理和自选下载目录正常工作；系统代理由 `MainFlutterWindow.swift` 的 `duanju/device` 通道读取。
