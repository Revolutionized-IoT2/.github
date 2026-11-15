# Static LAN addresses

Applies to: a compose install whose services get addresses of their own on the LAN, on a QNAP NAS
(Container Station) or any Linux Docker host, with `deploy/compose.lan.yml`.

Without it, every service publishes its ports on the Docker host's address. That doesn't work when the
host needs those ports itself: a QNAP's web interface uses 80 and 8080. With `compose.lan.yml`, the
broker, UI, orchestrator and node each get an address on an external network that is bridged to the
LAN, and no ports are published.

| Service | Variable | Ports on its address |
|---|---|---|
| Broker | `RIOT2_LAN_IP_MQTT` | 1883 (MQTT), 9001 (WebSocket for browsers) |
| UI | `RIOT2_LAN_IP_UI` | 80 (UI 1.15.0; 8080 with an older image) |
| Orchestrator | `RIOT2_LAN_IP_ORCHESTRATOR` | 8080 |
| Node | `RIOT2_LAN_IP_NODE` | 80 |
| InfluxDB (`compose.lan.influx.yml`) | `RIOT2_LAN_IP_INFLUXDB` | 8086 |
| Grafana (both files below) | `RIOT2_LAN_IP_GRAFANA` | 3000 |
| OpenTelemetry Collector (`compose.lan.observability.yml`) | `RIOT2_LAN_IP_OTEL` | 4317 |
| Prometheus (`compose.lan.observability.yml`) | `RIOT2_LAN_IP_PROMETHEUS` | 9090 |

The connectors, the Prometheus exporter and `cloudflared` only connect outwards: they stay on the
project's default network. So does the remote workflow host (`elsa`), with its ports on `RIOT2_HOST`.
Every service also stays on the default network, where they find each other by name.

## Before you start

- Pick free addresses outside the router's DHCP pool, or reserve them in the router. Give the Raspberry
  Pi and ESP32 nodes fixed addresses too: the orchestrator calls the node URLs they announce.
- RIoT2 has no login while the security mode is off ([security.md](security.md)). Anyone on this LAN
  can use the API and read the broker password from the UI. A separate IoT network (VLAN) for these
  addresses limits that; decide before the nodes are set up, because they store the broker's address.
- On a macvlan network, and usually on qnet, the Docker host can't reach these addresses itself. Open
  them from another machine. The installer reaches the orchestrator through the default network.

## The network

The network belongs to the host, not to the compose project: `docker compose down --volumes` keeps it.
`install.sh` creates it when it's missing, from `site.conf` ([site-configuration.md](site-configuration.md)):

```text
LAN_DRIVER=qnet           # or macvlan
LAN_PARENT=eth0           # qnet: the physical port, not br0; macvlan: the LAN interface (ip -br addr)
LAN_SUBNET=192.168.1.0/24
LAN_GATEWAY=192.168.1.1
LAN_IP_RANGE=             # macvlan only: addresses Docker may hand out itself, the spare ones
LAN_IPV6_SUBNET=          # for Matter: the LAN's /64 prefix, or a unique local one
```

By hand, the same network is:

```bash
# QNAP Container Station: the qnet driver needs QNAP's IPAM driver too, and takes no --ip-range
docker network create -d qnet --opt iface=eth0 --ipam-driver qnet --ipam-opt iface=eth0 --subnet 192.168.1.0/24 --gateway 192.168.1.1 riot2-lan
# Other Linux hosts
docker network create -d macvlan --opt parent=eth0 --subnet 192.168.1.0/24 --gateway 192.168.1.1 --ip-range 192.168.1.38/31 riot2-lan
```

- Without the qnet IPAM driver, containers don't start: "cannot find IPAM config by mac address". The
  installer makes such a network again when no container runs on it.
- The networks Container Station made show the port to use: `docker network inspect` one with the
  `qnet` driver and look at `iface`.
- Add `--ipv6 --subnet <prefix>/64` for IPv6 (macvlan; qnet isn't known to support it). Check the
  network before installing: a test container must get its address, and other machines must reach it.

```bash
docker run --rm --network riot2-lan --ip 192.168.1.39 alpine sh -c 'ip addr; ping -c 3 192.168.1.1; wget -qO- https://example.com > /dev/null && echo internet ok'
```

## Compose files and settings

In `deploy/.env` (the site's `hosts/<host>/deploy.env`):

```text
COMPOSE_PATH_SEPARATOR=:
COMPOSE_FILE=docker-compose.yml:compose.influx.yml:compose.observability.yml:compose.lan.yml:compose.lan.influx.yml:compose.lan.observability.yml
COMPOSE_PROFILES=node
RIOT2_HOST=<the NAS's own address>
RIOT2_LAN_IP_MQTT=192.168.1.30
RIOT2_LAN_IP_UI=192.168.1.31
...
```

- `RIOT2_HOST` is still required, but compose builds the orchestrator's and node's URLs and the UI's
  broker address from the LAN addresses.
- With the observability files, keep `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` for the
  services on this host.
- Don't add `compose.matter.yml`, whose host network replaces these addresses. The Matter bridge
  advertises itself on the orchestrator's interfaces, the LAN address among them. Create the network with
  IPv6 (macvlan; qnet isn't known to support it), and check that a Matter controller finds the bridge
  before you rely on it.
- The UI listens on port 80 from UI 1.15.0 (`RIOT2_UI_PORT`, with the sysctl
  `net.ipv4.ip_unprivileged_port_start`); an older UI image stays on 8080.

## QNAP Container Station

- Enable SSH (Control Panel, Network & File Services, Telnet / SSH) and log in as an administrator.
  `install.sh` finds Container Station's `docker` by itself when it's not on `PATH`.
- QTS resets the home folder and `PATH` when it restarts: keep the RIoT2 files on a share, for example
  `/share/Container/riot2/`, and run the installer by its full path.
- QTS has no `git`. Copy the repositories to the share from a PC, or clone them with
  `docker run --rm -v /share/Container/riot2:/git alpine/git clone <url> <folder>`.
- From a Windows PC: clone the RIoT2 files into the share (`\\<NAS>\Container\riot2`), keep the site
  folder on the PC, and install from there ([site-configuration.md](site-configuration.md#install-from-a-pc)):

  ```powershell
  ./install.ps1 -Site <site> -HostName qnap -RemoteHost admin@<NAS> -RemoteDeploy /share/Container/riot2/.github/deploy
  ```

  It runs `install.sh` with `bash`, because a checkout on an SMB share has no executable bits. QTS's
  bash is 3.2, which the scripts support. Connect once with `ssh admin@<NAS>` first, to accept the
  NAS's key. A firmware update or reset can change that key: then `ssh` refuses with "remote host
  identification has changed", and `ssh-keygen -R <NAS>` removes the old one.
- Projects started from the command line appear in Container Station. Manage them with the installer,
  `docker compose` and the backup scripts, not from Container Station's own settings.
- QTS's own web server keeps ports 80, 443 and 8080 on the NAS's address; the services' own addresses
  don't conflict with it.

## Other nodes

- **Raspberry Pi** ([deployment.md](deployment.md#raspberry-pi-node)): in its `.env` (the site's
  `hosts/raspi/deploy.env`), `RIOT2_MQTT_IP` is the broker's LAN address and
  `OTEL_EXPORTER_OTLP_ENDPOINT` is `http://<collector address>:4317`. Install it with
  `install.sh --host raspi` on the Pi.
- **ESP32 nodes** ([deployment.md](deployment.md#esp32-nodes-m5stack-core2-m5dial)): enter the broker's LAN
  address as the MQTT URL in the setup portal, and keep the values in the site's `firmware/` record.
