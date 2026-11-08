#!/bin/sh
# Derives the overlays of LG's systemUi.js, Notification/Services.qml and the compositor's
# StarfishFullscreenContainer.qml, StarfishImageSplash.qml, StarfishSystemUIManager.qml and
# StarfishViewStateController.qml on the TV, so that LG's files stay out of the
# repository. Refuses unless all six are LG's originals, which also means: not mounted
# over.
#
#   make-overlays.sh <release-dir>
set -eu

DIR=$1
field() { awk -v name="$1" -v column="$2" '$1 == name { print $column }' "$DIR/lg-targets.txt"; }
original() {
    file=$(field "$1" 2)
    [ "$(sha256sum "$file" | cut -d' ' -f1)" = "$(field "$1" 3)" ] || {
        echo "$file is not LG's original, or something is mounted over it" >&2
        exit 1
    }
    echo "$file"
}
expect() { [ "$(grep -c "$1" "$2")" = "$3" ] || { echo "$2: expected $3 lines with $1" >&2; exit 1; }; }

keys=$(original systemUi.js)
toast=$(original Services.qml)

# The home key opens our launcher while the marker is on. LG sets the pointer of the
# Magic Remote to "on" at every start, the copy sets it to "off". With a menu open over
# our launcher on the home layer, back goes to the menu, not to the launcher below.
sed -e '/^    applicationManager.launchDefaultApp(JSON.stringify({"category": "home"/i\    if (novosLauncherActive()) { lunaCall.send("com.webos.service.systemUIManager", "/launch", JSON.stringify({"appId": "com.webos.app.store-streamer"})); return; }' \
    -e "s/\"settings\":{\"remotePointer\":\"on\"}/\"settings\":{\"remotePointer\":\"off\"}/" \
    -e '/^        if (!pressed && homeView.visible) {$/i\        if (overlayView.visible \&\& homeView.visible) return KeyPolicy.NotAccepted; // novOS: a menu over our launcher takes back first' \
    -e '/^    if (pressed && homeView.visible) {$/i\    if (novosHomeKeyOnLauncher(pressed)) return KeyPolicy.Accepted; // novOS: home on our launcher' \
    "$keys" > "$DIR/systemUi.js"
cat "$DIR/launcher-home-key.inc" >> "$DIR/systemUi.js"
expect novosLauncherActive "$DIR/systemUi.js" 3
expect '"remotePointer":"on"' "$DIR/systemUi.js" 0
expect 'a menu over our launcher takes back first' "$DIR/systemUi.js" 1
expect 'novosHomeKeyOnLauncher' "$DIR/systemUi.js" 2

# Toasts and plain dialogs go to the source picker's window while the marker is on.
sed -e '/^        property int toastModelMaxCount: 1$/r '"$DIR"'/toast-filter.inc' \
    -e '/^            if (toastModel.count > 0) {$/i\            if (replacedByPill(modelData)) return;' \
    -e '/^            \/\/ Check the duplications (upto 5 recent items)$/i\            if (toastModel.replacedAlert(modelData.alertInfo)) return;' \
    "$toast" > "$DIR/Services.qml"
expect replacedByPill "$DIR/Services.qml" 2
expect replacedAlert "$DIR/Services.qml" 2
# LG's Home stays out of sight while our launcher stands in for it.
fullscreen=$(original StarfishFullscreenContainer.qml)
[ "$(tail -n 1 "$fullscreen")" = "}" ] || { echo "$fullscreen: last line is not the closing brace" >&2; exit 1; }
sed -e '/^        id: surfaceItemContainer$/a\        opacity: root.novosHideHome ? 0 : 1' -e '$d' \
    "$fullscreen" > "$DIR/StarfishFullscreenContainer.qml"
cat "$DIR/fullscreen-home.inc" >> "$DIR/StarfishFullscreenContainer.qml"
echo "}" >> "$DIR/StarfishFullscreenContainer.qml"
expect 'opacity: root.novosHideHome' "$DIR/StarfishFullscreenContainer.qml" 1
expect 'function novosUpdateHide' "$DIR/StarfishFullscreenContainer.qml" 1
# LG's grey input splash stays out of sight while our interface runs.
splash=$(original StarfishImageSplash.qml)
[ "$(tail -n 1 "$splash")" = "}" ] || { echo "$splash: last line is not the closing brace" >&2; exit 1; }
[ "$(grep -c '^    id: root$' "$splash")" = 1 ] || { echo "$splash: no single root id" >&2; exit 1; }
sed -e '/^    id: root$/a\    opacity: root.novosHideSplash(root.splashAppId) ? 0 : 1' -e '$d' \
    "$splash" > "$DIR/StarfishImageSplash.qml"
