// SPDX-License-Identifier: Apache-2.0
//
// Autonomous systems that are hosting providers, data centers or VPN/proxy
// operators. The collector compares the visitor's ASN (which Cloudflare puts in
// request.cf, so no address is needed) with this table. A match sets the
// "net" flag on the row; the ASN itself is never stored. No address ranges
// (CIDR) are used anywhere.
//
// UNVERIFIED STARTER DATA. Written from general knowledge on 2026-11-05 and not
// yet replaced by the decided source. The monthly refresh derives the reviewed
// list from X4BNet/lists_vpn (MIT) and uses ipverse/as-metadata (CC0) only for
// its report. This note stays until the first generated import is merged. A
// wrong or missing entry only changes a flag; it cannot break delivery.
//
// Format: [ASN, class] where class is "hosting-datacenter" or "vpn-proxy".
// Generated refreshes give vpn-proxy precedence on overlap. The starter rows
// below predate that rule. Only ASN numbers and classes ship in the Function.

export const HOSTING_ASNS = new Map([
  [14061, "hosting-datacenter"], // DigitalOcean
  [16509, "hosting-datacenter"], // Amazon (AWS)
  [14618, "hosting-datacenter"], // Amazon (AWS)
  [396982, "hosting-datacenter"], // Google Cloud
  [8075, "hosting-datacenter"], // Microsoft (Azure)
  [31898, "hosting-datacenter"], // Oracle Cloud
  [16276, "hosting-datacenter"], // OVH
  [24940, "hosting-datacenter"], // Hetzner
  [63949, "hosting-datacenter"], // Linode (Akamai Connected Cloud)
  [20473, "hosting-datacenter"], // Vultr
  [51167, "hosting-datacenter"], // Contabo
  [12876, "hosting-datacenter"], // Scaleway
  [45102, "hosting-datacenter"], // Alibaba Cloud
  [132203, "hosting-datacenter"], // Tencent Cloud
  [9009, "vpn-proxy"], // M247 (hosts many commercial VPN exits)
  [212238, "vpn-proxy"], // Datacamp (VPN and proxy exits)
  [60068, "vpn-proxy"], // Datacamp / CDN77 (VPN and proxy exits)
  [136787, "vpn-proxy"], // commercial VPN exits
  [207137, "vpn-proxy"], // commercial VPN exits
  [13335, "vpn-proxy"], // Cloudflare (WARP and relay traffic)
]);
