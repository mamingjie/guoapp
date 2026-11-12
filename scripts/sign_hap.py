#!/usr/bin/env python3
"""给 ohos 产物签名（OpenHarmony 本地调试证书）。

用法:
  python scripts/sign_hap.py                     # 签 entry-default-unsigned.hap
  python scripts/sign_hap.py --install           # 签完并安装到已连接设备
  python scripts/sign_hap.py --hap <path> --out <path>

依赖 DevEco Studio 自带的 hap-sign-tool.jar 与 OpenHarmony.p12，
签名材料缓存到 <repo>/.ohos-sign/（不纳入版本管理）。
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIGN_DIR = os.path.join(ROOT, '.ohos-sign')
HAP_DEFAULT = os.path.join(
    ROOT, 'ohos', 'entry', 'build', 'default', 'outputs', 'default',
    'entry-default-unsigned.hap')

CANDIDATE_STUDIOS = [
    r'C:\Program Files\Huawei\DevEco Studio',
    r'D:\Program Files\Huawei\DevEco Studio',
]


def find_studio():
    env = os.environ.get('DEVECO_STUDIO_HOME')
    for base in ([env] if env else []) + CANDIDATE_STUDIOS:
        if base and os.path.isfile(os.path.join(base, 'jbr', 'bin', 'java.exe')):
            return base
    raise SystemExit('未找到 DevEco Studio，请设置 DEVECO_STUDIO_HOME')


def find_hdc(studio):
    for root, _dirs, files in os.walk(os.path.join(studio, 'sdk')):
        if 'hdc.exe' in files:
            return os.path.join(root, 'hdc.exe')
    raise SystemExit('未找到 hdc.exe')


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True,
                            encoding='utf-8', errors='replace', **kwargs)
    if result.returncode != 0:
        sys.stderr.write(result.stdout or '')
        sys.stderr.write(result.stderr or '')
        raise SystemExit('命令失败: %s' % ' '.join(cmd))
    return result.stdout


def profile_template(lib, udid):
    """按是否指定设备 UDID 选 profile 模板与签名材料。

    debug 型 profile 用 development-certificate，只允许 profile 里列出的设备安装；
    release 型用 distribution-certificate，不绑设备。两个模板的证书字段名不同，
    拿 debug 模板删掉 debug-info 冒充 release 会被工具以
    「11015001 Require cert in bundleInfo!」拒掉，所以必须各用各的模板。
    """
    if udid:
        return (os.path.join(lib, 'UnsgnedDebugProfileTemplate.json'),
                'development-certificate',
                'openharmony application profile debug',
                os.path.join(lib, 'OpenHarmonyProfileDebug.pem'),
                'debug')
    return (os.path.join(lib, 'UnsgnedReleasedProfileTemplate.json'),
            'distribution-certificate',
            'openharmony application profile release',
            os.path.join(lib, 'OpenHarmonyProfileRelease.pem'),
            'release')


def ensure_material(studio, bundle_name):
    """准备证书链 + 已签名 profile，返回 (chain, profile)。"""
    lib = os.path.join(studio, 'sdk', 'default', 'openharmony', 'toolchains', 'lib')
    keystore = os.path.join(lib, 'OpenHarmony.p12')
    sign_tool = os.path.join(lib, 'hap-sign-tool.jar')
    java = os.path.join(studio, 'jbr', 'bin', 'java.exe')
    keytool = os.path.join(studio, 'jbr', 'bin', 'keytool.exe')

    udid = os.environ.get('OHOS_DEVICE_UDID', '').strip()
    (template, cert_field, profile_key, profile_cert, mode) = profile_template(lib, udid)

    os.makedirs(SIGN_DIR, exist_ok=True)
    chain = os.path.join(SIGN_DIR, 'appchain.cer')
    # profile 按包名 + 模式分开存，两个变体交替打时不会互相覆盖。
    profile = os.path.join(SIGN_DIR, '%s-%s.p7b' % (bundle_name, mode))
    meta_path = os.path.join(SIGN_DIR, 'meta.json')
    if os.path.isfile(chain) and os.path.isfile(profile) and os.path.isfile(meta_path):
        with open(meta_path, encoding='utf-8') as fp:
            saved = json.load(fp)
        if (saved.get('bundleName') == bundle_name
                and saved.get('udid') == udid
                and saved.get('mode') == mode):
            return chain, profile

    pw = '123456'
    root = os.path.join(SIGN_DIR, 'rootca.cer')
    sub = os.path.join(SIGN_DIR, 'subca.cer')

    def export(alias, out):
        run([keytool, '-exportcert', '-rfc', '-alias', alias,
             '-keystore', keystore, '-storepass', pw,
             '-storetype', 'PKCS12', '-file', out])

    export('openharmony application root ca', root)
    export('openharmony application ca', sub)

    run([java, '-jar', sign_tool, 'generate-app-cert',
         '-keyAlias', 'openharmony application release', '-keyPwd', pw,
         '-issuer', 'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA',
         '-issuerKeyAlias', 'openharmony application ca', '-issuerKeyPwd', pw,
         '-subject', 'C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application Release',
         '-validity', '3650', '-signAlg', 'SHA256withECDSA',
         '-keystoreFile', keystore, '-keystorePwd', pw,
         '-outForm', 'certChain', '-rootCaCertFile', root,
         '-subCaCertFile', sub, '-outFile', chain])

    with open(chain, encoding='utf-8') as fp:
        certs = re.findall(
            r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', fp.read(), re.S)
    if not certs:
        raise SystemExit('证书链 %s 里没解析出证书' % chain)

    with open(template, encoding='utf-8') as fp:
        data = json.load(fp)
    now = int(time.time())
    data['bundle-info'][cert_field] = certs[0] + '\n'
    data['bundle-info']['bundle-name'] = bundle_name
    data['bundle-info']['developer-id'] = 'guoapp'
    data['validity'] = {'not-before': now - 86400, 'not-after': now + 5 * 365 * 86400}
    if udid:
        data['debug-info'] = {'device-ids': [udid], 'device-id-type': 'udid'}
    else:
        data.pop('debug-info', None)
    data['type'] = mode
    unsigned = os.path.join(SIGN_DIR, 'profile.json')
    with open(unsigned, 'w', encoding='utf-8') as fp:
        json.dump(data, fp, ensure_ascii=False, indent=2)

    run([java, '-jar', sign_tool, 'sign-profile',
         '-keyAlias', profile_key, '-signAlg', 'SHA256withECDSA', '-mode', 'localSign',
         '-profileCertFile', profile_cert, '-inFile', unsigned,
         '-keystoreFile', keystore, '-outFile', profile,
         '-keyPwd', pw, '-keystorePwd', pw])

    with open(meta_path, 'w', encoding='utf-8') as fp:
        json.dump({'bundleName': bundle_name, 'udid': udid, 'mode': mode}, fp)
    print('签名材料：%s 型 profile（%s）' % (mode, os.path.basename(profile)))
    return chain, profile


def read_bundle_name():
    path = os.path.join(ROOT, 'ohos', 'AppScope', 'app.json5')
    with open(path, encoding='utf-8') as fp:
        text = fp.read()
    match = re.search(r'"bundleName"\s*:\s*"([^"]+)"', text)
    if not match:
        raise SystemExit('无法从 app.json5 读取 bundleName')
    return match.group(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--hap', default=HAP_DEFAULT)
    parser.add_argument('--out', default=os.path.join(SIGN_DIR, 'guoapp-signed.hap'))
    parser.add_argument('--install', action='store_true', help='签名后安装到设备')
    args = parser.parse_args()

    if not os.path.isfile(args.hap):
        raise SystemExit('找不到待签名 HAP: %s' % args.hap)

    studio = find_studio()
    lib = os.path.join(studio, 'sdk', 'default', 'openharmony', 'toolchains', 'lib')
    java = os.path.join(studio, 'jbr', 'bin', 'java.exe')
    bundle_name = read_bundle_name()

    chain, profile = ensure_material(studio, bundle_name)
    run([java, '-jar', os.path.join(lib, 'hap-sign-tool.jar'), 'sign-app',
         '-keyAlias', 'openharmony application release',
         '-signAlg', 'SHA256withECDSA', '-mode', 'localSign',
         '-appCertFile', chain, '-profileFile', profile,
         '-inFile', args.hap, '-keystoreFile', os.path.join(lib, 'OpenHarmony.p12'),
         '-outFile', args.out, '-keyPwd', '123456', '-keystorePwd', '123456'])
    size = os.path.getsize(args.out) / 1048576
    print('已签名: %s (%.1f MB)' % (args.out, size))

    if args.install:
        hdc = find_hdc(studio)
        out = run([hdc, 'install', '-r', os.path.basename(args.out)],
                  cwd=os.path.dirname(args.out))
        print(out.strip())


if __name__ == '__main__':
    main()
