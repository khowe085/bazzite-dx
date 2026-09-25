var panel = new Panel
// The panel is made on the first line and nowhere else: the KDE build step turns floating off
// right after it.
// Fedora Dark's desktop layout loads this template and the dock for a new profile; both are also in
// Add Panel. Sizes are in logical pixels, so they do not depend on the screen's resolution.
panel.location = "top"
panel.height = 48

panel.addWidget("org.kde.plasma.systemmonitor.cpu")
panel.addWidget("org.kde.plasma.systemmonitor.memory")

// The hottest CPU temperature as a pie from 39 degrees. The generic widget has no preset of its own
// to load over these settings when it starts, unlike the ones above.
var temperature = panel.addWidget("org.kde.plasma.systemmonitor")
temperature.currentConfigGroup = ["Appearance"]
temperature.writeConfig("chartFace", "org.kde.ksysguard.piechart")
temperature.currentConfigGroup = ["Sensors"]
temperature.writeConfig("highPrioritySensorIds", '["cpu/all/maximumTemperature"]')
temperature.writeConfig("totalSensors", '["cpu/all/maximumTemperature"]')
temperature.currentConfigGroup = ["SensorColors"]
temperature.writeConfig("cpu/all/maximumTemperature", "195,233,61")
temperature.currentConfigGroup = ["org.kde.ksysguard.piechart", "General"]
temperature.writeConfig("rangeAuto", false)
temperature.writeConfig("rangeFrom", 39)

panel.addWidget("org.kde.plasma.systemmonitor.cpucore")
panel.addWidget("org.kde.plasma.systemmonitor.net")
panel.addWidget("org.kde.plasma.systemmonitor.diskactivity")
panel.addWidget("org.kde.plasma.pager")
panel.addWidget("org.kde.plasma.panelspacer")

// Volume, network, Bluetooth, camera, brightness and battery sit in the panel next to the tray
// instead of inside it, so the tray leaves them out. It adds every tray widget it does not know yet,
// so all of them are listed as known, and extraItems names the ones it shows.
var tray = panel.addWidget("org.kde.plasma.systemtray")
tray.currentConfigGroup = ["General"]
tray.writeConfig("knownItems", [
    "org.kde.kdeconnect", "org.kde.plasma.vault", "org.kde.kscreen", "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth", "org.kde.plasma.brightness", "org.kde.plasma.cameraindicator",
    "org.kde.plasma.clipboard", "org.kde.plasma.devicenotifier", "org.kde.plasma.keyboardindicator",
    "org.kde.plasma.keyboardlayout", "org.kde.plasma.manage-inputmethod", "org.kde.plasma.mediacontroller",
    "org.kde.plasma.networkmanagement", "org.kde.plasma.notifications", "org.kde.plasma.printmanager",
    "org.kde.plasma.volume", "org.kde.plasma.weather"
])
tray.writeConfig("extraItems", [
    "org.kde.kdeconnect", "org.kde.plasma.vault", "org.kde.kscreen", "org.kde.plasma.clipboard",
    "org.kde.plasma.devicenotifier", "org.kde.plasma.keyboardindicator", "org.kde.plasma.keyboardlayout",
    "org.kde.plasma.manage-inputmethod", "org.kde.plasma.mediacontroller", "org.kde.plasma.printmanager",
    "org.kde.plasma.weather"
])
tray.writeConfig("scaleIconsToFit", true)
tray.reloadConfig()

var volume = panel.addWidget("org.kde.plasma.volume")
volume.currentConfigGroup = ["General"]
volume.writeConfig("showVirtualDevices", true)

panel.addWidget("org.kde.plasma.cameraindicator")
panel.addWidget("org.kde.plasma.networkmanagement")
panel.addWidget("org.kde.plasma.bluetooth")
panel.addWidget("org.kde.plasma.brightness")

var battery = panel.addWidget("org.kde.plasma.battery")
battery.currentConfigGroup = ["General"]
battery.writeConfig("showPercentage", true)

// Date below the time as "Thu Sep 24"; the tooltip also shows Los Angeles and London.
var clock = panel.addWidget("org.kde.plasma.digitalclock")
clock.currentConfigGroup = ["Appearance"]
clock.writeConfig("dateDisplayFormat", "BelowTime")
clock.writeConfig("dateFormat", "custom")
clock.writeConfig("customDateFormat", "ddd MMM d")
clock.writeConfig("selectedTimeZones", ["America/Los_Angeles", "Local", "Europe/London"])

// The user's picture only, without a name.
var user = panel.addWidget("org.kde.plasma.userswitcher")
user.currentConfigGroup = ["General"]
user.writeConfig("showFace", true)
user.writeConfig("showName", false)
user.writeConfig("showFullName", false)
