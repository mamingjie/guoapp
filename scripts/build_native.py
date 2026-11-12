import argparse
import os
import platform
import shutil
import subprocess
from pathlib import Path

from app_build import BuildVariant, add_variant_argument, add_sources_argument, link_sources

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--platform', choices=['android', 'windows', 'darwin', 'ohos'], required=True)
parser.add_argument('--abi', action='append', choices=['arm64-v8a', 'armeabi-v7a', 'x86_64'])
add_variant_argument(parser)
add_sources_argument(parser)
options = parser.parse_args()
variant = BuildVariant(options.all_sources)
link_sources(options.sources)

# 鸿蒙必须用 OpenHarmony SIG 的 Go fork（详见文件末尾 ohos 分支的说明）。
# 它在 PATH 最前面插入 fork 的 bin，让下面的 shutil.which('go') 拿到 fork。
if options.platform == 'ohos':
    fork_root = Path(os.environ.get('OHOS_GOROOT') or (root.parent / 'toolchain' / 'ohos-go'))
    fork_bin = fork_root / 'bin'
    if not (fork_bin / ('go.exe' if platform.system() == 'Windows' else 'go')).is_file():
        raise SystemExit(
            '缺少鸿蒙专用 Go 工具链：%s\n'
            '  1) git clone --depth 1 -b release-branch.go1.24 '
            'https://gitcode.com/openharmony-sig/ohos_golang_go.git "%s"\n'
            '  2) 在 "%s/src" 下执行 make.bat（Windows）或 ./make.bash\n'
            '  也可用环境变量 OHOS_GOROOT 指定已有目录。' % (fork_bin, fork_root, fork_root))
    os.environ['PATH'] = str(fork_bin) + os.pathsep + os.environ.get('PATH', '')
    os.environ['GOROOT'] = str(fork_root)

environment = os.environ.copy()
environment.setdefault('GOPROXY', 'https://goproxy.cn,direct')
environment.setdefault('GOSUMDB', 'off')
environment['CGO_ENABLED'] = '1'
go = shutil.which('go')
if not go:
    raise SystemExit('请先安装 Go 1.24.1 或更新版本。')
bootstrap_env = environment.copy()
bootstrap_env['GOSUMDB'] = os.environ.get('GOSUMDB', 'sum.golang.org')
if bootstrap_env['GOSUMDB'] == 'off':
    bootstrap_env['GOSUMDB'] = 'sum.golang.org'
toolchain_root = subprocess.check_output([go, 'env', 'GOROOT'], cwd=root / 'native',
    env=bootstrap_env, text=True).strip()
go = str(Path(toolchain_root) / 'bin' / ('go.exe' if platform.system() == 'Windows' else 'go'))

def build(goos, architecture, compiler, output, extra=None):
    output.parent.mkdir(parents=True, exist_ok=True)
    build_env = environment.copy()
    build_env.update(GOOS=goos, GOARCH=architecture, CC=str(compiler))
    if extra:
        build_env.update(extra)
    print('Building ' + str(output.relative_to(root)), flush=True)
    subprocess.run([go, 'build', '-trimpath', '-buildmode=c-shared',
                    *variant.go_arguments, '-o', str(output), './bridge'],
                   cwd=root / 'native', env=build_env, check=True)

if options.platform == 'android':
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise SystemExit('请设置 ANDROID_HOME 为 Android SDK 目录。')
    ndk = Path(os.environ.get('ANDROID_NDK_HOME', Path(sdk) / 'ndk' / '28.2.13676358'))
    host = {'Darwin': 'darwin-x86_64', 'Linux': 'linux-x86_64', 'Windows': 'windows-x86_64'}[platform.system()]
    compilers = ndk / 'toolchains' / 'llvm' / 'prebuilt' / host / 'bin'
    mappings = {
        'arm64-v8a': ('arm64', 'aarch64-linux-android24-clang'),
        'armeabi-v7a': ('arm', 'armv7a-linux-androideabi24-clang'),
        'x86_64': ('amd64', 'x86_64-linux-android24-clang'),
    }
    for abi in options.abi or list(mappings):
        architecture, name = mappings[abi]
        compiler = compilers / (name + ('.cmd' if platform.system() == 'Windows' else ''))
        if not compiler.exists():
            raise SystemExit('缺少 Android NDK 编译器：' + str(compiler))
        output = root / 'android' / 'app' / 'src' / 'main' / 'jniLibs' / abi / 'libduanju_core.so'
        extra = {'CGO_LDFLAGS': '-Wl,-z,max-page-size=16384'}
        if architecture == 'arm':
            extra['GOARM'] = '7'
        build('android', architecture, compiler, output, extra)
