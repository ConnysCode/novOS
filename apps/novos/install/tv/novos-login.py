#!/usr/bin/env python3
"""Signs an LG account in on this TV with a code, as LG's own account app does ("easyLogin").

    novos-login.py serve [--folder /tmp/novos-login]

The settings page "Profil hinzufügen" leaves a command in <folder>/command.ini (SetupBridge);
the supervisor starts this service for it, and the service answers in <folder>/state.json:

  code   asks LG for a new code: a QR code and a short code for LG's sign-in page on a phone.
         Then it asks LG every 5 s whether someone signed in there; once they did, it fetches
         the account (EMP) and signs it in with luna://com.webos.service.accountmanager/loginAccount.
  close  ends the service; it also ends by itself when the code expires.

phase: starting, waiting, finishing, done, offline, expired, error (with "error").

The two app keys LG's servers want are read at run time from LG's account web app, never
kept in novOS: the web app is fetched, unpacked with the TV's node (it is brotli) and the
keys taken from it. They are cached for a day in the folder. See docs/profile-sign-in.md.
"""

import importlib.util
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

FOLDER = "/tmp/novos-login"
HERE = os.path.dirname(os.path.abspath(__file__))
WEB_APP = "https://%s.membership.lgwebostv.com/membership-webapp_2024/"
SDP = "https://%s.nextlgsdp.com/home/easyLogin/9.0.0/"
EMP = "https://%s.emp.lgsmartplatform.com/emp/v2.0/account/user/detail"
POLL_EVERY = 5
KEYS_FOR = 24 * 3600
TIMEOUT = 20

SDP_HEADERS = ["Accept", "Authorization", "X-Authentication", "X-Device-ContentsQA-Flag", "X-Device-Country",
               "X-Device-Country-Group", "X-Device-Eco-Info", "X-Device-Eula", "X-Device-FCK",
               "X-Device-FW-Version", "X-Device-ID", "X-Device-Language", "X-Device-Locale", "X-Device-Model",
               "X-Device-Netcast-Platform-Version", "X-Device-Platform", "X-Device-Product",
               "X-Device-Publish-Flag", "X-Device-Remote-Flag", "X-Device-SDK-VERSION", "X-Device-Sales-Model",
               "X-Device-Type", "X-SDPUser-Number", "X-User-Number"]
EMP_HEADERS = ["Accept", "X-Authentication", "X-Device-Country", "X-Device-Language", "X-Device-Model",
               "X-Device-Publish-Flag", "X-Device-Type"]


