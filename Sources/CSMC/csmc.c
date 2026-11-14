#include "csmc.h"

#include <IOKit/IOKitLib.h>
#include <pthread.h>
#include <string.h>

// 以下结构体布局必须和 AppleSMC 内核扩展里的一致，不能改字段顺序和类型。
typedef struct {
    char major, minor, build, reserved[1];
    UInt16 release;
} smc_vers_t;

typedef struct {
    UInt16 version, length;
    UInt32 cpuPLimit, gpuPLimit, memPLimit;
} smc_plimit_t;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char dataAttributes;
} smc_keyinfo_t;

typedef struct {
    UInt32 key;
    smc_vers_t vers;
    smc_plimit_t pLimitData;
    smc_keyinfo_t keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    unsigned char bytes[32];
} smc_param_t;

enum { kSMCUserClientCall = 2 };
enum { kSMCReadBytes = 5, kSMCWriteBytes = 6, kSMCReadIndex = 8, kSMCReadKeyInfo = 9 };

static io_connect_t g_conn = 0;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

// 调用前必须持有 g_lock
static kern_return_t ensure_open(void) {
    if (g_conn != 0) return KERN_SUCCESS;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (svc == 0) return kIOReturnNoDevice;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) g_conn = 0;
    return kr;
}

// 调用前必须持有 g_lock
static csmc_status call(smc_param_t *in, smc_param_t *out) {
    csmc_status st = {0, 0};
    kern_return_t kr = ensure_open();
    if (kr != KERN_SUCCESS) {
        st.kr = kr;
        return st;
    }
    size_t outSize = sizeof(smc_param_t);
    memset(out, 0, sizeof(*out));
    kr = IOConnectCallStructMethod(g_conn, kSMCUserClientCall, in, sizeof(smc_param_t), out, &outSize);
    st.kr = kr;
    st.result = (uint8_t)out->result;
    return st;
}

static csmc_status key_info_locked(uint32_t key, csmc_keyinfo *info) {
    smc_param_t in, out;
    memset(&in, 0, sizeof(in));
    in.key = key;
    in.data8 = kSMCReadKeyInfo;
    csmc_status st = call(&in, &out);
    if (st.kr == 0 && st.result == 0 && info != NULL) {
        info->size = out.keyInfo.dataSize;
        info->type = out.keyInfo.dataType;
        info->attr = (uint8_t)out.keyInfo.dataAttributes;
    }
    return st;
}

csmc_status csmc_key_info(uint32_t key, csmc_keyinfo *info) {
    pthread_mutex_lock(&g_lock);
    csmc_status st = key_info_locked(key, info);
    pthread_mutex_unlock(&g_lock);
    return st;
}

csmc_status csmc_read(uint32_t key, csmc_keyinfo *info, uint8_t bytes[32]) {
    pthread_mutex_lock(&g_lock);
    csmc_keyinfo ki = {0, 0, 0};
    csmc_status st = key_info_locked(key, &ki);
    if (st.kr == 0 && st.result == 0) {
        smc_param_t in, out;
        memset(&in, 0, sizeof(in));
        in.key = key;
        in.keyInfo.dataSize = ki.size;
        in.data8 = kSMCReadBytes;
        st = call(&in, &out);
        if (st.kr == 0 && st.result == 0) {
            memcpy(bytes, out.bytes, 32);
            if (info != NULL) *info = ki;
        }
    }
    pthread_mutex_unlock(&g_lock);
    return st;
}

csmc_status csmc_write(uint32_t key, const uint8_t *bytes, uint32_t size) {
    csmc_status st = {0, 0};
    if (size > 32) {
        st.kr = kIOReturnBadArgument;
        return st;
    }
    pthread_mutex_lock(&g_lock);
    smc_param_t in, out;
    memset(&in, 0, sizeof(in));
    in.key = key;
    in.keyInfo.dataSize = size;
    in.data8 = kSMCWriteBytes;
    memcpy(in.bytes, bytes, size);
    st = call(&in, &out);
    pthread_mutex_unlock(&g_lock);
    return st;
}

csmc_status csmc_key_at_index(uint32_t index, uint32_t *key) {
    pthread_mutex_lock(&g_lock);
    smc_param_t in, out;
    memset(&in, 0, sizeof(in));
    in.data8 = kSMCReadIndex;
    in.data32 = index;
    csmc_status st = call(&in, &out);
    if (st.kr == 0 && st.result == 0 && key != NULL) *key = out.key;
    pthread_mutex_unlock(&g_lock);
    return st;
}
