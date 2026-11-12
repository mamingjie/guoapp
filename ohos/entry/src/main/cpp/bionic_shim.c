/*
 * Android(bionic) → OpenHarmony(musl) 兼容层。
 *
 * 发布版 libduanju_core.so 是 Go 以 GOOS=android 编出来的，动态依赖只有
 * liblog.so / libdl.so / libc.so。这个文件编成 liblog.so（名字必须和被依赖
 * 的名字一致），放在 HAP 的 libs/<abi>/ 下；核心库按 NEEDED 顺序解析符号，
 * liblog 排在 libc 前面，于是下面这些实现会优先于 musl 的版本生效。
 *
 * 一、补 bionic 专有符号（56 个未定义符号里只差这 3 个）
 *   __errno              bionic 的 errno 存取器，musl 叫 __errno_location
 *   __register_atfork    bionic 内部名，musl 公开的是 pthread_atfork
 *   __android_log_vprint Android logcat，鸿蒙没有，直接丢弃
 *
 * 二、修正 struct sigaction 的布局差异（这一条决定了库能不能加载）
 *   x_cgo_sigaction 里是「按 bionic 头文件编译的 C 代码」：
 *
 *       struct sigaction act, oldact;          // bionic: 32 字节
 *       sigaction(signum, &act, &oldact);      // 交给 musl 的 sigaction
 *
 *   bionic(x86_64/aarch64) 的 struct sigaction 是 32 字节，sa_mask 只占
 *   8 字节（64 个信号）；musl 的是 152 字节，sa_mask 占 128 字节。
 *   如果让 musl 的 sigaction 直接处理这块内存：
 *     - 读的时候把 bionic 的 sa_flags 当成 handler、把 handler 当成掩码，
 *       于是装上去的处理函数地址其实是 flags 的值；
 *     - 写旧动作时往 32 字节的 oldact 里灌 152 字节，直接冲掉调用者
 *       x_cgo_sigaction 保存的 rbx/r12-r15/rbp 和返回地址。
 *   实测后果就是 dlopen 阶段 retq 跳到地址 0（SIGSEGV @0，rip=0）。
 *
 *   所以这里自己实现一份，在两个布局之间做翻译，底层直接走 rt_sigaction
 *   系统调用。
 *
 *   注意导出名是 sig_ohos 而不是 sigaction：musl 查符号时先走「全局作用域」
 *   （主程序 + libc），再走被加载对象的依赖链，所以 libc 的 sigaction 一定
 *   比这里的优先，叫什么名字都抢不过来。办法是反过来改核心库——用
 *   scripts/build_ohos.py 的 rename_import() 把它导入的 sigaction 符号名
 *   改写成 sig_ohos（只改 .dynstr 里那一个字符串，长度不变），这样全局作用域
 *   里没人叫这个名字，才会落到这里。
 */
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

/* ---------- 一、bionic 专有符号 ---------- */

/* 必须返回 musl 自己那份线程局部 errno，否则 Go 读到的 errno 永远是 0。 */
int *__errno(void) {
    return __errno_location();
}

int __register_atfork(void (*prepare)(void),
                      void (*parent)(void),
                      void (*child)(void),
                      void *dso_handle) {
    (void)dso_handle;
    return pthread_atfork(prepare, parent, child);
}

/* Go 只在 cgo 打印诊断时用，丢掉不影响功能。 */
int __android_log_vprint(int prio, const char *tag, const char *fmt, va_list ap) {
    (void)prio;
    (void)tag;
    (void)fmt;
    (void)ap;
    return 0;
}

int __android_log_print(int prio, const char *tag, const char *fmt, ...) {
    (void)prio;
    (void)tag;
    (void)fmt;
    return 0;
}

int __android_log_write(int prio, const char *tag, const char *text) {
    (void)prio;
    (void)tag;
    (void)text;
    return 0;
}

/* 版本查询类调用，返回一个固定值即可。 */
int __android_get_device_api_level(void) {
    return 26;
}

/* ---------- 二、struct sigaction 布局翻译 ---------- */

#define BIONIC_SA_RESTORER 0x04000000UL

/* bionic 布局，由 x_cgo_sigaction 的反汇编确认：
 *   +0  int sa_flags
 *   +8  handler（sa_handler / sa_sigaction 共用同一槽位）
 *   +16 sigset_t sa_mask（64 位下只有 8 字节）
 *   +24 sa_restorer
 * 整体 32 字节。 */
typedef struct {
    int flags;
    void *handler;
    unsigned long long mask;
    void *restorer;
} bionic_sigaction_t;

/* 内核看到的 struct sigaction，x86_64 与 aarch64 布局一致：
 * handler / flags / restorer / sigset(8 字节)。 */
