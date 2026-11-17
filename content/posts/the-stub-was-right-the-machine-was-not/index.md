---
title: "The Stub Was Right, the Machine Was Not"
date: 2026-11-17T12:00:00-05:00
draft: false
description: "A laptop rehearsal found a silent installer placeholder, a repair step that passed its stubs and failed on real hardware, and a validator that lies."
slug: "the-stub-was-right-the-machine-was-not"
categories: ["Open Source"]
tags: ["proxmox", "homelab", "automation", "testing", "identity"]
syndicate: false
image: "featured.webp"
imageAlt: "AI-generated dark illustration of a workbench with a spare laptop and a cardboard cutout beside seven rack-mount servers on a shelf on the left, and a cartoon penguin mascot holding a rifle on the right."
build:
  publishResources: false
---

The Proxmox installer gave me a perfectly valid static address on a network that did not exist.

<!--more-->

I was running the first complete dress rehearsal for Prox & Recreation, my toolkit for taking fresh Proxmox VE installations from one box to a multi-node cluster. The name is a pun and a homage to a favorite TV show. The goal is that the operator should have to assign, at most, a hostname and, where the firewall does not provide DHCP reservations, an address and the basic network settings.

The production target is seven Lanner NCA-1515 appliances. Those systems are still to come. They use Intel Atom C3000-class processors and have several GbE ports, LOM, serial console, eMMC, and M.2 or 2.5-inch storage options. One was installed by hand earlier, but I still need a serial cable before I can collect the hardware command output. The exact BMC protocol is also unverified.

This work happened on a spare laptop: wired Ethernet, UEFI, one 167.7 GB SATA SSD, and Proxmox VE 9.2.2. It sat on a dedicated virtualization VLAN behind a pfSense firewall. That laptop was not a rough approximation of testing. It was where I intended to find all the assumptions that looked reasonable in code and fell apart when Linux, firmware, security policy, and an actual network got involved.

For every domain shown here, `chiefgyk3d.com` is a stand-in. I did not use that domain for this lab. The real lab runs on a separate domain I own. Using a subdomain of a primary domain may not provide enough isolation, and using an entirely separate domain can make sense. I chose a separate domain for a bit of separation. I am more public than most people running a homelab, and a second domain reduces the potential blast radius. You do not need to do this, but many companies run multiple domains to split things out for exactly that kind of reason.

## A Silent Static Placeholder

The first prepared ISO installed successfully. The system rebooted and came up at 192.168.100.2/24 with a gateway of 192.168.100.1.

Those values were not in my inventory, DHCP configuration, pfSense firewall, or dedicated virtualization VLAN. They came from the Proxmox installer itself.

When the installer snapshots its network state without a default route, it writes that placeholder address and gateway into the installed system as a static configuration. It does this silently. There was no visible failure saying that network discovery was incomplete, and the installed node behaved as though somebody had intentionally configured an unreachable subnet.

That behavior changed the installation design. I had originally expected the installer to carry through the address it had received during boot. Instead, the single TOML inventory now generates a per-node answer file with static network settings. It also generates password hashes, a mode 600 credentials file, and optionally the prepared ISO. The installation no longer depends on DHCP being available at the exact moment the installer takes its snapshot.

I still kept a first-boot repair path, but made it deliberately conservative. It detects the exact placeholder stanza, requests DHCP once, and changes only the address and gateway lines for `vmbr0` plus the hostname line in `/etc/hosts`. It creates backups and reloads the network once. If anything fails, it leaves a marker and continues booting.

I did not want a generic network fixer wandering through a new hypervisor. I wanted one specific workaround for one observed installer failure.

## Stubs Only Prove the Stubbed World

The repair step passed its tests. Then it failed on the laptop.

The first design ran a private `dhclient` instance with its lease and PID files under `/tmp`. In the test environment, that was tidy and isolated. On the real Proxmox node, AppArmor confined `dhclient` to specific paths and refused to execute any script except its own. One attempt also left a daemonized process behind.

The design included an `ip addr flush`, too. That looked like a convenient way to remove the bad address before applying the good one. On a remote system, especially one whose management path runs through the interface being modified, flushing addresses casually is a good way to turn a repair into an outage.

I moved the lease and PID files to permitted locations under `/run`, removed the flush, and fixed the process handling. The real machine then behaved.

The lesson was not that stubs are useless. I still want them, and the inventory tool and passphrase generator have 77 tests between them. The stub confirmed that the repair code responded correctly to the conditions I modeled. It could not tell me that AppArmor rejected the file layout, that `dhclient` imposed script restrictions, or that a process would escape the lifecycle I expected.

Hardware-facing work needs an early hardware pass. Waiting until the code looks finished only concentrates all the wrong assumptions at the end.

## Validation That Exits Successfully on Failure

`proxmox-auto-install-assistant validate-answer` returns exit status 0 even when its output reports errors.

That is simply wrong behavior for a validator used from automation. A shell script has every reason to interpret zero as success. Mine did until I checked what the tool actually printed.

The build now looks for the validator’s explicit “no errors found” text instead of trusting the process status. I also verified several answer-file details instead of relying on plausible-looking TOML: `dns` must be a single string, not a list; `Etc/UTC` is rejected while `UTC` is accepted; and unknown keys are rejected.

Disk selection had a similar wording problem. The question is not whether the Proxmox installer uses the whole selected disk. It does. The important question is which disk it selects.

The tool offers `sata`, `nvme`, and custom presets. The SATA preset uses `ID_BUS=ata`, while the NIC selection uses `ID_NET_NAME`. There is intentionally no “any non-USB disk” preset. I could not express that safely without also allowing the installer to select an 8 GB eMMC device or another disk that happened not to be USB.

