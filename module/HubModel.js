.pragma library

// Turns devices of LG's com.webos.service.homeconnect into what the hub's tiles show:
// kind (icon and type name), the resource that switches it, and a state line. One
// device model covers ThinQ, Matter and other brands (UEI); resources carry
// {value, vr, writable, valid}. tr(key, params) gives a text of namespace "hub".

// Resources that switch a device on and off, by ecosystem.
var POWER = ["OnOffCluster.OnOff", "switch.binary", "state.poweronoff"];

// UEI types are numbers.
var UEI_KINDS = { 10: "light", 20: "plug", 30: "lock", 70: "plug", 80: "blind", 90: "thermostat" };

function kind(device) {
    var type = device.deviceType;
    if (typeof type === "number") return UEI_KINDS[type] || "device";
    type = String(type || "").toUpperCase();
    var rules = [
        [/WASHTOWER|WASHER|WASHING/, "washer"], [/DRYER/, "dryer"], [/REFRIGERATOR|FRIDGE|KIMCHI/, "fridge"],
        [/AIR_CONDITIONER|AIRCON|HEAT_PUMP/, "ac"], [/PURIFIER|DEHUMIDIFIER|HUMIDIFIER/, "purifier"],
        [/ROBOT|CLEANER/, "robot"], [/LAMP/, "lamp"], [/LIGHT|BULB/, "light"], [/PLUG|OUTLET|SWITCH/, "plug"],
        [/THERMOSTAT|HEAT|COOL/, "thermostat"], [/WINDOW|BLIND|COVER|SHADE|CURTAIN/, "blind"],
        [/LOCK/, "lock"], [/SENSOR|CONTACT|OCCUPANCY/, "sensor"], [/FAN/, "fan"]
    ];
    for (var i = 0; i < rules.length; ++i) {
        if (rules[i][0].test(type)) return rules[i][1];
    }
    return "device";
}

function resource(device, id) {
    var resources = device.resources || {};
    var entry = resources[id];
    return entry && !entry.unused && entry.valid !== false ? entry : null;
}

function reachable(device) {
    return device.status === "connected";
}

// The writable power resource, or "" if OK does not switch this device.
function powerResource(device) {
    for (var i = 0; i < POWER.length; ++i) {
        var entry = resource(device, POWER[i]);
        if (entry && entry.writable) return POWER[i];
    }
    return "";
}

function truthy(value) {
    return value === true || value === 1 || value === "on" || value === "ON" || value === "POWER_ON";
}

function isOn(device) {
    for (var i = 0; i < POWER.length; ++i) {
        var power = resource(device, POWER[i]);
        if (power) return truthy(power.value);
    }
    if (kind(device) === "washer" || kind(device) === "dryer") {
        var state = resource(device, "state.washer") || resource(device, "state.dryer");
        return !!state && state.value !== "POWER_OFF";
    }
    return device.offed === false;
}

// The value OK sends to switch the device.
function toggleValue(device) {
    var id = powerResource(device);
    var value = resource(device, id).value;
    if (typeof value === "boolean") return !value;
    if (typeof value === "number") return value ? 0 : 1;
    if (value === "POWER_ON" || value === "POWER_OFF") return value === "POWER_ON" ? "POWER_OFF" : "POWER_ON";
    return truthy(value) ? "off" : "on";
}

function percent(device) {
    var level = resource(device, "LevelControlCluster.CurrentLevel");
    if (level && typeof level.value === "number") return Math.round(level.value / 2.54);
    var lightness = resource(device, "color.lightness");
    if (lightness && typeof lightness.value === "number") return Math.round(lightness.value);
    return -1;
}

function decimal(value) {
    return (Math.round(value * 2) / 2).toFixed(1).replace(".", ",");
}

function target(device) {
    var heating = resource(device, "ThermostatCluster.OccupiedHeatingSetpoint");
    if (heating && typeof heating.value === "number") return heating.value / 100;
    var uei = resource(device, "temperature.target");
    if (uei && typeof uei.value === "number") return uei.value;
    var aircon = resource(device, "temperature.target.aircon");
    if (aircon && typeof aircon.value === "number") return aircon.value;
    return NaN;
}

function remaining(device) {
    var hours = resource(device, "time.remain.hour2");
    var minutes = resource(device, "time.remain.minute2");
    if (!hours || !minutes) return "";
    var total = hours.value * 60 + minutes.value;
    if (total <= 0) return "";
    return Math.floor(total / 60) + ":" + (total % 60 < 10 ? "0" : "") + total % 60 + " h";
}

// The line under the device's name, as short as it can be.
function stateText(device, tr) {
    if (!reachable(device)) return tr("state.offline");
    var what = kind(device);
    if (what === "washer" || what === "dryer") {
        var state = resource(device, "state.washer") || resource(device, "state.dryer");
        var text = state ? tr("state.washer." + state.value) : tr(isOn(device) ? "state.on" : "state.off");
        var left = remaining(device);
        return left !== "" && isOn(device) ? text + " · " + tr("state.remaining", { time: left }) : text;
    }
    if (what === "thermostat" || what === "ac") {
        var goal = target(device);
        if (!isNaN(goal)) return tr("state.target", { value: decimal(goal) });
    }
    if (what === "blind") {
        var lift = resource(device, "WindowCoveringCluster.CurrentPositionLiftPercent100ths");
        var position = resource(device, "blind.position");
        var open = lift ? 100 - Math.round(lift.value / 100) : position ? position.value : -1;
        if (open === 0) return tr("state.closed");
        if (open >= 100) return tr("state.open");
        if (open > 0) return tr("state.position", { value: open });
    }
    if (what === "lock" && lockResource(device) !== "") return tr(isLocked(device) ? "state.locked" : "state.unlocked");
    if (what === "sensor") {
        var contact = resource(device, "BooleanStateCluster.StateValue");
        if (contact) return tr(contact.value ? "state.closed" : "state.open");
    }
    var on = isOn(device);
    var level = percent(device);
    if (on && level >= 0 && (what === "light" || what === "lamp")) {
        return tr("state.on") + " · " + tr("state.brightness", { value: level });
    }
    return tr(on ? "state.on" : "state.off");
}