def _upload_module():
    spec = importlib.util.spec_from_file_location("novos_upload", os.path.join(HERE, "novos-upload.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def luna(url, payload):
    """One luna call through the supervisor's helper, which gives luna-send its terminal."""
    try:
        text = subprocess.run(["python3", os.path.join(HERE, "novos-supervisor.py"), "call", url,
                               json.dumps(payload)], capture_output=True, text=True, timeout=30).stdout
        return json.loads(text or "{}")
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


class LoginError(Exception):
    pass


def fetch(url, headers=None, timeout=TIMEOUT):
    request = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(request, timeout=timeout) as answer:
        return answer.read()


def fetch_json(url, headers):
    try:
        return json.loads(fetch(url, headers).decode("utf-8", "replace") or "{}")
    except urllib.error.HTTPError as error:
        try:
            body = json.loads(error.read().decode("utf-8", "replace") or "{}")
        except ValueError:
            body = {}
        code = str(((body.get("error") or {}).get("code")) or error.code)
        raise LoginError(code)


def unpack(data):
    """LG serves its web app only brotli-packed; the TV's node can unpack it."""
    script = ("const z=require('zlib');let b=[];process.stdin.on('data',d=>b.push(d));"
              "process.stdin.on('end',()=>process.stdout.write(z.brotliDecompressSync(Buffer.concat(b))))")
    done = subprocess.run(["node", "-e", script], input=data, capture_output=True, timeout=60)
    if done.returncode != 0:
        raise LoginError("unpack")
    return done.stdout.decode("utf-8", "replace")


def read_keys(folder, region):
    cache = os.path.join(folder, "keys.json")
    try:
        with open(cache) as file:
            keys = json.load(file)
        if time.time() - float(keys.get("at", 0)) < KEYS_FOR and keys.get("sdp") and keys.get("emp"):
            return keys
    except (OSError, ValueError):
        pass
    base = WEB_APP % region.lower()
    page = fetch(base + "membership.html").decode("utf-8", "replace")
    found = re.search(r'src="/membership-webapp_2024/(app\.[0-9a-f]+\.js(?:\.br)?)"', page)
    if not found:
        raise LoginError("keys")
    data = fetch(base + found.group(1), timeout=60)
    text = unpack(data) if found.group(1).endswith(".br") else data.decode("utf-8", "replace")
    sdp = re.search(r'"x-lge-appKey"\]=\w+\["a"\]\.isPublishServer\(\)\?"([0-9a-f]+)"', text)
    emp = re.search(r'"X-Application-Key"\]="([0-9a-f]+)"', text)
    if not sdp or not emp:
        raise LoginError("keys")
    keys = {"sdp": sdp.group(1), "emp": emp.group(1), "bundle": found.group(1), "at": time.time()}
    descriptor = os.open(cache, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as file:
        json.dump(keys, file)
    return keys


def adult_status(account):
    """As LG's actLoginAccount derives it."""
    adult = account.get("isAdult")
    if account.get("authUser") == "Y":
        return "Verified" if adult == "Y" else ("false" if adult == "N" else "needAge")
    return "notVerified" if adult == "Y" else ("false" if adult == "N" else "needAge")


class Service:
    def __init__(self, folder):
        self.folder = folder
        self.upload = _upload_module()
        self.serial = ""
        self.phase = "starting"
        self.error = ""
        self.device = None
        self.headers = None
        self.keys = None
        self.qr = ""
        self.profile = {}
        self.revision = 0

    def publish(self, serving=True):
        self.revision += 1
        state = {"serving": serving, "pid": os.getpid(), "id": self.serial, "phase": self.phase,
                 "error": self.error, "revision": self.revision, "profile": self.profile}
        if self.device and self.phase in ("waiting", "finishing"):
            state.update({"url": self.device.get("verificationURL", ""), "code": self.device.get("userCode", ""),
                          "qr": self.qr, "expires": self.expires()})
        self.upload.write_json(self.folder + "/state.json", state)

    def expires(self):
        value = int(str(self.device.get("expirationEpochTime", "0")) or 0) if self.device else 0
        return value // 1000 if value > 10 ** 11 else value

    def online(self):
        status = luna("luna://com.palm.connectionmanager/getstatus", {})
        return status.get("isInternetConnectionAvailable") is True

    def prepare(self):
        raw = luna("luna://com.webos.service.sdx/getHttpHeaderForServiceRequest", {})
        if not raw.get("HOST"):
            raise LoginError("headers")
        region = str(raw["HOST"]).split(".")[0]
        self.keys = read_keys(self.folder, region)
        sdp = {name: str(raw[name]) for name in SDP_HEADERS if name in raw}
        sdp.update({"x-lge-appKey": self.keys["sdp"], "X-Device-Language-Type": "IETF"})
        emp = {name: str(raw[name]) for name in EMP_HEADERS if name in raw}
        if "X-Device-Platform" in raw:
            emp["X-Platform-Code"] = str(raw["X-Device-Platform"])
        emp["X-Application-Key"] = self.keys["emp"]
        self.headers = {"region": region, "sdp": sdp, "emp": emp}

    def new_code(self):
        self.phase = "starting"
        self.error = ""
        self.device = None
        self.publish()
        if not self.online():
            self.phase = "offline"
            self.publish()
            return
        try:
            if self.headers is None:
                self.prepare()
            answer = fetch_json(SDP % self.headers["region"] + "device", self.headers["sdp"])
            self.device = answer.get("easyLoginDevice") or {}
            if not self.device.get("deviceCode"):
                raise LoginError("code")
        except (LoginError, OSError, ValueError) as error:
            self.fail(error)
            return
        if self.qr:
            remove(self.qr)
        self.qr = "%s/qr-%s.png" % (self.folder, self.serial)
        address = str(self.device.get("verificationURL", ""))
        link = address if address.startswith("http") else "https://" + address
        self.upload.write_png(self.qr, self.upload.qr_matrix(link))
        self.phase = "waiting"
        self.publish()

    def fail(self, error):
        self.phase = "error"
        self.error = str(error.args[0] if getattr(error, "args", None) else error)[:40]
        self.publish()

    def poll(self):
        try:
            answer = fetch_json(SDP % self.headers["region"] + "loginSession/" + self.device["deviceCode"],
                                self.headers["sdp"])
        except LoginError:
            return False          # nobody signed in yet; LG answers with an error code meanwhile
        except (OSError, ValueError):
            return False
        session = ((answer.get("easyLoginSession") or {}).get("empLoginSessionId") or "")
        if not session:
            return False
        self.finish(session)
        return True

    def finish(self, session):
        self.phase = "finishing"
        self.publish()
        try:
            headers = dict(self.headers["emp"])
            headers["X-Login-Session"] = session
            detail = fetch_json(EMP % self.headers["region"], headers)
            account = (detail.get("account") or {})
            if not account.get("userNo"):
                raise LoginError("account")
            status = adult_status(account)
            request = {"serviceName": "LGE", "id": str(account.get("displayUserID") or account.get("userID") or ""),
                       "userData": {"userNumber": account["userNo"], "adultAuthStatus": status,
                                    "adultAuthStatusNew": status, "serverId": str(account.get("userID") or "")},
                       "loginSession": session, "accountType": str(account.get("userIDType") or "LGE"),
                       "countryCode": str(account.get("country") or "")}
            signed = luna("luna://com.webos.service.accountmanager/getLoginID", {"serviceName": "LGE"})
            if signed.get("id"):
                request["mode"] = "switch"
                request["userNo"] = account["userNo"]
            answer = luna("luna://com.webos.service.accountmanager/loginAccount", request)
            if answer.get("returnValue") is not True and str(answer.get("errCode")) != "0003":
                raise LoginError("login " + str(answer.get("errCode") or answer.get("errorText") or ""))
        except (LoginError, OSError, ValueError, KeyError) as error:
            self.fail(error)
            return
        self.profile = {"userNo": account["userNo"]}
        self.phase = "done"
        self.publish()

    def run(self):
        os.makedirs(self.folder, exist_ok=True)
        handled = ""
        last_poll = 0.0
        idle_since = time.time()
        try:
            while True:
                command = self.upload.read_ini(self.folder + "/command.ini")
                serial = command.get("serial", "")
                if serial and serial != handled:
                    handled = serial
                    idle_since = time.time()
                    if command.get("command") == "close":
                        break
                    if command.get("command") == "code":
                        self.serial = serial
                        self.new_code()
                        last_poll = time.time()
                if self.phase == "waiting":
                    if time.time() > self.expires():
                        self.phase = "expired"
                        self.publish()
                    elif time.time() - last_poll >= POLL_EVERY:
                        last_poll = time.time()
                        self.poll()
                elif self.phase in ("done", "error", "offline", "expired") and time.time() - idle_since > 600:
                    break
                time.sleep(0.3)
        finally:
            if self.qr:
                remove(self.qr)
            self.device = None
            self.publish(serving=False)


def remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


def main():
    arguments = sys.argv[1:]
    if arguments[:1] != ["serve"]:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    options = dict(zip(arguments[1::2], arguments[2::2]))
    Service(options.get("--folder", FOLDER)).run()


if __name__ == "__main__":
    main()
