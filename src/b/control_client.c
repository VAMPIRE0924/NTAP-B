#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include "b/control_client.h"

#include "common/direct_token.h"
#include "common/net.h"
#include "common/ntap_time.h"
#include "common/tap.h"
#include "common/wire.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
static void sleep_msec(unsigned int msec)
{
    Sleep(msec);
}
#else
#include <errno.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <time.h>
static void sleep_msec(unsigned int msec)
{
    struct timespec ts;

    ts.tv_sec = (time_t)(msec / 1000u);
    ts.tv_nsec = (long)((msec % 1000u) * 1000000u);
    (void)nanosleep(&ts, NULL);
}
#endif

#define NTAP_B_MAX_SOCKS_STREAMS 32
#define NTAP_B_SOCKS_READ_CHUNK 8192u
#define NTAP_B_MAX_DIRECT_CLIENTS 8

typedef struct b_socks_stream {
    int active;
    uint32_t stream_id;
    ntap_socket_t fd;
    int client_fin;
    int target_fin;
} b_socks_stream_t;

typedef struct b_direct_client {
    int active;
    ntap_socket_t fd;
    char remote[128];
} b_direct_client_t;

static int b_direct_listener_start(const ntap_config_push_t *runtime_config,
                                   ntap_socket_t *out,
                                   char *err, size_t err_len);
static int b_direct_accept_client(ntap_socket_t listen_fd,
                                  const char *node_id, const char *node_key,
                                  int64_t network_id, ntap_socket_t *out,
                                  char *remote_out, size_t remote_out_len,
                                  char *err, size_t err_len);

static int recv_expected(ntap_socket_t fd, uint8_t expected_type, ntap_hdr_t *hdr,
                         uint8_t *payload, size_t payload_cap, size_t *payload_len,
                         char *err, size_t err_len)
{
    if (ntap_recv_msg(fd, hdr, payload, payload_cap, payload_len, err, err_len) != 0) {
        return -1;
    }
    if (hdr->type != expected_type) {
        (void)snprintf(err, err_len, "expected %s, got %s",
                       ntap_msg_type_name(expected_type), ntap_msg_type_name(hdr->type));
        return -1;
    }
    return 0;
}

static const uint8_t k_test_frame[14] = {
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0x02, 0x00, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x00
};

static int send_test_tap_frame(ntap_socket_t fd, uint32_t session_id,
                               uint32_t network_id, char *err, size_t err_len)
{
    uint8_t payload[64];
    size_t payload_len = 0;

    if (ntap_encode_tap_frame(payload, sizeof(payload), &payload_len,
                              network_id, k_test_frame,
                              (uint16_t)sizeof(k_test_frame)) != 0) {
        (void)snprintf(err, err_len, "failed to encode test TAP_FRAME");
        return -1;
    }
    return ntap_send_msg(fd, NTAP_MSG_TAP_FRAME, session_id, payload,
                         (uint32_t)payload_len, err, err_len);
}

#ifndef _WIN32
static int send_tap_payload(ntap_socket_t fd, uint32_t session_id, uint32_t network_id,
                            const uint8_t *frame, uint16_t frame_len,
                            char *err, size_t err_len)
{
    uint8_t payload[NTAP_MAX_MTU + NTAP_TAP_PAYLOAD_EXTRA];
    size_t payload_len = 0;

    if (ntap_encode_tap_frame(payload, sizeof(payload), &payload_len,
                              network_id, frame, frame_len) != 0) {
        (void)snprintf(err, err_len, "failed to encode TAP_FRAME");
        return -1;
    }
    return ntap_send_msg(fd, NTAP_MSG_TAP_FRAME, session_id, payload,
                         (uint32_t)payload_len, err, err_len);
}

static void b_direct_clients_close_all(b_direct_client_t *clients)
{
    int i = 0;

    for (i = 0; i < NTAP_B_MAX_DIRECT_CLIENTS; i++) {
        if (clients[i].active) {
            ntap_socket_close(clients[i].fd);
            clients[i].active = 0;
        }
    }
}

static void b_direct_client_close(b_direct_client_t *client, const char *reason)
{
    if (client == NULL || !client->active) {
        return;
    }
    (void)printf("ntap-b: direct client closed remote=%s reason=%s\n",
                 client->remote, reason);
    (void)fflush(stdout);
    ntap_socket_close(client->fd);
    client->active = 0;
    client->remote[0] = '\0';
}

static void b_direct_clients_add(b_direct_client_t *clients, ntap_socket_t fd,
                                 const char *remote)
{
    int i = 0;

    for (i = 0; i < NTAP_B_MAX_DIRECT_CLIENTS; i++) {
        if (!clients[i].active) {
            clients[i].active = 1;
            clients[i].fd = fd;
            (void)snprintf(clients[i].remote, sizeof(clients[i].remote), "%s",
                           remote == NULL ? "unknown" : remote);
            (void)printf("ntap-b: direct client online remote=%s\n",
                         clients[i].remote);
            (void)fflush(stdout);
            return;
        }
    }
    (void)printf("ntap-b: direct client rejected remote=%s reason=capacity\n",
                 remote == NULL ? "unknown" : remote);
    (void)fflush(stdout);
    ntap_socket_close(fd);
}

