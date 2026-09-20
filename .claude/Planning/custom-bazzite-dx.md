# custom-bazzite-dx

Custom Universal Blue image based on `ghcr.io/ublue-os/bazzite-dx:stable` (KDE, AMD/Intel), published as `ghcr.io/khowe085/bazzite-dx`.

Written 2026-09-11. Decisions marked **(K)** were confirmed by Kevin; **(open)** are my defaults, not confirmed.

## Scope

| Item | Approach | Status |
|---|---|---|
| Base image | `bazzite-dx:stable` pinned by digest (Renovate-friendly) | **(K)** |
| .NET 10 SDK | Fedora 44 package `dotnet-sdk-10.0` (10.0.111) | **(open)** vs Microsoft repo |
| 1Password | Official RPM repo, installed at build; relocated `/var/opt/1Password` → `/usr/lib/opt/1Password` + tmpfiles symlink (bazzite-dx's own `/opt` pattern); groups pre-created with fixed GIDs + `sysusers.d` so they exist on existing installs | verified spike |
| Firefox flatpak ↔ 1Password | `xdg-native-messaging-proxy` route: install the proxy, allow-list it in `/etc/1password/custom_allowed_browsers`, oneshot service that (a) copies a pref file (`widget.use-xdg-desktop-portal.native-messaging-proxy=1`) into the `org.mozilla.firefox.systemconfig` extension's `defaults/pref/` (the mechanism Bazzite's own flatpak manager uses for `/usr/share/ublue-os/firefox-config/*.js`) and (b) adds `--talk-name=org.freedesktop.NativeMessagingProxy` to the system flatpak override. Stable Flathub Firefox only gets the proxy client with 157 (2026-09-29 per Mozilla's calendar). **Pivot 2026-09-19 (K): install Firefox beta (157, on beta since 2026-09-14) from the `flathub-beta` remote via the preinstall drop-in; the setup service fills both the `stable` and `beta` extension branches with Bazzite's prefs plus ours.** Flip the drop-in to `Branch=stable` once stable is ≥ 157. | **(K)** |
| EmuDeck | `ujust get-emudeck` is GUI-driven (downloads, then hands the file to Gear Lever), so the first-login hook does its non-interactive equivalent: download the latest EmuDeck AppImage to `~/Applications` + desktop entry. Wizard choices (High integration = Steam ROM Manager, Cloud Sync, Bezels, Autosave, classic 4:3 ARs, Patreon token) cannot be pre-seeded — state lives in Electron localStorage — so they are documented in the README. | **(K)** run Bazzite's recipe; token stays out of image |
| Eden | Fetch latest `Eden-Linux-<ver>-amd64-clang-pgo.AppImage` from git.eden-emu.dev at build into `/usr/lib/eden`; hook places it at `~/Applications/Eden.AppImage` (the exact path EmuDeck's `emuDeckEden.sh` expects, since EmuDeck doesn't download Eden). Replaced when the image carries a newer version than the hook last placed; a user-placed copy (no stamp) is left alone. | variant **(open)** |
| KDE defaults | **2026-09-20 (K): default theme Fedora Dark, background Picture of the Day with the "Astronomy (NASA)" provider.** Both done the way the base does its own. Theme: Bazzite's `steamdeck-kde-presets-desktop` names Vapor in `/etc/xdg/kdeglobals` (`[KDE] LookAndFeelPackage=com.valve.vapor.desktop`); `55-kde-defaults.sh` rewrites that one line to `org.fedoraproject.fedoradark.desktop` (from `plasma-lookandfeel-fedora`, a hard dependency of plasma-workspace) and fails the build if the key is gone. `startplasma` compares the configured package with `~/.config/kdedefaults/package` at every login and regenerates the defaults when they differ, so existing users who never picked a global theme switch too; an explicit choice in `~/.config/kdeglobals` wins. Wallpaper: a Plasma update script next to the base's `bazzite-pins.js` (`/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/`); `ShellCorona::load()` runs those once per user, after the default layout for new profiles and at the next login for existing ones. It sets `wallpaperPlugin=org.kde.potd` and `Provider=apod` (the provider's identifier; "Astronomy (NASA)" is its display name) only on desktops still on `org.kde.image` with no `Image` entry, which is what an untouched profile looks like under both Vapor and the Fedora themes (neither writes one). My reading of "default": a wallpaper or theme Kevin already chose is not overridden. Lock screen and login screen untouched. **Natural scrolling as the default for mouse and touchpad (K, same day):** the build step appends `[Libinput][Defaults][Touchpad]` and `[Libinput][Defaults][Pointer]` with `NaturalScroll=true` to `/etc/xdg/kcminputrc`. KWin (`Connection::applyDeviceConfig`, present since Plasma 6.3) hands a device the defaults group of its type, and `Device::naturalScrollEnabledByDefault()` reads the key from it; the per-device group System Settings writes to the user's `kcminputrc` wins. Appended rather than shipped as a file because the base may have a `kcminputrc` of its own and KConfig merges repeated groups. | **(K)** theme, wallpaper, natural scrolling for both device types; leaving existing choices alone is **(open)** |
| Flatpaks | Obsidian, Spotify, OBS Studio, Discord (official client, `com.discordapp.Discord`) and Firefox beta via `/usr/share/flatpak/preinstall.d/custom-apps.preinstall` + `custom-flatpak-preinstall.service` (`flatpak preinstall -y` at boot; Fedora ships the command but no unit). bazzite-dx's `/etc/ublue-os/system_flatpaks` has no consumer in the base image, so it cannot be relied on for rebased machines. | **(K)** Spotify/Obsidian/OBS; Kevin chose the official Discord client over Vesktop (2026-09-19) |
| Claude Desktop | **2026-09-19 (K): in an Ubuntu distrobox instead of converting the `.deb`.** Manifest `/usr/share/claude-distrobox/claude.ini`, also appended to `/etc/distrobox/apps.ini` (ublue's manifest for `ujust setup-distrobox-app`): image `ghcr.io/ublue-os/ubuntu-toolbox` (Ubuntu 26.04), init hook = `/run/host/usr/libexec/claude-distrobox-init` (Anthropic's apt repo, key fingerprint pinned, `apt install claude-desktop`, skipped once dpkg reports the package installed), app exported to the menu. The first-login hook only launches `/usr/libexec/claude-distrobox-setup` via `systemd-run --user`, because ublue-user-setup runs hooks sequentially; the setup reads the `/usr` manifest (a locally edited `/etc` file survives image updates, and assemble exits 0 when the section is missing), verifies the box exists instead of trusting assemble's exit status, and finishes a half-made box rather than deleting it. | **(K)** automatic at first login |
| Tailscale | Already in base (RPM 1.102.3). `tailscaled` enabled at build = what `ujust tailscale enable` does. | **(K)** |
| 1Password CLI | Not included. | **(open)** |
| `gh` and `tea` | **2026-09-20 (K).** `gh` from Fedora 44's package (2.97.0; the base's convention is to avoid extra repos). `tea` = Gitea's CLI (my reading of "tea"; it also works with Forgejo): nobody packages it, so `build_files/install-tea.sh` takes the latest release binary from dl.gitea.com, version found through the `releases/latest` redirect, verified against the published `.sha256`, installed to `/usr/bin/tea`. | **(K)** include both; sources **(open)** |

## Repo layout (from ublue-os/image-template)

```
Containerfile                 FROM bazzite-dx:stable@sha256:…, runs /ctx/build.sh, bootc container lint
Justfile, image-template.env  template recipes; IMAGE_NAME=bazzite-dx, REPO_ORGANIZATION=khowe085
.github/workflows/            build.yml (build+push+cosign sign), build-disk.yml
build_files/build.sh          copies system_files/ (modes normalised), runs NN-*.sh in order
build_files/10-dotnet.sh
build_files/20-1password.sh
build_files/30-firefox-native-messaging.sh   installs xdg-native-messaging-proxy, enables service
build_files/40-eden.sh        downloads the Eden AppImage into /usr/lib/eden + VERSION stamp
build_files/50-tailscale.sh   enables tailscaled
build_files/55-kde-defaults.sh   Fedora Dark as the default global theme (/etc/xdg/kdeglobals), natural scrolling defaults (/etc/xdg/kcminputrc)
build_files/60-flatpaks.sh    enables custom-flatpak-preinstall.service
build_files/70-claude-distrobox.sh   appends /usr/share/claude-distrobox/claude.ini to /etc/distrobox/apps.ini
build_files/80-forge-clis.sh  installs gh (dnf) and runs install-tea.sh
build_files/install-tea.sh    downloads and checksum-verifies Gitea's tea; not numbered, so build.sh does not run it on its own
build_files/90-verify.sh      image test (see Testing)
system_files/etc/1password/custom_allowed_browsers
system_files/etc/flatpak/remotes.d/flathub-beta.flatpakrepo   Flathub's official beta remote file, verbatim
system_files/usr/lib/sysusers.d/onepassword.conf
system_files/usr/lib/tmpfiles.d/onepassword.conf
system_files/usr/lib/systemd/system/onepassword-firefox-flatpak.service
system_files/usr/lib/systemd/system/custom-flatpak-preinstall.service
system_files/usr/libexec/onepassword-firefox-flatpak-setup
system_files/usr/libexec/claude-distrobox-init   runs inside the claude box as its init hook
system_files/usr/libexec/claude-distrobox-setup  per-user creation of the box, started detached by the hook
system_files/usr/share/claude-distrobox/claude.ini   the box's manifest
system_files/usr/share/ublue-os/firefox-config/zz-onepassword-native-messaging.js
system_files/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/picture-of-the-day-wallpaper.js   Plasma update script, once per user
system_files/usr/share/flatpak/preinstall.d/custom-apps.preinstall
system_files/usr/share/ublue-os/user-setup.hooks.d/30-emudeck.sh
system_files/usr/share/ublue-os/user-setup.hooks.d/40-claude-distrobox.sh
tests/                        script tests (bash, run in a container via `just test`)
```

## Testing (TDD)

- `build_files/90-verify.sh` is written first and run against the untouched base (red), then runs as the last build step (green). It asserts package presence, file modes/ownership (setgid `1Password-BrowserSupport`, setuid `chrome-sandbox`), fixed GIDs, tmpfiles/sysusers entries, allow-list contents, service enablement, the Firefox pref file, the beta remote and its signing key, AppImage + stamp, hook syntax.
- `tests/test-claude-distrobox-init.sh`, `-setup.sh` and `-hook.sh` cover the in-box install script (stub curl/gpg/apt-get/dpkg-query), the per-user setup (stub distrobox) and the launcher hook (stub systemd-run).
- `tests/test-install-tea.sh` covers the tea download (stub curl, real sha256sum): happy path, checksum mismatch, unusable version lookup, failed download.
- `tests/test-emudeck-hook.sh` and `tests/test-firefox-setup.sh` run the two runtime scripts with a temp `HOME`, a stub `flatpak`, and overridable source dirs, asserting the files they produce.
- Local runs use Docker Desktop (`docker build` / `docker run`); CI uses the template's podman recipes.
- `tests/test-kde-defaults.sh` runs the KDE build step against scratch copies of Bazzite's kdeglobals (one line changed, fails when the key or the file is gone) and of kcminputrc (both defaults groups appended, with or without an existing file). The wallpaper update script is JavaScript for Plasma's scripting engine and the repo has no JS runtime to test with: its logic ran once against stub desktops under Windows Script Host (declarations rewritten to `var`), and `90-verify.sh` checks statically that it, the Fedora Dark theme, the `org.kde.potd` wallpaper and the APOD provider plugin are in the image.
- Review gate: `code-reviewer` agent, up to 3 rounds, before anything is pushed. No commits without Kevin's go-ahead.

## Kevin's manual steps

1. ~~Create the GitHub repo `khowe085/bazzite-dx`~~ Done 2026-09-19 (public). Nothing pushed yet.
2. ~~Generate the cosign key pair, add `cosign.key` as repo secret `SIGNING_SECRET`, commit `cosign.pub`~~ Done 2026-09-19 (empty password, as the workflow expects). `cosign.key` stays local and gitignored.
3. Push; first build publishes `ghcr.io/khowe085/bazzite-dx:latest`.
4. On the machine: `sudo bootc switch ghcr.io/khowe085/bazzite-dx:latest`, reboot.
5. Run the EmuDeck wizard once (choices listed in README); enter the Patreon token there.

## Risks / uncertainty

- The 2026-09-19 Firefox-beta pivot was not built or run locally (Kevin chose to skip Docker runs): only the stubbed script test ran, in Git Bash. Unverified flatpak behaviour it relies on: `flatpak preinstall` installing `Branch=beta` next to an already-installed stable, the extension point following the app's branch, and the newly installed branch becoming current. The first CI build is the first real run of `90-verify.sh` with these changes.
- Claude Desktop in a distrobox is untested on a real desktop: Electron sandbox in a rootless container, browser login hand-off (`claude://`), Cowork (QEMU/KVM in the box). Mechanics confirmed only by reading distrobox 1.8.2.5's source (the version Fedora 44 ships).
- KDE defaults have not run under Plasma: the update script's first real run is a login on Kevin's machine. Mechanics confirmed by reading plasma-workspace (`startplasma.cpp`, `shellcorona.cpp`, `scriptengine.cpp`) and kdeplasma-addons on their Plasma/6.7 branches, not by running them. The image wallpaper only writes its `Image` entry when the user picks or drops a picture (its `main.xml` default is empty, and `main.qml` assigns it in the drag-and-drop handler alone), which is what the script's "untouched" test rests on; if that reading is wrong, the script leaves his wallpaper alone and he sets Picture of the Day by hand.
- Firefox proxy route is untested end to end; 1Password accepting `xdg-native-messaging-proxy` as the parent process is inferred from the `xdg-desktop-portal` / `flatpak-session-helper` precedents (~75%).
- Fixed GIDs (see sysusers.d) must stay free on the target machine; sysusers falls back to another GID on collision, which would silently break the setgid check.
- 1Password's polkit owner list is generated from `/etc/passwd`, which is empty at image build time, so the build bakes in `unix-user:1000` … `unix-user:1009`. Users with other UIDs cannot use the CLI/SSH-agent authorisation prompts.