typedef struct {
    void *handler;
    unsigned long flags;
    void *restorer;
    unsigned long long mask;
} kern_sigaction_t;

/* 处理函数正常返回时内核要跳的回跳点，两个架构各一条 rt_sigreturn。 */
__attribute__((naked, used)) static void ohos_restore_rt(void) {
#if defined(__x86_64__)
    __asm__ volatile("movl $15, %eax\n\tsyscall");
#else
    __asm__ volatile("mov x8, #139\n\tsvc #0");
#endif
}

int sig_ohos(int sig, const bionic_sigaction_t *act, bionic_sigaction_t *old) {
    kern_sigaction_t kact, kold;
    kern_sigaction_t *pkact = NULL;
    kern_sigaction_t *pkold = NULL;
    long r;

    if (act != NULL) {
        kact.handler = act->handler;
        kact.flags = (unsigned long)act->flags;
        kact.mask = act->mask;
        if ((kact.flags & BIONIC_SA_RESTORER) != 0) {
            kact.restorer = act->restorer;
        } else {
            kact.flags |= BIONIC_SA_RESTORER;
            kact.restorer = (void *)ohos_restore_rt;
        }
        pkact = &kact;
    }
    if (old != NULL) {
        pkold = &kold;
    }

    r = syscall(SYS_rt_sigaction, sig, pkact, pkold, sizeof(kold.mask));
    if (r < 0) {
        return -1; /* syscall 已经写好 errno */
    }

    if (old != NULL) {
        old->flags = (int)kold.flags;
        old->handler = kold.handler;
        old->mask = kold.mask;
        old->restorer = kold.restorer;
    }
    return 0;
}

/* ---------- 三、信号掩码 ---------- */

/* sigset 系列（sigemptyset/sigaddset/sigismember/...）不用管：
 * musl 的实现在 64 位下只碰 sigset_t 的第一个机器字，正好等于 bionic
 * 8 字节 sigset_t 的宽度，实测二者行为一致（见 probe 结论）。
 * pthread_sigmask 同理，musl 也是按 _NSIG/8 交给内核的。 */

/* ---------- 四、TLS 槽位自检 ---------- */

/* 背景：Go 的 runtime 用 `runtime.tls_g` 这个变量记「当前 g 存在线程指针的
 * 第几字节」。官方值 16 是 bionic 的 TLS_SLOT_APP（系统给应用预留的空槽），
 * musl 没有这个预留区，所以构建时会把 tls_g 改写成 musl
 * `struct pthread` 里一个确认无人使用的槽位（见 scripts/build_ohos.py 的
 * TLS_G_SLOTS）。
 *
 * x86_64 的偏移（+216）是在模拟器上用「灌魔数 + 压力测试」实测出来的；
 * arm64（-136）只能按 musl 头文件的字段序推导，没有真机可验证。所以这里在
 * 加载时读一次那个偏移，把结果记下来并尽量写进 hilog —— 万一 arm64 上撞了
 * 别人在用的字段，能从日志里第一时间看出来，而不是表现为随机崩溃。
 *
 * GUO_TLS_SLOT 由构建脚本按 ABI 传入，避免两处各写一份偏移。
 */
#ifndef GUO_TLS_SLOT
#define GUO_TLS_SLOT 0
#endif

static unsigned long guo_tls_before;   /* 构造函数看到的原始值 */
static unsigned long guo_tls_after;    /* 上一次查询时看到的值 */
static void *guo_tls_tp;               /* 线程指针，方便对照日志 */

static void *guo_thread_pointer(void) {
    void *tp;
#if defined(__x86_64__)
    /* musl 的 pthread_self() 就是 fs:0；probe 实测 tp == fs:0 == fsbase */
    __asm__ volatile("movq %%fs:0, %0" : "=r"(tp));
#else
    __asm__ volatile("mrs %0, tpidr_el0" : "=r"(tp));
#endif
    return tp;
}

static unsigned long guo_tls_read(long offset) {
    unsigned long value;
#if defined(__x86_64__)
    __asm__ volatile("movq %%fs:(%1), %0" : "=r"(value) : "r"(offset));
#else
    /* 和 Go 的 load_g 一样，直接按 TPIDR_EL0 + 偏移取；偏移落在 TLS 块所在
     * 的那一页里，不会越界访问。 */
    value = *(volatile unsigned long *)((char *)guo_thread_pointer() + offset);
#endif
    return value;
}

/* 把诊断信息送进 hilog。用 dlopen 拿符号而不是加 DT_NEEDED：
 * 拿不到就静默跳过，绝不让「打日志」这件事影响库能不能加载。 */
