# bazzite-dx (custom)

A [bootc](https://github.com/bootc-dev/bootc) image built on
[`ghcr.io/ublue-os/bazzite-dx:stable`](https://github.com/ublue-os/bazzite-dx) (KDE, AMD/Intel graphics),
published as `ghcr.io/khowe085/bazzite-dx`. Layout follows the
[Universal Blue image template](https://github.com/ublue-os/image-template).

## What the image adds

| Item | How |
|---|---|
| .NET 10 SDK | Fedora's `dotnet-sdk-10.0` package |
| 1Password | Official RPM, relocated to `/usr/lib/opt/1Password` with a tmpfiles link at `/var/opt/1Password`; groups `onepassword` (GID 20200) and `onepassword-mcp` (GID 20201) declared in `sysusers.d` so they exist on every machine |
| Firefox flatpak ↔ 1Password | Firefox beta Flatpak plus the `xdg-native-messaging-proxy` route (see below) |
| `gh` and `tea` | GitHub's CLI from Fedora's `gh` package; Gitea's CLI `tea` (also works with Forgejo) as the latest release binary from dl.gitea.com, checked against its published SHA-256 |
| Tailscale | Already in Bazzite; `tailscaled` is enabled at build, run `sudo tailscale up` once |
| KDE defaults | Global theme Fedora Dark instead of Bazzite's Vapor (`LookAndFeelPackage` in `/etc/xdg/kdeglobals`), and Picture of the Day from the "Astronomy (NASA)" provider as the desktop background (a Plasma update script, run once per user). Natural scrolling for touchpads and mice (`[Libinput][Defaults]` groups in `/etc/xdg/kcminputrc`, which KWin reads per device type). All three are defaults: a global theme you picked yourself, a picture you set as wallpaper or another wallpaper type, and a scroll direction you set for a device all stay, and whatever you choose afterwards in System Settings sticks. The lock and login screens are not changed |
| EmuDeck | First-login hook downloads the latest EmuDeck AppImage into `~/Applications` and adds a menu entry |
| Eden | Latest AppImage from git.eden-emu.dev baked into `/usr/lib/eden`; the same hook copies it to `~/Applications/Eden.AppImage`, where EmuDeck expects it |
| Flatpaks | Obsidian, Spotify, OBS Studio, Discord and Firefox beta are installed at boot via `flatpak preinstall` (`/usr/share/flatpak/preinstall.d/custom-apps.preinstall`); uninstalling one keeps it uninstalled |
| Claude Desktop | Anthropic's official Ubuntu build inside a distrobox named `claude`, created at first login and exported to the menu (see below) |

The last build step, `build_files/90-verify.sh`, checks all of the above and fails the build otherwise.

## Firefox flatpak and 1Password

The sandboxed Firefox cannot reach the host 1Password app on its own. This image opens one narrow path,
the `xdg-native-messaging-proxy` route:

- `xdg-native-messaging-proxy` is installed and allow-listed in `/etc/1password/custom_allowed_browsers`.
- `onepassword-firefox-flatpak.service` runs at boot. It copies the default prefs in
  `/usr/share/ublue-os/firefox-config/` (Bazzite's own plus
  `widget.use-xdg-desktop-portal.native-messaging-proxy = 1`) into the Firefox flatpak's `systemconfig`
  extension for both the `stable` and `beta` branches, and grants the flatpak
  `--talk-name=org.freedesktop.NativeMessagingProxy`.

Firefox only gained the proxy client in **Firefox 157**, which reaches Flathub's stable channel on
2026-09-29. Until then the image installs **Firefox beta** from the `flathub-beta` remote
(`Branch=beta` in `custom-apps.preinstall`). Stable Firefox from the Bazzite ISO stays installed next to
it, and both share one profile.

- The menu entry launches whichever branch is "current", normally the one installed last. To set it:

  ```bash
  flatpak make-current --system org.mozilla.firefox beta
  ```

- To go back to stable once it is 157 or newer, change `Branch=beta` to `Branch=stable` in the drop-in and
  rebuild, or run `flatpak make-current --system org.mozilla.firefox stable` and uninstall
  `org.mozilla.firefox//beta`. Do it before the beta moves on to 158; otherwise Firefox treats the shared
  profile as a downgrade and offers a fresh one (`--allow-downgrade` overrides that).

To check the link: in Firefox open `about:config` and confirm the pref is `1`, install the 1Password
extension, then look at `journalctl --user -u xdg-native-messaging-proxy` and 1Password's
Settings → Browser → integration status. If 1Password refuses the connection, the parent process name it
sees is what belongs in `custom_allowed_browsers`.

## EmuDeck

The hook only places the AppImages. Run EmuDeck once and pick in the wizard:

- **High** integration (Steam ROM Manager adds games as non-Steam games with per-system collections).
- Cloud Sync, and enter the Patreon/lifetime token on the Patreon step. The token is never stored in
  this image.
- Quick settings: Bezels on, Autosave on, classic aspect ratios set to 4:3.
- Select Eden as the Switch emulator; the hook already put `Eden.AppImage` where EmuDeck looks.

The hook replaces `~/Applications/Eden.AppImage` when the image carries a newer release than it placed
before. An Eden you put there yourself (no `.eden.image-version` stamp next to it) is left alone.

To ship a different Eden flavour (`steamdeck`, `rog-ally`, `legacy`, or the `gcc-standard` builds), pass
`--build-arg EDEN_VARIANT=steamdeck-clang-pgo` to `podman build` / `docker build`, or change the `ARG`
default in the Containerfile (the `just build` recipe passes no build args).

## Claude Desktop

Anthropic only ships Claude Desktop for Debian and Ubuntu, so it lives in an Ubuntu
[distrobox](https://distrobox.it/) instead of the image:

- The box is defined in `/usr/share/claude-distrobox/claude.ini`: image `ghcr.io/ublue-os/ubuntu-toolbox`,
  `claude-desktop` exported to the menu. The build also appends that entry to `/etc/distrobox/apps.ini`,
  the manifest behind Bazzite's `ujust setup-distrobox-app`.
- The box's init hook is `/usr/libexec/claude-distrobox-init` from this image, which the box sees under
  `/run/host`. On the first start it adds Anthropic's apt repository, refuses any signing key other than
  the fingerprint Anthropic documents, and runs `apt install claude-desktop`. Later starts skip all of it.
- A first-login hook starts `/usr/libexec/claude-distrobox-setup` as a detached user unit, so the other
  setup hooks are not held up by what is roughly a 1 GB download, once per user. It reads the manifest
  under `/usr`, so a locally edited `apps.ini` cannot make it silently skip the box. An attempt that fails
  part-way is finished at the next login, not rebuilt. Follow it with
  `journalctl --user -u claude-distrobox-setup`.

Updates arrive through apt inside the box (`distrobox upgrade claude`). To rebuild the box from scratch:

```bash
distrobox assemble create --replace --file /usr/share/claude-distrobox/claude.ini
```

`ujust setup-distrobox-app claude` does the same from `/etc/distrobox/apps.ini`, but silently does nothing
if you have edited that file, because an edited `/etc` file keeps its old contents across image updates.
A box you remove (`distrobox rm claude`) stays removed. To have the next login create it again, remove
the box first and then delete `~/.local/state/claude-distrobox.created`; with a box still present the
setup treats it as yours and leaves it alone.

## Setting up the repository

1. Create the GitHub repository `khowe085/bazzite-dx` and enable Actions.
2. Create a signing key and store the private half as the `SIGNING_SECRET` repository secret:

   ```bash
   COSIGN_PASSWORD="" cosign generate-key-pair
   gh secret set SIGNING_SECRET < cosign.key
   ```

   Commit `cosign.pub`; never commit `cosign.key`.
3. Push `main`. The workflow builds, pushes `ghcr.io/khowe085/bazzite-dx:latest` and signs it.
4. On the machine:

   ```bash
   sudo bootc switch ghcr.io/khowe085/bazzite-dx:latest
   ```

   then reboot.

## Building and testing locally

```bash
just build
```

builds `localhost/bazzite-dx:latest` with podman (the verification step runs inside the build). With
Docker instead:

```bash
docker build -f Containerfile -t bazzite-dx:local .
```

The runtime scripts have their own tests, run inside a container with the repo mounted at `/src`
(CI runs them after every build):

```bash
just test
```

or with Docker:

```bash
docker run --rm -v "$PWD:/src:ro" bazzite-dx:local bash /src/tests/test-firefox-setup.sh
docker run --rm -v "$PWD:/src:ro" bazzite-dx:local bash /src/tests/test-emudeck-hook.sh
```

## Known limits

- The fixed 1Password GIDs must be free on the target machine; `systemd-sysusers` picks another GID
  on a collision, which would break the setgid check silently.
- 1Password's polkit policy lists `unix-user:1000` … `unix-user:1009` as owners (the file is generated
  from `/etc/passwd` at install time, which has no desktop users inside a build). Users with other UIDs
  cannot use the CLI/SSH-agent authorisation prompts.
- The Eden and EmuDeck downloads are trusted on HTTPS alone: Eden publishes no checksums for its release
  assets, and Bazzite's own `ujust get-emudeck` verifies nothing either. `tea` is checked against a
  SHA-256 that Gitea serves from the same host as the binary, which catches a broken download but not a
  compromised server; Gitea publishes no signature for it.
- Claude Desktop in the distrobox has not been run on a real desktop yet. Anthropic supports Ubuntu
  22.04 and later and the box is Ubuntu 26.04, but the Electron sandbox inside a rootless container, the
  login hand-off from the browser, and Cowork (which needs QEMU/KVM inside the box) are untried.
