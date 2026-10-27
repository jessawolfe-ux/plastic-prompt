#!/bin/bash
# Plastic Prompt installer: asks which colour of plastic you want, builds the app, puts it in ~/Applications,
# and connects it to Claude Code (adds a few hooks to ~/.claude/settings.json, backing it up first).
#
#   ./install.sh            set up from scratch (asks the colour)
#   ./install.sh --rebuild  rebuild and relaunch after changing the code, keeping your colour and permissions
#   ./install.sh --update   get the newest version from GitHub, then rebuild
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Plastic Prompt.app"
DATA="$HOME/Library/Application Support/PromptBar"
BUNDLE="art.jessa.plasticprompt"
MODE="${1:-}"
c() { printf "\033[38;2;%d;%d;%dm██\033[0m" "$1" "$2" "$3"; }

if [ "$MODE" = "--update" ]; then
  echo "  Getting the newest Plastic Prompt…"; git pull --ff-only; MODE="--rebuild"
fi
if [ "$MODE" = "--rebuild" ] && [ ! -d "$APP" ]; then MODE=""; fi   # never installed: ask the question

if [ "$MODE" != "--rebuild" ]; then
echo ""
echo "  💾  Hi! Let's set up Plastic Prompt."
echo ""
echo "  Which plastic? (the 1998 and 1999 iMac colours)"
echo ""
echo "    1) $(c 31 181 201) Bondi blue    5) $(c 140 147 160) Graphite"
echo "    2) $(c 255 95 162) Strawberry    6) $(c 90 99 216) Indigo"
echo "    3) $(c 255 138 42) Tangerine     7) $(c 155 226 74) Key Lime"
echo "    4) $(c 58 160 255) Blueberry"
echo ""
read -r -p "  Pick one [1]: " pick
case "${pick:-1}" in [1-7]) COLOUR=$((pick - 1));; *) COLOUR=0;; esac
defaults write "$BUNDLE" colour -int "$COLOUR"
NAMES=("Bondi blue" "Strawberry" "Tangerine" "Blueberry" "Graphite" "Indigo" "Key Lime")
echo ""
echo "  ✓ ${NAMES[$COLOUR]} it is. (You can change it any time from the right-click menu.)"
echo ""
fi   # end of the question

# --- build ---
if ! command -v swiftc >/dev/null; then
  echo "  Plastic Prompt needs Apple's command line tools to build. Installing them now (a window will pop up)…"
  xcode-select --install || true
  echo "  When that finishes, run ./install.sh again."; exit 1
fi
echo "  Building Plastic Prompt… (about 30 seconds)"
rm -rf build && mkdir -p "build/Plastic Prompt.app/Contents/MacOS" "build/Plastic Prompt.app/Contents/Resources/sfx"
if ! swiftc -O PlasticPrompt.swift -o "build/Plastic Prompt.app/Contents/MacOS/PlasticPrompt" 2> build/errors.txt; then
  # some Command Line Tools versions ship a duplicate Swift module map; build around it if so
  if grep -q "redefinition of module" build/errors.txt; then
    printf '' > build/empty.modulemap
    printf '{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "file", "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap", "external-contents": "%s/build/empty.modulemap" } ] }\n' "$PWD" > build/overlay.yaml
    swiftc -O -vfsoverlay build/overlay.yaml PlasticPrompt.swift -o "build/Plastic Prompt.app/Contents/MacOS/PlasticPrompt"
  else cat build/errors.txt; exit 1; fi
