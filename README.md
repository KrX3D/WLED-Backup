# WLED Backup Docker

A lightweight container that automatically discovers every WLED device on your LAN (via mDNS/Avahi) and pulls down both `cfg.json` and `presets.json` for safe-keeping.

**Inspired by Michael Bisbjerg’s excellent bash tutorial:**  
https://blog.mbwarez.dk/posts/2025/03/wled-backup-script/  

---

## Contents

- [Introduction](#introduction)  
- [Requirements](#requirements)  
- [Enabling mDNS in WLED](#enabling-mdns-in-wled)  
- [Usage](#usage)  
  - [Docker CLI](#docker-cli)  
  - [Script Details](#script-details)  
- [Scheduling Backups](#scheduling-backups)  
- [CI & Unraid Packaging](#ci--unraid-packaging)  
- [Credits & License](#credits--license)  

---

## Introduction

WLED (https://kno.wled.ge) is an open-source Wi-Fi controller for addressable LEDs. Managing multiple devices means you’ll want an automated way to back up each device’s settings. This container wraps Michael Bisbjerg’s bash scripts into Docker, letting you:

- Discover all WLED instances via mDNS  
- Fetch and store `cfg.json` and `presets.json` per device  
- Mount a host folder for easy access to your backup snapshots  

---

## Requirements

- **WLED devices** with mDNS enabled  
- **Docker** on your backup host  
- Host-mounted **backup volume** (e.g. `/path/to/backups`)  
- (Optional) `jq` inside the container for pretty JSON  

---

## Enabling mDNS in WLED

In the WLED web UI, go to:

```text
Config → WiFi Setup → mDNS Name
```

Set a unique name (e.g. wled-stairs) so wled-stairs.local becomes discoverable.

---

## Usage

### Docker CLI

```bash
docker run --rm \
  --network=host \
  -v /path/to/backups:/backups \
  ghcr.io/krx3d/wled-backup:latest
```

**Notes**
- mDNS discovery requires host networking (`--network=host`) so Avahi can see your LAN.
- Backups are organized by timestamp under `/backups` (see [Script Details](#script-details)).

### Script Details

The container runs `backup-discover.sh`, which:
1) Discovers WLED devices via mDNS  
2) Adds any `EXTRA_HOSTS` you specify  
3) Backs up JSON endpoints to a timestamped folder  
4) Prunes old runs based on `RETENTION_DAYS`  

#### Environment variables

| Variable | Default | Description |
|---|---|---|
| `BACKUP_ROOT` | `/backups` | Root folder for backup runs. |
| `RETENTION_DAYS` | `30` | Keep runs for N days before pruning. |
| `EXTRA_HOSTS` | *(empty)* | Comma-separated hostnames/IPs to back up in addition to mDNS results. |
| `ENDPOINTS` | *(empty)* | Overrides default endpoints. Comma-separated list (e.g. `cfg,presets,state`). |
| `ADDITIONAL_ENDPOINTS` | *(empty)* | Appended to `ENDPOINTS` or defaults (e.g. `info,eff,pal`). |
| `PROTOCOLS` | `http,https` | Protocol order to try for each endpoint. |
| `SKIP_TLS_VERIFY` | `false` | Set to `true` to allow HTTPS with self-signed certs. |
| `OFFLINE_OK` | `true` | When `true`, skips devices that do not respond to `cfg.json` and continues. |
| `LOG_TO_FILE` | `false` | When `true`, write a timestamped log to `<BACKUP_ROOT>/<timestamp>.log`. |

**Default endpoints:** `cfg`, `presets`, and `state`.  

**Common additional endpoints:** `info`, `si`, `nodes`, `eff`, `palx`, `fxdata`, `net`, `live`, `pal`.  
> Note: endpoint availability can vary by WLED version. Use `ENDPOINTS` or `ADDITIONAL_ENDPOINTS` to tune what you need.

---

## Scheduling Backups

Common options:
- **Unraid**: use the User Scripts plugin to schedule a Docker run on a timer.
- **Docker host**: run via `cron` or a systemd timer.

Example cron entry (runs daily at 2am):
```cron
0 2 * * * docker run --rm --network=host -v /path/to/backups:/backups ghcr.io/krx3d/wled-backup:latest
```

---

## CI & Unraid Packaging

GitHub Actions builds and pushes the container on `main` and version tags. See `.github/workflows/ci.yml`.

### Unraid User Scripts (example)

If you start a pre-configured container from Unraid, this script provides a clearer log message and verifies the container exists before starting:

```bash
#!/bin/bash
DOCKER_CONTAINER="wled-backup"

if ! docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
  echo "Container '${DOCKER_CONTAINER}' not found. Create it first in Unraid."
  exit 1
fi

echo "Starting WLED backup container..."
docker start "${DOCKER_CONTAINER}"
```

### Unraid Template XML (example)

This template example generalizes IP/MAC and adds an icon placeholder. Adjust paths and variables to your environment.

```xml
<?xml version="1.0"?>
<Container version="2">
  <Name>wled-backup</Name>
  <Repository>ghcr.io/krx3d/wled-backup:latest</Repository>
  <Registry/>
  <Network>br0</Network>
  <MyIP>YOUR.IP.ADDR.HERE</MyIP>
  <Shell>bash</Shell>
  <Privileged>true</Privileged>
  <Support/>
  <Project/>
  <Overview>&#13;
  -e ENDPOINTS="cfg,presets,state,info,si,nodes,eff,palx,fxdata,net,live,pal" </Overview>
  <Category/>
  <WebUI/>
  <TemplateURL/>
  <Icon>https://raw.githubusercontent.com/Aircoookie/WLED/master/wled00/data/favicon-192x192.png</Icon>
  <ExtraParams>--mac-address YOUR:MAC:OPTIONAL</ExtraParams>
  <PostArgs/>
  <CPUset/>
  <DateInstalled>0</DateInstalled>
  <DonateText/>
  <DonateLink/>
  <Requires/>
  <Config Name="backups" Target="/backups" Default="/mnt/user/backup/wled/" Mode="rw" Description="" Type="Path" Display="always" Required="false" Mask="false">/mnt/user/backup/wled/</Config>
  <Config Name="EXTRA_HOSTS" Target="EXTRA_HOSTS" Default="" Mode="" Description="" Type="Variable" Display="always" Required="false" Mask="false">deskbar.lan,example.lan</Config>
  <Config Name="RETENTION_DAYS" Target="RETENTION_DAYS" Default="7" Mode="" Description="" Type="Variable" Display="always" Required="false" Mask="false">14</Config>
  <Config Name="PROTOCOLS" Target="PROTOCOLS" Default="http,https" Mode="" Description="" Type="Variable" Display="always" Required="false" Mask="false">http,https</Config>
  <Config Name="SKIP_TLS_VERIFY" Target="SKIP_TLS_VERIFY" Default="true" Mode="" Description="" Type="Variable" Display="always" Required="false" Mask="false">true</Config>
  <Config Name="OFFLINE_OK" Target="OFFLINE_OK" Default="true" Mode="" Description="" Type="Variable" Display="always" Required="false" Mask="false">true</Config>
  <Config Name="LOG_TO_FILE" Target="LOG_TO_FILE" Default="false" Mode="" Description="" Type="Variable" Display="always" Required="false" Mask="false">false</Config>
  <Config Name="ENDPOINTS" Target="ENDPOINTS" Default="cfg,presets,state,info,si,nodes,eff,palx,fxdata,net,live,pal" Mode="" Description="" Type="Variable" Display="always" Required="false" Mask="false">cfg,presets,state,info,si,nodes,eff,palx,fxdata,net,pal</Config>
  <TailscaleStateDir/>
</Container>
```

---

## Ideas for Future Enhancements

If you want to expand backups later, consider:
- `json/info` (device info)
- `json/eff` (effect list)
- `json/pal` (palette list)
- `json/nodes` (sync node list)
- `json/state` segments (already included by default)

---

## Credits & License

See [LICENSE](LICENSE) for usage terms.
