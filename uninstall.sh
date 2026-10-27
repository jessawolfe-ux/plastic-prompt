#!/bin/bash
# removes Plastic Prompt, its chat log and its Claude Code hooks (Mochi's hooks, if you have Mochi, are left alone)
pkill -x PlasticPrompt 2>/dev/null || true
rm -rf "$HOME/Applications/Plastic Prompt.app" "$HOME/Library/Logs/PlasticPrompt.log"
defaults delete art.jessa.plasticprompt 2>/dev/null || true
python3 - <<'PY'
import json, os
path = os.path.expanduser("~/.claude/settings.json")
if os.path.exists(path):
    s = json.load(open(path))
    for ev, arr in list(s.get("hooks", {}).items()):
        for m in arr: m["hooks"] = [h for h in m.get("hooks", []) if "PromptBar/hooks/notify.py" not in h.get("command", "")]
        s["hooks"][ev] = [m for m in arr if m.get("hooks")]
        if not s["hooks"][ev]: del s["hooks"][ev]
    json.dump(s, open(path, "w"), indent=2)
PY
rm -f "$HOME/Library/Application Support/PromptBar/hooks/notify.py"
echo "  Plastic Prompt is gone. The chime will be missed."
