#!/bin/sh
# Reads, without writing anything, the values, descriptors and configs the settings
# modal asks for, from the TV behind `ssh lg-tv`. Input is the output of
# `node settings-check.js keys`; output is the state file for `settings-check.js run`.
set -eu
KEYS=$1
python3 -I - "$KEYS" <<'PY'
import json, subprocess, sys

def luna(uri, params):
    command = "luna-send -f -n 1 -w 8000 %s '%s'" % (uri, json.dumps(params))
    out = subprocess.run(["ssh", "-tt", "lg-tv", command], capture_output=True, text=True).stdout
    try:
        return json.loads(out.replace("\r", ""))
    except ValueError:
        return {}

wanted = json.load(open(sys.argv[1]))
state = {"values": [], "descs": [], "configs": {}}
for category, keys in wanted["keys"].items():
    if category == "novos":
        continue
    asked = {"category": category, "keys": keys}
    state["values"].append(luna("luna://com.webos.settingsservice/getSystemSettings", asked))
    desc = luna("luna://com.webos.settingsservice/getSystemSettingDesc", asked)
    desc["asked"] = asked
    state["descs"].append(desc)
if wanted["configs"]:
    state["configs"] = luna("luna://com.webos.service.config/getConfigs",
                            {"configNames": wanted["configs"]}).get("configs", {})
apps = luna("luna://com.webos.applicationManager/listApps", {}).get("apps", [])
state["apps"] = [app["id"] for app in apps]
json.dump(state, sys.stdout)
PY
