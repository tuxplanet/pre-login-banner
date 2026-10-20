# Pre-Login Banner for Ubuntu Server

A small set of scripts that replaces the plain pre-login text on the server console
(`/etc/issue`) with a colored, boxed banner showing live host information. The banner is
rebuilt on every boot, so the data on the login screen is always current.

Developed for **Ubuntu Server** and tested on **Ubuntu Server 26.04.1 LTS**. It uses only standard tools, so it should work
on other recent Ubuntu/Debian systems that use systemd.

## What it looks like

```
╔════════════════════════════════════════════════════════════════════════════╗
║                             Ubuntu 26.04.1 LTS                             ║
╠════════════════════════════════════════════════════════════════════════════╣
║ Hostname                                        myhost (FQDN: myhost.test) ║
║ -------------------------------------------------------------------------- ║
║ Platform                                                   64-bit (x86_64) ║
║ -------------------------------------------------------------------------- ║
║ Kernel                                                    7.0.0-38-generic ║
║ -------------------------------------------------------------------------- ║
║ Disk usage (/)                         140 GiB free of 155 GiB (5% in use) ║
║────────────────────────────────────────────────────────────────────────────║
║ Interface                                                           enp0s3 ║
║ -------------------------------------------------------------------------- ║
║ IPv4                                                          10.0.2.15/24 ║
║ IPv6                                                      2001:db8:1::5/64 ║
║ -------------------------------------------------------------------------- ║
║ Gateway (IPv4)                                                    10.0.2.2 ║
║ Gateway (IPv6)                                                     fe80::1 ║
║ -------------------------------------------------------------------------- ║
║ DNS                                                               10.0.2.3 ║
╚════════════════════════════════════════════════════════════════════════════╝

myhost login:
```

(Colors are not shown here: cyan frame, yellow labels, light grey values, white title.)

## What it shows

| Field | Source / notes |
|---|---|
| Title | OS name and version from `/etc/os-release` (`PRETTY_NAME`), centered |
| Hostname | Short name plus FQDN, e.g. `myhost (FQDN: myhost.test)`. If no FQDN is configured, only the short name is shown |
| Platform | 32- or 64-bit (`getconf LONG_BIT`) and CPU architecture (`uname -m`) |
| Kernel | `uname -r` |
| Disk usage (/) | Free space, total size and percentage in use of the root filesystem, in GiB/TiB (1024-based). The percentage comes from `df`, so it matches `df -h /` |
| Interface | Every interface with a global IPv4 or IPv6 address |
| IPv4 | Address in CIDR notation, e.g. `10.0.2.15/24`. Several addresses on one interface are listed one under another. `none` if absent |
| IPv6 | Global address in CIDR notation, e.g. `2001:db8:1::5/64`. Temporary privacy and deprecated addresses are skipped. `none` if absent |
| Gateway (IPv4) | Default IPv4 gateway of that interface (`none` if there is no default route on it) |
| Gateway (IPv6) | Default IPv6 gateway of that interface, often a link-local address such as `fe80::1` (`none` if there is no default route) |
| DNS | DNS servers of that interface, one per line |

Notes:

- The DNS list shows IPv4 DNS servers only; IPv6 DNS servers are skipped.
- These interfaces are skipped: `lo`, `docker*`, `veth*`, `br-*`, `virbr*`, `lxcbr*`, `lxdbr*`, `cni*`, `flannel*`, `cali*`.
- If no interface has an IPv4 address, the banner shows `Network: no IP address assigned`.

## Files

| File | Installed to | Permissions | Executable |
|---|---|---|---|
| `update-issue.sh` | `/usr/local/sbin/update-issue.sh` | `0755` (`rwxr-xr-x`), root | Yes |
| `update-issue.service` | `/etc/systemd/system/update-issue.service` | `0644` (`rw-r--r--`), root | No |
| `install.sh` | stays where you downloaded it | any | Not needed (run with `sudo bash install.sh`) |
| `README.md` | - | - | - |

`/etc/issue` itself must stay world-readable (`0644`); the script sets this.

## Installation

Put the three files (`install.sh`, `update-issue.sh`, `update-issue.service`) in the same
directory and run:

```bash
sudo bash install.sh
```

The installer:

1. copies the script to `/usr/local/sbin/` and the unit to `/etc/systemd/system/`,
2. saves the original `/etc/issue` as `/etc/issue.orig` (only the first time),
3. runs `systemctl daemon-reload` and `systemctl enable update-issue.service`,
4. builds the banner immediately.

To see the new banner, log out of the console (`exit`) or switch consoles (`Alt+F2`, then `Alt+F1`).
The installer does not restart the getty, so it never logs out a user who is working on tty1.

### Manual installation

```bash
sudo install -m 0755 update-issue.sh /usr/local/sbin/update-issue.sh
sudo install -m 0644 update-issue.service /etc/systemd/system/update-issue.service
sudo cp -a /etc/issue /etc/issue.orig
sudo systemctl daemon-reload
sudo systemctl enable update-issue.service
sudo update-issue.sh
```

## How it works

- `update-issue.sh` gathers the data, builds the banner and writes it to `/etc/issue`.
  It writes to a temporary file first and then moves it into place, so `agetty` never
  reads a half-written file.
