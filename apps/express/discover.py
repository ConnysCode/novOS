"""Find LG webOS TVs on the local multicast network without external packages."""

import ipaddress
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor


SEARCH_TARGET = "urn:lge-com:service:webos-second-screen:1"
MULTICAST = ("239.255.255.250", 1900)
PRIVATE_NETWORKS = tuple(
    ipaddress.ip_network(value)
    for value in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)
SEARCH_REQUEST = (
    "M-SEARCH * HTTP/1.1\r\n"
    "HOST: 239.255.255.250:1900\r\n"
    'MAN: "ssdp:discover"\r\n'
    "MX: 2\r\n"
    "ST: " + SEARCH_TARGET + "\r\n\r\n"
).encode("ascii")


def private_ipv4(value):
    try:
        address = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError:
        return False
    return any(address in network for network in PRIVATE_NETWORKS)


def parse_ssdp(packet):
    lines = packet.decode("iso-8859-1", errors="replace").splitlines()
    if not lines or not lines[0].startswith("HTTP/1.1 200"):
        return None
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            name, value = line.split(":", 1)
            headers[name.strip().lower()] = value.strip()
    if headers.get("st") != SEARCH_TARGET:
        return None
    return {"location": headers.get("location", ""), "server": headers.get("server", "")}


def search(wait=4):
    seen = {}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as connection:
        connection.bind(("0.0.0.0", 0))
        connection.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
        for _ in range(3):
            connection.sendto(SEARCH_REQUEST, MULTICAST)
            time.sleep(0.1)
        deadline = time.monotonic() + wait
        while time.monotonic() < deadline:
            connection.settimeout(max(0.01, deadline - time.monotonic()))
            try:
                packet, sender = connection.recvfrom(4096)
            except socket.timeout:
                break
            address = sender[0]
            if not private_ipv4(address):
                continue
            response = parse_ssdp(packet)
            if response and address not in seen:
                seen[address] = {"address": address, **response}
            if len(seen) >= 16:
                break
    return list(seen.values())


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, newurl):
        return None


def xml_value(root, name):
    for node in root.iter():
        if node.tag.rsplit("}", 1)[-1] == name:
            return (node.text or "").strip()[:100]
    return ""


def describe(answer):
    result = {"address": answer["address"], "name": "LG TV", "model": "", "ssh": False}
    location = answer["location"]
    try:
        url = urllib.parse.urlsplit(location)
        if (
            url.scheme == "http"
            and url.hostname == answer["address"]
            and url.username is None
            and url.password is None
        ):
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect)
            with opener.open(location, timeout=3) as response:
                data = response.read(65537)
            if len(data) <= 65536:
                root = ET.fromstring(data)
                result["name"] = xml_value(root, "friendlyName") or "LG TV"
                result["model"] = xml_value(root, "modelName")
    except (ValueError, OSError, ET.ParseError, urllib.error.URLError):
        pass
    result["ssh"] = ssh_reachable(answer["address"])
    return result


def ssh_reachable(address, timeout=0.7):
    try:
        with socket.create_connection((address, 22), timeout=timeout):
            return True
    except OSError:
        return False


def discover_lg_tvs(wait=4):
    answers = search(wait)
    with ThreadPoolExecutor(max_workers=8) as pool:
        devices = list(pool.map(describe, answers))
    return sorted(devices, key=lambda item: (not item["ssh"], item["name"].casefold(), item["address"]))
