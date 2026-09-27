// Default desktop background: a slideshow of the NASA pictures this image ships in
// /usr/share/wallpapers/bazzite-dx-nasa (Hubble, Webb and Earth Observatory; CREDITS.md there),
// so the background never needs a network.
// Plasma runs an update script once per user, new or existing, so a wallpaper chosen later in
// System Settings stays. It only fills in what the user has not set: a desktop that already shows
// a picture of their choosing, or uses another wallpaper type, is left alone.
// Plasma remembers update scripts by path. This one replaces picture-of-the-day-default.js, which
// set the Picture of the Day wallpaper with NASA's Astronomy Picture of the Day; the new name
// makes it run on profiles that script already set up, and it takes that setting for untouched.

// What an untouched desktop has for a picture: no entry at all (profiles set up under the Fedora
// themes), or the one Bazzite's Vapor theme writes into every profile it sets up
// (plasmoidsetupscripts/org.kde.plasma.folder.js). System Settings would store it as a file:// URL.
const untouchedImages = ["", "/usr/share/wallpapers/convergence.jxl"];
const slidePath = "/usr/share/wallpapers/bazzite-dx-nasa/";

function untouched(desktop) {
    if (desktop.wallpaperPlugin === "org.kde.image") {
        desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
        const image = String(desktop.readConfig("Image", "")).replace(/^file:\/\//, "");
        return untouchedImages.indexOf(image) !== -1;
    }
    // What picture-of-the-day-default.js set; with no entry, Plasma shows that provider too (its
    // default). Another provider was the user's choice.
    if (desktop.wallpaperPlugin === "org.kde.potd") {
        desktop.currentConfigGroup = ["Wallpaper", "org.kde.potd", "General"];
        return String(desktop.readConfig("Provider", "apod")) === "apod";
    }
    return false;
}

const allDesktops = desktops();

for (let i = 0; i < allDesktops.length; ++i) {
    const desktop = allDesktops[i];

    if (!untouched(desktop)) {
        continue;
    }

    // A new picture once a day (seconds; System Settings shows it as 24 hours, its maximum).
    // Plasma's defaults do the rest: random order, scaled and cropped to fill the screen.
    desktop.wallpaperPlugin = "org.kde.slideshow";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.slideshow", "General"];
    desktop.writeConfig("SlidePaths", [slidePath]);
    desktop.writeConfig("SlideInterval", 86400);
}