- `update-issue.service` is a `oneshot` unit enabled in `multi-user.target`. It runs on
  every boot **before** `getty@tty1.service` (and `serial-getty@ttyS0.service`), so the
  banner is up to date when the login prompt appears.
- The service sets `ISSUE_WAIT=20`: the script waits up to 20 seconds for a default
  route, IPv4 or IPv6 (plus 2 seconds for DHCP/DNS to settle). On a server without a network this delays
  the login prompt by at most that long. `TimeoutStartSec=60` is the hard limit.
- The colors are plain ANSI escape codes. `agetty` passes them to the console unchanged.
  The banner contains no backslashes, so `agetty` does not try to expand anything in it.

### Hostname and FQDN detection

`hostname -f` returns the first name on the matching `/etc/hosts` line, so with a line like

```
127.0.1.1   myhost myhost.test
```

it returns only `myhost`. The script therefore tries, in order:

1. `hostname -f`
2. `hostname -a` (aliases)
3. the `/etc/hosts` entry (`getent hosts <short name>`)

and prefers a name of the form `<short name>.<domain>`. If none is found, only the short name
is shown. To make the FQDN appear:

```bash
sudo hostnamectl set-hostname myhost
sudo nano /etc/hosts        # add:  10.0.2.15   myhost.test myhost
hostname -f                 # should print myhost.test
sudo update-issue.sh
```

If the hostname reverts after a reboot on a cloud-init system, add `preserve_hostname: true`
to a file in `/etc/cloud/cloud.cfg.d/`.

### DNS detection

1. `resolvectl dns <interface>` (the servers systemd-resolved uses for that interface),
2. otherwise the upstream servers in `/run/systemd/resolve/resolv.conf`,
3. otherwise the `nameserver` lines in `/etc/resolv.conf` (the local stub `127.0.0.53` is ignored).

IPv6 DNS servers are skipped.

## Usage

Refresh the banner by hand (for example after changing the IP address):

```bash
sudo update-issue.sh
```

Preview the banner without touching `/etc/issue`:

```bash
update-issue.sh /tmp/banner-preview.txt
cat /tmp/banner-preview.txt
```

Check that the service is enabled and ran at boot:

```bash
systemctl is-enabled update-issue.service
systemctl status update-issue.service
journalctl -u update-issue.service -b
```

## Customization

Edit `/usr/local/sbin/update-issue.sh` and run `sudo update-issue.sh` to apply.

| Setting | Where | Meaning |
|---|---|---|
| `W=76` | top of the script | Inner width of the box. The total width is `W + 2` = 78 columns, which fits a standard 80-column console |
| `LW=14` | top of the script | Width of the label column |
| `C`, `D`, `Y`, `G`, `T` | top of the script | ANSI colors: frame, dashed lines, labels, values, title |
| `ISSUE_WAIT=20` | `update-issue.service` | Seconds to wait for the network at boot. Set to `0` to never wait |
| interface filter | the `case $IF in ...` line in `build()` | Interface name patterns to hide |

After editing the service file run `sudo systemctl daemon-reload`.

## Troubleshooting

**The banner did not change after running the script**

`agetty` reads `/etc/issue` only when it shows the prompt. Log out, or switch consoles
(`Alt+F2`, `Alt+F1`). If you are at the login prompt and not logged in, you can run
`sudo systemctl restart getty@tty1`. Do not do this while someone is logged in on tty1:
it ends that session.

**Check what is actually in the file**

```bash
cat -v /etc/issue | head -5
```

You should see color codes (`^[[1;36m`) followed by the box characters.

**The banner shows on the console but not over SSH**

That is expected. `/etc/issue` is only used by local console logins. For SSH, either point
`Banner` in `sshd_config` at a copy of the text, or use a script in `/etc/update-motd.d/`
(shown after login).

**The frame looks broken or shows odd symbols**

The console font or locale cannot display the box-drawing characters. Run
`sudo dpkg-reconfigure console-setup` and choose a UTF-8 character set. On a serial console
or a very basic remote console, replace the box characters (`═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ─`) in the script
with plain ASCII (`= | +`).

**The Network section is empty or `Gateway (IPv4)`/`Gateway (IPv6)`/`DNS` show `none` after boot**

The network was not ready within `ISSUE_WAIT` seconds (for example a slow DHCP server).
Run `sudo update-issue.sh` once the network is up, or increase `ISSUE_WAIT` in the service file.

**The hostname is overwritten at every boot**

See "Hostname and FQDN detection" above (cloud-init `preserve_hostname`) and check that
`hostnamectl` shows the static hostname you set.

## Uninstall

```bash
sudo systemctl disable --now update-issue.service
sudo rm -f /etc/systemd/system/update-issue.service /usr/local/sbin/update-issue.sh
sudo systemctl daemon-reload
sudo cp /etc/issue.orig /etc/issue     # restore the original login text
```

## Requirements

- systemd (Ubuntu Server 24.04+)
- Standard tools: `bash` 4+, `ip` (iproute2), `awk`, `sed`, `df`, `hostname`, `getconf`, `timeout`
- Optional: `resolvectl` (systemd-resolved) for per-interface DNS servers
