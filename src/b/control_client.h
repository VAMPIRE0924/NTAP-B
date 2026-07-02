#ifndef NTAP_B_CONTROL_CLIENT_H
#define NTAP_B_CONTROL_CLIENT_H

#include <stddef.h>

#include "b/config.h"

int ntap_b_control_run_once(const ntap_b_config_t *cfg, char *err, size_t err_len);
int ntap_b_control_run_loop(const ntap_b_config_t *cfg, int max_attempts,
                            int max_sessions, int ping_count,
                            unsigned int ping_interval_ms,
                            int send_test_frame_count, int expect_test_frame,
                            int send_test_frame_each_pong, int tap_mode,
                            char *err, size_t err_len);

#endif
