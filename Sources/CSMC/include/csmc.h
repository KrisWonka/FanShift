// AppleSMC 用户态接口的最小封装。
// 调用方式：IOServiceOpen("AppleSMC") + IOConnectCallStructMethod(选择子 2)，
// 80 字节的结构体里 data8 表示命令：9 读键信息、5 读、6 写、8 按序号取键名。
#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>

// kr 是内核返回值（0 = 成功），result 是 SMC 固件的应答字节（0 = 成功，
// 0x82 = 固件拒绝，0x84 = 没有这个键）。两个都是 0 才算成功。
typedef struct {
    int32_t kr;
    uint8_t result;
} csmc_status;

typedef struct {
    uint32_t size;
    uint32_t type;  // 四字符类型码，如 'flt '、'ui8 '
    uint8_t attr;
} csmc_keyinfo;

csmc_status csmc_key_info(uint32_t key, csmc_keyinfo *info);
csmc_status csmc_read(uint32_t key, csmc_keyinfo *info, uint8_t bytes[32]);
csmc_status csmc_write(uint32_t key, const uint8_t *bytes, uint32_t size);
csmc_status csmc_key_at_index(uint32_t index, uint32_t *key);

#endif
