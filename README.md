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
  ghcr.io/<your-org>/wled-backup:latest
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

**Default endpoints:** `cfg`, `presets`, and `state`.  

---

## Scheduling Backups

Common options:
- **Unraid**: use the User Scripts plugin to schedule a Docker run on a timer.
- **Docker host**: run via `cron` or a systemd timer.

Example cron entry (runs daily at 2am):
```cron
0 2 * * * docker run --rm --network=host -v /path/to/backups:/backups ghcr.io/<your-org>/wled-backup:latest
```

---

## CI & Unraid Packaging

GitHub Actions builds and pushes the container on `main` and version tags. See `.github/workflows/ci.yml`.

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

