// Default desktop background: Picture of the Day from the "Astronomy (NASA)" provider.
// Plasma runs an update script once per user, new or existing, so a wallpaper chosen later in
// System Settings stays. Like bazzite-pins.js next to this file, it only fills in what the user
// has not set: a desktop that already shows a picture of their choosing, or uses another wallpaper
// type, is left alone.
const allDesktops = desktops();

for (let i = 0; i < allDesktops.length; ++i) {
    const desktop = allDesktops[i];

    if (desktop.wallpaperPlugin !== "org.kde.image") {
        continue;
    }
    // An untouched desktop has no Image entry; the image wallpaper falls back to the theme's picture.
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    if (desktop.readConfig("Image", "") !== "") {
        continue;
    }

    desktop.wallpaperPlugin = "org.kde.potd";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.potd", "General"];
    desktop.writeConfig("Provider", "apod");
}