// A washer can only be started from afar when its remote option is on.
function remoteOff(device) {
    var remote = resource(device, "option.remocon");
    return (kind(device) === "washer" || kind(device) === "dryer") && !!remote && remote.value === false;
}

// The devices of a room; roomId "" is every visible device.
function inRoom(devices, roomId) {
    return devices.filter(function (device) {
        return device.visible !== false && device.hiding !== true && (roomId === "" || device.roomId === roomId);
    });
}

// "2 devices · 1 on" for the stage of a room.
function roomSummary(devices, tr) {
    if (devices.length === 0) return tr("detail.no_devices");
    var on = devices.filter(function (device) { return reachable(device) && isOn(device); }).length;
    var count = devices.length === 1 ? tr("detail.one_device") : tr("detail.devices", { count: devices.length });
    return count + " · " + tr("detail.on_count", { count: on });
}

// The lock's resource; Matter's LockState is 1 when locked.
function lockResource(device) {
    if (resource(device, "DoorLockCluster.LockState")) return "DoorLockCluster.LockState";
    if (resource(device, "uei.lock")) return "uei.lock";
    return "";
}

function isLocked(device) {
    var lock = resource(device, lockResource(device));
    return !!lock && (lock.value === 1 || lock.value === true || lock.value === "locked");
}

function lockValue(device, locked) {
    var lock = resource(device, lockResource(device));
    if (typeof lock.value === "boolean") return locked;
    if (typeof lock.value === "string") return locked ? "locked" : "unlocked";
    return locked ? 1 : 2;
}

function writableOf(device, ids) {
    for (var i = 0; i < ids.length; ++i) {
        var entry = resource(device, ids[i]);
        if (entry && entry.writable) return ids[i];
    }
    return "";
}

// What the detail modal sets with left and right, after K3-Home-A-Heizung: kind
// "target" in °C, "level" and "position" in percent; null when there is nothing.
// shown is the value on screen, raw the resource's own value.
function adjustable(device) {
    var what = kind(device);
    var id = writableOf(device, ["ThermostatCluster.OccupiedHeatingSetpoint", "temperature.target",
                                 "temperature.target.aircon"]);
    if (id !== "" && (what === "thermostat" || what === "ac")) {
        var hundredths = id.indexOf("Cluster") > 0;
        var range = resource(device, id).vr || {};
        var scale = hundredths ? 100 : 1;
        return { kind: "target", resourceId: id, shown: target(device), step: 0.5,
                 min: typeof range.min === "number" ? range.min / scale : 5,
                 max: typeof range.max === "number" ? range.max / scale : 30, scale: scale };
    }
    id = writableOf(device, ["LevelControlCluster.CurrentLevel", "color.lightness"]);
    if (id !== "" && (what === "light" || what === "lamp")) {
        return { kind: "level", resourceId: id, shown: Math.max(1, percent(device)), step: 10, min: 1, max: 100,
                 scale: id === "color.lightness" ? 1 : 2.54 };
    }
    id = writableOf(device, ["WindowCoveringCluster.CurrentPositionLiftPercent100ths", "blind.position"]);
    if (id !== "" && what === "blind") {
        var lift = id.indexOf("Cluster") > 0;
        var raw = resource(device, id).value;
        return { kind: "position", resourceId: id, shown: lift ? 100 - Math.round(raw / 100) : raw,
                 step: 10, min: 0, max: 100, lift: lift };
    }
    return null;
}

// The resource value for a value on screen.
function rawValue(setting, shown) {
    if (setting.kind === "target") return Math.round(shown * setting.scale);
    if (setting.kind === "level") return Math.max(1, Math.round(shown * setting.scale));
    return setting.lift ? (100 - shown) * 100 : shown;
}

function shownText(setting, shown) {
    if (setting.kind === "target") return decimal(shown) + "°";
    return Math.round(shown) + " %";
}

// "Gerade 21,5 °C · Luftfeuchte 48 %" for a thermostat, otherwise the state line.
function detailLine(device, tr) {
    var local = resource(device, "ThermostatCluster.LocalTemperature");
    if (local && typeof local.value === "number" && reachable(device)) {
        var line = tr("detail.current", { value: decimal(local.value / 100) });
        var humidity = resource(device, "RelativeHumidityMeasurementCluster.MeasuredValue");
        if (humidity && typeof humidity.value === "number")
            line += " · " + tr("detail.humidity", { value: Math.round(humidity.value / 100) });
        return line;
    }
    return stateText(device, tr);
}

// Does the device have more than its switch to show? Locks, thermostats, blinds and
// appliances open their detail on OK; switched devices on a long OK.
function hasDetail(device) {
    return adjustable(device) !== null || lockResource(device) !== "" || powerResource(device) !== "" ||
           kind(device) === "washer" || kind(device) === "dryer";
}
