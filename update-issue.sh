#!/bin/bash
# update-issue.sh
# Builds a colored login banner in /etc/issue showing:
# hostname (short + FQDN), OS, platform (32/64-bit), kernel, disk usage
# and network details (IPv4 + netmask, gateway, DNS) per interface.
#
# Usage:
#   sudo update-issue.sh               writes /etc/issue
#   update-issue.sh /tmp/preview.txt   writes to another file (for testing)
#
# ISSUE_WAIT=N  wait up to N seconds for a default route to appear.
#               Used by the systemd service at boot.

export LC_ALL=C.UTF-8
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

OUT="${1:-/etc/issue}"
W=76                 # inner width of the box
LW=14                # label column width
VW=$(( W - LW - 3 )) # value column width

# Colors (agetty passes ESC codes through to the console)
C=$'\e[1;36m'        # border (cyan)
D=$'\e[0;36m'        # dashed separator lines (dim cyan)
Y=$'\e[1;33m'        # labels (yellow)
G=$'\e[0;37m'        # values (light grey)
T=$'\e[1;37m'        # title (bold white)
N=$'\e[0m'           # reset

# ---------- helpers ----------
rep() { local s="" i; for (( i = 0; i < $2; i++ )); do s+="$1"; done; printf '%s' "$s"; }

hline() {            # hline LEFT FILL RIGHT
  printf '%s%s%s%s%s\n' "$C" "$1" "$(rep "$2" "$W")" "$3" "$N"
}

