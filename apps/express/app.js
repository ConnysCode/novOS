const csrfToken = document.documentElement.dataset.csrf;
const card = document.querySelector("#card");
const views = card.querySelectorAll(".card-view");
const deviceList = document.querySelector("#device-list");
const empty = document.querySelector("#empty");
const listMessage = document.querySelector("#list-message");
const listTitle = document.querySelector("#card-title");
const scanStatus = document.querySelector("#scan-status");
const rescanButton = document.querySelector("#rescan-button");
const confirmTitle = document.querySelector("#confirm-title");
const openButton = document.querySelector("#open-button");
const cancelButton = document.querySelector("#cancel-button");
const startingTarget = document.querySelector("#starting-target");
const doneTitle = document.querySelector("#done-title");
const againButton = document.querySelector("#again-button");
const sky = document.querySelector("#sky");
const ipHint = document.querySelector("#ip-hint");
const ipToggle = document.querySelector("#ip-toggle");
const ipForm = document.querySelector("#ip-form");
const ipInput = document.querySelector("#ip-input");
const ipSubmit = document.querySelector("#ip-submit");
const ipError = document.querySelector("#ip-error");

const SVG = "http://www.w3.org/2000/svg";

let devices = [];
let scanning = false;
let scanSerial = 0;
let chosen = null;
let ipOpen = false;
let adding = false;

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function tvIcon() {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("focusable", "false");
  svg.classList.add("icon");
  const screen = document.createElementNS(SVG, "rect");
  for (const [key, value] of Object.entries({
    x: "2.5",
    y: "4.5",
    width: "19",
    height: "12.5",
    rx: "2",
  })) {
    screen.setAttribute(key, value);
  }
  const stand = document.createElementNS(SVG, "path");
  stand.setAttribute("d", "M8.5 20.5h7");
  svg.append(screen, stand);
  return svg;
}

function displayName(device) {
  return device.name || device.model || "LG-Fernseher";
}

function quoted(device) {
  return "„" + displayName(device) + "“";
}

function showView(name, focusTarget) {
  for (const view of views) view.hidden = view.dataset.view !== name;
  placeHorizon();
  if (focusTarget) {
    focusTarget.setAttribute("tabindex", "-1");
    focusTarget.focus({ preventScroll: true });
  }
}

function showListMessage(text, state = "") {
  listMessage.textContent = text;
  listMessage.dataset.state = state;
}

function deviceMeta(device) {
  if (device.state === "error") return device.reason;
  const parts = [device.model || "LG-Fernseher"];
  if (device.webos) parts.push("webOS " + device.webos);
  else if (device.firmware) parts.push("Firmware " + device.firmware);
  else parts.push(device.address);
  return parts.join(" · ");
}

function statusPill(device) {
  const pill = element("span", "pill");
  pill.dataset.state = device.state;
  if (device.state === "checking") {
    const spinner = element("span", "spinner");
    spinner.setAttribute("aria-hidden", "true");
    pill.append(spinner, "Wird geprüft");
  } else if (device.state === "ready") {
    pill.textContent = "Bereit";
  } else {
    pill.textContent = "Nicht bereit";
  }
  return pill;
}

function renderDevices() {
  deviceList.replaceChildren();
  const nothingFound = !scanning && devices.length === 0;
  listTitle.dataset.empty = String(nothingFound);
  scanStatus.hidden = !scanning;
  rescanButton.hidden = scanning;
  empty.hidden = !nothingFound;
  deviceList.hidden = nothingFound;
  ipForm.hidden = !(nothingFound || ipOpen);
  ipHint.hidden = nothingFound || ipOpen || scanning;
  ipToggle.setAttribute("aria-expanded", String(ipOpen));
  ipSubmit.disabled = scanning || adding;

  if (scanning && devices.length === 0) {
    const row = element("li", "device device-placeholder");
    row.textContent = "Einen Moment, die Suche dauert ein paar Sekunden.";
    deviceList.append(row);
    placeHorizon();
    return;
  }

  for (const device of devices) {
    const row = element("li", "device");
    row.dataset.state = device.state;

    const icon = element("span", "device-icon");
    icon.append(tvIcon());

    const copy = element("span", "device-copy");
    const title = element("span", "device-title");
    title.append(element("span", "device-name", displayName(device)), statusPill(device));
    copy.append(title, element("span", "device-meta", deviceMeta(device)));

    row.append(icon, copy);

    if (device.state === "ready") {
      const action = element("span", "device-action");
      const button = element("button", "button button-primary", "Installieren");
      button.type = "button";
      button.setAttribute("aria-label", "novOS auf " + quoted(device) + " installieren");
      button.addEventListener("click", () => askToOpen(device));
      action.append(button);
      row.append(action);
    }
    deviceList.append(row);
  }
  placeHorizon();
}

async function checkDevice(device, serial) {
  if (!device.ssh) {
    device.state = "error";
    device.reason = "Kein Root-Zugang per SSH erreichbar.";
    return;
  }
  const result = await fetch("/api/status?tv=" + encodeURIComponent(device.id), {
    cache: "no-store",
  })
    .then((response) => response.json().then((body) => ({ ok: response.ok, body })))
    .catch(() => ({ ok: false, body: {} }));
  if (serial !== scanSerial) return;
  if (result.ok && result.body.ready === true) {
    device.state = "ready";
    device.model = result.body.model || device.model;
    device.firmware = result.body.firmware || "";
    device.webos = result.body.webos || "";
  } else {
    device.state = "error";
    device.reason =
      result.body.error || "Die Verbindung zu diesem Fernseher konnte nicht geprüft werden.";
  }
  renderDevices();
}

