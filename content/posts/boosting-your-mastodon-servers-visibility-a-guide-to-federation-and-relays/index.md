---
title: "Boosting Your Mastodon Server's Visibility: A Guide to Federation and Relays"
date: 2023-02-08T23:13:50-05:00
slug: "boosting-your-mastodon-servers-visibility-a-guide-to-federation-and-relays"
image: "featured.jpg"
imageAlt: "Six sprinters in a black and white photo run toward the camera on a track during a relay race, one holding a baton."
build:
  publishResources: false
description: "How a new Mastodon server gets noticed: directories, follower scanning tools and relays that improve federation."
archive: true
categories: ["Social Media"]
tags: ["mastodon", "fediverse", "relays"]
syndicate: false
syndicated:
  mastodon: "https://social.chiefgyk3d.com/@chiefgyk3d/109832833300461037"
aliases:
  - "/boosting-your-mastodon-servers-visibility-a-guide-to-federation-and-relays/"
---

Starting your own Mastodon server can be an exciting journey, but it can also be daunting when you realize that no one knows about your existence. Mastodon is a federated platform, meaning that new servers have to work to properly federate with other users. There are different ways to get the word out and make your server more visible.

One way is to list your account from your server in various wikis and databases, such as [https://communitywiki.org/trunk](https://communitywiki.org/trunk) and [https://fedi.directory/](https://fedi.directory/). You can also try scanning your Twitter followers with tools like [https://twitodon.com/](https://twitodon.com/).

Another way to boost your server's visibility is by subscribing to a relay. A relay is a piece of software that increases federation between instances that subscribe to it. This is a great way for smaller instances to populate their federated timeline. You can find a list of relays at [https://joinfediverse.wiki/index.php?title=Fediverse_relays](https://joinfediverse.wiki/index.php?title=Fediverse_relays).

As an instance admin, you can subscribe to a relay by going to Settings > Administration > Relays, entering the URL of the relay and adding "/inbox" to the end. You'll then need to wait for the relay owners to accept your instance.

Federation is a form of decentralization, which means that instead of a single central service that everyone uses, there are multiple services that anyone can use. For example, email, XMPP, and phone networks are federated, while Twitter, Facebook, and Instagram are centralized.

A Mastodon website operates like a traditional website, with people signing up, posting messages, and interacting with each other. The difference is that Mastodon websites can interoperate and allow users to communicate with each other, just like sending an email from one provider to another.

Mastodon uses the standardized, open protocol called ActivityPub to implement federation. Any software that implements federation via ActivityPub can communicate seamlessly with Mastodon, just like Mastodon websites communicate with one another. The term for all websites that can communicate over ActivityPub is called the "fediverse," which includes Mastodon servers as well as other implementations such as [Pleroma](https://pleroma.social/), [Pixelfed](https://pixelfed.org/), [Misskey](https://misskey-hub.net/en/), [PeerTube](https://joinpeertube.org/), [Plume](https://joinplu.me/), and personal websites.

In practical terms, interoperability between different software means that if two services used the same protocol, users could follow and interact with each other even if they weren't on the same platform. With a Mastodon account, you can communicate with any compatible website, as long as it supports the necessary subset of the ActivityPub protocol.