static void b_direct_clients_send_tap(b_direct_client_t *clients, int skip_index,
                                      uint32_t network_id, const uint8_t *frame,
                                      uint16_t frame_len)
{
    char local_err[128];
    int i = 0;

    for (i = 0; i < NTAP_B_MAX_DIRECT_CLIENTS; i++) {
        if (!clients[i].active || i == skip_index) {
            continue;
        }
        local_err[0] = '\0';
        if (send_tap_payload(clients[i].fd, 0, network_id, frame, frame_len,
                             local_err, sizeof(local_err)) != 0) {
            b_direct_client_close(&clients[i],
                                  local_err[0] == '\0' ? "send_failed" : local_err);
            continue;
        }
        (void)printf("ntap-b: direct TAP_FRAME sent remote=%s len=%u\n",
                     clients[i].remote, frame_len);
        (void)fflush(stdout);
    }
}

static void b_direct_clients_handle_readable(b_direct_client_t *clients, int index,
                                             ntap_tap_t *tap, uint32_t network_id)
{
    uint8_t payload[NTAP_PAYLOAD_MAX_CONTROL];
    ntap_hdr_t hdr;
    size_t payload_len = 0;
    char local_err[128];
    ntap_tap_frame_t tap_frame;

    if (index < 0 || index >= NTAP_B_MAX_DIRECT_CLIENTS ||
        !clients[index].active || tap == NULL) {
        return;
    }
    local_err[0] = '\0';
    if (ntap_recv_msg(clients[index].fd, &hdr, payload, sizeof(payload),
                      &payload_len, local_err, sizeof(local_err)) != 0) {
        b_direct_client_close(&clients[index],
                              local_err[0] == '\0' ? "recv_failed" : local_err);
        return;
    }
    if (hdr.type != NTAP_MSG_TAP_FRAME ||
        ntap_decode_tap_frame(&tap_frame, payload, payload_len) != 0 ||
        tap_frame.network_id != network_id) {
        b_direct_client_close(&clients[index], "invalid_tap_frame");
        return;
    }
    if (ntap_tap_write(tap, tap_frame.frame, tap_frame.frame_len,
                       local_err, sizeof(local_err)) != 0) {
        b_direct_client_close(&clients[index],
                              local_err[0] == '\0' ? "tap_write_failed" : local_err);
        return;
    }
    (void)printf("ntap-b: direct TAP_FRAME received remote=%s len=%u\n",
                 clients[index].remote, tap_frame.frame_len);
    (void)fflush(stdout);
    b_direct_clients_send_tap(clients, index, network_id, tap_frame.frame,
                              tap_frame.frame_len);
}

