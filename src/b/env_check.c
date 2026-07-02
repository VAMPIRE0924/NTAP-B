#ifndef _WIN32
#define _GNU_SOURCE
#endif

#include "b/env_check.h"

#include "common/proto.h"
#include "common/tap.h"

#include <stdio.h>
#include <string.h>

#ifdef _WIN32
int ntap_b_env_check(FILE *out, const char *bridge_name, char *err, size_t err_len)
{
    (void)bridge_name;
    (void)err;
    (void)err_len;
    (void)fprintf(out, "platform=windows\n");
    (void)fprintf(out, "tun_check=unsupported\n");
    (void)fprintf(out, "privilege_check=unsupported\n");
    return 0;
}
#else
int ntap_b_env_check(FILE *out, const char *bridge_name, char *err, size_t err_len)
{
    ntap_tap_t tap;

    tap.fd = -1;
    tap.name[0] = '\0';
    if (ntap_tap_open(&tap, "ntapchk%d", NTAP_DEFAULT_MTU, err, err_len) != 0) {
        return 1;
    }
    (void)fprintf(out, "tun_check=ok\n");
    (void)fprintf(out, "privilege_check=ok\n");
    (void)fprintf(out, "tap_probe=%s\n", tap.name);
    if (bridge_name != NULL && bridge_name[0] != '\0') {
        if (ntap_tap_attach_bridge(&tap, bridge_name, err, err_len) != 0) {
            ntap_tap_close(&tap);
            return 1;
        }
        (void)fprintf(out, "bridge_check=ok\n");
        (void)fprintf(out, "bridge_probe=%s\n", bridge_name);
    }
    ntap_tap_close(&tap);
    return 0;
}
#endif
