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


