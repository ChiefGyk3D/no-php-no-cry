#!/usr/bin/env python3
"""Structurally guard the scheduled live-header workflow.

The repository does not depend on PyYAML, so this script parses the small YAML
subset used by GitHub Actions with the Python standard library. Exit 0 clean,
1 on a finding, and 2 on a usage or read error.
"""
import pathlib
import json
import re
import sys

DEFAULT = pathlib.Path(__file__).resolve().parent.parent / ".github/workflows/live-headers.yml"
ALLOWED_TRIGGERS = {"schedule", "workflow_dispatch"}
EXPECTED_MATRIX = [
    {"name": "dev host", "environment": "staging", "base-url": "https://test-blog.chiefgyk3d.com/", "host": "test-blog.chiefgyk3d.com"},
    {"name": "apex (read only)", "environment": "production", "base-url": "https://chiefgyk3d.com/", "host": "chiefgyk3d.com"},
]
EXPECTED_VERIFIERS = [
    {"name": "Dev host headers", "if": "matrix.environment == 'staging'", "run": "scripts/verify-live.sh test-blog.chiefgyk3d.com --public tmp/live-build --env staging"},
    {"name": "Apex headers", "if": "matrix.environment == 'production'", "run": "scripts/verify-live.sh chiefgyk3d.com --public tmp/live-build --env production"},
]


class YamlError(ValueError):
    """The file is outside the supported, unambiguous YAML subset."""


def strip_comment(value):
    quote = None
    for index, char in enumerate(value):
        if quote:
            if char == quote and (quote == "'" or index == 0 or value[index - 1] != "\\"):
                quote = None
        elif char in "'\"":
            quote = char
        elif char == "#" and (index == 0 or value[index - 1].isspace()):
            return value[:index].rstrip(), value[index + 1:].strip()
    return value.rstrip(), ""


def split_key(value):
    quote = None
    depth = 0
    for index, char in enumerate(value):
        if quote:
            if char == quote and (quote == "'" or value[index - 1] != "\\"):
                quote = None
        elif char in "'\"":
            quote = char
        elif char in "[{":
            depth += 1
        elif char in "]}":
            depth -= 1
        elif char == ":" and depth == 0:
            return value[:index].strip(), value[index + 1:].strip()
    raise YamlError(f"expected a mapping entry: {value}")


def split_flow(value):
    parts, start, quote, depth = [], 0, None, 0
    for index, char in enumerate(value):
        if quote:
            if char == quote and (quote == "'" or value[index - 1] != "\\"):
                quote = None
        elif char in "'\"":
            quote = char
        elif char in "[{":
            depth += 1
        elif char in "]}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(value[start:index].strip())
            start = index + 1
    parts.append(value[start:].strip())
    return parts


def validate_key(key, context="mapping"):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", key):
        raise YamlError(f"unsupported {context} key: {key}")
    return key


def scalar(value):
    if value.startswith("{") and value.endswith("}"):
        result = {}
        inside = value[1:-1].strip()
        for item in split_flow(inside) if inside else []:
            key, raw = split_key(item)
            key = validate_key(key, "flow mapping")
            if key in result:
                raise YamlError(f"duplicate key: {key}")
            result[key] = scalar(raw)
        return result
    if value.startswith(("&", "*", "!", "?", "[")):
        raise YamlError(f"unsupported YAML scalar or collection: {value}")
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    if len(value) >= 2 and value[0] == value[-1] == '"':
        try:
            return json.loads(value)
        except json.JSONDecodeError as error:
            raise YamlError(f"unsupported double-quoted scalar: {error.msg}") from error
    if value in ("true", "false"):
        return value == "true"
    if value in ("null", "~"):
        return None
    if re.fullmatch(r"[0-9]+", value):
        return int(value)
    return value


