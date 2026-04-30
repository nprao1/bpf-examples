// SPDX-License-Identifier: GPL-2.0
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include "xdpsock.h"

/* This XDP program is only needed for multi-buffer and XDP_SHARED_UMEM modes.
 * If you do not use these modes, libbpf can supply an XDP program for you.
 */

struct {
	__uint(type, BPF_MAP_TYPE_XSKMAP);
	__uint(max_entries, MAX_SOCKS);
	__uint(key_size, sizeof(int));
	__uint(value_size, sizeof(int));
} xsks_map SEC(".maps");

int num_socks = 0;

SEC("xdp_sock") int xdp_sock_prog(struct xdp_md *ctx)
{
	/* Use hardware queue index to redirect to corresponding AF_XDP socket.
	 * This ensures packets from queue N go to socket bound to queue N.
	 */
	return bpf_redirect_map(&xsks_map, ctx->rx_queue_index, XDP_DROP);
}
