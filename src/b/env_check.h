#ifndef NTAP_B_ENV_CHECK_H
#define NTAP_B_ENV_CHECK_H

#include <stddef.h>
#include <stdio.h>

int ntap_b_env_check(FILE *out, const char *bridge_name, char *err, size_t err_len);

#endif
