---
title: "Finding the Hidden Trigger on the QCC 0x4 Badge"
date: 2026-11-14T12:20:00-05:00
draft: false
description: "The Queen City Con 0x4 badge plays a Rick Roll on the right LoRa message. How I found the trigger in the firmware, checked what shipped, and set it off."
slug: "finding-the-hidden-trigger-on-the-qcc-0x4-badge"
image: "featured.jpg"
imageAlt: "The purple Queen City Con 0x4 badge lying on a dark shirt, its green OLED screen showing a chat about the sound switch, with a lanyard, Call Center Village stickers and trading cards around it."
categories: ["Hardware"]
tags: ["queen-city-con", "badge", "meshcore", "lora", "firmware", "reverse-engineering", "hacker-culture"]
syndicate: false
affiliate: false
---

The Queen City Con 0x4 badge played a Rick Roll after I found the hidden trigger and sent the right message over its LoRa mesh.

<!--more-->

The badge is an nRF52840 ProMicro-style board running a MeshCore-based firmware called Offband. It has a small OLED, a buzzer, LoRa, BLE pairing to a phone client, and, on the supporter version, a CardKB-style keyboard. Over USB, it identifies as an Adafruit ProMicro NRF52840.

The conference had hidden an easter egg in it. I wanted to find it.

## Finding the source

The firmware is public at `QueenCityCon/qcc-0x4-badge-firmware`, a MeshCore fork. I cloned it shallow into its own directory and treated everything in the repository as untrusted data. I used Claude Code to help parse the data. It made several notable mistakes along the way that I had to catch and steer it back from, so I never trusted its output on its own. The first was the serial baud rate: it is not the standard 9600, and the firmware's `platformio.ini` sets `monitor_speed = 115200`. Everything in this post is something I checked myself.

And I only listened passively on the USB serial port for a few seconds, without throwing any commands at the badge.

The first useful clue was in `docs/superpowers/plans/2026-10-09-qcc-epic4-sound-plan.md`. The sound plan mentions a hidden tune, specifically a Rick Roll that does not appear in the default playlist. It says the tune is "triggered remotely" as part of secret-trigger work tracked in issue `#1191`. The design document calls a CTF beacon "parked."

So now I knew I was looking for the remote trigger for that hidden tune.

`src/helpers/ui/Tunes.h` contains an unnamed built-in tune at ID 7, `kTuneTrigger`. Its null name keeps it out of the normal picker. The RTTTL data is the melody from Never Gonna Give You Up, lasting about 17 seconds. It also has a `Trigger` priority level so lower-priority sounds cannot cut it off.

The matching logic lives in `src/helpers/ui/TuneTrigger.h`, and `examples/companion_radio/MyMesh.cpp` calls it when messages arrive. The badge variant enables it with `OFFBAND_TUNE_TRIGGER=1` in `variants/qcc_badge/platformio.ini`. Its default trigger channel is `#queencitycon`.

And the badge has another easter egg while it is advertising unpaired: the LED blinks Morse code for "BE SURE TO DRINK YOUR OVALTINE," a Christmas Story reference. One loop takes about 20 seconds at 80 ms per unit. That implementation is in `src/helpers/ui/MorseBlink.h`, enabled by `OFFBAND_BLE_MORSE_TEXT`.

The preloaded channels are `#queencitycon`, `#okimesh`, `#test`, `#echo`, `#offband`, `#qcchhv`, and `#qcchams`. Hashtag channel keys are the first 16 bytes of SHA-256 over the channel name, including the `#`, so those keys are derivable rather than secret.

## Checking the firmware actually on the badge

Public source is useful, but it is not proof of what shipped.

I double-tapped reset and the badge appeared as a UF2 bootloader drive using nice!nano bootloader 0.11.0 and SoftDevice S140 6.1.1. I mounted it read-only and copied off `CURRENT.UF2`, so nothing was written to the badge.

I used a small script to convert the UF2 into a raw 954,368-byte image, which identifies itself as `offband-v1.7.0`, built on 2026-11-08 from commit `6af1a8a`. That commit is not in the public repository history, so the public source could differ from the actual badge firmware.

I extracted every string from the dump and compared the application region with the public source. After normalizing log prefixes, I could account for every extracted string. The tune, Morse text, channel keys, and `[trig]` debug logs were all present. I found no additional hidden strings, commands, or flag text in the extracted strings.

