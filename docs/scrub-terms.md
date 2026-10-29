# Scrub terms

The WordPress converter (`tools/wxr2hugo/`) checks its output for private
material before it writes anything. Some checks need no configuration; the rest
read a list of terms. This page says where the list lives and how to change it.
Real term values never go in this repository, in an issue or in a pull request.

## What needs terms and what does not

Built in, no terms needed: callsign and grid-square shapes, and generic
private-network hostnames (10/8, 172.16/12 and 192.168/16 addresses, and names
ending `.local`, `.lan`, `.internal` or `.home.arpa`).

From the terms list: the `employer`, `hostname` and `serial` categories.

## Where the terms live

Doppler project `no-php-no-cry`, config `prd`, secret `SCRUB_TERMS`. The format
is one `category:term` per line:

```
employer:TERM
hostname:TERM
serial:TERM
allow:TOKEN
# a comment
```

`allow:TOKEN` exempts a known false positive. Lines starting with `#` are
comments.

## Current state: starter content only

The secret holds a starter list. `hostname:bluehost` is a real term. The
`employer` and `serial` lines are inert PLACEHOLDER lines: they make those two
categories print as `ran`, but they match nothing real. Until someone replaces
them with real terms, **employer and serial are effectively unchecked**, even
though the run reports them as having run.

## Add a term (no echo, no shell history)

Paste this block. It prompts for the line, appends it to the existing secret
and writes the result back, so the term is never printed, never on a command
line and never in history:

```sh
read -r -p "category:term " L; { doppler secrets get SCRUB_TERMS --project no-php-no-cry --config prd --plain; printf '%s\n' "$L"; } | doppler secrets set SCRUB_TERMS --project no-php-no-cry --config prd >/dev/null; unset L
```

Type the line at the prompt, for example `serial:` followed by the value.
(`read` without `-s` shows what you type on your own terminal; nothing is
echoed anywhere else.)

## Replace a placeholder line

Appending leaves the placeholder in place. To replace it, edit the secret in
Doppler, or rewrite the whole secret by piping the complete new content into
`doppler secrets set SCRUB_TERMS --project no-php-no-cry --config prd`. Keep the
comment lines and any `allow:` lines you still need.

## Run the converter with the terms

The terms go in over stdin, so they never touch disk:

```sh
doppler secrets get SCRUB_TERMS --project no-php-no-cry --config prd --plain | python3 -I tools/wxr2hugo/convert.py --wxr PATH/export.xml --out DIR --scrub-terms - --require-terms
```

`--require-terms` makes a list with no `employer`, `hostname` or `serial` term
exit 2. A placeholder line counts as a term, so it does not trigger that exit;
see the current-state note above. A finding prints its category, file and line
only (never the term), exits 3 and writes nothing.