static void guo_log(const char *text) {
    typedef int (*PrintFn)(int, int, unsigned int, const char *, const char *, ...);
    static PrintFn print;
    static int tried;
    if (!tried) {
        tried = 1;
        void *handle = dlopen("libhilog_ndk.z.so", RTLD_LAZY);
        if (handle != NULL) {
            print = (PrintFn)dlsym(handle, "OH_LOG_Print");
        }
    }
    if (print != NULL) {
        /* 0x0000 = LOG_APP；4 = LOG_INFO */
        print(0x0000, 4, 0x0, "guoapp", "%{public}s", text);
    }
}

static void guo_hex(char *out, unsigned long value) {
    static const char digits[] = "0123456789abcdef";
    int index;
    out[0] = '0';
    out[1] = 'x';
    for (index = 0; index < 16; index++) {
        out[2 + index] = digits[(value >> (60 - index * 4)) & 0xF];
    }
    out[18] = '\0';
}

__attribute__((constructor)) static void guo_tls_selfcheck(void) {
    char line[128];
    char tp_hex[20];
    char slot_hex[20];

    guo_tls_tp = guo_thread_pointer();
    guo_tls_before = guo_tls_read((long)GUO_TLS_SLOT);
    guo_tls_after = guo_tls_before;

    /* 手工拼串而不是 snprintf：构造函数里尽量少碰 libc 的可变参数路径 */
    guo_hex(tp_hex, (unsigned long)guo_tls_tp);
    guo_hex(slot_hex, guo_tls_before);
    snprintf(line, sizeof(line), "tls tp=%s off=%ld slot=%s",
             tp_hex, (long)GUO_TLS_SLOT, slot_hex);
    guo_log(line);

    if (guo_tls_before != 0) {
        /* 槽位里已经有别人的数据：Go 写进去就会把 musl 的字段冲掉。 */
        guo_log("tls slot 非空，可能与 musl 字段冲突");
    }
}

/* 给 Dart 侧查的接口，返回 {tp, 加载时槽值, 当前槽值, 当前槽非空标记}。
 *
 * 注意：out[1] 是构造函数那会儿读的，只对初始化线程有意义；
 * 判断「调用线程的槽能不能用」必须看 out[2]/out[3]。 */
void guoapp_tls_state(unsigned long *out) {
    if (out == NULL) {
        return;
    }
    guo_tls_after = guo_tls_read((long)GUO_TLS_SLOT);
    out[0] = (unsigned long)guo_thread_pointer();
    out[1] = guo_tls_before;
    out[2] = guo_tls_after;
    out[3] = (guo_tls_after != 0) ? 1UL : 0UL;
}

static void guo_tls_write(unsigned long value) {
#if defined(__x86_64__)
    long offset = (long)GUO_TLS_SLOT;
    __asm__ volatile("movq %0, %%fs:(%1)" : : "r"(value), "r"(offset) : "memory");
#else
    *(volatile unsigned long *)((char *)guo_thread_pointer() + (long)GUO_TLS_SLOT) = value;
#endif
}

/* ---------- 五、进 Go 之前清零 g 槽 ---------- */

/* 为什么必须清：Go 的 cgocallback 用「TLS 里的 g 是否为 0」判断这个线程是不是
 * 第一次进 Go（0 → needm 领一个 m；非 0 → 认为已经有 m，直接 havem）。
 * 而 dropm 只在「C 线程主动调 cgocallback(nil, ...) 退出」或「Go 自己注册的
 * pthread key 析构器」里才跑；Flutter 的 DartWorker 是 pthread 建完、函数返回
 * 就退出的普通线程，两者都不会触发，于是它 pthread 结构体里的 g 槽带着旧值
 * 被 musl 回收。下一个 DartWorker 复用同一块内存，一进 cgocallback 就读到那个
 * 残留 g，跳过 needm，接着取 m.curg —— 那个 m 早已还回空闲池、curg 为 0，
 * 于是在 56(%rsi) 处 SIGSEGV @0x38。实测这就是 tls_g=216 时唯一会崩的场景
 * （probe27：人工往槽里写 0xdeadbeef，调用立刻崩在同一处）。
 *
 * 解法：由调用方在每次发起请求前显式清零，让每个线程都走 needm 这条正规路径。
 * 用 thread-local 深度计数兜住「Go 回调进 C 又回调进 Go」的嵌套，避免内层把
 * 外层的 g 清掉。
 */
static __thread int guo_go_depth;

void guoapp_tls_enter(void) {
    if (guo_go_depth == 0) {
        guo_tls_write(0);
    }
    guo_go_depth++;
}

void guoapp_tls_leave(void) {
    if (guo_go_depth > 0) {
        guo_go_depth--;
    }
}

