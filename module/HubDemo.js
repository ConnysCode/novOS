.pragma library

// A made-up home for trying the hub without the devices: five rooms, eighteen devices in
// the device model of LG's homeconnect, so that HubModel reads them like real ones.
// Switched on in the debug menu; nothing of it goes to LG. tr(key) gives a text of
// namespace "hub".

var PREFIX = "demo-";

function isDemo(device) {
    return !!device && String(device.deviceId || "").indexOf(PREFIX) === 0;
}

function value(v, writable, min, max) {
    var entry = { value: v, writable: !!writable, valid: true };
    if (min !== undefined) entry.vr = { min: min, max: max };
    return entry;
}

function device(id, type, room, resources, status) {
    return { deviceId: PREFIX + id, deviceType: type, roomId: PREFIX + room, nameKey: "demo." + id,
             status: status || "connected", resources: resources };
}

function light(on, level) {
    return { "OnOffCluster.OnOff": value(on, true),
             "LevelControlCluster.CurrentLevel": value(level, true, 1, 254) };
}

function plug(on) {
    return { "OnOffCluster.OnOff": value(on, true) };
}

function heating(target, local, humidity) {
    var result = { "ThermostatCluster.OccupiedHeatingSetpoint": value(target, true, 500, 3000),
                   "ThermostatCluster.LocalTemperature": value(local, false) };
    if (humidity !== undefined) result["RelativeHumidityMeasurementCluster.MeasuredValue"] = value(humidity, false);
    return result;
}

function blind(open) {
    return { "WindowCoveringCluster.CurrentPositionLiftPercent100ths": value((100 - open) * 100, true, 0, 10000) };
}

var ROOMS = ["living", "kitchen", "bedroom", "bath", "hall"];

function rooms(tr) {
    return ROOMS.map(function (id) { return { id: PREFIX + id, name: tr("demo.room." + id) }; });
}

// A fresh copy each time, so that switching keeps to the copy in use.
function devices(tr) {
    var list = [
        device("ceiling", "LIGHT", "living", light(true, 178)),
        device("floor_lamp", "LAMP", "living", light(false, 102)),
        device("heating_living", "THERMOSTAT", "living", heating(2200, 2150, 4800)),
        device("blind_living", "WINDOW_COVERING", "living", blind(70)),
        device("shelf_plug", "SMART_PLUG", "living", plug(true)),
        device("worktop", "LIGHT", "kitchen", light(true, 254)),
        device("coffee", "SMART_PLUG", "kitchen", plug(false)),
        device("fridge", "REFRIGERATOR", "kitchen", { "state.poweronoff": value("POWER_ON", false) }),
        device("bedside", "LAMP", "bedroom", light(false, 64)),
        device("heating_bedroom", "THERMOSTAT", "bedroom", heating(1850, 1900, 5200)),
        device("blind_bedroom", "WINDOW_COVERING", "bedroom", blind(0)),
        device("purifier", "AIR_PURIFIER", "bedroom", plug(true)),
        device("heating_bath", "THERMOSTAT", "bath", heating(2300, 2210)),
        device("washer", "WASHER", "bath", { "state.washer": value("RUNNING", false),
                                             "time.remain.hour2": value(1, false),
                                             "time.remain.minute2": value(12, false),
                                             "option.remocon": value(true, false) }),
        device("window", "CONTACT_SENSOR", "bath", { "BooleanStateCluster.StateValue": value(true, false) }),
        device("front_door", "DOOR_LOCK", "hall", { "DoorLockCluster.LockState": value(1, true) }),
        device("hall_light", "LIGHT", "hall", light(false, 200)),
        device("robot", "ROBOT_CLEANER", "hall", plug(false), "disconnected")
    ];
    list.forEach(function (entry) {
        entry.alias = tr(entry.nameKey);
    });
    return list;
}
