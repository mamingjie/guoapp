"""检查 HAP 里的核心库与兼容层是否都带上了补丁。

`build_ohos.verify_hap()` 只确认 so 有没有被塞进包里（hvigor 在 libs 为空时
也会安静地打出缺 so 的包）；这里补上内容层面的校验：

  - ELF 架构与目标 ABI 一致
  - `x_cgo_inittls` 已是 ret 桩（第三关）
  - `runtime.tls_g` 是本架构的预期槽位（第四关）
  - 兼容层导出了 guoapp_tls_enter / leave / state（第五关的入口）

用法：

    python3 scripts/check_hap_patch.py dist/ohos/*.hap
"""

import os
import struct
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'scripts'))
import build_ohos

# inittls 入口的短路桩：x86_64 一条 ret；arm64 是 bti c; ret
STUBS = {
    'x86_64': b'\xc3',
    'arm64-v8a': b'\x5f\x24\x03\xd5\xc0\x03\x5f\xd6',
}
MACHINE = {'x86_64': 62, 'arm64-v8a': 183}
SHIM_EXPORTS = ('guoapp_tls_enter', 'guoapp_tls_leave', 'guoapp_tls_state')


def _u16(data, offset):
    return struct.unpack_from('<H', data, offset)[0]


def _u32(data, offset):
    return struct.unpack_from('<I', data, offset)[0]


def _u64(data, offset):
    return struct.unpack_from('<Q', data, offset)[0]


def _sections(data):
    shoff = _u64(data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x3A)
    out = []
    for index in range(shnum):
        base = shoff + index * shentsize
        out.append(dict(name_off=_u32(data, base), type=_u32(data, base + 4),
                        off=_u64(data, base + 24), size=_u64(data, base + 32),
                        link=_u32(data, base + 40)))
    names = out[shstrndx]['off']
    for section in out:
        end = data.index(b'\0', names + section['name_off'])
        section['name'] = data[names + section['name_off']:end].decode()
    return out


def _dynsym_names(data, sections):
    dynsym = next(s for s in sections if s['type'] == 11)
    strtab = sections[dynsym['link']]['off']
    names = set()
    for index in range(dynsym['size'] // 24):
        offset = _u32(data, dynsym['off'] + index * 24)
        if offset:
            names.add(data[strtab + offset:data.index(b'\0', strtab + offset)].decode())
    return names


def check(hap, abi):
    archive = zipfile.ZipFile(hap)
    core = archive.read('libs/%s/libduanju_core.so' % abi)
    shim = archive.read('libs/%s/liblog.so' % abi)

    print('== %s（%s）' % (os.path.basename(hap), abi))
    machine = _u16(core, 18)
    print('  machine = %-3d %s'
          % (machine, 'OK' if machine == MACHINE[abi] else '**与 ABI 不符**'))

    va2off, tags = build_ohos._elf_load_map(core)

    # 第三关：inittls 短路。注意 dynsym 里那个值是 RELATIVE 重定位目标，
    # 文件里是 0，真正的入口在 r_addend 里。
    entry = None
    for name, _shndx, value in build_ohos._dynsym_symbols(core, va2off, tags):
        if name == 'x_cgo_inittls':
            addend = build_ohos._relocation_addend(core, va2off, tags, value)
            entry = addend if addend is not None else value
            break
    stub = STUBS[abi]
    if not entry:
        print('  inittls  **解析不到符号**')
    else:
        got = core[va2off(entry):va2off(entry) + len(stub)]
        print('  inittls @0x%-8x 入口=%s %s'
              % (entry, got.hex(), 'OK' if got == stub else '**未短路**'))

    # 第四关：tls_g 槽位。find_tls_g 以「目标处 8 字节 == TLS_G_INIT」筛选，
    # 这里把常量临时换成打完补丁的期望值，它就去找那条读取指令了。
    slot = build_ohos.TLS_G_SLOTS[abi]
    build_ohos.TLS_G_INIT = slot & 0xFFFFFFFFFFFFFFFF
    try:
        ranked = build_ohos.find_tls_g(core, va2off)
    finally:
        build_ohos.TLS_G_INIT = 16
    if not ranked:
        print('  tls_g  **没找到读取 tls_g 的指令**')
    else:
        target = ranked[0][0]
        value = struct.unpack_from('<q', core, va2off(target))[0]
        print('  tls_g  @0x%-8x 值=%-6d 期望=%-6d %s'
              % (target, value, slot, 'OK' if value == slot else '**不符**'))

    # 第五关：清零 g 槽的入口。Dart 侧靠它们调用，缺了会静默跳过。
    exported = _dynsym_names(shim, _sections(shim))
    print('  shim   ' + '  '.join(
        '%s=%s' % (name, '有' if name in exported else '**缺**')
        for name in SHIM_EXPORTS))
    print()


def main(paths):
    if not paths:
        raise SystemExit(__doc__.strip().splitlines()[-1].strip())
    for path in paths:
        name = os.path.basename(path)
        abi = 'arm64-v8a' if 'arm64' in name else 'x86_64' if 'x86' in name else None
        if abi is None:
            raise SystemExit('从文件名看不出 ABI：%s' % name)
        check(path, abi)


if __name__ == '__main__':
    main(sys.argv[1:])