static int run_tap_loop(ntap_socket_t fd, const char *tap_name, uint16_t mtu,
                        const ntap_auth_ok_t *auth_ok,
                        const ntap_config_push_t *runtime_config,
                        const char *node_id, const char *node_key,
                        unsigned int ping_interval_ms,
                        char *err, size_t err_len)
{
    ntap_tap_t tap;
    b_direct_client_t direct_clients[NTAP_B_MAX_DIRECT_CLIENTS];
    ntap_socket_t direct_listen_fd = NTAP_INVALID_SOCKET;
    uint8_t payload[NTAP_PAYLOAD_MAX_CONTROL];
    uint8_t frame_buf[NTAP_MAX_MTU + 64u];
    ntap_hdr_t hdr;
    size_t payload_len = 0;

    (void)memset(direct_clients, 0, sizeof(direct_clients));
    tap.fd = -1;
    tap.name[0] = '\0';
    if (ntap_tap_open(&tap, tap_name, mtu, err, err_len) != 0) {
        return -1;
    }
    (void)printf("ntap-b: TAP opened name=%s mtu=%u\n", tap.name, mtu);
    (void)fflush(stdout);

    if (b_direct_listener_start(runtime_config, &direct_listen_fd,
                                err, err_len) != 0) {
        ntap_tap_close(&tap);
        return -1;
    }
    if (ntap_send_msg(fd, NTAP_MSG_PING, auth_ok->session_id, NULL, 0,
                      err, err_len) != 0) {
        if (direct_listen_fd != NTAP_INVALID_SOCKET) {
            ntap_socket_close(direct_listen_fd);
        }
        ntap_tap_close(&tap);
        return -1;
    }

    for (;;) {
        fd_set readfds;
        int maxfd = fd > tap.fd ? fd : tap.fd;
        int selected = 0;
        struct timeval tv;
        int i = 0;

        FD_ZERO(&readfds);
        FD_SET(fd, &readfds);
        FD_SET(tap.fd, &readfds);
        if (direct_listen_fd != NTAP_INVALID_SOCKET) {
            FD_SET(direct_listen_fd, &readfds);
            if (direct_listen_fd > maxfd) {
                maxfd = direct_listen_fd;
            }
        }
        for (i = 0; i < NTAP_B_MAX_DIRECT_CLIENTS; i++) {
            if (direct_clients[i].active) {
                FD_SET(direct_clients[i].fd, &readfds);
                if (direct_clients[i].fd > maxfd) {
                    maxfd = direct_clients[i].fd;
                }
            }
        }
        tv.tv_sec = (long)(ping_interval_ms / 1000u);
        tv.tv_usec = (long)((ping_interval_ms % 1000u) * 1000u);
        if (tv.tv_sec == 0 && tv.tv_usec == 0) {
            tv.tv_sec = 1;
        }

        selected = select(maxfd + 1, &readfds, NULL, NULL, &tv);
        if (selected < 0) {
            if (errno == EINTR) {
                continue;
            }
            (void)snprintf(err, err_len, "select failed: %s", strerror(errno));
            if (direct_listen_fd != NTAP_INVALID_SOCKET) {
                ntap_socket_close(direct_listen_fd);
            }
            b_direct_clients_close_all(direct_clients);
            ntap_tap_close(&tap);
            return -1;
        }
        if (selected == 0) {
            if (ntap_send_msg(fd, NTAP_MSG_PING, auth_ok->session_id, NULL, 0,
                              err, err_len) != 0) {
                if (direct_listen_fd != NTAP_INVALID_SOCKET) {
                    ntap_socket_close(direct_listen_fd);
                }
                b_direct_clients_close_all(direct_clients);
                ntap_tap_close(&tap);
                return -1;
            }
            continue;
        }
        if (FD_ISSET(tap.fd, &readfds)) {
            size_t frame_len = 0;

            if (ntap_tap_read(&tap, frame_buf, sizeof(frame_buf), &frame_len,
                              err, err_len) != 0) {
                if (direct_listen_fd != NTAP_INVALID_SOCKET) {
                    ntap_socket_close(direct_listen_fd);
                }
                b_direct_clients_close_all(direct_clients);
                ntap_tap_close(&tap);
                return -1;
            }
            if (frame_len >= 14u && frame_len <= (size_t)mtu + 18u) {
                if (send_tap_payload(fd, auth_ok->session_id, auth_ok->network_id,
                                     frame_buf, (uint16_t)frame_len,
                                     err, err_len) != 0) {
                    if (direct_listen_fd != NTAP_INVALID_SOCKET) {
                        ntap_socket_close(direct_listen_fd);
                    }
                    b_direct_clients_close_all(direct_clients);
                    ntap_tap_close(&tap);
                    return -1;
                }
                b_direct_clients_send_tap(direct_clients, -1, auth_ok->network_id,
                                          frame_buf, (uint16_t)frame_len);
                (void)printf("ntap-b: TAP_FRAME sent len=%zu\n", frame_len);
                (void)fflush(stdout);
            }
        }
        if (FD_ISSET(fd, &readfds)) {
            if (ntap_recv_msg(fd, &hdr, payload, sizeof(payload), &payload_len,
                              err, err_len) != 0) {
                if (direct_listen_fd != NTAP_INVALID_SOCKET) {
                    ntap_socket_close(direct_listen_fd);
                }
                b_direct_clients_close_all(direct_clients);
                ntap_tap_close(&tap);
                return -1;
            }
            if (hdr.type == NTAP_MSG_PONG) {
                continue;
            }
            if (hdr.type == NTAP_MSG_TAP_FRAME) {
                ntap_tap_frame_t tap_frame;

                if (ntap_decode_tap_frame(&tap_frame, payload, payload_len) != 0 ||
                    tap_frame.network_id != auth_ok->network_id) {
                    (void)snprintf(err, err_len, "invalid relayed TAP_FRAME");
                    if (direct_listen_fd != NTAP_INVALID_SOCKET) {
                        ntap_socket_close(direct_listen_fd);
                    }
                    b_direct_clients_close_all(direct_clients);
                    ntap_tap_close(&tap);
                    return -1;
                }
                if (ntap_tap_write(&tap, tap_frame.frame, tap_frame.frame_len,
                                   err, err_len) != 0) {
                    if (direct_listen_fd != NTAP_INVALID_SOCKET) {
                        ntap_socket_close(direct_listen_fd);
                    }
                    b_direct_clients_close_all(direct_clients);
                    ntap_tap_close(&tap);
                    return -1;
                }
                b_direct_clients_send_tap(direct_clients, -1, auth_ok->network_id,
                                          tap_frame.frame, tap_frame.frame_len);
                (void)printf("ntap-b: TAP_FRAME received len=%u\n", tap_frame.frame_len);
                (void)fflush(stdout);
                continue;
            }
            (void)snprintf(err, err_len, "unexpected message in tap mode: %s",
                           ntap_msg_type_name(hdr.type));
            if (direct_listen_fd != NTAP_INVALID_SOCKET) {
                ntap_socket_close(direct_listen_fd);
            }
            b_direct_clients_close_all(direct_clients);
            ntap_tap_close(&tap);
            return -1;
        }
        if (direct_listen_fd != NTAP_INVALID_SOCKET &&
            FD_ISSET(direct_listen_fd, &readfds)) {
            ntap_socket_t direct_fd = NTAP_INVALID_SOCKET;
            char remote[128];

            remote[0] = '\0';
            if (b_direct_accept_client(direct_listen_fd, node_id, node_key,
                                       (int64_t)auth_ok->network_id,
                                       &direct_fd, remote, sizeof(remote),
                                       err, err_len) != 0) {
                if (direct_listen_fd != NTAP_INVALID_SOCKET) {
                    ntap_socket_close(direct_listen_fd);
                }
                b_direct_clients_close_all(direct_clients);
                ntap_tap_close(&tap);
                return -1;
            }
            if (direct_fd != NTAP_INVALID_SOCKET) {
                b_direct_clients_add(direct_clients, direct_fd, remote);
            }
            continue;
        }
        for (i = 0; i < NTAP_B_MAX_DIRECT_CLIENTS; i++) {
            if (direct_clients[i].active &&
                FD_ISSET(direct_clients[i].fd, &readfds)) {
                b_direct_clients_handle_readable(direct_clients, i, &tap,
                                                 auth_ok->network_id);
            }
        }
    }
}
#endif

