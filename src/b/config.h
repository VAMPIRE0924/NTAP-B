#ifndef NTAP_B_CONFIG_H
#define NTAP_B_CONFIG_H

#include <stddef.h>
#include <stdint.h>

#include "common/config.h"

typedef struct ntap_b_config {
    char path[NTAP_CONFIG_VALUE_MAX];
    char server_addr[NTAP_CONFIG_VALUE_MAX];
    char node_id[NTAP_CONFIG_VALUE_MAX];
    char node_key[NTAP_CONFIG_VALUE_MAX];
    char tap_name[NTAP_CONFIG_VALUE_MAX];
    uint16_t mtu;
    char log_level[NTAP_CONFIG_VALUE_MAX];
    char log_file[NTAP_CONFIG_VALUE_MAX];
} ntap_b_config_t;

int ntap_b_config_load(ntap_b_config_t *out, const char *path, char *err, size_t err_len);

#endif
