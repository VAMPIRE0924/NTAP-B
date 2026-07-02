#include "b/config.h"
#include "b/control_client.h"
#include "b/env_check.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(FILE *out)
{
    (void)fprintf(out,
                  "usage:\n"
                  "  ntap-b -c <config> -t\n"
                  "  ntap-b check-env\n"
                  "  ntap-b -c <config> run [--once] [--max-attempts <n>] "
                  "[--max-sessions <n>] [--ping-count <n>] [--ping-interval-ms <n>] "
                  "[--send-test-frame] [--send-test-frame-count <n>] "
                  "[--send-test-frame-each-pong] [--expect-test-frame] [--tap]\n");
}

static const char *arg_value(int argc, char **argv, int start, const char *name)
{
    int i = 0;

    for (i = start; i < argc - 1; i++) {
        if (strcmp(argv[i], name) == 0) {
            return argv[i + 1];
        }
    }
    return NULL;
}

static bool has_flag(int argc, char **argv, int start, const char *name)
{
    int i = 0;

    for (i = start; i < argc; i++) {
        if (strcmp(argv[i], name) == 0) {
            return true;
        }
    }
    return false;
}

int main(int argc, char **argv)
{
    const char *config_path = NULL;
    bool test_config = false;
    ntap_b_config_t cfg;
    char err[256];
    int i = 0;
    int command_start = 0;

    err[0] = '\0';
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-c") == 0) {
            if (i + 1 >= argc) {
                usage(stderr);
                return 2;
            }
            config_path = argv[++i];
        } else if (strcmp(argv[i], "-t") == 0) {
            test_config = true;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(stdout);
            return 0;
        } else {
            command_start = i;
            break;
        }
    }

    if (command_start > 0 && strcmp(argv[command_start], "check-env") == 0) {
        int rc = ntap_b_env_check(stdout, err, sizeof(err));

        if (rc != 0) {
            (void)fprintf(stderr, "ntap-b: check-env failed: %s\n", err);
        }
        return rc;
    }

    if (ntap_b_config_load(&cfg, config_path, err, sizeof(err)) != 0) {
        (void)fprintf(stderr, "ntap-b: config error: %s\n", err);
        return 1;
    }

    if (test_config) {
        (void)printf("ntap-b: config ok (%s)\n", cfg.path);
        return 0;
    }

    if (command_start > 0) {
        if (strcmp(argv[command_start], "run") == 0) {
            bool once = has_flag(argc, argv, command_start + 1, "--once");
            const char *max_s = arg_value(argc, argv, command_start + 1, "--max-attempts");
            const char *session_s = arg_value(argc, argv, command_start + 1, "--max-sessions");
            const char *ping_s = arg_value(argc, argv, command_start + 1, "--ping-count");
            const char *interval_s = arg_value(argc, argv, command_start + 1,
                                               "--ping-interval-ms");
            const char *test_frame_count_s = arg_value(argc, argv, command_start + 1,
                                                       "--send-test-frame-count");
            int max_attempts = max_s == NULL ? 0 : atoi(max_s);
            int max_sessions = session_s == NULL ? 0 : atoi(session_s);
            int ping_count = ping_s == NULL ? 0 : atoi(ping_s);
            unsigned int ping_interval_ms = interval_s == NULL ? 1000u :
                                            (unsigned int)atoi(interval_s);
            int send_test_frame_count =
                has_flag(argc, argv, command_start + 1, "--send-test-frame") ? 1 : 0;
            int send_test_frame_each_pong =
                has_flag(argc, argv, command_start + 1,
                         "--send-test-frame-each-pong") ? 1 : 0;
            int expect_test_frame = has_flag(argc, argv, command_start + 1,
                                             "--expect-test-frame") ? 1 : 0;
            int tap_mode = has_flag(argc, argv, command_start + 1, "--tap") ? 1 : 0;
            if (test_frame_count_s != NULL) {
                send_test_frame_count = atoi(test_frame_count_s);
                if (send_test_frame_count <= 0) {
                    (void)fprintf(stderr,
                                  "ntap-b: --send-test-frame-count must be greater than 0\n");
                    return 2;
                }
            }
            if (tap_mode && once) {
                (void)fprintf(stderr, "ntap-b: --tap is a long-running mode; omit --once\n");
                return 2;
            }
            if (tap_mode && (send_test_frame_count > 0 || send_test_frame_each_pong ||
                             expect_test_frame)) {
                (void)fprintf(stderr,
                              "ntap-b: --tap cannot be combined with synthetic frame flags\n");
                return 2;
            }
            if (send_test_frame_each_pong && send_test_frame_count <= 0) {
                (void)fprintf(stderr,
                              "ntap-b: --send-test-frame-each-pong requires a test frame count\n");
                return 2;
            }
            int rc = once ? ntap_b_control_run_once(&cfg, err, sizeof(err)) :
                            ntap_b_control_run_loop(&cfg, max_attempts, max_sessions,
                                                    ping_count, ping_interval_ms,
                                                    send_test_frame_count,
                                                    expect_test_frame,
                                                    send_test_frame_each_pong, tap_mode,
                                                    err, sizeof(err));

            if (rc != 0) {
                (void)fprintf(stderr, "ntap-b: run failed: %s\n", err);
            }
            return rc;
        }
        (void)fprintf(stderr, "ntap-b: unknown command: %s\n", argv[command_start]);
        usage(stderr);
        return 2;
    }

    (void)printf("ntap-b: phase 0 skeleton ready; use -t to validate config\n");
    return 0;
}