static void b_socks_streams_close_all(b_socks_stream_t *streams)
{
    int i = 0;

    for (i = 0; i < NTAP_B_MAX_SOCKS_STREAMS; i++) {
        if (streams[i].active) {
            ntap_socket_close(streams[i].fd);
            streams[i].active = 0;
        }
    }
}

static b_socks_stream_t *b_socks_stream_find(b_socks_stream_t *streams,
                                             uint32_t stream_id)
{
    int i = 0;

    if (stream_id == 0) {
        return NULL;
    }
    for (i = 0; i < NTAP_B_MAX_SOCKS_STREAMS; i++) {
        if (streams[i].active && streams[i].stream_id == stream_id) {
            return &streams[i];
        }
    }
    return NULL;
}

static int b_send_socks_close(ntap_socket_t fd, uint32_t session_id,
                              uint32_t stream_id, uint16_t reason_code,
                              uint16_t flags,
                              char *err, size_t err_len)
{
    uint8_t payload[NTAP_SOCKS_CLOSE_REASON_SIZE];

    if (ntap_encode_socks_close_reason(payload, stream_id, reason_code,
                                       flags) != 0) {
        (void)snprintf(err, err_len, "failed to encode SOCKS close");
        return -1;
    }
    return ntap_send_msg(fd, NTAP_MSG_SOCKS_STREAM_CLOSE, session_id,
                         payload, sizeof(payload), err, err_len);
}

static int b_socks_stream_open(b_socks_stream_t *streams, ntap_socket_t control_fd,
                               uint32_t session_id, const uint8_t *payload,
                               size_t payload_len, char *err, size_t err_len)
{
    ntap_socks_open_t open_msg;
    ntap_socket_t target_fd = NTAP_INVALID_SOCKET;
    char target[320];
    int i = 0;

    if (ntap_decode_socks_open(&open_msg, payload, payload_len) != 0) {
        (void)snprintf(err, err_len, "invalid SOCKS_STREAM_OPEN");
        return -1;
    }
    if (b_socks_stream_find(streams, open_msg.stream_id) != NULL) {
        (void)snprintf(err, err_len, "duplicate SOCKS stream");
        return -1;
    }
    (void)snprintf(target, sizeof(target), "%s:%u", open_msg.host, open_msg.port);
    if (ntap_tcp_connect(target, &target_fd, err, err_len) != 0) {
        (void)b_send_socks_close(control_fd, session_id, open_msg.stream_id,
                                 NTAP_SOCKS_CLOSE_REASON_TARGET_CONNECT_FAILED,
                                 0,
                                 err, err_len);
        return 0;
    }
    for (i = 0; i < NTAP_B_MAX_SOCKS_STREAMS; i++) {
        if (!streams[i].active) {
            streams[i].active = 1;
            streams[i].stream_id = open_msg.stream_id;
            streams[i].fd = target_fd;
            streams[i].client_fin = 0;
            streams[i].target_fin = 0;
            (void)printf("ntap-b: SOCKS stream open stream_id=%u target=%s\n",
                         open_msg.stream_id, target);
            (void)fflush(stdout);
            return 0;
        }
    }
    ntap_socket_close(target_fd);
    (void)b_send_socks_close(control_fd, session_id, open_msg.stream_id,
                             NTAP_SOCKS_CLOSE_REASON_RESOURCE_LIMITED,
                             0,
                             err, err_len);
    return 0;
}

static int b_socks_stream_data(b_socks_stream_t *streams, const uint8_t *payload,
                               size_t payload_len, char *err, size_t err_len)
{
    ntap_socks_data_t data;
    b_socks_stream_t *stream = NULL;

    if (ntap_decode_socks_data(&data, payload, payload_len) != 0) {
        (void)snprintf(err, err_len, "invalid SOCKS_STREAM_DATA");
        return -1;
    }
    stream = b_socks_stream_find(streams, data.stream_id);
    if (stream == NULL) {
        return 0;
    }
    if (stream->client_fin) {
        return 0;
    }
    return ntap_send_all(stream->fd, data.data, data.data_len, err, err_len);
}

static void b_socks_stream_close(b_socks_stream_t *streams, uint32_t stream_id)
{
    b_socks_stream_t *stream = b_socks_stream_find(streams, stream_id);

    if (stream == NULL) {
        return;
    }
    ntap_socket_close(stream->fd);
    stream->active = 0;
}

