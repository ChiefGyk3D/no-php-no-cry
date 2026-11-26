---
title: "What the Link-Priority Manager Had to Prove"
date: 2026-11-25T14:30:00-05:00
draft: false
description: "A network repair exposed mistakes in the proposed fix, the test fakes and the standard used to call something ready. The useful result came from testing the real failure path."
slug: "link-priority-manager-and-network-repair"
categories: ["Journal"]
tags: ["networking", "testing", "ai-assistant", "review", "linux"]
syndicate: false
image: "featured.webp"
imageAlt: "A black Motorola MicroTAC flip phone from 1989 with its antenna up and the flip cover open, on a dark background."
---

The lesson from this network repair is simple: a test double that agrees with the implementation can still be completely wrong about the system. My cellular failover passed its tests, then failed the first time I turned off the Wi-Fi radio.

<!--more-->

The original requirement was not complicated. Ethernet should come first, Wi-Fi second and cellular last. The modem must remain connected as a fallback, with a separate emergency mode that deliberately puts cellular first.

The laptop was doing something very different. In about six hours, the modem carried roughly 1.3 GB up and 5 GB down. About 750 MB was VPN tunnel traffic. This had apparently continued for weeks without being noticed.

Wi-Fi and cellular already had route metrics of 600 and 1100. That ordering worked for IPv4, but Wi-Fi had no IPv6 on that network. The modem held the only IPv6 default route, so IPv6 used it.

Twingate also selected ONE gateway and interface, then bound its controller and relay sockets to that device. With both defaults present, it chose cellular. With only the Wi-Fi default present, it chose Wi-Fi. Its exact selection rule remains unknown.

## The first answer was called ready too early

The AI assistant’s first fix was an nftables guard that left the modem connected but rejected its egress. It went through three adversarial review rounds and was installed.

It broke the VPN and DNS.

Twingate stayed bound to the modem, while the guard rejected the packets it tried to send there. My DNS resolvers come from the VPN, so both failed together.

That design should not have been called ready. It had been reviewed as code, but it had not been proved through the path I actually use.

The assistant also moved toward taking the modem down, even though I had explicitly required it to remain connected. That was not a small interpretation difference. It discarded one of the reasons for doing the work.

I rejected the shortcut and demanded the deeper end-to-end check.

## The real system corrected the model

The working base configuration was to set `ipv4.never-default` and `ipv6.never-default` on the normal cellular profile. The modem stayed connected and kept its address, but it stopped advertising default routes.

Twingate rebound to Wi-Fi. DNS worked. The Ollama service on port 11434 and SSH on port 22 answered through the VPN. Cellular byte counters stayed flat for 50 seconds.

The link-priority manager then handled failover every 15 seconds. It waited for two failed probe rounds on both Ethernet and Wi-Fi before opening cellular, and two good rounds on either before closing it. A write-ahead ledger protected rollback after a crash, kill or logout.

The test suite said this worked. The live radio-off test said it did not.

The fake NetworkManager allowed live device changes to restore the modem’s default route. Actual NetworkManager did not. Once a modem was activated with `never-default`, its gateway was absent from the live configuration. Neither `nmcli device modify` nor adding a static default route that way repaired it. Only `nmcli connection up` did.

The safe rollback mattered here. The manager attempted failover every 15 seconds, logged the failure and left Wi-Fi alone. The incorrect implementation failed closed instead of breaking the working link.

After three focused experiments, the design changed to two profiles. The normal profile remains closed to defaults. The cloned failover profile permits defaults, uses metric 50 and NEVER autoconnects. Failover activates that profile; recovery activates the normal one.

Then the fake was changed to reproduce the measured behavior. The revised tests fail against the old code.

That order matters. Reality corrected the model, then the test preserved the correction.

## Review found the unglamorous failures

The work went through nine bounded adversarial review rounds with an AI reviewer. Every round was fixed before the next one. The final round had no High, Medium or Low findings.

The implementer also mutation-tested the suite, deliberately breaking the program to confirm the tests noticed. The final suite contains more than 1,100 checks.

Several late findings were in installation and uninstallation, especially failures halfway through those operations. That is ordinary, dangerous software behavior. Runtime logic can be correct while a partial install leaves the machine in a state nobody planned for. The runtime code remained byte-identical to what was already running live while those surrounding paths were repaired.

The final live checks behaved as intended. With Wi-Fi off, cellular took ownership within 10 seconds, both default routes appeared through the modem at metric 50, and the VPN came online. With Wi-Fi restored, ownership returned within 25 seconds and only Wi-Fi retained a default route. Cell-first and the return to automatic mode also worked, with an internet request returning HTTP 200.

I added a one-click Network Repair action to Hammunition Tray, with a visible state and a default two-hour expiry. That desktop path is not verified on a real desktop yet, only in offscreen tests. A reboot during failover and stopping the timer during failover are also unverified. IPv6 lacked a default route during cell-first for an undiagnosed reason, although the VPN and lab still worked. A later run showed the IPv6 default present from the first sample and a ping over IPv6 answered with no loss, so I could not reproduce it.

The repair is better because the early answers were challenged by the real machine. The guard was not ready, the proposed disconnect violated the requirement, and the original fakes proved only that the code agreed with itself.
