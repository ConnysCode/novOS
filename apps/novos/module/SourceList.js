.pragma library

// The sources as tiles show them, shared by the source picker and the launcher.

// A name the user gave wins. Otherwise the name the device sends over CEC, which reads better
// than LG's own guess such as "Apple OTT".
function deviceName(device) {
    if (device.modified === true) return device.label;
    return cecName(device) || device.label;
}

// Off only counts when CEC reports it for every device on the port.
function deviceIsOff(device) {
    var known = false;
    for (var i = 0; i < device.subList.length; i++) {
        var power = device.subList[i].cecPower;
        if (power === "On") return false;
        if (power === "Off") known = true;
    }
    return known;
}

// LG's icon field to our icons. All values and where they come from are in docs/live-glass.md.
// LG draws settopbox.png and streamingbox.png from the same file.
var deviceIcons = {
    "bluray.png": "source-disc",
    "camera.png": "source-camera",
    "dvd.png": "source-disc",
    "gameconsole.png": "source-gamepad",
    "hometheater.png": "source-audio",
    "mobile.png": "source-mobile",
    "pc.png": "source-pc",
    "portaltv.png": "source-box",
    "satellite.png": "source-satellite",
    "settopbox.png": "source-box",
    "streamingbox.png": "source-box"
};

// The types LG offers for an HDMI input, in LG's order (Home Hub, IconSelectPanel). "key" is the
// text in namespace "source" as "type.<key>". eim stores the file name as it is, and pc.png also
// switches the input's PC mode, as in LG's own menu.
var iconChoices = [
    { value: "hdmigeneric.png", key: "standard" },
    { value: "satellite.png", key: "satellite" },
    { value: "settopbox.png", key: "set_top_box" },
    { value: "dvd.png", key: "dvd" },
    { value: "bluray.png", key: "bluray" },
    { value: "hometheater.png", key: "home_theater" },
    { value: "gameconsole.png", key: "game_console" },
    { value: "streamingbox.png", key: "streaming_box" },
    { value: "camera.png", key: "camera" },
    { value: "pc.png", key: "pc" },
    { value: "mobile.png", key: "mobile" }
];

// The choice for the current icon. The port icons HDMI_1.png to HDMI_4.png are the standard.
function iconChoice(device) {
    for (var i = 0; i < iconChoices.length; i++) {
        if (iconChoices[i].value === device.icon) return iconChoices[i];
    }
    return iconChoices[0];
}

// The device's own CEC name, empty without one.
function cecName(device) {
    for (var i = 0; i < device.subList.length; i++) {
        if (device.subList[i].osdName) return device.subList[i].osdName;
    }
    return "";
}

// HDMI_1.png to HDMI_4.png, hdmigeneric.png and anything unknown say nothing about the device.
function deviceIcon(device) {
    return deviceIcons[device.icon] || "source-hdmi";
}

// tr(key, params) gives the text in the language of the TV, in namespace "source".
function build(list, active, withManagement, tr) {
    var result = [];
    var empty = [];
    for (var i = 0; i < list.length; i++) {
        var device = list[i];
        var port = "HDMI " + device.port;
        if (device.hdmiPlugIn) {
            var off = deviceIsOff(device);
            result.push({ appId: device.appId, title: deviceName(device), icon: deviceIcon(device),
                          port: port, detail: off ? tr("detail.port_off", { port: port }) : port, off: off,
                          running: device.appId === active });
        } else {
            empty.push({ appId: device.appId, title: port, detail: tr("detail.no_device"),
                         icon: "source-hdmi", disabled: true });
        }
    }
    // No tile for screen share until it has its own guide screen: com.webos.app.miracast closes
    // itself when no device is connected. See docs/screen-share.md. Its texts and the icon
    // source-cast stay for that screen.
    [{ appId: "com.webos.app.livetv", title: tr("title.live_tv"), detail: tr("detail.antenna"), icon: "source-tv" },
     { appId: "com.webos.app.mediadiscovery", title: tr("title.media_library"), detail: tr("detail.usb_and_network"), icon: "source-library" }
    ].forEach(function (entry) {
        entry.running = entry.appId === active;
        result.push(entry);
    });
    if (!withManagement) return result;
    result = result.concat(empty);
    result.push({ manage: true, title: tr("title.manage"), detail: tr("detail.sources_and_devices"), icon: "source-manage" });
    return result;
}
