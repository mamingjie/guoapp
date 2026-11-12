# guoapp 项目长期约定

## 语言与平台

- 用户称呼「工头」；对话用简体中文。
- 前端 Flutter，原生核心 Go（`native/`，cgo 导出 `DuanjuRequest`/`DuanjuFree`），平台：Android、Windows、macOS、HarmonyOS。

## 两个变体（不要把开关拆开用）

`scripts/app_build.py` 的 `BuildVariant` 是唯一权威。切换变体必须三处同时翻，否则应用启动时版本校验会失败：

1. Go：`-tags=hongguojian` / `-tags=zhenguojian`
2. Flutter：`--dart-define=APP_FLAVOR=hongguojian` / `zhenguojian`
3. 包名 + 应用名：红果鉴 / 真果鉴

各平台直接传 `variant.go_arguments`、`variant.flutter_arguments`，不要手写。

## 构建脚本约定

- **不要 `shutil.rmtree`**。环境的 safe-delete 守卫会拦批量删除，抛的不是 `Exception`，`except Exception` 兜不住，进程会直接退出（表现为「构建刚开始就没了」）。清理一律 `shutil.move` 到 `.tmp/`。
- 构建产物/缓存掉进 `.tmp/` 前先想清楚谁清；不要用脚本删用户的文件。
- 打包脚本要自检产物：核心库在不在、变体对不对、包名对不对。hvigor 会安静地打出只有 `libflutter.so` 的空壳包。

## 鸿蒙（HarmonyOS）

- Go 核心只能用 `OpenHarmony-SIG/ohos_golang_go`（`release-branch.go1.24`，`GOOS=openharmony`），主线 Go 的 arm64 initial-exec TLS 过不了 musl 的 `dlopen`。x86_64 没有对应 fork，只能验 UI。
- 不要手动跑 `ohpm install --all`：依赖是 `flutter build hap` 每次注入再移除的，手动跑会把自己当成孤儿目录清掉。
- 不要手工拼 POSIX 路径的 PATH 去调 `ohpm.bat`，`:calculateFirstParamLen` 会按字符递归，直接爆 CMD 栈。
- 签名：设了 `OHOS_DEVICE_UDID` 走 debug 型 profile（绑设备），没设走 release 型（不绑设备），两种模板的证书字段不同。

## 测试

```sh
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos lib test
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=APP_FLAVOR=zhenguojian
```