fi
cp assets/AppIcon.icns "build/Plastic Prompt.app/Contents/Resources/AppIcon.icns"
for d in sfx/*/; do n="$(basename "$d")"; case "$n" in _raw|hits) continue;; esac; mkdir -p "build/Plastic Prompt.app/Contents/Resources/sfx/$n"; cp "$d"*.wav "build/Plastic Prompt.app/Contents/Resources/sfx/$n/"; done
cat > "build/Plastic Prompt.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Plastic Prompt</string>
  <key>CFBundleDisplayName</key><string>Plastic Prompt</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE</string>
  <key>CFBundleExecutable</key><string>PlasticPrompt</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Plastic Prompt pastes your message into Terminal, where Claude Code is running.</string>
</dict></plist>
PLIST

# --- sign it with a local certificate (made once, kept in your login keychain) so macOS remembers its
# Terminal and Accessibility permissions every time it's rebuilt. Mochi's cert is reused if you have her.
CERT="Plastic Prompt Local Signing"
security find-certificate -c "Mochi Local Signing" >/dev/null 2>&1 && CERT="Mochi Local Signing"
if ! security find-certificate -c "$CERT" >/dev/null 2>&1; then
  T="$(mktemp -d)"
  cat > "$T/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/key.pem" -out "$T/cert.pem" -days 3650 -config "$T/cert.cnf" >/dev/null 2>&1
  openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -name "$CERT" -out "$T/pp.p12" -passout pass:plastic >/dev/null 2>&1
  security import "$T/pp.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P plastic -T /usr/bin/codesign >/dev/null 2>&1 || true
  rm -rf "$T"
fi
if security find-certificate -c "$CERT" >/dev/null 2>&1 && codesign --force --sign "$CERT" "build/Plastic Prompt.app" >/dev/null 2>&1; then
  echo "  ✓ Signed (macOS will remember its permissions through future rebuilds)"
else
  codesign --force --sign - "build/Plastic Prompt.app" >/dev/null 2>&1 || true
fi
pkill -x PlasticPrompt 2>/dev/null || true
mkdir -p "$HOME/Applications" && rm -rf "$APP" && cp -R "build/Plastic Prompt.app" "$APP"
echo "  ✓ Plastic Prompt is in ~/Applications"

# --- connect it to Claude Code: hooks that write what Claude is doing into ~/Library/Application Support/PromptBar/
mkdir -p "$DATA/hooks" && cp hooks/notify.py "$DATA/hooks/notify.py"
python3 - "$DATA/hooks/notify.py" <<'PY'
import json, os, shutil, sys, time
notify = sys.argv[1]; path = os.path.expanduser("~/.claude/settings.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
s = json.load(open(path)) if os.path.exists(path) else {}
hooks = s.setdefault("hooks", {})
# the same hooks already here (the Prompt Bar, or an earlier install): nothing to add
have = [h.get("command", "") for arr in hooks.values() for m in arr for h in m.get("hooks", [])]
if any("notify.py" in c and ("prompt-bar" in c or "PromptBar" in c) for c in have):
    print("  ✓ Claude Code is already connected (the Prompt Bar hooks are in place)"); sys.exit()
before = json.dumps(s, sort_keys=True)
cmd = lambda flag: f'python3 "{notify}"{(" " + flag) if flag else ""} 2>/dev/null || true'
want = [("Stop", None, "", 10), ("UserPromptSubmit", None, "--working", 5), ("PreToolUse", "AskUserQuestion", "--question", 5),
        ("PreToolUse", "*", "--doing", 5), ("PostToolUse", "AskUserQuestion", "--answered", 5), ("PostToolUse", "*", "--progress", 5)]
for ev, matcher, flag, t in want:
    arr = hooks.setdefault(ev, [])
    entry = {"hooks": [{"type": "command", "command": cmd(flag), "timeout": t}]}
    if matcher: entry["matcher"] = matcher
    arr.append(entry)
if json.dumps(s, sort_keys=True) != before:
    if os.path.exists(path): shutil.copy(path, path + ".before-plastic-prompt-" + time.strftime("%Y%m%d-%H%M%S"))
    json.dump(s, open(path, "w"), indent=2)
    print("  ✓ Connected to Claude Code (your old settings were backed up next to ~/.claude/settings.json)")
PY

open "$APP"
if [ "$MODE" = "--rebuild" ]; then echo "  💾  Rebuilt and back."; exit 0; fi
echo ""
echo "  💾  Plastic Prompt is up. Look for it at the bottom right of your screen (drag it anywhere)."
echo ""
echo "  One permission, once:"
echo "  • Automation: the first time you send a message, macOS asks to let Plastic Prompt control"
echo "    Terminal (and System Events). Say OK. Terminal writes your line into the Claude tab itself,"
echo "    so nothing comes forward while you type."
echo "  • Only if you turn on 'Bring Terminal forward when sending' in the menu: also allow it under"
echo "    System Settings → Privacy & Security → Accessibility."
echo ""
echo "  • Type in the pill and press Return. Replies show up on the screen."
echo "  • Click the little box at the top left of the screen for the desktop: one icon per Claude tab."
echo "  • Right-click anywhere on it for colours, sounds, Open at Login and Quit."
echo ""