static void b_socks_stream_mark_client_fin(b_socks_stream_t *streams,
                                           uint32_t stream_id)
{
    b_socks_stream_t *stream = b_socks_stream_find(streams, stream_id);

    if (stream == NULL) {
        return;
    }
    stream->client_fin = 1;
    ntap_socket_shutdown_send(stream->fd);
    if (stream->target_fin) {
        ntap_socket_close(stream->fd);
        stream->active = 0;
    }
}

static void b_socks_stream_mark_target_fin(b_socks_stream_t *streams,
                                           uint32_t stream_id)
{
    b_socks_stream_t *stream = b_socks_stream_find(streams, stream_id);

    if (stream == NULL) {
        return;
    }
    stream->target_fin = 1;
    if (stream->client_fin) {
        ntap_socket_close(stream->fd);
        stream->active = 0;
    }
}

static int b_direct_listener_start(const ntap_config_push_t *runtime_config,
                                   ntap_socket_t *out,
                                   char *err, size_t err_len)
{
    char addr[64];

    if (out == NULL) {
        return -1;
    }
    *out = NTAP_INVALID_SOCKET;
    if (runtime_config == NULL || !runtime_config->direct_enabled ||
        runtime_config->direct_port == 0) {
        return 0;
    }
    (void)snprintf(addr, sizeof(addr), "0.0.0.0:%u",
                   runtime_config->direct_port);
    if (ntap_tcp_listen(addr, 8, out, err, err_len) != 0) {
        return -1;
    }
    (void)printf("ntap-b: direct server start addr=%s\n", addr);
    (void)fflush(stdout);
    return 0;
}

static int b_direct_read_token_line(ntap_socket_t client_fd, char *token_buf,
                                    size_t token_buf_len, const char *remote,
                                    char *err, size_t err_len)
{
    int wait_rc = 0;
    size_t len = 0;

    if (token_buf == NULL || token_buf_len == 0) {
        return -1;
    }
    token_buf[0] = '\0';
    while (len + 1u < token_buf_len) {
        char ch = '\0';
        int n = 0;

        wait_rc = ntap_socket_wait_read(client_fd, 2000u, err, err_len);
        if (wait_rc != 0) {
            (void)printf("ntap-b: direct token rejected remote=%s reason=read_timeout\n",
                         remote);
            (void)fflush(stdout);
            return 1;
        }
        n = recv(client_fd, &ch, 1, 0);
        if (n <= 0) {
            (void)printf("ntap-b: direct token rejected remote=%s reason=read_failed\n",
                         remote);
            (void)fflush(stdout);
            return 1;
        }
        if (ch == '\n') {
            break;
        }
        token_buf[len++] = ch;
    }
    if (len + 1u >= token_buf_len) {
        (void)printf("ntap-b: direct token rejected remote=%s reason=too_long\n",
                     remote);
        (void)fflush(stdout);
        return 1;
    }
    token_buf[len] = '\0';
    len = strlen(token_buf);
    while (len > 0 &&
           (token_buf[len - 1u] == '\n' || token_buf[len - 1u] == '\r' ||
            token_buf[len - 1u] == ' ' || token_buf[len - 1u] == '\t')) {
        token_buf[--len] = '\0';
    }
    return 0;
}

static int b_direct_accept_client(ntap_socket_t listen_fd,
                                  const char *node_id, const char *node_key,
                                  int64_t network_id, ntap_socket_t *out,
                                  char *remote_out, size_t remote_out_len,
                                  char *err, size_t err_len)
{
    ntap_socket_t client_fd = NTAP_INVALID_SOCKET;
    ntap_direct_token_t token;
    char token_buf[NTAP_DIRECT_TOKEN_MAX];
    char remote[128];
    int token_rc = 0;

    if (out == NULL) {
        return -1;
    }
    *out = NTAP_INVALID_SOCKET;
    remote[0] = '\0';
    if (remote_out != NULL && remote_out_len > 0) {
        remote_out[0] = '\0';
    }
    if (ntap_tcp_accept(listen_fd, &client_fd, remote, sizeof(remote),
                        err, err_len) != 0) {
        return -1;
    }
    token_rc = b_direct_read_token_line(client_fd, token_buf, sizeof(token_buf),
                                        remote, err, err_len);
    if (token_rc != 0) {
        ntap_socket_close(client_fd);
        return token_rc < 0 ? -1 : 0;
    }
    if (ntap_direct_token_verify(token_buf, node_key, node_id, network_id,
                                 ntap_time_unix_sec(), &token) != 0) {
        (void)printf("ntap-b: direct token rejected remote=%s\n", remote);
        (void)fflush(stdout);
        ntap_socket_close(client_fd);
        return 0;
    }
    (void)printf("ntap-b: direct token accepted remote=%s user_id=%lld network_id=%lld\n",
                 remote, (long long)token.user_id, (long long)token.network_id);
    (void)fflush(stdout);
    if (remote_out != NULL && remote_out_len > 0) {
        (void)snprintf(remote_out, remote_out_len, "%s", remote);
    }
    *out = client_fd;
    return 0;
}

