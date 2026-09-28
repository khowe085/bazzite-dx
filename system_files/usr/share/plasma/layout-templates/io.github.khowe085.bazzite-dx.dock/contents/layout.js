var panel = new Panel
// The panel is made on the first line and nowhere else: the KDE build step turns floating off
// right after it.
// Fedora Dark's desktop layout loads this template and the top bar for a new profile; both are also
// in Add Panel.
panel.location = "bottom"
panel.height = 64
panel.hiding = "autohide"

// Centred, between about 3/8 and 4/5 of the screen's width depending on how many windows are open.
// Taken as fractions so the dock looks the same at any resolution.
var geo = screenGeometry(panel.screen)
panel.alignment = "center"
panel.lengthMode = "custom"
panel.maximumLength = Math.round(geo.width * 0.8235)
panel.minimumLength = Math.round(geo.width * 0.376)

var kickoff = panel.addWidget("org.kde.plasma.kickoff")
kickoff.currentConfigGroup = ["General"]
kickoff.writeConfig("icon", "framework")

// Nothing pinned: the task manager shows open windows only. Bazzite's update script that pins its
// own apps to an empty task manager (bazzite-pins.js) is removed by the KDE build step.
panel.addWidget("org.kde.plasma.icontasks")

panel.addWidget("org.kde.plasma.marginsseparator")
panel.addWidget("org.kde.plasma.notifications")
