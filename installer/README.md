# installer

Bazzite's live ISO installer, copied from
[`installer/` in ublue-os/bazzite](https://github.com/ublue-os/bazzite/tree/f84dc6e454f30304f7627e98da2f606983dd4402/installer)
at commit `f84dc6e` (Apache-2.0, as is this repository). `.github/workflows/build-disk.yml` turns it
into an ISO with titanoboa, the way Bazzite's own ISO workflow does.

The GNOME files (`gnome_flatpaks/`, `system_files/gnome/`) are left out because this image is KDE only.
Everything else is unchanged, so a newer upstream version can be copied over whole, except for one
addition: `install-image-flatpaks.sh`, run by a second `RUN` in the `Containerfile`, installs the
flatpaks this image lists in `system_files/usr/share/flatpak/preinstall.d` into the live image next to
Bazzite's, with `flatpak preinstall`. The workflow passes `system_files/` as the `image-files` build
context. Without it, a machine whose only network is a Wi-Fi set up in the first-boot setup would boot
offline and `custom-flatpak-preinstall.service` would install nothing until the next boot.

None of this goes into the image. The live session is Bazzite's own image (`LIVE_IMAGE` in the
workflow); the image it installs is this repository's, which the hooks find by name (`bazzite*`) in
the installer's container storage.