static int b_direct_accept_probe(ntap_socket_t listen_fd,
                                 const char *node_id, const char *node_key,
                                 int64_t network_id, char *err, size_t err_len)
{
    ntap_socket_t client_fd = NTAP_INVALID_SOCKET;

    if (b_direct_accept_client(listen_fd, node_id, node_key, network_id,
                               &client_fd, NULL, 0, err, err_len) != 0) {
        return -1;
    }
    if (client_fd != NTAP_INVALID_SOCKET) {
        ntap_socket_close(client_fd);
    }
    return 0;
}

static int run_control_loop(ntap_socket_t fd, const ntap_auth_ok_t *auth_ok,
                            const ntap_config_push_t *runtime_config,
                            const char *node_id, const char *node_key,
                            int ping_count, unsigned int ping_interval_ms,
                            int send_test_frame_count, int expect_test_frame,
                            int send_test_frame_each_pong,
                            char *err, size_t err_len)
{
    b_socks_stream_t streams[NTAP_B_MAX_SOCKS_STREAMS];
    uint8_t payload[NTAP_PAYLOAD_MAX_CONTROL];
    uint8_t out_payload[NTAP_PAYLOAD_MAX_SOCKS];
    uint8_t target_buf[NTAP_B_SOCKS_READ_CHUNK];
    ntap_hdr_t hdr;
    size_t payload_len = 0;
    size_t out_len = 0;
    int pings_done = 0;
    int sent_test_frames = 0;
    int got_test_frame = 0;
    ntap_socket_t direct_listen_fd = NTAP_INVALID_SOCKET;
    int rc = 1;

    (void)memset(streams, 0, sizeof(streams));
    if (b_direct_listener_start(runtime_config, &direct_listen_fd,
                                err, err_len) != 0) {
        return 1;
    }
    if (ntap_send_msg(fd, NTAP_MSG_PING, auth_ok->session_id, NULL, 0,
                      err, err_len) != 0) {
        goto done;
    }
    for (;;) {
        fd_set readfds;
        struct timeval tv;
        int selected = 0;
        int i = 0;
#ifndef _WIN32
        ntap_socket_t maxfd = fd;
#endif

        FD_ZERO(&readfds);
        FD_SET(fd, &readfds);
        if (direct_listen_fd != NTAP_INVALID_SOCKET) {
            FD_SET(direct_listen_fd, &readfds);
#ifndef _WIN32
            if (direct_listen_fd > maxfd) {
                maxfd = direct_listen_fd;
            }
#endif
        }
        for (i = 0; i < NTAP_B_MAX_SOCKS_STREAMS; i++) {
            if (streams[i].active && !streams[i].target_fin) {
                FD_SET(streams[i].fd, &readfds);
#ifndef _WIN32
                if (streams[i].fd > maxfd) {
                    maxfd = streams[i].fd;
                }
#endif
            }
        }
        tv.tv_sec = (long)(ping_interval_ms / 1000u);
        tv.tv_usec = (long)((ping_interval_ms % 1000u) * 1000u);
        if (tv.tv_sec == 0 && tv.tv_usec == 0) {
            tv.tv_sec = 1;
        }
#ifdef _WIN32
        selected = select(0, &readfds, NULL, NULL, &tv);
#else
        selected = select(maxfd + 1, &readfds, NULL, NULL, &tv);
#endif
        if (selected < 0) {
#ifndef _WIN32
            if (errno == EINTR) {
                continue;
            }
#endif
            (void)snprintf(err, err_len, "select failed");
            goto done;
        }
        if (selected == 0) {
            if (ntap_send_msg(fd, NTAP_MSG_PING, auth_ok->session_id, NULL, 0,
                              err, err_len) != 0) {
                goto done;
            }
            continue;
        }
        if (FD_ISSET(fd, &readfds)) {
            if (ntap_recv_msg(fd, &hdr, payload, sizeof(payload), &payload_len,
                              err, err_len) != 0) {
                if (pings_done > 0 && ping_count <= 0 && !expect_test_frame) {
                    rc = 0;
                }
                goto done;
            }
            if (hdr.type == NTAP_MSG_PONG) {
                pings_done++;
                (void)printf("ntap-b: pong received count=%d\n", pings_done);
                (void)fflush(stdout);
                if (send_test_frame_count > 0 &&
                    ((send_test_frame_each_pong &&
                      sent_test_frames < send_test_frame_count) ||
                     (!send_test_frame_each_pong && sent_test_frames == 0))) {
                    int j = 0;
                    int to_send = send_test_frame_each_pong ? 1 : send_test_frame_count;

                    for (j = 0; j < to_send; j++) {
                        if (send_test_tap_frame(fd, auth_ok->session_id,
                                                auth_ok->network_id,
                                                err, err_len) != 0) {
                            goto done;
                        }
                        sent_test_frames++;
                    }
                    (void)printf("ntap-b: test TAP_FRAME sent count=%d\n",
                                 sent_test_frames);
                    (void)fflush(stdout);
                }
                if (ping_count > 0 && pings_done >= ping_count &&
                    (!expect_test_frame || got_test_frame)) {
                    rc = 0;
                    goto done;
                }
                continue;
            }
            if (hdr.type == NTAP_MSG_TAP_FRAME) {
                ntap_tap_frame_t frame;

                if (ntap_decode_tap_frame(&frame, payload, payload_len) != 0 ||
                    frame.network_id != auth_ok->network_id ||
                    frame.frame_len != sizeof(k_test_frame) ||
                    memcmp(frame.frame, k_test_frame, sizeof(k_test_frame)) != 0) {
                    (void)snprintf(err, err_len, "unexpected TAP_FRAME");
                    goto done;
                }
                got_test_frame = 1;
                (void)printf("ntap-b: test TAP_FRAME received\n");
                (void)fflush(stdout);
                if (ping_count > 0 && pings_done >= ping_count) {
                    rc = 0;
                    goto done;
                }
                continue;
            }
            if (hdr.type == NTAP_MSG_SOCKS_STREAM_OPEN) {
                if (b_socks_stream_open(streams, fd, auth_ok->session_id,
                                        payload, payload_len, err, err_len) != 0) {
                    goto done;
                }
                continue;
            }
            if (hdr.type == NTAP_MSG_SOCKS_STREAM_DATA) {
                if (b_socks_stream_data(streams, payload, payload_len,
                                        err, err_len) != 0) {
                    goto done;
                }
                continue;
            }
            if (hdr.type == NTAP_MSG_SOCKS_STREAM_CLOSE) {
                ntap_socks_close_t close_msg;

                if (ntap_decode_socks_close(&close_msg, payload, payload_len) != 0) {
                    (void)snprintf(err, err_len, "invalid SOCKS_STREAM_CLOSE");
                    goto done;
                }
                if ((close_msg.flags & NTAP_SOCKS_CLOSE_FLAG_FIN) != 0) {
                    b_socks_stream_mark_client_fin(streams, close_msg.stream_id);
                } else {
                    b_socks_stream_close(streams, close_msg.stream_id);
                }
                continue;
            }
            (void)snprintf(err, err_len, "unexpected message: %s",
                           ntap_msg_type_name(hdr.type));
            goto done;
        }
        if (direct_listen_fd != NTAP_INVALID_SOCKET &&
            FD_ISSET(direct_listen_fd, &readfds)) {
            if (b_direct_accept_probe(direct_listen_fd, node_id, node_key,
                                      (int64_t)auth_ok->network_id,
                                      err, err_len) != 0) {
                goto done;
            }
            continue;
        }
        for (i = 0; i < NTAP_B_MAX_SOCKS_STREAMS; i++) {
            int n = 0;

            if (!streams[i].active || !FD_ISSET(streams[i].fd, &readfds)) {
                continue;
            }
            n = recv(streams[i].fd, (char *)target_buf, (int)sizeof(target_buf), 0);
            if (n <= 0) {
                uint32_t stream_id = streams[i].stream_id;

                if (b_send_socks_close(fd, auth_ok->session_id, stream_id,
                                       NTAP_SOCKS_CLOSE_REASON_REMOTE_CLOSED,
                                       NTAP_SOCKS_CLOSE_FLAG_FIN,
                                       err, err_len) != 0) {
                    goto done;
                }
                b_socks_stream_mark_target_fin(streams, stream_id);
                continue;
            }
            if (ntap_encode_socks_data(out_payload, sizeof(out_payload), &out_len,
                                       streams[i].stream_id, target_buf,
                                       (uint32_t)n) != 0 ||
                ntap_send_msg(fd, NTAP_MSG_SOCKS_STREAM_DATA, auth_ok->session_id,
                              out_payload, (uint32_t)out_len,
                              err, err_len) != 0) {
                goto done;
            }
        }
    }

done:
    if (direct_listen_fd != NTAP_INVALID_SOCKET) {
        ntap_socket_close(direct_listen_fd);
        (void)printf("ntap-b: direct server stop\n");
        (void)fflush(stdout);
    }
    b_socks_streams_close_all(streams);
    return rc;
}

