# Rotating the PGP key

The business contact on the About page shows a PGP fingerprint and a link to
the public key. The key is published on keys.openpgp.org. This site does not
host a key file, so there is nothing to upload to the repository.

When the key changes:

1. Upload the new public key to keys.openpgp.org first, and confirm the record
   resolves at `https://keys.openpgp.org/vks/v1/by-fingerprint/<FINGERPRINT>`
   (the old record stays where it is).
2. In `data/about.yaml`, set `contact.pgp_fingerprint` to the new fingerprint in
   groups of four (`XXXX XXXX ...`, 10 groups, uppercase), and `contact.pgp_url`
   to that by-fingerprint URL with the fingerprint written without spaces.
3. Run `scripts/test-pages.sh`. It fails when the fingerprint is not 40 hex
   characters in groups of four, or when the link's path does not end with
   exactly that fingerprint, so the two cannot drift.

The contact block stays all or nothing: the email, the fingerprint and the key
link must all be set or none of them is published (`scripts/about-email.sh`).
The link is a plain outbound link, so the site's content security policy does
not change.
