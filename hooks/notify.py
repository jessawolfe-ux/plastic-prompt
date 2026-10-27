#!/usr/bin/env python3
# Claude Code hooks for Mochi (the Prompt Bar). Everything lands in ~/Library/Application Support/PromptBar/.
#   (no flag)     Stop hook: the reply, as a short summary plus the whole text (cleaned up) for the paged bubble -> last.json
#   --working     UserPromptSubmit: Claude has started working (Mochi thinks, the meter starts)          -> working.json
#   --progress    PostToolUse: what Claude has said so far this turn, plus time and tokens for the meter -> progress.json
#   --question    PreToolUse on AskUserQuestion: the question and its options, and which Terminal tab    -> question.json
#   --answered    PostToolUse on AskUserQuestion: the question is answered, take the pop-up down
import json, os, re, subprocess, sys, time

DIR = os.path.expanduser("~/Library/Application Support/PromptBar")
OUT = os.path.join(DIR, "last.json")


def write(name, obj):
    os.makedirs(DIR, exist_ok=True)
    p = os.path.join(DIR, name)
    with open(p + ".tmp", "w") as f:
        json.dump(obj, f)
    os.replace(p + ".tmp", p)


def entries(path, tail=600_000):
    # the newest part of the transcript (it can get big, and only this turn matters)
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - tail))
            data = f.read().decode("utf-8", "ignore")
    except OSError:
        return []
    out = []
    for line in data.splitlines()[1 if size > tail else 0:]:
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def texts(e):
    c = e.get("message", {}).get("content")
    parts = [c] if isinstance(c, str) else [b.get("text", "") for b in c or [] if isinstance(b, dict) and b.get("type") == "text"]
    return "\n".join(p for p in parts if p.strip())


def is_prompt(e):
    # a message typed by the person (not a tool result coming back)
    if e.get("type") != "user":
        return False
    c = e.get("message", {}).get("content")
    if isinstance(c, str):
        return True
    blocks = [b for b in c or [] if isinstance(b, dict)]
    # messages sent mid-turn ride along with tool results; those don't start a new turn
    return any(b.get("type") == "text" for b in blocks) and not any(b.get("type") == "tool_result" for b in blocks)


def this_turn(d):
    es = entries(d.get("transcript_path", ""))
    start = 0
    for i, e in enumerate(es):
        if is_prompt(e):
            start = i + 1
    return es[start:]


def last_reply(d):
    if d.get("last_assistant_message"):
        return d["last_assistant_message"]
    text = ""
    for e in entries(d.get("transcript_path", "")):
        if e.get("type") == "assistant" and texts(e).strip():
            text = texts(e)
    return text


def clean(t, limit=4000):
    # the whole reply, readable in a little bubble: no code blocks, tables or markdown marks
    t = re.sub(r"```.*?```", " [code] ", t, flags=re.S)
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", t)
    lines = []
    for ln in t.split("\n"):
        s = ln.strip()
        if s.startswith("|") or re.fullmatch(r"[-*_]{3,}", s):
            continue
        s = re.sub(r"^#+\s*", "", s)
        s = re.sub(r"^[-*]\s+", "• ", s)
        s = re.sub(r"[*_`]+", "", s)
        lines.append(s)
    t = re.sub(r"\n{2,}", "\n", "\n".join(lines)).strip()
    return t if len(t) <= limit else t[:limit - 1].rsplit(" ", 1)[0] + "…"


def summarize(t, limit=150):
    t = re.sub(r"```.*?```", " ", t, flags=re.S)
    t = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", t)
    t = re.sub(r"[*_`#>]+", "", t)
    # the first paragraph, plus the next ones while it's short (so a greeting like "Hi Michael!" doesn't hide the answer)
    paras = [p.strip() for p in re.split(r"\n\s*\n", t) if p.strip() and not p.strip().startswith("|")]
    para = ""
    for p in paras:
        para = (para + " " + p).strip()
        if len(para) >= 60:
            break
    para = re.sub(r"\s+", " ", para)
    out = ""
    for s in re.split(r"(?<=[.!?])\s+", para):
        if out and len(out) + len(s) + 1 > limit:
            break
        out = (out + " " + s).strip()
    if len(out) > limit:
        out = out[:limit - 1].rsplit(" ", 1)[0] + "…"
    return out


def tty_of_claude():
    # walk up from this hook to the claude process and read its terminal (like /dev/ttys002)
    pid = os.getppid()
    for _ in range(6):
        try:
            out = subprocess.run(["ps", "-o", "tty=,ppid=", "-p", str(pid)], capture_output=True, text=True).stdout.split()
        except OSError:
            return ""
        if len(out) < 2:
            return ""
        if out[0].startswith("ttys"):
            return "/dev/" + out[0]
        pid = int(out[1])
    return ""


d = json.load(sys.stdin)
project = os.path.basename(d.get("cwd", "").rstrip("/"))

if "--working" in sys.argv:
    write("working.json", {"project": project, "time": time.time()})
    try:
        os.remove(os.path.join(DIR, "progress.json"))
    except OSError:
        pass
    sys.exit(0)

if "--doing" in sys.argv:
    # PreToolUse: the little note for the step Claude is starting (its own description when it gave one)
    tool, ti = d.get("tool_name", ""), d.get("tool_input") or {}
    base = lambda k: os.path.basename(str(ti.get(k, "")).rstrip("/"))
    note = ti.get("description") or {
        "Read": "Reading " + base("file_path"), "Edit": "Editing " + base("file_path"), "Write": "Writing " + base("file_path"),
        "Grep": "Searching the code", "Glob": "Looking for files", "WebFetch": "Reading a web page", "WebSearch": "Searching the web",
        "Agent": "Asking a helper", "Skill": "Loading a skill", "ToolSearch": "Loading tools",
    }.get(tool, "")
    if not note and tool.startswith("mcp__"):
        note = "Using " + tool.split("__")[1].replace("claude_ai_", "").replace("_", " ")
    if note and tool != "AskUserQuestion":
        write("doing.json", {"text": note[:90], "project": project, "time": time.time()})
    sys.exit(0)

if "--progress" in sys.argv:
    turn = this_turn(d)
    seen, tokens, said = set(), 0, ""
    for e in turn:
        if e.get("type") != "assistant":
            continue
        m = e.get("message", {})
        if m.get("id") not in seen:
            seen.add(m.get("id"))
            tokens += (m.get("usage") or {}).get("output_tokens", 0)
        if texts(e).strip():
            said = texts(e)
    write("progress.json", {"project": project, "tokens": tokens, "text": clean(said) if said else "", "time": time.time()})
    sys.exit(0)

if "--question" in sys.argv:
    qs = (d.get("tool_input") or {}).get("questions") or []
    write("question.json", {"project": project, "tty": tty_of_claude(), "questions": qs,
                            "id": d.get("tool_use_id", str(time.time())), "time": time.time()})
    sys.exit(0)

if "--answered" in sys.argv:
    try:
        os.remove(os.path.join(DIR, "question.json"))
    except OSError:
        pass
    sys.exit(0)

# Stop: the finished reply
for f in ("question.json", "progress.json"):
    try:
        os.remove(os.path.join(DIR, f))
    except OSError:
        pass
full = last_reply(d)
s = summarize(full)
if s:
    write("last.json", {"text": s, "full": clean(full), "project": project, "time": time.time()})