static int run_session(const ntap_b_config_t *cfg, int ping_count,
                       unsigned int ping_interval_ms,
                       int send_test_frame_count, int expect_test_frame,
                       int send_test_frame_each_pong, int tap_mode,
                       char *err, size_t err_len)
{
    ntap_socket_t fd = NTAP_INVALID_SOCKET;
    uint8_t payload[NTAP_PAYLOAD_MAX_CONTROL];
    uint8_t out_payload[NTAP_PAYLOAD_MAX_CONTROL];
    size_t payload_len = 0;
    size_t out_len = 0;
    uint8_t client_nonce[NTAP_NONCE_SIZE];
    uint8_t sign[NTAP_HMAC_SHA256_SIZE];
    ntap_hdr_t hdr;
    ntap_hello_t server_hello;
    ntap_auth_ok_t auth_ok;
    ntap_config_push_t runtime_config;
    const char *tap_name = NULL;
    uint16_t tap_mtu = NTAP_DEFAULT_MTU;
    int rc = 1;

    if (cfg == NULL) {
        return 1;
    }
    if (ntap_net_init(err, err_len) != 0 ||
        ntap_tcp_connect(cfg->server_addr, &fd, err, err_len) != 0) {
        ntap_net_cleanup();
        return 1;
    }
    if (ntap_random_nonce(client_nonce) != 0 ||
        ntap_encode_hello(out_payload, sizeof(out_payload), &out_len, NTAP_ROLE_NODE,
                          "ntap-b/0.1", 0, client_nonce) != 0 ||
        ntap_send_msg(fd, NTAP_MSG_HELLO, 0, out_payload, (uint32_t)out_len,
                      err, err_len) != 0) {
        goto done;
    }
    if (recv_expected(fd, NTAP_MSG_HELLO, &hdr, payload, sizeof(payload),
                      &payload_len, err, err_len) != 0 ||
        ntap_decode_hello(&server_hello, payload, payload_len) != 0) {
        goto done;
    }
    if (server_hello.role != NTAP_ROLE_SERVER) {
        (void)snprintf(err, err_len, "server HELLO role mismatch");
        goto done;
    }
    if (ntap_auth_node_sign(cfg->node_key, server_hello.nonce, client_nonce,
                            cfg->node_id, sign) != 0 ||
        ntap_encode_auth_node(out_payload, sizeof(out_payload), &out_len,
                              cfg->node_id, client_nonce, sign) != 0 ||
        ntap_send_msg(fd, NTAP_MSG_AUTH_NODE, 0, out_payload, (uint32_t)out_len,
                      err, err_len) != 0) {
        goto done;
    }
    if (ntap_recv_msg(fd, &hdr, payload, sizeof(payload), &payload_len, err, err_len) != 0) {
        goto done;
    }
    if (hdr.type == NTAP_MSG_AUTH_FAIL) {
        (void)snprintf(err, err_len, "auth failed");
        rc = 3;
        goto done;
    }
    if (hdr.type != NTAP_MSG_AUTH_OK ||
        ntap_decode_auth_ok(&auth_ok, payload, payload_len) != 0) {
        (void)snprintf(err, err_len, "invalid auth response");
        goto done;
    }
    if (recv_expected(fd, NTAP_MSG_CONFIG_PUSH, &hdr, payload, sizeof(payload),
                      &payload_len, err, err_len) != 0 ||
        ntap_decode_config_push(&runtime_config, payload, payload_len) != 0 ||
        runtime_config.network_id != auth_ok.network_id) {
        (void)snprintf(err, err_len, "invalid CONFIG_PUSH");
        goto done;
    }
    tap_name = runtime_config.tap_name[0] == '\0' ? cfg->tap_name : runtime_config.tap_name;
    tap_mtu = runtime_config.mtu;
    (void)printf("ntap-b: auth ok session_id=%u network_id=%u\n",
                 auth_ok.session_id, auth_ok.network_id);

#ifdef _WIN32
    (void)tap_name;
    (void)tap_mtu;
    if (tap_mode) {
        (void)snprintf(err, err_len, "TAP mode is not supported on Windows in current phase");
        goto done;
    }
#else
    if (tap_mode) {
        if (!runtime_config.tap_enabled) {
            (void)snprintf(err, err_len, "CONFIG_PUSH disabled TAP");
            goto done;
        }
        rc = run_tap_loop(fd, tap_name, tap_mtu, &auth_ok, &runtime_config,
                          cfg->node_id, cfg->node_key, ping_interval_ms,
                          err, err_len);
        goto done;
    }
#endif

    rc = run_control_loop(fd, &auth_ok, &runtime_config, cfg->node_id, cfg->node_key,
                          ping_count, ping_interval_ms,
                          send_test_frame_count, expect_test_frame,
                          send_test_frame_each_pong, err, err_len);

done:
    ntap_socket_close(fd);
    ntap_net_cleanup();
    return rc;
}