elif options.platform == 'ohos':
    # HarmonyOS：必须用 OpenHarmony SIG 的 Go fork（GOOS=openharmony），不能用主线 Go。
    #
    # 原因：Go 的 c-shared 在 arm64 上用 initial-exec 模型访问 runtime.tls_g（存 g 指针），
    # 产物 .dynamic 带 STATIC_TLS、重定位是 R_AARCH64_TLS_TPREL64。鸿蒙 libc 是 musl，
    # 它不给 dlopen 进来的库分配静态 TLS，于是 dlopen 直接失败：
    #   Error relocating libduanju_core.so: initial-exec TLS resolves to dynamic definition
    # （上游 golang/go#54805，鸿蒙同款现象广泛见于 sing-box 等）
    # fork 加了 openharmony 目标，并把 arm64 的 TLS 访问降到 GD 模型（TLSDESC），
    # musl 对 dlopen 库里的 TLSDESC 完全支持。
    # 副作用：该 fork 只实现了 openharmony/arm64，x86_64 无法用这条路线。
    sdk_home = os.environ.get('HOS_SDK_HOME') or os.environ.get('DEVECO_SDK_HOME')
    if not sdk_home:
        raise SystemExit('请设置 HOS_SDK_HOME 为 DevEco Studio 的 sdk 目录。')
    ndk = Path(os.environ.get('OHOS_NDK_HOME', Path(sdk_home) / 'default' / 'openharmony' / 'native'))
    clang = ndk / 'llvm' / 'bin' / ('clang.exe' if platform.system() == 'Windows' else 'clang')
    sysroot = ndk / 'sysroot'
    if not clang.exists():
        raise SystemExit('缺少鸿蒙 NDK 编译器：' + str(clang))
    mappings = {
        'arm64-v8a': ('arm64', 'aarch64-linux-ohos'),
        'x86_64': ('amd64', 'x86_64-linux-ohos'),
    }
    for abi in options.abi or ['arm64-v8a']:
        if abi not in mappings:
            raise SystemExit('鸿蒙只支持 arm64-v8a 与 x86_64（模拟器）：' + abi)
        architecture, triple = mappings[abi]
        wrapper = root / 'native' / 'build' / 'ohos' / ('cc-%s.cmd' % abi)
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        # NDK 自带的 aarch64-unknown-linux-ohos-clang 是 sh 脚本，路径含空格时
        # 在 Windows 上跑不起来，这里生成一个带引号的包装脚本。
        if platform.system() == 'Windows':
            wrapper.write_text(
                '@echo off\r\n"%s" --target=%s --sysroot="%s" %%*\r\n'
                % (clang, triple, sysroot), encoding='utf-8')
            compiler = wrapper
        else:
            compiler = clang
        output = root / 'ohos' / 'entry' / 'libs' / abi / 'libduanju_core.so'
        # --target 与 --sysroot 已经写进包装脚本，这里不能再带（路径含空格会被拆开）。
        if abi == 'arm64-v8a':
            build('openharmony', architecture, compiler, output, {
                'CGO_LDFLAGS': '-fuse-ld=lld',
            })
        else:
            # x86_64 只用于模拟器调试：fork 没有 openharmony/amd64，只能用主线 Go 的
            # linux/amd64 产物，dlopen 时会被 musl 拒绝（UI 起得来，本地核心加载不了）。
            print('警告：x86_64 产物用主线 Go 构建，仅可用于模拟器上调试界面，'
                  '本地核心（libduanju_core.so）会在 dlopen 阶段被 musl 拒绝。', flush=True)
            build('linux', architecture, compiler, output, {
                'CGO_LDFLAGS': '-fuse-ld=lld',
            })
elif options.platform == 'windows':
    compiler = shutil.which('x86_64-w64-mingw32-gcc') or (shutil.which('gcc') if platform.system() == 'Windows' else None)
    if not compiler:
        raise SystemExit('请安装 MinGW-w64，并将其 bin 目录加入 PATH。')
    build('windows', 'amd64', compiler, root / 'windows' / 'runner' / 'duanju_core.dll',
          {'CGO_LDFLAGS': '-static-libgcc'})
else:
    if platform.system() != 'Darwin':
        raise SystemExit('macOS 核心需要在 macOS 上构建。')
    compiler = shutil.which('clang')
    if not compiler:
        raise SystemExit('需要安装 Xcode Command Line Tools。')
    output = root / 'macos' / 'DuanjuCore' / 'libDuanjuCore.a'
    slices = []
    for architecture, triple in [('arm64', 'arm64-apple-macos12.0'), ('amd64', 'x86_64-apple-macos12.0')]:
        library = root / 'native' / 'build' / 'macos' / architecture / 'libDuanjuCore.a'
        library.parent.mkdir(parents=True, exist_ok=True)
        print('Building ' + str(library.relative_to(root)), flush=True)
        build_env = environment | {'GOOS': 'darwin', 'GOARCH': architecture, 'CC': str(compiler),
                                   'CGO_CFLAGS': '-target ' + triple, 'CGO_LDFLAGS': '-target ' + triple}
        subprocess.run([go, 'build', '-trimpath', '-buildmode=c-archive',
                        *variant.go_arguments, '-o', str(library), './bridge'],
                       cwd=root / 'native', env=build_env, check=True)
        slices.append(str(library))
    subprocess.run(['lipo', '-create', *slices, '-output', str(output)], check=True)
