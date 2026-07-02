#ifndef _WIN32
#define _GNU_SOURCE
#endif

#include "b/env_check.h"

#include <stdio.h>
#include <string.h>

#ifdef _WIN32
int ntap_b_env_check(FILE *out, char *err, size_t err_len)
{
    (void)err;
    (void)err_len;
    (void)fprintf(out, "platform=windows\n");
    (void)fprintf(out, "tun_check=unsupported\n");
    (void)fprintf(out, "privilege_check=unsupported\n");
    return 0;
}
#else
#include <errno.h>
#include <fcntl.h>
#include <linux/if_tun.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <unistd.h>

static void set_err(char *err, size_t err_len, const char *prefix)
{
    if (err == NULL || err_len == 0) {
        return;
    }
    (void)snprintf(err, err_len, "%s: %s", prefix, strerror(errno));
}

int ntap_b_env_check(FILE *out, char *err, size_t err_len)
{
    int fd = -1;
    struct ifreq ifr;

    fd = open("/dev/net/tun", O_RDWR);
    if (fd < 0) {
        set_err(err, err_len, "missing or unopenable /dev/net/tun");
        return 1;
    }
    (void)fprintf(out, "tun_check=ok\n");

    (void)memset(&ifr, 0, sizeof(ifr));
    ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
    (void)snprintf(ifr.ifr_name, sizeof(ifr.ifr_name), "ntapchk%%d");

    if (ioctl(fd, TUNSETIFF, (void *)&ifr) < 0) {
        set_err(err, err_len, "missing CAP_NET_ADMIN/root privileges for TAP");
        close(fd);
        return 1;
    }
    (void)fprintf(out, "privilege_check=ok\n");
    (void)fprintf(out, "tap_probe=%s\n", ifr.ifr_name);
    close(fd);
    return 0;
}
#endif