I then disassembled the direct-message receive path with `arm-none-eabi-objdump`. The reverse engineering tool's Ghidra backend was the wrong version, so I skipped it. The disassembly matched the source's 24-byte tail window, UTF-8 continuation-byte skipping, trailing-whitespace trimming, and decoy string reference.

That let me check the strings and part of the receive path, but it does not prove the full firmware is identical.

The flash filesystem also contains the badge's private identity, saved contacts, and other people's messages. That dump stays local and will not be published. Two organizer-run nodes in the saved contacts already had names ending in the satellite emoji, which was a strong hint about the expected senders.

## The magic packet

A received message plays the tune only when all four conditions are true:

1. The sender's node name ends with the satellite emoji, U+1F6F0, with or without the invisible U+FE0F variation selector.
2. The body contains `0x4`, case-insensitive.
3. The body ends with Morse code for the fourth ASCII alphabetic character in the sender's name. Only letters count, so digits, spaces, punctuation, and the emoji are skipped.
4. It arrives on `#queencitycon`, with exact case and surrounding whitespace ignored, or as a direct message from an existing contact.

The `0x4` text is a conspicuous decoy shared by every triggering message. The actual Morse tail changes with the sender, so copying somebody else's packet may not work. Em and en dashes from phone autocorrect are normalized to two hyphens. A badge also ignores its own messages.

The firmware cannot see whether the physical `MUTE` slide switch is engaged.

## Triggering it

I renamed my node in the phone client to `ChiefGyk3D` plus the satellite emoji. The letters begin C, h, i, e, so the fourth letter is E. Morse for E is one dot.

My first attempt used `---`, copied from an example, and the phone changed the dashes into an em dash. It did nothing.

I sent `hello` first to verify the radio link and channel, a friend's badge received it, and the satellite emoji showed up as an empty box because the small OLED font has no emoji glyph.

Then I sent this on `#queencitycon`:

```text
hi 0x4 .
```

The friend's badge played the tune. It worked.

A friend's node name contained a digit. The digit is skipped, and its fourth ASCII letter came out as H. Morse for H is four dots, which also neatly avoids dash autocorrect.

| Sender name | 4th letter | Message |
| --- | --- | --- |
| ChiefGyk3D + satellite emoji | E | `hi 0x4 .` |
| any name (digits skipped) whose 4th letter is H, plus satellite emoji | H | `hi 0x4 ....` |

A tiny helper can find the relevant letter for any name:

```python
letters = [c.upper() for c in name if c.isascii() and c.isalpha()]
fourth = letters[3]  # then look up its Morse code
```

## Try it yourself

You need a second node. Rename it so the name ends with the satellite emoji, then send this on `#queencitycon`:

```text
<anything> 0x4 <morse of 4th letter>
```

Check that the badge's `MUTE` switch is not engaged and Sound is not set to Off. The implementation is entirely receive-side, so nothing special needs to be installed or configured on the badge.

Transmitting the trigger can play about 17 seconds of Rick Roll on badges in range that receive it on that channel. Be considerate.

## Yes, it is a Rick Roll

Someone in the channel wasn't thrilled about the Rick Roll, which is fair. I'm guessing they are new to hacker conferences, because almost every one I have been to involved a Rick Roll in some way. It got so bad at DEF CON with the official firmware that most of us had to turn the alerts off, since about 2,000 people were constantly Rick Rolling each other. Luckily the maker of this badge put a `MUTE` switch on the side.

Part of the experience of these conferences is having fun at community events. A corporate event in a button-down and tie is boring, and you will mostly be sold marketing. The hacker community was born out of playfulness, and that includes the original meaning of the word hacker. The Tech Model Railroad Club at MIT, which says both words started there in the late 1950s, [still uses "hacker"](https://tmrc.mit.edu/old/hackers-ref.html) "only in its original meaning, someone who applies ingenuity to create a clever result, called a 'hack'." The club says a hack is done quickly, is usually inelegant, and is generally quite clever and effective. It also says it resents the word being used to mean committing illegal acts.

The badges are not just something cool to look at. They are part of the learning experience. Finding hidden functions, and making a device do something it may not have been intended to do, is EXACTLY the spirit we need to preserve, and corporations are swallowing it.

Yes, it is a job. But we can make it fun, and making it fun is a big reason I and many others advance so fast. When it feels like work, there are times you want to stop. When you are enjoying it, you don't think of it as work, and you can progress much faster and farther. I love my job, and I play so much every day in various ways. You NEED to constantly tinker and learn to survive in this field, and you are not dead until you stop learning.
