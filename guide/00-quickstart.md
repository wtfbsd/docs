<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Quickstart: your first customized desktop in one sitting

[Index](README.md) · Next: [Stage 1: fork and name](01-fork-and-name.md)

This page walks through one small, complete change on the FreeBSD 16
template, the most complete of the four: you fork it, give it your name,
add your own wallpaper and greeter theme as a small package of your own,
add one application from upstream, build the media and boot it in a VM.
Every command here is one the templates, the wtfbsd/agents scripts or
the FreeBSD base system have. Where a step is not automated yet, the
page says so.

The example product is **ExampleBSD** (slug `examplebsd`) under the
GitHub organisation `example-org`. Use your own name, slug and
organisation.

"One sitting" means one day: the build compiles the FreeBSD base system
from source. With 8 make jobs (`JOBS=8`) the whole build takes about
2.5 hours; it scales with the number of jobs.

## What you need

- A GitHub account or organisation, and the GitHub CLI `gh`, logged in
  (`gh auth login`).
- A build host: a FreeBSD 16 amd64 machine or VM, with root, network
  access to the upstream package repository, a FreeBSD 16 source tree in
  `/usr/src`, a ports tree in `/usr/ports`, and about 50 GB of free disk
  for the source, the ports tree, the world build and the images (the
  two images alone are about 23 GB before compression). FreeBSD 16 is
  the development branch (16-CURRENT); there is no 16.0-RELEASE yet. git
  is not in the base system, so on a fresh system install it first, then
  fetch the `main` branch of both trees (the ports tree is about 1.1 GB):

  ```sh
  pkg bootstrap
  pkg install git-lite
  git clone --depth 1 https://git.FreeBSD.org/src.git /usr/src
  git clone --depth 1 https://git.FreeBSD.org/ports.git /usr/ports
  ```

  The ports tree is there because the template rebuilds out-of-kernel
  drivers (`KMOD_REBUILD=yes`, the default) for the exact kernel it
  built when the repository's builds of them do not match it; when they
  already match, nothing is rebuilt. Building with
  `KMOD_REBUILD=no ALLOW_KMOD_MISMATCH=yes` skips that and the ports
  tree, but only as an explicit escape: a kernel and driver that do not
  match can panic the GPU drivers.

  The build runs one make job per CPU; set `JOBS` to change that, for
  example `JOBS=8 ./build.sh ...` (the knob is described at the top of
  the template's `build.sh`); the build time is given at the top of this page.
- Somewhere to boot the result: any VM software that boots UEFI and has a
  graphical display, with an empty virtual disk of 20 GB or more.
- Two pictures of your own, in PNG: a wallpaper, 1920x1080, and a logo,
  128x128.

## 1. Name it

On any machine with `gh` (it does not have to be the build host), get the
tooling and write your answers:

```sh
git clone https://github.com/wtfbsd/agents && cd agents
cat > answers.yaml <<'EOF'
DISTRO_OS: freebsd
DISTRO_NAME: ExampleBSD
DISTRO_SLUG: examplebsd
DISTRO_ARCH: amd64
FILESYSTEM_ROOT: zfs
PROFILE: desktop
INSTALLER: tui
MOTD: Welcome to ExampleBSD
BRAND_COLOR: 3b6ea5
BRAND_URL: https://example.org
PUBLISH_TARGET: example.org
PUBLISHER_ORG: example-org
EOF
scripts/apply-answers.sh -c answers.yaml       # check only, writes nothing
scripts/apply-answers.sh answers.yaml          # writes ./product.conf
```

`DISTRO_NAME` is the name people see; `DISTRO_SLUG` is the lowercase
name used in repository names, file names, paths and package names.
Choose the slug carefully: changing it later touches all of those (see
[Stage 1](01-fork-and-name.md#4-choose-the-slug-carefully)). The
`-c` run prints every key, its value and where the value came from.

## 2. Fork

```sh
scripts/fork-distro.sh --os freebsd --name ExampleBSD --slug examplebsd \
    --org example-org                  # dry run: prints the plan
scripts/fork-distro.sh --os freebsd --name ExampleBSD --slug examplebsd \
    --org example-org --apply          # makes the four forks
```

That gives you `example-org/examplebsd` (the product repository, from
the FreeBSD template), `examplebsd-ports`, `examplebsd-installer` and
`examplebsd-ci`. The script does not clone them and does not copy
`product.conf`. On the build host:

```sh
gh repo clone example-org/examplebsd
gh repo clone example-org/examplebsd-ports
cp /path/to/agents/product.conf examplebsd/product.conf
cd examplebsd
./build.sh -c product.conf -n          # dry run: prints the plan, changes nothing
```

The dry run must exit 0 before you go on.

## 3. Your artwork, as a package of your own

The desktop profile already points the LightDM greeter at your artwork.
In the product repository,
`overlay/profiles/desktop/rootfs/usr/local/etc/lightdm/lightdm-gtk-greeter.conf`
says:

```
[greeter]
background=/usr/local/share/@SLUG@/artwork/wallpapers/wallpaper-1-1920x1080.png
default-user-image=/usr/local/share/@SLUG@/artwork/logo/logo-128.png
```

`build.sh` replaces `@SLUG@` with your slug. The template ships no
artwork at all (`overlay/profiles/desktop/branding.conf` documents the
contract), so these two files must come from somewhere. They go in a
package rather than in the overlay: a package can be updated with
`pkg upgrade` later, a file in the overlay only with new media.

This is a `product` package: content only you have. It has no compiled
code, so it is one directory with a manifest and a file list. Put it in
your ports repository. This page assumes both forks are cloned side by
side: `examplebsd` (the product) and `examplebsd-ports`. The ports template
is only a README today, so you create the directory yourself:

```sh
cd ../examplebsd-ports
mkdir -p examplebsd-artwork/meta
mkdir -p examplebsd-artwork/stage/usr/local/share/examplebsd/artwork/wallpapers
mkdir -p examplebsd-artwork/stage/usr/local/share/examplebsd/artwork/logo
cp ~/my-wallpaper.png examplebsd-artwork/stage/usr/local/share/examplebsd/artwork/wallpapers/wallpaper-1-1920x1080.png
cp ~/my-logo.png      examplebsd-artwork/stage/usr/local/share/examplebsd/artwork/logo/logo-128.png
```

The manifest, `examplebsd-artwork/meta/+MANIFEST`:

```
name: examplebsd-artwork
version: "1.0.20261031.1"
origin: examplebsd/artwork
comment: "ExampleBSD wallpaper, logo and greeter theme"
desc: "Wallpaper and logo for the ExampleBSD desktop and its LightDM greeter."
maintainer: "you@example.org"
www: "https://example.org"
prefix: /usr/local
abi: "FreeBSD:16:*"
```

The version is a base version, then the build date, then a counter (here
`1.0`, `20261031` and `1`), so that every rebuild is newer than the last (see [Stage 3](03-packages.md#keep-ours-small)).
`FreeBSD:16:*` is the ABI of an architecture-independent package. The
file list, `examplebsd-artwork/plist`, relative to the prefix:

```
share/examplebsd/artwork/wallpapers/wallpaper-1-1920x1080.png
share/examplebsd/artwork/logo/logo-128.png
```

Record why the package is yours, in `ours.list` at the top of the ports
repository:

```
# ours.list: every package the product repository publishes, and why
examplebsd-artwork  product  wallpaper, logo and greeter theme
```

Build the package and a catalogue for it:

```sh
mkdir -p out
pkg create -m examplebsd-artwork/meta -p examplebsd-artwork/plist \
    -r examplebsd-artwork/stage -o out/
pkg repo out/
```

`pkg repo out/` without a key writes an **unsigned** catalogue. That is
acceptable only for this first sitting, on your own build host, read from
the local disk. Before anybody else installs from it, the repository is
signed and served over HTTPS as [Stage 3b](03b-packages-per-os.md#freebsd-16)
describes; that part is not automated in the templates yet.

## 4. Let the build see your package

The template's package step is `pkg -r <stage> install -y` over the
package lists, and it uses the package repositories configured **on the
build host**. So the quickest way to make your package visible to it is
a repository file on the build host, as root, in
`/usr/local/etc/pkg/repos/ExampleBSD-local.conf`:

```
ExampleBSD-local: {
  url: "file:///home/you/examplebsd-ports/out",
  enabled: yes
}
```

Use the absolute path of your `out/` directory. Then check that pkg
sees exactly your package, and run the self-hosted check on it. The
check is `scripts/ours-check.sh` in your clone of wtfbsd/agents; copy it
from there to `tests/ours-check.sh` in the ports repository so it
travels with it:

```sh
pkg update -f
pkg rquery -a -r ExampleBSD-local '%n' > published.txt
cat published.txt                      # examplebsd-artwork
mkdir -p tests && cp /path/to/agents/scripts/ours-check.sh tests/
sh tests/ours-check.sh ours.list published.txt
```

It prints `ours-check: pass (1 self-hosted packages, each with a
reason)`. What it checks, and the four-argument form that also compares
against upstream, is [the self-hosted check](03-packages.md#the-self-hosted-check).

This file is a shortcut, and the installed system does not get it: it
lives on the build host only. The finished way is a signed repository
whose client file ships in the overlay and which the build uses through
`pkg -R` (see [Stage 4](04-build-media.md#freebsd-16)); the template's
`build.sh` does not do that yet.

## 5. Add your package and one application to the desktop

Back in the product repository (`cd ../examplebsd`), add these lines to
`overlay/profiles/desktop/packages.list` (one package name per line,
`#` starts a comment):

```
# ours: wallpaper, logo and greeter theme (examplebsd-ports)
examplebsd-artwork
# from upstream, unchanged
firefox
```

`firefox` is an upstream package: it comes from FreeBSD's repository
exactly as FreeBSD builds it, so it does not go in `ours.list`. Pick any
other upstream application the same way; `pkg search <name>` on the
build host shows what upstream has.

To change more of the greeter than the background and the user image,
edit the same `lightdm-gtk-greeter.conf` in the overlay. The settings it
accepts are in the sample configuration the `lightdm-gtk-greeter`
package installs (`pkg info -l lightdm-gtk-greeter` shows where). Any
file the settings name goes in your artwork package, not in the
overlay.

Run the template's own tests, which include the leak check, then commit
your changes in both forks. Run git and the tests as the user who owns
the clones, not as root: git refuses a repository owned by another user
("detected dubious ownership"). In the product repository (`examplebsd`):

```sh
sh tests/run-tests.sh
git add overlay/profiles/desktop/packages.list
git commit -m "desktop: add examplebsd-artwork and firefox"
```

In the ports repository (`examplebsd-ports`), keep `out/` and
`published.txt` out of git: they are generated by the build. The ports template has no `.gitignore`, so
make one first:

```sh
cd ../examplebsd-ports
printf 'out/\npublished.txt\n' > .gitignore
git add ours.list examplebsd-artwork tests/ours-check.sh .gitignore
git commit -m "add examplebsd-artwork, ours.list, the self-hosted check and .gitignore"
cd ../examplebsd
```

## 6. Build the media

```sh
./build.sh -c product.conf -n -p desktop       # read the plan: your two packages are in step [4]
./build.sh -c product.conf -p desktop          # the real build, as root
```

The output is `out/desktop/examplebsd-desktop-amd64.img` (a raw disk
image), `out/desktop/examplebsd-desktop-amd64.iso` (the installer) and
`out/SHA256`. Recompute a checksum with `sha256 -r FILE` and compare it
with the line in `out/SHA256`.

A build that finishes in seconds built nothing: check that both files
exist and have a sensible size. At the time of writing the `.img` is
about 13 GB and the `.iso` about 10 GB. For the full list of what
`build.sh` does, see [Stage 4](04-build-media.md#freebsd-16).

## 7. Boot it and see the change

**Automated, serial console only.** The template's boot test starts the
raw image in bhyve and waits for `login:` on the serial console. With
the reference provider it runs bhyve(8) directly, so run it as root on
a host that can run bhyve, prepared as the template README says ("The
reference provider"):

```sh
sh tests/boot-test.sh out/desktop/examplebsd-desktop-amd64.img desktop
```

It proves the image boots. It does **not** look at the screen: for the
desktop profile there is no greeter screenshot check in the template
yet (see [Stage 5](05-ci.md)).

**By eye, in a VM with a display.** The template has no command that
starts a graphical VM yet, so use your VM software:

1. Make a VM with UEFI firmware, 4 GB of memory or more, an empty disk
   and the ISO as its CD.
2. Boot it. Root is locked, so the ISO starts `examplebsd-install` on the
   console by itself. It asks, in this order: a user name, one SSH
   public key line (it is required), a password and the password again
   (you need it to log in at the greeter), then the disk from a menu:
   pick the empty one, and type `yes` to confirm. If the VM has a serial
   port, the installer runs there: follow it in your VM software's serial
   console (or `cu`/`screen` on the host); the display shows
   only boot messages.
3. When it asks, remove the ISO and reboot from the disk.
4. The LightDM greeter shows **your wallpaper** as its background and
   **your logo** as the user picture.
5. Log in. Xfce starts, and **Firefox** is in the applications menu.

On a VM without a GPU driver the system uses the plain framebuffer
driver (scfb) with GLX turned off; the greeter and Xfce work the same.

What you will not see yet: the Xfce desktop background after login is
still Xfce's default. The template sets the greeter's background, not the
desktop's; a system-wide Xfce default is a file you would add to the
overlay or to the artwork package, and this page does not cover it.

## What you did, and what comes next

You made a product from unmodified FreeBSD plus three layers of your
own: an overlay setting (the greeter configuration the template already
had), a package of your own with a reason in `ours.list`, and an upstream
application in a package list. That is the whole model; the stages make
each part solid:

- [Stage 2](02-overlays-and-profiles.md): more overlay files, and when a
  file belongs in a package instead.
- [Stage 3](03-packages.md) and [3b](03b-packages-per-os.md): a signed
  product repository on HTTPS in place of the unsigned local one, its
  client file and public key in the overlay, and the self-hosted check
  in CI.
- [Stage 4](04-build-media.md): building against upstream plus your
  repository with `pkg -R`, and the firmware coverage gate.
- [Stage 5](05-ci.md): Jenkins builds and boots every change, with the
  installer and greeter checks the templates do not have yet.
- [Stage 6](06-release-and-publish.md) and [7](07-operations.md):
  releases, signed checksums, and keeping it current.
