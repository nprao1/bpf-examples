#!/bin/bash

usage() {
    echo "Usage: $0 <mode> [options]"
    echo ""
    echo "Modes:"
    echo "  send, tx      - TX only (send packets)"
    echo "  recv, rx      - RX drop (receive and drop packets)"
    echo "  l2fwd, fwd    - L2 forward (MAC swap and forward)"
    echo ""
    echo "Options:"
    echo "  -r, --remote IP    Remote IP for ARP resolution (default: 192.168.0.2)"
    echo "  -l, --local IP     Local IP address (default: 192.168.0.1)"
    echo "  -m, --mtu N        MTU size (default: 9000)"
    echo "  -q, --queue N      Starting queue number (default: 1)"
    echo "  -n, --num-queues N Number of queues (default: 1)"
    echo "  -h, --help         Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 send                     # TX only on queue 1"
    echo "  $0 recv -n 4                # RX drop on 4 queues"
    echo "  $0 l2fwd -q 2 -n 8          # L2FWD on queues 2-9"
    exit 1
}

# Defaults
REMOTE_IP="192.168.0.2"
LOCAL_IP="192.168.0.1"
MTU=9000
QUEUE=1
NUM_QUEUES=1
MODE=""

# Parse mode (first argument)
case "$1" in
    send|tx)
        MODE="tx"
        shift
        ;;
    recv|rx)
        MODE="rx"
        shift
        ;;
    l2fwd|fwd)
        MODE="l2fwd"
        shift
        ;;
    -h|--help|"")
        usage
        ;;
    *)
        echo "ERROR: Unknown mode '$1'"
        usage
        ;;
esac

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--remote)
            REMOTE_IP="$2"
            shift 2
            ;;
        -l|--local)
            LOCAL_IP="$2"
            shift 2
            ;;
        -m|--mtu)
            MTU="$2"
            shift 2
            ;;
        -q|--queue)
            QUEUE="$2"
            shift 2
            ;;
        -n|--num-queues)
            NUM_QUEUES="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "ERROR: Unknown option '$1'"
            usage
            ;;
    esac
done

# Find interface using ionic driver
intf=$(ls -l /sys/class/net/*/device/driver 2>/dev/null | grep ionic | awk -F'/' '{print $5}')
if [ -z "$intf" ]; then
    echo "ERROR: No interface found with ionic driver"
    exit 1
fi
echo "Found ionic interface: $intf"

# Configure interface
ip addr add $LOCAL_IP/24 dev $intf 2>/dev/null || true
ip link set dev $intf up
ip link set dev $intf mtu $MTU
echo "Configured $intf with IP $LOCAL_IP, MTU $MTU"

# Build xdpsock command
CMD="./xdpsock -i $intf -q $QUEUE -N -z -F -B"

# Add num-queues if > 1
if [ "$NUM_QUEUES" -gt 1 ]; then
    CMD="$CMD -D $NUM_QUEUES"
fi

# Add mode-specific options
case "$MODE" in
    tx)
        # TX needs remote MAC for destination
        ping -c 1 -W 1 $REMOTE_IP > /dev/null 2>&1
        mac=$(ip neigh show $REMOTE_IP | awk '{print $5}')
        if [ -z "$mac" ] || [ "$mac" = "FAILED" ]; then
            echo "ERROR: Could not resolve MAC for $REMOTE_IP"
            echo "Make sure remote host is reachable and responds to ARP"
            exit 1
        fi
        echo "Resolved $REMOTE_IP -> $mac"
        CMD="$CMD -t --tx-dmac=$mac"
        ;;
    rx)
        CMD="$CMD -r"
        ;;
    l2fwd)
        CMD="$CMD -l"
        ;;
esac

echo "Running: $CMD"
exec $CMD
