#include "b/config.h"

#include "common/proto.h"

#include <stdio.h>
#include <string.h>

static void copy_optional(char *out, size_t out_len, const char *value)
{
    if (out == NULL || out_len == 0) {
        return;
    }
    if (value == NULL) {
        out[0] = '\0';
        return;
    }
    (void)snprintf(out, out_len, "%s", value);
}

int ntap_b_config_load(ntap_b_config_t *out, const char *path, char *err, size_t err_len)
{
    ntap_config_t cfg;

    if (out == NULL) {
        return -1;
    }
    (void)memset(out, 0, sizeof(*out));
    if (path == NULL || *path == '\0') {
        path = "ntap-b.conf";
    }
    (void)snprintf(out->path, sizeof(out->path), "%s", path);

    if (ntap_config_load(&cfg, path, err, err_len) != 0) {
        return -1;
    }
    if (ntap_config_require_addr(&cfg, "node", "server_addr",
                                 out->server_addr, sizeof(out->server_addr), err, err_len) != 0 ||
        ntap_config_require(&cfg, "node", "node_id",
                            out->node_id, sizeof(out->node_id), err, err_len) != 0 ||
        ntap_config_require(&cfg, "node", "node_key",
                            out->node_key, sizeof(out->node_key), err, err_len) != 0) {
        return -1;
    }

    copy_optional(out->tap_name, sizeof(out->tap_name),
                  ntap_config_get(&cfg, "tap", "tap_name"));
    if (out->tap_name[0] == '\0') {
        (void)snprintf(out->tap_name, sizeof(out->tap_name), "ntap-b0");
    }
    if (ntap_config_get_u16(&cfg, "tap", "mtu", NTAP_DEFAULT_MTU,
                            NTAP_MIN_MTU, NTAP_MAX_MTU, &out->mtu,
                            err, err_len) != 0) {
        return -1;
    }

    copy_optional(out->log_level, sizeof(out->log_level),
                  ntap_config_get(&cfg, "log", "level"));
    copy_optional(out->log_file, sizeof(out->log_file),
                  ntap_config_get(&cfg, "log", "file"));
    if (out->log_level[0] == '\0') {
        (void)snprintf(out->log_level, sizeof(out->log_level), "info");
    }
    return 0;
}