class YamlParser:
    def __init__(self, text):
        self.lines = []
        raw_lines = text.splitlines()
        index = 0
        while index < len(raw_lines):
            number, raw = index + 1, raw_lines[index]
            index += 1
            if "\t" in raw[:len(raw) - len(raw.lstrip())]:
                raise YamlError(f"line {number}: tabs cannot indent YAML")
            content, comment = strip_comment(raw.lstrip())
            if not content:
                continue
            indent = len(raw) - len(raw.lstrip(" "))
            if content.startswith(("---", "...", "%", "!", "&", "*")):
                raise YamlError(f"line {number}: unsupported YAML feature")
            if content.endswith(": |") or content.endswith(": >"):
                style = content[-1]
                if style == ">":
                    raise YamlError(f"line {number}: folded block scalars are unsupported")
                key, block = content[:-3].rstrip(), []
                while index < len(raw_lines):
                    following = raw_lines[index]
                    following_indent = len(following) - len(following.lstrip(" "))
                    if following.strip() and following_indent <= indent:
                        break
                    index += 1
                    block.append(following[indent + 2:] if following.strip() else "")
                value = "\n".join(block) if style == "|" else " ".join(line.strip() for line in block)
                content = f"{key}: {value}"
            self.lines.append((indent, content, comment, number))
        self.position = 0

    def parse(self):
        if not self.lines:
            raise YamlError("empty document")
        value = self.block(self.lines[0][0])
        if self.position != len(self.lines):
            raise YamlError(f"line {self.lines[self.position][3]}: unexpected indentation")
        if not isinstance(value, dict):
            raise YamlError("document root must be a mapping")
        return value

    def block(self, indent):
        if self.lines[self.position][0] != indent:
            raise YamlError(f"line {self.lines[self.position][3]}: inconsistent indentation")
        content = self.lines[self.position][1]
        return self.sequence(indent) if content == "-" or content.startswith("- ") else self.mapping(indent)

    def mapping(self, indent):
        result = {}
        while self.position < len(self.lines):
            current, content, _comment, number = self.lines[self.position]
            if current < indent:
                break
            if current != indent or content == "-" or content.startswith("- "):
                break
            key, raw = split_key(content)
            key = validate_key(key)
            if not key or key in result:
                raise YamlError(f"line {number}: duplicate or empty key: {key}")
            self.position += 1
            if raw:
                result[key] = scalar(raw)
            elif self.position < len(self.lines) and self.lines[self.position][0] > indent:
                result[key] = self.block(self.lines[self.position][0])
            else:
                result[key] = None
        return result

    def sequence(self, indent):
        result = []
        while self.position < len(self.lines):
            current, content, _comment, number = self.lines[self.position]
            if current < indent:
                break
            if current != indent or not (content == "-" or content.startswith("- ")):
                break
            raw = content[1:].strip()
            self.position += 1
            if not raw:
                result.append(self.block(self.lines[self.position][0]) if self.position < len(self.lines) and self.lines[self.position][0] > indent else None)
                continue
            try:
                key, value = split_key(raw)
            except YamlError:
                result.append(scalar(raw))
                continue
            key = validate_key(key, "sequence mapping")
            item = {key: scalar(value) if value else None}
            if self.position < len(self.lines) and self.lines[self.position][0] > indent:
                continuation = self.mapping(self.lines[self.position][0])
                for extra_key, extra_value in continuation.items():
                    if extra_key in item:
                        raise YamlError(f"line {number}: duplicate key: {extra_key}")
                    item[extra_key] = extra_value
            result.append(item)
        return result


def contains_secret(value):
    if isinstance(value, dict):
        return any(contains_secret(key) or contains_secret(item) for key, item in value.items())
    if isinstance(value, list):
        return any(contains_secret(item) for item in value)
    return isinstance(value, str) and re.search(r"\bsecrets\b", value, re.I) is not None


def action_refs(workflow):
    refs = []
    jobs = workflow.get("jobs", {})
    for job in jobs.values() if isinstance(jobs, dict) else []:
        if isinstance(job, dict) and "uses" in job:
            refs.append(job["uses"])
        for step in job.get("steps", []) if isinstance(job, dict) else []:
            if isinstance(step, dict) and "uses" in step:
                refs.append(step["uses"])
    return refs


