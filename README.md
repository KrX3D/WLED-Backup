# WLED Backup Docker

A lightweight container that automatically discovers every WLED device on your network (using mDNS/Avahi) and pulls down both cfg.json and presets.json for safe-keeping.

• Zero configuration — just mount a backup volume and run in host networking mode.
• Fully automated — script discovers devices and snapshots settings.

Ideal for home-automation enthusiasts who want regular, hands-off backups of their LED controller configs.
