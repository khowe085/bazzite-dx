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
| KDE defaults | Global theme Fedora Dark instead of Bazzite's Vapor (`LookAndFeelPackage` in `/etc/xdg/kdeglobals`), and Picture of the Day from the "Astronomy (NASA)" provider as the desktop background (a Plasma update script, run once per user). For touchpads and mice: natural scrolling, no pointer acceleration, and tap-and-drag that allows briefly lifting the finger (`[Libinput][Defaults]` groups in `/etc/xdg/kcminputrc`, which KWin reads per device type). No action in the top-left screen corner (`/etc/xdg/kwinrc`), and the screen never locks by itself but does lock after waking from sleep (`/etc/xdg/kscreenlockerrc`). bazzite-dx is built on Bazzite's Deck (handheld/HTPC) edition, so the Deck-only presets its desktop edition leaves out are removed: the "Return to Gaming Mode" shortcut on new users' desktops, the IBus input-method daemon at login, and Baloo indexing file names only. These are defaults: a global theme you picked yourself, a picture you set as wallpaper or another wallpaper type, and whatever you set for a device, the corner or the lock all stay, and whatever you choose afterwards in System Settings sticks. Panels do not float (the Add Panel templates, which a new profile's default layout uses too). The look of the lock and login screens is not changed |
| Power management | Per power state (`/etc/xdg/powerdevilrc`): on AC, dim after 15 minutes, screen off after 30, sleep after 30, closing the lid does nothing, Performance profile; on battery 5, 10 and 10 minutes, the lid sleeps, Balanced; on low battery 2, 5 and 5 minutes, the lid sleeps, Power Save. In all three the power button sleeps and the screen-off time applies whether the screen is locked or not. Bazzite's Steam Deck profiles (`/etc/xdg/powermanagementprofilesrc`, Plasma 5) are removed, because powerdevil copies them into every new profile at its first login. Changes made in System Settings afterwards stay. Power profiles and the non-floating panel reach profiles whose first desktop login is on this image, as after installing from its ISO; a profile set up on stock Bazzite before `bootc switch` has already saved Bazzite's power values and a floating panel |
| EmuDeck | First-login hook downloads the latest EmuDeck AppImage into `~/Applications` and adds a menu entry |
| Eden | Latest AppImage from git.eden-emu.dev baked into `/usr/lib/eden`; the same hook copies it to `~/Applications/Eden.AppImage`, where EmuDeck expects it |
| Flatpaks | Obsidian, Spotify, OBS Studio, Discord, VacuumTube (YouTube), Jellyfin Desktop and Firefox beta are installed at boot via `flatpak preinstall` (`/usr/share/flatpak/preinstall.d/custom-apps.preinstall`); uninstalling one keeps it uninstalled |
| Bazzite Portal selections | Cockpit, DisplayLink, virtualization, Framework fan control, HDMI 2.1 on AMD, sudo password asterisks, `/var/home` snapshots and deduplication, Steam icon cleanup, FSR4 on RDNA3, JetBrains Toolbox, LM Studio and Crunchyroll, switched on up front (see below) |
| Claude Desktop | Anthropic's official Ubuntu build inside a distrobox named `ubuntu`, created at first login and exported to the menu (see below) |
| SSH keys and Git signing | The system side of 1Password's SSH agent and commit signing setup; choosing the key stays in the app (see below) |

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

## SSH keys and Git signing with 1Password