def version_comments(text):
    comments = {}
    for raw in text.splitlines():
        content, comment = strip_comment(raw.lstrip())
        if (content.startswith("- uses:") or content.startswith("uses:")) and comment:
            comments[content.split(":", 1)[1].strip()] = comment
    return comments


def contains_key(value, wanted):
    if isinstance(value, dict):
        return wanted in value or any(contains_key(item, wanted) for item in value.values())
    if isinstance(value, list):
        return any(contains_key(item, wanted) for item in value)
    return False


def contains_failure_swallow(value):
    if isinstance(value, dict):
        return any(contains_failure_swallow(item) for item in value.values())
    if isinstance(value, list):
        return any(contains_failure_swallow(item) for item in value)
    return isinstance(value, str) and re.search(r"\|\|\s*true\b", value) is not None


def check(text):
    workflow = YamlParser(text).parse()
    out = []
    triggers = workflow.get("on")
    if not isinstance(triggers, dict):
        out.append("triggers are not a mapping")
    else:
        schedule = triggers.get("schedule")
        if not (isinstance(schedule, list) and schedule and all(isinstance(entry, dict) and isinstance(entry.get("cron"), str) and entry["cron"] for entry in schedule)):
            out.append("no schedule with a cron entry")
        if "workflow_dispatch" not in triggers:
            out.append("no workflow_dispatch trigger")
        for bad in sorted(triggers.keys() - ALLOWED_TRIGGERS):
            out.append(f"unexpected trigger {bad}")
    if workflow.get("permissions") != {"contents": "read"}:
        out.append("top-level permissions are not exactly contents: read")
    if "defaults" in workflow:
        out.append("top-level run defaults can mediate verifier failures")
    jobs = workflow.get("jobs")
    if not isinstance(jobs, dict):
        out.append("jobs are not a mapping")
        jobs = {}
    for name, job in jobs.items():
        if not isinstance(job, dict):
            out.append(f"job {name} is not a mapping")
            continue
        if "permissions" in job:
            out.append(f"job {name} overrides permissions")
        if "defaults" in job:
            out.append(f"job {name} has run defaults that can mediate verifier failures")
        if "steps" in job and not isinstance(job["steps"], list):
            out.append(f"job {name} steps are not a list")
    verify = jobs.get("verify")
    if not isinstance(verify, dict):
        out.append("verify job is missing")
        verify = {}
    if "if" in verify:
        out.append("the verify job is conditional")
    if verify.get("continue-on-error") not in (None, False):
        out.append("the verify job is allowed to fail")
    strategy = verify.get("strategy", {})
    matrix = strategy.get("matrix", {}) if isinstance(strategy, dict) else {}
    if matrix != {"include": EXPECTED_MATRIX}:
        out.append("verify matrix is not the two expected static hosts")
    steps = verify.get("steps")
    if not isinstance(steps, list):
        out.append("verify steps are missing")
        steps = []
    for expected in EXPECTED_VERIFIERS:
        matching = [step for step in steps if isinstance(step, dict) and step.get("name") == expected["name"]]
        if matching != [expected]:
            out.append(f"{expected['name']} is not the exact required verifier step")
    if contains_key(workflow, "continue-on-error") or contains_failure_swallow(workflow):
        out.append("a workflow command or step is allowed to fail")
    if contains_secret(workflow):
        out.append("reads the secrets context")
    comments = version_comments(text)
    for ref in action_refs(workflow):
        if not isinstance(ref, str) or not re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", ref) or not re.search(r"^v[0-9]", comments.get(ref, "")):
            out.append(f"action not pinned by commit with a version comment: {ref}")
    return out


def main(argv):
    if len(argv) > 2:
        print(__doc__)
        return 2
    path = pathlib.Path(argv[1]) if len(argv) == 2 else DEFAULT
    try:
        text = path.read_text()
        findings = check(text)
    except OSError as error:
        print(f"cannot read {path}: {error}")
        return 2
    except YamlError as error:
        print(f"cannot parse {path}: {error}")
        return 1
    for finding in findings:
        print(f"FAIL: {finding}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
