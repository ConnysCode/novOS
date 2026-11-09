.pragma library
// Every screen of the setup as a debug slide, in the order of the design canvas
// (page "Installieren & Updates"). The screens are visual only for now: values and
// states are the ones drawn on the boards. Update-1, Update-3 and Update-6 are not here:
// the update notice, the download pill and "installed" show over whatever runs, so novOS
// draws them, not the setup.
//
// id: what the preview script and the control file name, board: the artboard,
// screen: the QML file that draws it, variant: which of its versions, scene: the picture
// behind it (SetupScene: a launcher picture, the glow or black), scrim: the dark layer
// between picture and glass.

var list = [
    { id: "install-1", board: "K3-Install-1-Willkommen", screen: "InstallWelcome", variant: "", scene: "picture", scrim: 0.3 },
    { id: "install-channel", board: "(no board: channel)", screen: "InstallChannel", variant: "", scene: "picture", scrim: 0.3 },
    { id: "install-2", board: "K3-Install-2-Pruefung", screen: "CheckScreen", variant: "install-2", scene: "picture", scrim: 0.3 },
    { id: "install-2b", board: "K3-Install-2b-Fehlt", screen: "CheckScreen", variant: "install-2b", scene: "picture", scrim: 0.3 },
    { id: "install-3", board: "K3-Install-3-Aenderungen", screen: "InstallChanges", variant: "", scene: "picture", scrim: 0.3 },
    { id: "install-4", board: "K3-Install-4-Datenschutz", screen: "InstallPrivacy", variant: "", scene: "picture", scrim: 0.3 },
    { id: "install-5", board: "K3-Install-5-Tastatur", screen: "InstallKeyboard", variant: "", scene: "picture", scrim: 0.3 },
    { id: "install-6", board: "K3-Install-6-Bereit", screen: "InstallSummary", variant: "", scene: "picture", scrim: 0.3 },
    { id: "install-7", board: "K3-Install-7-Laeuft", screen: "ProgressScreen", variant: "install", scene: "picture", scrim: 0.3 },
    { id: "install-8", board: "K3-Install-8-Neustart", screen: "RestartScreen", variant: "install", scene: "glow", scrim: 0 },
    { id: "install-9", board: "K3-Install-9-Fertig", screen: "InstallDone", variant: "", scene: "picture", scrim: 0.3 },
    { id: "install-x", board: "K3-Install-X-Fehler", screen: "CheckScreen", variant: "install-x", scene: "picture", scrim: 0.3 },
    { id: "update-2", board: "K3-Update-2-Details", screen: "UpdateDetails", variant: "", scene: "picture", scrim: 0.3 },
    { id: "update-4", board: "K3-Update-4-Installieren", screen: "ProgressScreen", variant: "update", scene: "picture", scrim: 0.3 },
    { id: "update-5", board: "K3-Update-5-Neustart", screen: "RestartScreen", variant: "update", scene: "glow", scrim: 0 },
    { id: "update-lg", board: "K3-Update-LG", screen: "CheckScreen", variant: "update-lg", scene: "picture", scrim: 0.3 },
    { id: "remove-2", board: "K3-Entfernen-2-Bestaetigen", screen: "RemoveConfirm", variant: "", scene: "picture", scrim: 0.3 },
    { id: "remove-3", board: "K3-Entfernen-3-Laeuft", screen: "ProgressScreen", variant: "remove", scene: "picture", scrim: 0.3 },
    { id: "remove-4", board: "K3-Entfernen-4-Fertig", screen: "RestartScreen", variant: "farewell", scene: "black", scrim: 0 }
];

function indexOf(id) {
    for (var i = 0; i < list.length; ++i) {
        if (list[i].id === id) return i;
    }
    var number = parseInt(id, 10);
    return isNaN(number) ? -1 : Math.max(0, Math.min(list.length - 1, number));
}