Those presets still need verification against the actual Lanner devices. Datasheets are useful, but they do not report the udev properties that the installed system will expose.

## Credentials Should Leave Fewer Footprints

Every node receives its own root and break-glass passphrases. Only SHA-512 hashes generated through `mkpasswd` go into the answer files. Plaintext is written only to a mode 600 credentials file and is never printed.

The passphrase generator supports two through six words from the EFF large, short, or silly lists. It can add capitalization, leetspeak, digits, and extra entropy. The default uses five words from the EFF large list.

That list has 7,776 entries, which works out to about 12.925 bits per word. Five independent words provide about 64.6 bits. Three provide about 38.8 bits. The generator refuses anything below 64 bits unless I force it.

The same rule carried into the directory bootstrap. The JumpCloud bind account password is read from standard input. It does not appear in an argument list, a repository file, or an image.

And device-side functions should not print their return values without knowing exactly what they return. On one pfSense version, a configuration function returned the entire configuration, including a password hash. Logging a success check could therefore disclose far more than the operation itself required. I now print counts and booleans from device operations, not returned configuration objects.

## Why Non-Windows Identity Is Often the Gap

Most business networks are Windows-oriented, but much of the infrastructure underneath them is Linux or another Unix-like system. Hypervisors, appliances, storage, web services, monitoring systems, and network management tools often sit outside the identity work that was completed for the Windows estate.

Across the industry, non-Windows identity has consistently been one of the largest gaps I have seen. Central login is part of it, but only part. The real job includes group-to-role mapping, limited administrative scopes, break-glass access, SSH key selection, credential rotation, and proving that removing somebody from a group actually removes access.

For this lab, I used JumpCloud LDAP with one directory, a bind account, and two groups: one for administrators and one for limited VM users. The bootstrap creates a Proxmox realm using LDAPS on port 636 and verifies the CA chain. It installs user and group filters, creates a pool, creates two custom roles, applies six per-path grants, and schedules synchronization every 30 minutes.

The bootstrap has 57 tests, but the important checks happened through Proxmox itself. A second read-only check reported zero differences, and, on the earlier hand-built node, a member of the limited group built a VM through the actual Create VM wizard.

That VM build required five per-path grants covering the pool, storage, ISO storage, SDN zone, and node audit. Missing `Pool.Audit` and `Sys.Audit` produced silent failures. Worse, the wizard returned HTTP 200 while refusing the operation. A successful HTTP response was not evidence that the user could create the VM.

LDAP produced its own collection of sharp edges. Error 49 can mean a bad password or a bad DN. I also got it once by entering the whole organization DN where only the organization ID belonged. At another point, the realm base DN lost its `ou=Users,` prefix.

Proxmox normalizes the sync-default options by sorting their keys, so comparing the returned string creates perpetual drift even when the configuration is equivalent. I changed the comparison to parsed key-value pairs. I also found that `pvesh set` requires the schedule on every sync-job update and merges values instead of clearing them.

The most important directory bug came out of review. I had classified dry-run lines containing “updating” as harmless, then skipped the real synchronization. But those lines also represent membership changes. A user removed from either group could remain active because my automation decided the dry run looked safe.

Unknown dry-run lines now count as changes and stop for review. And `--apply` always runs the real synchronization. Directory automation has to fail closed, especially around revocation.

## A Fresh Node Is Different From a Clean-Looking Node

The hand-built Proxmox node hid a filesystem assumption. On a fresh installation, `/etc/pve/priv/realm` does not exist until a realm password exists. My bootstrap assumed the directory was already there because it existed on the system I had been developing against.

The real reinstall failed. I created the directory manually that night, and the proper fix remains tracked.

This is why a wipe-and-reinstall rehearsal is different from rerunning a script on a machine that has accumulated state. Idempotence is valuable, and the second check returning zero differences told me something useful. It did not tell me whether the first run would work on untouched storage.

SSH gave me another example. Running `ssh` without `-i` allowed it to select a default key file silently. A login that I believed had used a hardware security key had actually used a software key. The corrected command pins the identity with `-i` and `IdentitiesOnly`, and I verified hardware-key root login after the fresh installation.

The broader rule is simple: do not claim which credential was used without evidence.

## What Was Actually Proven

On the second pass, I checked the fresh node read-only. Its static address was active on `vmbr0` over the wired NIC. The hostname was correct in `/etc/hosts`. The break-glass user and first-boot CA chain were present. The repair step logged that it had not found the placeholder and made no changes.

All four Proxmox services were active. LDAPS and the package mirror were reachable. Hardware-key root login worked. The realm bootstrap’s second check found zero differences. The limited group’s VM build through the real wizard was proven on the earlier node. Repeating it on this fresh node is still pending.

One network problem remains: NTP over UDP 123 is blocked out of the virtualization VLAN. Chrony cannot reach a source. The hardware clock happens to be correct today, but LDAPS certificate validation depends on correct time, so that cannot remain an assumption. The firewall rule is tracked.

The seven production Lanner nodes are not built. Their disk and NIC presets are not verified. Serial-console behavior and BMC details are pending. I still need the answer server that will allow one generic installer stick to select per-machine answers by MAC address, cluster formation, a guided wizard, and the NTP rule. FreeIPA as an on-premises failover remains a low-priority possibility, and Active Directory realms are untested.

The installer, setup tool, and guide will be open sourced after those pieces are confirmed. Right now, this is a dress rehearsal on a spare laptop, which is exactly why the silent placeholder, AppArmor failure, fresh-realm directory bug, misleading SSH login, and incomplete synchronization logic showed up before seven production boxes depended on them.