cat "$DIR/splash-hide.inc" >> "$DIR/StarfishImageSplash.qml"
echo "}" >> "$DIR/StarfishImageSplash.qml"
expect 'opacity: root.novosHideSplash' "$DIR/StarfishImageSplash.qml" 1
expect 'function novosHideSplash' "$DIR/StarfishImageSplash.qml" 1
# Our launcher sits on the home layer below the menus while the relay runs.
manager=$(original StarfishSystemUIManager.qml)
sed -e '/^            ev.windowType = select(ev.payload.windowType, getWindowType(info));$/a\            if (novosLauncherHome(ev)) { ev.defaultWindowType = "home"; ev.windowType = "_WEBOS_SYSTEM_UI_TYPE_HOME"; }' \
    "$manager" |
    awk -v inc="$DIR/launcher-home.inc" '$0 == "        function getByAppId(appId) {" { while ((getline line < inc) > 0) print line } { print }' \
    > "$DIR/StarfishSystemUIManager.qml"
expect 'if (novosLauncherHome(ev))' "$DIR/StarfishSystemUIManager.qml" 1
expect 'function novosLauncherHome' "$DIR/StarfishSystemUIManager.qml" 1
# The launcher stays when the quick menu or the source picker opens over it. It also
# stays when the user activity timer runs out after two minutes without a key, which
# closes LG's Home; the screen saver starting still closes it, as LG's Home.
controller=$(original StarfishViewStateController.qml)
[ "$(tail -n 1 "$controller")" = "}" ] || { echo "$controller: last line is not the closing brace" >&2; exit 1; }
awk '/^        target: views.starfishOverlay$/ { block = 1 }
     /^        onUserActivityExpired: \{$/ { idle = 1 }
     block && $0 == "            if (views.starfishHome)" { print "            if (views.starfishHome && !novosLauncherOnHome())"; block = 0; next }
     idle && $0 == "            if (views.starfishHome)" { print "            if (views.starfishHome && !(userActivityTimer && novosLauncherOnHome()))"; idle = 0; next }
     { print }' "$controller" | sed '$d' > "$DIR/StarfishViewStateController.qml"
cat "$DIR/launcher-stays.inc" >> "$DIR/StarfishViewStateController.qml"
echo "}" >> "$DIR/StarfishViewStateController.qml"
expect 'novosLauncherOnHome' "$DIR/StarfishViewStateController.qml" 3
expect 'if (views.starfishHome && !novosLauncherOnHome())' "$DIR/StarfishViewStateController.qml" 1
expect 'if (views.starfishHome && !(userActivityTimer && novosLauncherOnHome()))' "$DIR/StarfishViewStateController.qml" 1
# A long press of the gear key opens novOS's settings modal instead of LG's settings app.# The quick panel takes "settings" as its launch page; a second long press over LG's
# app still closes LG's app as before.
launch=$(original appLaunch.js)
[ "$(grep -c '^                    applicationManager.checkLaunch(settingsAppId);$' "$launch")" = 1 ] || {
    echo "$launch: the settings launch of the long press is not where it was" >&2
    exit 1
}
# A long press of the source key (Key_Video, com.webos.keyaction.inputHub) opens
# novOS's smart home hub instead of LG's Home Hub. The hub lives in the launcher's
# window; pressed again over the hub, it closes. Another app configured for the key
# stays as LG has it.
[ "$(grep -c '^                            applicationManager.checkLaunch(inputHubAction.appId, JSON.stringify({"appID":settingsService.lastInputApp}));$' "$launch")" = 1 ] || {
    echo "$launch: the launch of the source key's long press is not where it was" >&2
    exit 1
}
sed -e 's#^                    applicationManager.checkLaunch(settingsAppId);$#                    lunaCall.send("com.webos.service.systemUIManager", "/launch", JSON.stringify({"appId": "com.webos.app.quicksettings", "params": {"page": "settings"}})); // novOS#' \
    -e 's#^                            applicationManager.checkLaunch(inputHubAction.appId, JSON.stringify({"appID":settingsService.lastInputApp}));$#                            if (inputHubAction.appId === "com.webos.app.homeconnect") lunaCall.send("com.webos.service.systemUIManager", "/launch", JSON.stringify({"appId": "com.webos.app.store-streamer", "params": {"page": "hub"}})); else applicationManager.checkLaunch(inputHubAction.appId, JSON.stringify({"appID":settingsService.lastInputApp})); // novOS#' \
    "$launch" > "$DIR/appLaunch.js"
expect '"params": {"page": "settings"}})); // novOS' "$DIR/appLaunch.js" 1
expect '"params": {"page": "hub"}})); else applicationManager.checkLaunch' "$DIR/appLaunch.js" 1
# LG's settings app opened without a target hands over to the modal, see settings-redirect.inc.
for name in settings-index.multi.html settings-index.html; do
    page=$(original "$name")
    [ "$(grep -c '<head>' "$page")" = 1 ] || { echo "$page: no single <head>" >&2; exit 1; }
    sed -e "/<head>/r $DIR/settings-redirect.inc" "$page" > "$DIR/$name"
    expect 'novOS: LG' "$DIR/$name" 1
done
echo "overlays made in $DIR"
