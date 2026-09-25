# installer

Bazzite's live ISO installer, copied from
[`installer/` in ublue-os/bazzite](https://github.com/ublue-os/bazzite/tree/f84dc6e454f30304f7627e98da2f606983dd4402/installer)
at commit `f84dc6e` (Apache-2.0, as is this repository). `.github/workflows/build-disk.yml` turns it
into an ISO with titanoboa, the way Bazzite's own ISO workflow does.

The GNOME files (`gnome_flatpaks/`, `system_files/gnome/`) are left out because this image is KDE only.
Everything else is unchanged, so a newer upstream version can be copied over whole.

None of this goes into the image. The live session is Bazzite's own image (`LIVE_IMAGE` in the
workflow); the image it installs is this repository's, which the hooks find by name (`bazzite*`) in
the installer's container storage.
