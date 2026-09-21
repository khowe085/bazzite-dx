// Default desktop background: Picture of the Day from the "Astronomy (NASA)" provider.
// Plasma runs an update script once per user, new or existing, so a wallpaper chosen later in
// System Settings stays. Like bazzite-pins.js next to this file, it only fills in what the user
// has not set: a desktop that already shows a picture of their choosing, or uses another wallpaper
// type, is left alone.
// Plasma remembers update scripts by path. This one replaces picture-of-the-day-wallpaper.js, which
// took Bazzite's own wallpaper for the user's choice; the new name makes it run on those profiles.

// What an untouched desktop has for a picture: no entry at all (profiles set up under the Fedora
// themes), or the one Bazzite's Vapor theme writes into every profile it sets up
// (plasmoidsetupscripts/org.kde.plasma.folder.js). System Settings would store it as a file:// URL.
const untouchedImages = ["", "/usr/share/wallpapers/convergence.jxl"];

const allDesktops = desktops();

for (let i = 0; i < allDesktops.length; ++i) {
    const desktop = allDesktops[i];

    if (desktop.wallpaperPlugin !== "org.kde.image") {
        continue;
    }
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    const image = String(desktop.readConfig("Image", "")).replace(/^file:\/\//, "");
    if (untouchedImages.indexOf(image) === -1) {
        continue;
    }

    desktop.wallpaperPlugin = "org.kde.potd";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.potd", "General"];
    desktop.writeConfig("Provider", "apod");
}