pad() {              # pad TEXT WIDTH (cuts/pads by characters, not bytes)
  local s=${1:0:$2}
  printf '%s%*s' "$s" $(( $2 - ${#s} )) ""
}

padl() {             # padl TEXT WIDTH (right-aligns the text)
  local s=${1:0:$2}
  printf '%*s%s' $(( $2 - ${#s} )) "" "$s"
}

row() {              # row LABEL VALUE  (label on the left, value right-aligned)
  printf '%s║%s %s%s%s %s%s%s %s║%s\n' \
    "$C" "$N" "$Y" "$(pad "$1" "$LW")" "$N" "$G" "$(padl "$2" "$VW")" "$N" "$C" "$N"
}

dash() {             # thin dashed line between rows; plain side borders (no T-junction stubs)
  printf '%s║%s %s %s║%s\n' "$C" "$D" "$(rep - $(( W - 2 )))" "$C" "$N"
}

center() {           # center TEXT
  local t=$1 l left right
  (( ${#t} > W - 2 )) && t=${t:0:W-2}
  l=${#t}; left=$(( (W - l) / 2 )); right=$(( W - l - left ))
  printf '%s║%s%*s%s%s%s%*s%s║%s\n' "$C" "$N" "$left" "" "$T" "$t" "$N" "$right" "" "$C" "$N"
}

prefix2mask() {      # 24 -> 255.255.255.0
  local p=$1 m="" i o
  for i in 1 2 3 4; do
    if   (( p >= 8 )); then o=255; p=$(( p - 8 ))
    elif (( p >  0 )); then o=$(( 256 - (1 << (8 - p)) )); p=0
    else o=0
    fi
    m+="${m:+.}$o"
  done
  printf '%s' "$m"
}

# ---------- wait for network (only when ISSUE_WAIT is set) ----------
waited=0
for (( i = 0; i < ${ISSUE_WAIT:-0}; i++ )); do
  if [ -n "$(ip route show default 2>/dev/null)" ]; then
    break
  fi
  sleep 1; waited=1
done
(( waited )) && sleep 2   # give DHCP/DNS a moment to finish

# ---------- data ----------
SHORT=$(hostname -s 2>/dev/null)
[ -n "$SHORT" ] || SHORT=$(hostname)

# Find the FQDN. "hostname -f" returns the first name on the matching /etc/hosts line,
# so it can return the short name when the line is "127.0.1.1 nebula nebula.test".
# In that case look at "hostname -a" (aliases) and at the /etc/hosts entry itself.
find_fqdn() {
  local cand c
  for cand in \
      "$(timeout 3 hostname -f 2>/dev/null)" \
      "$(timeout 3 hostname -a 2>/dev/null)" \
      "$(timeout 3 getent hosts "$SHORT" 2>/dev/null)"; do
    # prefer a name of the form SHORT.something
    for c in $cand; do
      [[ $c == "$SHORT".* ]] && { printf '%s' "$c"; return; }
    done
  done
  for cand in \
      "$(timeout 3 hostname -f 2>/dev/null)" \
      "$(timeout 3 hostname -a 2>/dev/null)"; do
    # otherwise accept any dotted name that is not an IP address
    for c in $cand; do
      [[ $c == *.* && ! $c =~ ^[0-9.]+$ && $c != localhost* ]] && { printf '%s' "$c"; return; }
    done
  done
}

FQDN=$(find_fqdn)
if [ -n "$FQDN" ] && [ "$FQDN" != "$SHORT" ]; then
  HOST="$SHORT (FQDN: $FQDN)"
else
  HOST=$SHORT                       # no FQDN configured: short name only
fi

OS=$( . /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-Linux}" )
[ -n "$OS" ] || OS=Linux

ARCH=$(uname -m)
BITS=$(getconf LONG_BIT 2>/dev/null)
case "$BITS" in 32|64) PLATFORM="${BITS}-bit ($ARCH)" ;; *) PLATFORM="$ARCH" ;; esac

KERNEL=$(uname -r)

size_h() {           # bytes -> "106 GiB" / "6.2 GiB" / "1.8 TiB"
  awk -v b="$1" 'BEGIN {
    g = b / 1073741824
    if      (g >= 1024) printf "%.1f TiB", g / 1024
    else if (g >=   10) printf "%.0f GiB", g
    else                printf "%.1f GiB", g }'
}

read -r DSIZE DAVAIL DPCT < <(df -B1 --output=size,avail,pcent / 2>/dev/null | tail -n 1)
DISK="$(size_h "$DAVAIL") free of $(size_h "$DSIZE") ($DPCT in use)"

# ---------- build the banner ----------
build() {
  echo
  hline ╔ ═ ╗
  center "$OS"
  hline ╠ ═ ╣
  row "Hostname"  "$HOST"
  dash
  row "Platform"  "$PLATFORM"
  dash
  row "Kernel"    "$KERNEL"
  dash
  row "Disk usage (/)" "$DISK"
  hline ║ ─ ║

  local ifaces first=1 IF a n n4 v4 gw4 dns d
  ifaces=$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $2}' | awk '!seen[$0]++')

  for IF in $ifaces; do
    IF=${IF%%@*}
    case $IF in lo|docker*|veth*|br-*|virbr*|lxcbr*|lxdbr*|cni*|flannel*|cali*) continue ;; esac

    (( first )) || hline ║ ─ ║
    first=0
    row "Interface" "$IF"
    dash

    # IPv4 addresses + netmask
    v4=$(ip -o -4 addr show dev "$IF" scope global 2>/dev/null | awk '{print $4}')
    n4=0
    for a in $v4; do
      row "$( (( n4 == 0 )) && echo IPv4 )" "$a  (netmask $(prefix2mask "${a#*/}"))"
      n4=$(( n4 + 1 ))
    done
    (( n4 )) || row "IPv4" "none"

    # Gateway
    dash
    gw4=$(ip -4 route show default dev "$IF" 2>/dev/null |
          awk '{for (i = 1; i < NF; i++) if ($i == "via") { print $(i+1); exit }}')
    row "Gateway" "${gw4:-none}"

    # DNS: this interface's own servers first, then systemd-resolved upstream servers
    dash
    dns=$(timeout 3 resolvectl dns "$IF" 2>/dev/null | sed 's/^[^:]*: *//')
    if [ -z "$dns" ]; then
      dns=$(awk '/^nameserver/ {print $2}' /run/systemd/resolve/resolv.conf 2>/dev/null | paste -sd' ')
    fi
    if [ -z "$dns" ]; then
      dns=$(awk '/^nameserver/ && $2 != "127.0.0.53" {print $2}' /etc/resolv.conf 2>/dev/null | paste -sd' ')
    fi
    n=0
    for d in $dns; do
      [[ $d == *:* ]] && continue      # IPv4 only: skip IPv6 DNS servers
      row "$( (( n == 0 )) && echo DNS )" "$d"
      n=$(( n + 1 ))
    done
    (( n )) || row "DNS" "none"
  done

  (( first )) && row "Network" "no IPv4 address assigned"

  hline ╚ ═ ╝
  echo
}

# ---------- write atomically so agetty never sees a half-written file ----------
TMP=$(mktemp "${OUT}.XXXXXX") || exit 1
build > "$TMP"
chmod 644 "$TMP"
mv -f "$TMP" "$OUT"
