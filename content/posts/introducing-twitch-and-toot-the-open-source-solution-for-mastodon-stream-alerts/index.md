---
title: "Introducing Twitch-and-toot: The Open-Source Solution for Mastodon Stream Alerts"
date: 2023-02-06T12:22:12-05:00
draft: true
slug: "introducing-twitch-and-toot-the-open-source-solution-for-mastodon-stream-alerts"
description: "Twitch-and-Toot is an open source tool that posts to Mastodon when a streamer goes live on Twitch. This is the story of how I built it."
categories: ["Open Source"]
tags: ["twitch-and-toot", "mastodon", "streaming", "python"]
syndicate: false
syndicated:
  mastodon: "https://social.chiefgyk3d.com/@chiefgyk3d/109819136558223108"
supersededBy: "/posts/stream-daemon-the-secure-open-source-stream-automation-engine-for-modern-creators/"
aliases:
  - "/introducing-twitch-and-toot-the-open-source-solution-for-mastodon-stream-alerts/"
---

Hi everyone! I am Moshe, also known as ChiefGyk3D, the author of Twitch-and-Toot ([https://github.com/ChiefGyk3D/twitch-and-toot](https://github.com/ChiefGyk3D/twitch-and-toot)), an open source project that allows you to post to Mastodon when a streamer is live on Twitch. The project was born from my initial idea to learn coding by using Twitter's API to rebuild alerts for TikTok, Twitch, and YouTube to my Twitter. However, since Elon Musk has an issue with developers using the API and allegedly wants to charge an outrageous amount for the API, I decided to move all my work to Mastodon on my own private server ([https://social.chiefgyk3d.com](https://social.chiefgyk3d.com)) as the API is free.

To my surprise, I couldn't find any existing projects to work with Twitch, TikTok, and YouTube notifications on Mastodon. That's when I decided to teach myself NodeJS with the help of Yitz Jordan and ChatGPT building about 80% of the project. And within 24 hours of announcing the project on Mastodon, I received three pull requests and some great improvements to the overall code. This was an amazing experience for my first ever community project I built, coded, and started myself.

About Twitch-and-Toot

Twitch-and-Toot is built on NodeJS and can run on a RaspberryPi, Single Board Computer, Linux VPS, or a private server. To run the script, you need to have NodeJS installed and obtain a Twitch API key (client ID and secret) from the Twitch Developer Dashboard, and a Mastodon API key (access token) from your Mastodon instance.

Here's how you can install and configure Twitch-and-Toot:

```
Clone the GitHub repository to your device: git clone https://github.com/ChiefGyk3D/twitch-and-toot.git
Install the required packages: npm install
Create a config.json file based on the config_template.json file in the repository. Fill in the required information such as Twitch API key, Mastodon API key, and the channel name you want to track.
Run the script: node twitch-and-toot.js
```

The configuration file config.json is used to store the required information such as Twitch API key, Mastodon API key, and the channel name you want to track. You can also customize the messages that will be posted to Mastodon when the streamer is live, but you currently must keep a total of five (5) messages for the array to work properly. This is customized directly in the script, but I hope to move it to config.json in the future.

Plans for the Future

I have some exciting plans for Twitch-and-Toot's future development:

```
Move Mastodon message choices to config.json and unhinge it from the five message option requirement
Consolidate the last post time information into the config.json file.
Add messaging for when the stream ends to post to Mastodon and thank followers.
Create a SystemD service to keep the script running and boot with the device hosting it.
```

Support and Donations

If you would like to support the development of Twitch-and-toot, you can donate through the following links: https://links.chiefgyk3d.com. You can also tip me with the following cryptocurrency addresses:

```
Bitcoin: bc1q5grpa7ramcct4kjmwexfrh74dvjuw9wczn4w2f
Monero: 85YxVz8Xd7sW1xSiyzUC5PNqSjYLYk4W8FMERVkvznR38jGTBEViWQSLCnzRYZjmxgUkUKGhxTt2JSFNpJuAqghQLhHgPS5
PIVX: DS1CuBQkiidwwPhkfVfQAGUw4RTWPnBXVM
Ethereum: 0x2a460d48ab404f191b14e9e0df05ee829cbf3733
```

If you have any questions or feedback, feel free to reach out on the GitHub repo or to me on my Mastodon Account at [https://social.chiefgyk3d.com/@chiefgyk3d](https://social.chiefgyk3d.com/@chiefgyk3d)
