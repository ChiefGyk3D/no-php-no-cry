"""Static check: every file a sparse-checkout job needs is in its sparse list.

Usage: python3 -I scripts/check-deploy-sparse.py <workflow.yml> <repo-root>

For each job of the workflow whose checkout step has a `sparse-checkout:` list,
the job's commands (comments and the sparse list itself removed) are searched for
the repository files they run or read: scripts/*.sh, static/_headers, static/_routes.json and the
script hash files. Each script is then read, and the scripts it sources or runs and
the data files it names are added, until nothing new appears. Any needed file
that the job's sparse list does not cover is printed as "job: path" and the exit
status is 1. Jobs with a full checkout are not checked.
"""
import os
import re
import sys

DATA = ("static/_headers", "static/_routes.json")
# Code that asks for the pinned scripts (scripts/artifact-rules.sh) reads one hash
# file per script on that file's PINNED_SCRIPTS allowlist: <name>.sha256 at the root.
HASH_TRIGGER = "pinned_script_names"


def jobs(text):
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("jobs:"))
    cur, out = None, {}
    for l in lines[start + 1:]:
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", l)
        if m:
            cur = m.group(1)
            out[cur] = []
        elif cur is not None:
            out[cur].append(l)
    return out


def sparse_list(job_lines):
    """Returns (entries, remaining lines) or (None, lines) with no sparse list."""
    for i, l in enumerate(job_lines):
        m = re.match(r"^(\s*)sparse-checkout:\s*(.*)$", l)
        if not m:
            continue
        indent, rest = len(m.group(1)), m.group(2).strip()
        consumed = 1
        entries = []
        if rest in ("|", ">", "|-", ">-"):
            while i + consumed < len(job_lines):
                nxt = job_lines[i + consumed]
                if nxt.strip() and len(nxt) - len(nxt.lstrip()) <= indent:
                    break
                entries.append(nxt.strip())
                consumed += 1
        else:
            entries.append(rest)
        entries = [e for e in entries if e and not e.startswith("#")]
        return entries, job_lines[:i] + job_lines[i + consumed:]
    return None, job_lines


def code_only(text):
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


def needed(root, text):
    found, todo = set(), [text]
    while todo:
        t = todo.pop()
        for m in re.finditer(r"(?<![\w.-])(?:\./)?(scripts/[A-Za-z0-9_.-]+\.(?:sh|py))", t):
            found_add(root, found, todo, m.group(1))
        for name in re.findall(r"(?<![\w.-])([A-Za-z0-9_-]+\.sh)\b", t):
            if os.path.exists(os.path.join(root, "scripts", name)):
                found_add(root, found, todo, "scripts/" + name)
        for d in DATA:
            if d in t:
                found.add(d)
        if HASH_TRIGGER in t:
            found.update(hash_files(root))
    return found


def hash_files(root):
    """The hash file of every script on the PINNED_SCRIPTS allowlist."""
    path = os.path.join(root, "scripts", "artifact-rules.sh")
    if not os.path.exists(path):
        return set()
    text = open(path, encoding="utf-8").read()
    m = re.search(r"^PINNED_SCRIPTS=\(([^)]*)\)", text, re.M)
    if not m:
        return set()
    return {name + ".sha256" for name in re.findall(r'"([A-Za-z0-9_.-]+):[^"]*"', m.group(1))}


def found_add(root, found, todo, rel):
    if rel in found:
        return
    found.add(rel)
    path = os.path.join(root, rel)
    if os.path.exists(path):
        todo.append(code_only(open(path, encoding="utf-8").read()))


def covered(entries, rel):
    for e in entries:
        e = e.lstrip("/")
        if e.endswith("/"):
            if rel.startswith(e):
                return True
        elif rel == e:
            return True
    return False


def main():
    wf, root = sys.argv[1], sys.argv[2]
    text = open(wf, encoding="utf-8").read()
    bad = 0
    checked = 0
    for name, lines in jobs(text).items():
        entries, rest = sparse_list(lines)
        if entries is None:
            continue
        checked += 1
        for rel in sorted(needed(root, code_only("\n".join(rest)))):
            if not covered(entries, rel):
                print(f"{name}: {rel}")
                bad += 1
    if checked == 0:
        print("no job with a sparse-checkout list was found")
        return 1
    return 1 if bad else 0


sys.exit(main())
