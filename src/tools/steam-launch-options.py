"""Set a game's Launch Options in Steam's localconfig.vdf, so the Play button
starts it with the same arguments as `macgames launch`.

Steam rewrites localconfig.vdf on exit, so run this while Steam is stopped.

usage: steam-launch-options.py <localconfig.vdf> <appid> <options>
"""
import re, sys

path, appid, options = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding="utf-8").read().split("\n")
APPS = ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"]

stack, pending, out = [], None, []
target_depth = None  # depth of the open "<appid>" block we're editing
done = False
for line in lines:
    s = line.strip()
    if s == "{":
        stack.append(pending)
        if stack == APPS + [appid]:
            target_depth = len(stack)
        out.append(line)
        continue
    if s == "}":
        if target_depth == len(stack) and not done:
            out.append("\t" * len(stack) + f'"LaunchOptions"\t\t"{options}"')
            done = True
        if target_depth == len(stack):
            target_depth = None
        stack.pop()
        out.append(line)
        continue
    m = re.match(r'^"((?:[^"\\]|\\.)*)"\s*(?:"((?:[^"\\]|\\.)*)")?$', s)
    if m and m.group(2) is None:
        pending = m.group(1)
    elif m and target_depth == len(stack) and m.group(1) == "LaunchOptions":
        line = re.sub(r'"LaunchOptions"(\s*)"(?:[^"\\]|\\.)*"', f'"LaunchOptions"\\1"{options}"', line)
        done = True
    out.append(line)

if not done:
    sys.exit(f"app {appid} not found in {path} (play it once from Steam first)")
open(path, "w", encoding="utf-8").write("\n".join(out))