int ntap_b_control_run_once(const ntap_b_config_t *cfg, char *err, size_t err_len)
{
    return run_session(cfg, 1, 0, 0, 0, 0, 0, err, err_len);
}

int ntap_b_control_run_loop(const ntap_b_config_t *cfg, int max_attempts,
                            int max_sessions, int ping_count,
                            unsigned int ping_interval_ms,
                            int send_test_frame_count, int expect_test_frame,
                            int send_test_frame_each_pong, int tap_mode,
                            char *err, size_t err_len)
{
    int attempt = 0;
    int sessions = 0;
    int rc = 1;

    while (max_sessions <= 0 || sessions < max_sessions) {
        if (max_attempts > 0 && attempt >= max_attempts) {
            return rc;
        }
        attempt++;
        rc = run_session(cfg, ping_count, ping_interval_ms,
                         send_test_frame_count, expect_test_frame,
                         send_test_frame_each_pong, tap_mode, err, err_len);
        if (rc == 0) {
            sessions++;
            (void)printf("ntap-b: session complete count=%d\n", sessions);
            (void)fflush(stdout);
            continue;
        }
        if (rc == 3) {
            return rc;
        }
        (void)fprintf(stderr, "ntap-b: connect/auth attempt %d failed: %s\n", attempt, err);
        sleep_msec(1000u);
    }
    return 0;
}