The system side of 1Password's [SSH agent](https://www.1password.dev/ssh/get-started/) and
[Git commit signing](https://www.1password.dev/ssh/git-commit-signing/) setup is already in place:

- `/etc/ssh/ssh_config.d/60-1password-agent.conf` points every host at the agent socket with
  `IdentityAgent ~/.1password/agent.sock`, the setting 1Password documents for `~/.ssh/config`. That
  setting outranks `SSH_AUTH_SOCK`, so the drop-in only applies it when 1Password's socket exists and
  you are not connected over SSH. When you SSH into this machine a forwarded agent keeps working, and
  with 1Password's agent off whatever agent the session has stays in charge. Your own `~/.ssh/config`
  still wins.
- The system Git config sets `gpg.format = ssh`, `gpg.ssh.program = /opt/1Password/op-ssh-sign` and
  `commit.gpgsign = true`.

What is left is per user and done in the app:

1. Settings → Developer → **Use the SSH Agent**, and Settings → General → **Keep 1Password in the system
   tray** so the agent outlives the window.
2. Open the SSH key you sign with, choose **Configure Commit Signing**, then **Edit Automatically**. That
   writes `user.signingkey` to `~/.gitconfig`.

Until a signing key is set, everything that creates a commit (`commit`, `rebase`, `cherry-pick`, `revert`,
`merge --no-ff`, `am`) stops with `either user.signingkey or gpg.ssh.defaultKeyCommand needs to be
configured`. `git commit --no-gpg-sign` gets past it for a commit, and `git -c commit.gpgsign=false
<command>` for the rest.

Optional, from the same docs: to verify signatures locally, create `~/.ssh/allowed_signers` and run
`git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers`. Tools that ignore `ssh_config`
need `SSH_AUTH_SOCK=~/.1password/agent.sock` instead.

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
[distrobox](https://distrobox.it/) instead of the image. The box is called `ubuntu`, the name the base's
own `distrobox.ini` uses for the same image, and is a general-purpose Ubuntu box apart from that:

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

Updates arrive through apt inside the box (`distrobox upgrade ubuntu`). To rebuild the box from scratch:

```bash
distrobox assemble create --replace --file /usr/share/claude-distrobox/claude.ini
```

`ujust setup-distrobox-app ubuntu` does the same from `/etc/distrobox/apps.ini`, but silently does nothing
if you have edited that file, because an edited `/etc` file keeps its old contents across image updates.
A box you remove (`distrobox rm ubuntu`) stays removed. To have the next login create it again, remove
the box first and then delete `~/.local/state/ubuntu-distrobox.created`; with a box still present the
setup treats it as yours and leaves it alone. That includes an `ubuntu` box you made yourself before the
first login: it is never touched, so it gets no Claude Desktop.

Bazzite's `ujust assemble` also offers a box called `ubuntu`, a plain one from `/etc/distrobox/distrobox.ini`,
and always replaces an existing box of that name. Choosing it there (or "ALL") swaps this box for one
without Claude Desktop, and the stamp keeps the login hook from bringing it back; use the rebuild command
above instead.

Earlier images called the box `claude`. A machine that still has that one gets the `ubuntu` box next to
it (a second download), and the menu shows Claude Desktop twice, "(on claude)" and "(on ubuntu)", until
you remove the old one with `distrobox rm claude`.

## Bazzite Portal selections

Entries of the Bazzite Portal, plus one `ujust` recipe, that this image switches on up front. Each is
done the way its recipe does it, so the Portal and `ujust` still show and toggle them. The package
install is the exception: the Portal only recognises layered packages, so it keeps listing DisplayLink
as not installed. Ignore its offer to install it.

| Portal entry | In this image |
|---|---|
| Enable Cockpit | `cockpit.service` enabled, reachable from the machine itself only (`http://localhost:9090`): the firewalld policy `cockpit-local-only` rejects port 9090 from every zone, which covers other machines, VMs and Tailscale peers, while loopback traffic never reaches a policy. Its login goes over SSH to localhost, so it lets nobody in until SSH is on too (`ujust ssh enable`, the Portal's "Enable SSH remote access"), which this image leaves off |
| Enable Tailscale | `tailscaled` enabled (see the table above) |
| Install support for DisplayLink | negativo17's `displaylink`; the `evdi` kernel module is part of Bazzite |
| Android Platform Tools | Nothing to do: bazzite-dx ships `android-tools` |
| Enable visible password asterisks in CLI | `/etc/sudoers.d/enable-pwfeedback` |
| Setup virtualization | bazzite-dx ships QEMU, libvirt and virt-manager and adds users to the `libvirt` group. Added here: `libvirtd` enabled, Bazzite's one-time `bazzite-libvirtd-setup.service`, the kernel arguments `kvm.ignore_msrs=1 kvm.report_ignored_msrs=0` (`/usr/lib/bootc/kargs.d/10-kvm-msrs.toml`) and `/var/lib/swtpm-localca` for emulated TPMs |
| `ujust enable-framework-fan-control` | `fw-fanctrl.service` enabled (the package is part of Bazzite). Nothing else in the image drives the fan |
| Enable HDMI 2.1 for AMD graphics cards | The kernel argument `amdgpu.dcfeaturemask=0x402` (`/usr/lib/bootc/kargs.d/20-amdgpu-hdmi21.toml`). The Portal warns that it can cause flickering or an unstable signal on some displays |
| Configure btrfs snapshots | First boot: a Snapper config for `/var/home` under Bazzite's config name `root`, keeping 5 hourly and 7 daily timeline snapshots and the 10 newest of those marked for Snapper's `number` cleanup, with the timeline and cleanup timers on. A snapshot taken without a cleanup algorithm stays until you delete it. A config that already exists is left alone. Restore with Btrfs Assistant |
| Setup btrfs deduplication | First boot: a `beesd` config for the filesystem behind `/var/home` with the recipe's sizing and options, and its daily timer (at most 30 minutes a run, only with enough free memory). A config that already exists is left alone |
| Clean Steam desktop icons automatically | First login: `steam-icons-cleanup.service` enabled for the user |
| Enable globally upgrading FSR3.1+ to FSR4 (RDNA3) | First login: `~/.config/environment.d/99-proton-fsr4-rdna3.conf`. Only Proton-GE, Proton-EM and similar builds act on it |
| JetBrains Toolbox, LM Studio | First login: the Portal's Homebrew cask installs, one after the other in a detached unit; follow it with `journalctl --user -u portal-brew-casks-setup`. Each is retried at every login until it has worked once |
| Get Media Apps: YouTube, Jellyfin | The VacuumTube and Jellyfin Desktop Flatpaks |
| Get Media Apps: Crunchyroll | First login: the AppImage the Portal downloads (github.com/aarron-lee/crunchyroll-linux, an unofficial client), placed at `~/Applications/Crunchyroll.AppImage` with a menu entry instead of being handed to Gear Lever. Placed once; move or delete it and it stays that way |

Still done by hand in the Portal, because their recipes need a desktop session or a running Steam:
Sunshine, Boxtron, Netflix, and adding the media apps to Steam.

- Everything under "first boot" and "first login" is applied once. Switch it off in the Portal or with
  `ujust` and it stays off. To apply it again, delete the stamp and start the unit
  (`/var/lib/custom-home-snapshots/done` with `custom-home-snapshots.service`,
  `/var/lib/custom-home-dedup/done` with `custom-home-dedup.service`), or delete the entry under
  `~/.local/state/portal-tweaks/` and log in again. A Snapper or bees config that is still there
  counts as yours and is left as it is, so remove that first (switching the entry off in the Portal or
  with `ujust` does).
- A first-boot unit that cannot do its job (say `/var/home` is not a btrfs subvolume of its own) fails
  at every boot and leaves the system `degraded`. `systemctl status custom-home-snapshots.service` (or
  `custom-home-dedup.service`) has the reason; `sudo systemctl disable` on the same unit ends it.
- Snapshots hold on to disk space: what you delete under `/var/home`, a Steam library included, is only
  freed once the last snapshot containing it ages out, up to a week later.
- To reach Cockpit from other machines after all, take the rule out of the policy and reload; the
  zone the connection arrives in must allow the port too (Fedora's workstation zone does):

  ```bash
  sudo firewall-cmd --permanent --policy=cockpit-local-only --remove-rich-rule='rule port port="9090" protocol="tcp" reject'
  ```

  then `sudo firewall-cmd --reload`.
- Kernel arguments from `kargs.d` are applied by `bootc switch` and `bootc upgrade`. Check
  `cat /proc/cmdline`; if they are missing, `rpm-ostree kargs --append-if-missing=kvm.ignore_msrs=1
  --append-if-missing=kvm.report_ignored_msrs=0` adds them (same for `amdgpu.dcfeaturemask=0x402`).
- If the screen flickers with the HDMI 2.1 argument, take it out with
  `sudo rpm-ostree kargs --delete-if-present=amdgpu.dcfeaturemask=0x402` and reboot; bootc only
  re-applies `kargs.d` entries when they change.

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

## Installing from an ISO

The KDE and power defaults reach a profile whose first desktop login is on this image. Installing from
an ISO of it gets you that; installing stock Bazzite and then running `bootc switch` does not, because
stock Bazzite has already saved its own power values and a floating panel into the profile by then.

The ISO is Bazzite's own live installer (`installer/`, copied from Bazzite), set up to install this image:

1. Actions → **Build ISO** → Run workflow, tag `latest` (or `pr-<number>` for a pull request's build).
   The ISO and its checksum are the run's `iso` artifact.
2. Write it to a USB stick and boot it. It starts a live Bazzite session with the same installer as
   Bazzite's ISO; choose the disk, encryption and your user there.
3. On a UEFI machine the installer queues the key Bazzite's kernel is signed with, whether Secure Boot
   is on or not. At the first reboot the MOK manager asks for it: choose "Enroll MOK", continue, and
   enter `universalblue`. If the firmware has the key already, nothing is asked.

The installed system follows the tag the ISO was built from. After installing from a `pr-<number>` ISO,
switch to `latest` once the pull request is merged, as described next.

## Testing a pull request on the machine

The workflow also publishes and signs every pull request opened from a branch of this repository, under
the tag `pr-<number>` (never `latest`). Forks and Dependabot pull requests are built and tested but not
published. The run's summary page shows the command:

```bash
sudo bootc switch ghcr.io/khowe085/bazzite-dx:pr-5
```

Reboot into it; `sudo bootc upgrade` follows later pushes to the same pull request. After the merge, go
back with `sudo bootc switch ghcr.io/khowe085/bazzite-dx:latest`, or the machine stays on the stale
`pr-<number>` tag. `sudo bootc rollback` returns to the deployment you came from if the test image does
not boot. Old `pr-<number>` tags stay in the registry until you delete them on the package's page.

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
- A distrobox shares your home, so it reads the `~/.gitconfig` that 1Password's commit signing setup
  writes, but it has no `/opt/1Password/op-ssh-sign`. Commits made inside a box, the `claude` box
  included, fail once signing is configured unless they pass `--no-gpg-sign`.