async function scanDevices() {
  if (scanning) return;
  const serial = ++scanSerial;
  scanning = true;
  devices = [];
  showListMessage("");
  renderDevices();

  const result = await fetch("/api/tvs", { cache: "no-store" })
    .then((response) => response.json().then((body) => ({ ok: response.ok, body })))
    .catch(() => ({
      ok: false,
      body: { error: "Der lokale Dienst antwortet nicht. Läuft server.py noch?" },
    }));
  if (serial !== scanSerial) return;

  scanning = false;
  if (!result.ok) {
    devices = [];
    showListMessage(result.body.error || "Die Suche ist fehlgeschlagen.", "error");
    renderDevices();
    return;
  }
  devices = (Array.isArray(result.body.devices) ? result.body.devices : [])
    .filter((device) => device && typeof device.id === "string" && device.id)
    .map((device) => ({ ...device, state: "checking", reason: "" }));
  if (devices.length > 0 && result.body.message) showListMessage(result.body.message);
  renderDevices();
  await Promise.all(devices.map((device) => checkDevice(device, serial)));
  if (serial === scanSerial) renderDevices();
}

function showIpError(text) {
  ipError.textContent = text;
  ipInput.setAttribute("aria-invalid", String(Boolean(text)));
}

async function addAddress(event) {
  event.preventDefault();
  if (adding || scanning) return;
  const address = ipInput.value.trim();
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(address)) {
    showIpError("Bitte eine IP-Adresse wie 192.168.178.20 eingeben.");
    ipInput.focus();
    return;
  }
  adding = true;
  showIpError("");
  ipSubmit.textContent = "Verbinde …";
  renderDevices();

  const serial = scanSerial;
  const result = await fetch("/api/device?address=" + encodeURIComponent(address), {
    method: "POST",
    headers: { Accept: "application/json", "X-Novos-CSRF": csrfToken },
  })
    .then((response) => response.json().then((body) => ({ ok: response.ok, body })))
    .catch(() => ({
      ok: false,
      body: { error: "Der lokale Dienst antwortet nicht. Läuft server.py noch?" },
    }));

  adding = false;
  ipSubmit.textContent = "Verbinden";
  if (result.ok && serial !== scanSerial) {
    // A new scan started meanwhile; the server keeps the address for that list.
    renderDevices();
    return;
  }
  if (!result.ok || !result.body.device) {
    showIpError(result.body.error || "Dieser Fernseher konnte nicht hinzugefügt werden.");
    renderDevices();
    ipInput.focus();
    return;
  }
  const device = { ...result.body.device, state: "checking", reason: "" };
  devices = devices.filter((item) => item.address !== device.address).concat(device);
  ipOpen = false;
  ipInput.value = "";
  showListMessage("");
  renderDevices();
  checkDevice(device, serial);
}

function askToOpen(device) {
  chosen = device;
  confirmTitle.textContent = "Assistent auf " + quoted(device) + " öffnen?";
  showView("confirm", confirmTitle);
}

function backToList(message = "", state = "") {
  chosen = null;
  showView("list", listTitle);
  showListMessage(message, state);
}

async function openWizard() {
  if (!chosen) return;
  const device = chosen;
  startingTarget.textContent = "Wartet auf " + quoted(device);
  showView("starting", card.querySelector('[data-view="starting"] h2'));

  const result = await fetch("/api/start?tv=" + encodeURIComponent(device.id), {
    method: "POST",
    headers: { Accept: "application/json", "X-Novos-CSRF": csrfToken },
  })
    .then((response) => response.json().then((body) => ({ ok: response.ok, body })))
    .catch(() => ({
      ok: false,
      body: { error: "Verbindung zum lokalen Dienst fehlgeschlagen." },
    }));

  if (result.ok && result.body.ok === true) {
    doneTitle.textContent = "Der Assistent läuft auf " + quoted(device);
    showView("done", doneTitle);
    return;
  }
  backToList(
    (result.body.error || "Der Assistent konnte nicht geöffnet werden.") +
      " (" +
      displayName(device) +
      ")",
    "error",
  );
}

/* The horizon sits behind the card: centered on desktop, peeking above it when stacked. */
function placeHorizon() {
  const box = card.getBoundingClientRect();
  const top = box.top + window.scrollY;
  const left = box.left + window.scrollX;
  const stacked = window.matchMedia("(max-width: 1100px)").matches;
  const x = left + box.width * (stacked ? 0.65 : 0.5);
  const y = stacked ? top - 30 : top + 442;
  sky.style.setProperty("--hx", Math.round(x) + "px");
  sky.style.setProperty("--hy", Math.round(y) + "px");
}

rescanButton.addEventListener("click", scanDevices);
ipToggle.addEventListener("click", () => {
  ipOpen = true;
  renderDevices();
  ipInput.focus();
});
ipForm.addEventListener("submit", addAddress);
openButton.addEventListener("click", openWizard);
cancelButton.addEventListener("click", () => backToList());
againButton.addEventListener("click", () => {
  backToList();
  scanDevices();
});
window.addEventListener("resize", placeHorizon);
document.fonts?.ready.then(placeHorizon);

placeHorizon();
scanDevices();
