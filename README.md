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
| Tailscale | Already in Bazzite; `tailscaled` is enabled at build, run `sudo tailscale up` once |
| EmuDeck | First-login hook downloads the latest EmuDeck AppImage into `~/Applications` and adds a menu entry |
| Eden | Latest AppImage from git.eden-emu.dev baked into `/usr/lib/eden`; the same hook copies it to `~/Applications/Eden.AppImage`, where EmuDeck expects it |
| Flatpaks | Obsidian, Spotify, OBS Studio, Discord and Firefox beta are installed at boot via `flatpak preinstall` (`/usr/share/flatpak/preinstall.d/custom-apps.preinstall`); uninstalling one keeps it uninstalled |

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
  assets, and Bazzite's own `ujust get-emudeck` verifies nothing either.
- Anthropic's Claude Desktop is not included. Its Linux beta is Debian-only, but the `.deb` is a plain
  `/usr/lib/claude-desktop` Electron payload whose dependencies bazzite-dx already has, so adding it
  would be one build script along the lines of the 1Password one.
