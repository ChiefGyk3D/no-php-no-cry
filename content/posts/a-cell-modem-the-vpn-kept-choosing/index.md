---
title: "A Cell Modem the VPN Kept Choosing"
date: 2026-11-25T14:00:00-05:00
draft: true
description: "A backup cellular modem kept carrying my laptop's traffic because IPv6 and a VPN bind ignored route metrics. What failed first, and what fixed it."
slug: "a-cell-modem-the-vpn-kept-choosing"
categories: ["Open Source"]
tags: ["linux", "networking", "networkmanager", "twingate", "cellular", "troubleshooting"]
syndicate: false
image: "featured.webp"
imageAlt: "A black Motorola MicroTAC flip phone from 1989 with its antenna up and the flip cover open, on a dark background."
---

My laptop sent about 1.3 GB up and 5 GB down through its backup cellular modem in roughly six hours. About 750 MB was VPN tunnel traffic, and some version of this had apparently been happening for weeks.

<!--more-->

The rule I wanted was plain: Ethernet first, Wi-Fi second, and cellular last. The modem should stay connected so it can take over when everything else fails, but it should not carry ordinary traffic.

I also wanted an emergency switch that deliberately puts cellular first. If the LAN firewall is down but cellular still works, I need to be able to reach the AI server in my lab through the VPN while I troubleshoot.

The route metrics looked like they already expressed that policy. Wi-Fi was metric 600 and the modem was metric 1100, settings tracked in quectel-usbnet issue #10. But those numbers only fixed the IPv4 ordering.

## IPv6 took the available road

Wi-Fi had no IPv6 on this network. The cellular modem did, which left it holding the only IPv6 default route.

That meant all IPv6 traffic went through cellular regardless of the IPv4 route metrics. The modem was not behaving like a last-resort path because, for IPv6, it was the only path.

Address-preference changes did not solve the whole problem either. Go programs ignore `/etc/gai.conf`, so adjusting preferences there had no effect on them.

Twingate added another layer. Its root service, `twingated`, selected ONE default gateway and interface, then bound its relay and controller sockets to that device. It did not simply allow normal route selection to follow the metrics.

The binary contains a `get_default_gateway_and_iface` function string and uses libnl route calls. With both Wi-Fi at metric 600 and the modem at 1100 holding default routes, it chose the modem. With only Wi-Fi holding a default route, it chose Wi-Fi.

I do not know Twingate’s exact selection rule, and I am not claiming more than I observed. What mattered operationally was that metrics did not keep its sockets off cellular while both interfaces advertised defaults.

## The first guard broke the useful path

My first fix was an nftables guard. The idea was to keep the modem connected while rejecting egress through it.

That guard went through three adversarial review rounds and was installed. It still broke the VPN tunnel and DNS.

Twingate remained bound to the modem while nftables rejected the modem’s traffic. My DNS resolvers are provided by the VPN, so losing that tunnel also took DNS with it. The guard was pinned off and superseded.

It should have been caught before it was called ready.

Taking the modem down entirely was not an acceptable correction. It is installed as a fallback connection, and staying connected is part of the requirement.

## Removing defaults without disconnecting

The verified fix was in the modem’s NetworkManager profile:

- `ipv4.never-default` enabled
- `ipv6.never-default` enabled

The modem remained connected and retained its address, but it no longer held an IPv4 or IPv6 default route.

Once those defaults disappeared, Twingate rebound all of its sockets to Wi-Fi. DNS answered again. The Ollama server in my lab answered on port 11434, and SSH answered on port 22. The modem’s byte counters stayed flat during a 50-second observation.

That proved the immediate repair, but it also removed automatic cellular fallback. A modem without a default route cannot take over merely because Wi-Fi stops working.

So the route fix needed a manager around it.

## Managing the profiles instead of fighting routes

The link-priority manager is in quectel-usbnet PR #26. It is a Bash script driven by a systemd user timer every 15 seconds.

In normal operation it touches only the cellular modem. It opens cellular failover after both Ethernet and Wi-Fi fail two probe rounds using real internet probes bound to those interfaces. It closes cellular again after either preferred link passes two rounds.

Ethernet and Wi-Fi are not demoted during ordinary failover. The separate cell-first mode is the emergency switch, and it performs a make-before-break transition before demoting the preferred links.

The manager also uses a write-ahead ledger. It records previous values before changing them, which gives it enough state to repair after a crash, kill or logout. Uninstall restores the prior settings too.

Then the first real radio-off test failed.

The test fakes had said failover worked. NetworkManager disagreed.

## A fake that agreed with the code

A modem activated with `never-default` loses its gateway from NetworkManager’s live configuration. Changing the live device with `nmcli device modify` did not restore a usable default route. Adding a static `0.0.0.0/0` route through the same mechanism did not restore it either.

Only reactivating the connection with `nmcli connection up` brought the default route back.

I ran three small experiments to isolate that behavior. While the manager was wrong, its safe rollback kept the laptop usable. It logged a failed attempt every 15 seconds and left Wi-Fi alone.

The redesign uses two NetworkManager profiles.

The normal cellular profile has `never-default` enabled. A cloned failover profile has `never-default` disabled, route metric 50 and autoconnect turned off. Opening failover activates that profile. Closing failover activates the normal profile again.

Autoconnect being off on the failover profile matters. After a reboot or reconnect, NetworkManager returns to the normal closed profile instead of silently making cellular a preferred route.

The fake NetworkManager in the tests was changed to reproduce the measured live behavior. The new tests fail against the old implementation, which is the useful kind of failure.

## What worked live

With the Wi-Fi radio off, the manager’s owner field changed from `none` to `cell` within 10 seconds. The failover profile became active, IPv4 and IPv6 default routes appeared through the modem at metric 50, and the VPN came online.

After I turned Wi-Fi back on, ownership returned to Wi-Fi within 25 seconds. Only Wi-Fi’s default route remained.

Cell-first mode worked, as did returning from cell-first to automatic selection. Wi-Fi’s default route came back without needing the reactivation fallback, and an internet request returned HTTP 200.

The work went through nine bounded adversarial review rounds with an AI reviewer. Each round’s findings were fixed before the next one, and the last review reported no High, Medium or Low findings. The implementer mutation-tested the tests by deliberately breaking code and confirming that the tests failed. The final suite contains more than 1,100 checks.

Several late findings involved install and uninstall scripts failing partway through. The runtime code remained byte-identical to the version already running live.

I also added a Network Repair action to Hammunition Tray. It is intended to make emergency cell-first mode available with one click, a visible icon state and a default two-hour expiry.

Some edges remain unverified: rebooting while the failover profile is active, stopping the timer during failover, and using the tray action and icon on a real desktop. The tray has only been tested offscreen. During cell-first testing, the IPv6 default route was empty for an undiagnosed reason, although the VPN and lab access still worked.
