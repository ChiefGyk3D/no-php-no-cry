---
title: "Lab Notes: Prox & Recreation Dress Rehearsal"
date: 2026-11-17T12:00:00-05:00
draft: true
description: "Notes from the first full rehearsal of my Proxmox toolkit on a spare laptop: the installer placeholder address, the first-boot repair, the LDAP realm bootstrap, and what is still open."
slug: "prox-and-recreation-dress-rehearsal"
categories: ["Journal"]
tags: ["proxmox", "homelab", "automation", "ldap"]
syndicate: false
---

The first fresh install came up at 192.168.100.2/24, with 192.168.100.1 as its gateway. Neither network existed anywhere in the lab.

<!--more-->

The Proxmox installer had taken its network snapshot while no default route was available. Instead of reporting that it could not determine the network configuration, it silently wrote its hardcoded placeholder as a static configuration. The resulting Proxmox VE 9.2.2 node booted normally, just on a subnet I did not have.

This was the first full dress rehearsal for Prox & Recreation, a pun and homage to a favorite TV show. The project is a toolkit for taking a fresh Proxmox VE installation from one box through a multi-node cluster, aimed at environments ranging from a homelab to a small enterprise. The production target is seven Lanner NCA-1515 boxes, but those are not built yet. Today’s work happened on a spare laptop with wired Ethernet, UEFI, and one 167.7 GB SATA SSD, isolated behind a pfSense firewall on a dedicated virtualization VLAN.

I prepared a Proxmox ISO with `proxmox-auto-install-assistant prepare-iso`, an answer file, and a first-boot hook. The answer file selects the SATA disk using the udev filter `ID_BUS=ata` and selects the network interface using `ID_NET_NAME`.

The larger change was moving node-specific installation data into one TOML inventory. The build tool now generates an answer file, password hashes, and a credentials file for each node. It can also generate the prepared ISO. Static addressing comes from the answer file, so the install no longer depends on DHCP being available when the installer takes its snapshot.

The credentials file is created with mode 600 and is never printed. Every node receives unique root and break-glass passphrases. Only their SHA-512 hashes, produced with `mkpasswd`, go into answer files.

I also finished the passphrase generator. It supports two through six words from the EFF large, short, or silly lists, with optional capitalization, leetspeak, digits, and additional entropy. The default is five words from the EFF large list. With 7,776 possible words, that is about 12.925 bits per word, or 64.6 bits total. Three words would only provide about 38.8 bits, so the tool refuses configurations under 64 bits unless I explicitly force them.

The inventory tool and passphrase generator have 77 tests between them. Today also produced a useful reminder about trusting vendor validation tools: `validate-answer` exits with status 0 even when it reports errors. The build now checks its output for the text indicating that no errors were found. I also verified that `dns` must be one string rather than a list, `Etc/UTC` is rejected in favor of `UTC`, and unknown answer-file keys are rejected.

The first-boot network repair needed more work once it reached real hardware. Its job is intentionally narrow. It detects the exact Proxmox placeholder stanza, requests DHCP once, then rewrites only the address and gateway lines for `vmbr0` and the hostname line in `/etc/hosts`. It makes backups, reloads the network once, and continues even if the repair fails. A failure leaves a marker file for later inspection.

My first design ran a private `dhclient` with its files under `/tmp`. That passed every stubbed test and failed on the laptop. AppArmor restricted `dhclient` to specific paths and refused to execute any script except its own. The attempt also left a stray daemonized process behind. Separately, I found that using `ip addr flush` in this path was dangerous. Moving the lease and PID files into the permitted `/run` paths, removing the flush, and tightening process handling fixed the hardware run. A stub proved that the code matched my assumptions. It did not prove that my assumptions matched the device.

After reinstalling, I performed the second-pass verification read-only. The static address was active on a bridge over the wired interface. The hostname and `/etc/hosts` entry were correct. The break-glass account and CA chain installed by first boot were present. The repair log said the configuration was not the placeholder and did nothing. All four Proxmox services were active, LDAPS and the package mirror were reachable, and root login using the hardware key worked.

That last check corrected another assumption. An earlier SSH command omitted `-i`, so SSH silently selected a default software key. I had thought I was testing the hardware key when I was not. The verification now pins the key and uses `IdentitiesOnly`. I am no longer claiming which credential was used unless the command provides evidence.

Next I bootstrapped the JumpCloud LDAP realm. There is one directory, a bind account, and two groups, one for administrators and one for limited VM users. The script creates the Proxmox realm over LDAPS on port 636 with the CA chain verified. It sets the user and group filters, reads the bind password from standard input, performs a dry-run sync before applying the real sync, creates a pool, creates two custom roles, installs six per-path grants, and schedules synchronization every 30 minutes.

The directory bootstrap has 57 tests. Check mode is read-only, and a second check reported zero differences. I had to compare parsed sync-default pairs because Proxmox sorts the keys. Comparing the raw string created permanent fake drift. I also confirmed that `pvesh set` requires the schedule on every sync-job update and merges values instead of clearing them.

A security review found a more serious sync problem. I had treated dry-run lines containing “updating” as harmless, which could skip the real sync. Those lines can represent group-membership changes, including a revoked member who should lose access. Unknown dry-run output now counts as a change and stops for review, while `--apply` always performs the real synchronization.

Earlier, on the hand-built rehearsal node before the wipe, the limited VM-users group built a VM through the actual Create VM wizard. That required five per-path grants covering the pool, storage, ISO storage, SDN zone, and node audit. The wizard returns HTTP 200 even when it refuses the operation, and missing `Pool.Audit` or `Sys.Audit` produced silent failures, so testing the real wizard was necessary.

The reinstall also exposed a bug hidden by the hand-built node. On a fresh installation, `/etc/pve/priv/realm` does not exist until a realm password exists. The bootstrap assumed the directory was already present. I created it manually tonight, and the proper fix remains tracked.

Still open: the seven production nodes are not built, and the disk and NIC presets remain unverified on the Lanner hardware. Serial-console and BMC details are pending a serial cable. The answer server, cluster formation, guided wizard, possible low-priority FreeIPA failover, Active Directory realms, and the NTP firewall rule also remain open. NTP over UDP 123 is currently blocked from the virtualization VLAN, so chrony has no source. The clock is right today because of the hardware clock, but LDAPS certificate validation cannot depend on that luck.
