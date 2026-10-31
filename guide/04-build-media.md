<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Stage 4: build the media

[Index](README.md) · Previous: [Stage 3b](03b-packages-per-os.md) · Next: [Stage 5: CI](05-ci.md)

Each template has one `build.sh`. It reads `product.conf` (it parses the
file, it never sources it), builds or unpacks the unmodified upstream base
system, applies your overlay, installs your package lists, and writes
images plus an `out/SHA256` file.

This stage comes after [Stage 3](03-packages.md) because the package
step installs from upstream **and** your product repository: the media
can only carry your packages once they are built and published.

Always start with a dry run. It validates the configuration, prints every
command the real build would run, and changes nothing. It works on any
POSIX host, including Linux and macOS:

```sh
./build.sh -c product.conf -n
./build.sh -c product.conf -n -p both
```

## Build hosts

**FreeBSD 16**

- Where the real build must run: a FreeBSD host (or VM) with the matching `/usr/src`
- Root needed: yes (`chown`, `pw -R`, `pkg -r`)

**NetBSD 11.0**

- Where the real build must run: the base and the image: any POSIX host (`src/build.sh` cross-builds its own tools). The package step (`pkg_add`): NetBSD only; elsewhere `build.sh` refuses it, or skips it with `WTFBSD_NO_PACKAGES=yes`
- Root needed: no: owners and modes go into the METALOG spec

**OpenBSD 8.0**

- Where the real build must run: the site set: a FreeBSD or Linux host (bsdtar or GNU tar set the owners without root). The media step: OpenBSD. The base system is upstream's stock install sets; building base yourself needs OpenBSD (`release(8)`), there is no cross build
- Root needed: site set: no (on OpenBSD itself it must run as root); media step: root, through one `doas` rule

**DragonFly 6.4.2**

- Where the real build must run: DragonFly itself; there is no cross build
- Root needed: yes

Use a throwaway VM per build when you can (see [Stage 5](05-ci.md)). Build
amd64 on amd64 and aarch64 on aarch64; cross-architecture package installs
are possible on FreeBSD (`PKG_ABI`) but not the recommended path.

## FreeBSD 16

Needs an unmodified FreeBSD source tree for the release you ship (default
`/usr/src`, or `-s DIR`).

```sh
./build.sh -c product.conf                       # PROFILE from product.conf
./build.sh -c product.conf -p both -o ./out
./build.sh -c product.conf -u ci -k ./ci.pub     # bake a CI first-boot user
KERNCONF=GENERIC ROOTSIZE=12g JOBS=8 ./build.sh -c product.conf
```

What it runs, in order (all visible in the dry run):

1. `make buildworld` and `make buildkernel` with `SRCCONF=overlay/base/src.conf`.
2. `installworld`, `installkernel`, `distribution` into a stage directory.
3. Copies `overlay/base/rootfs` then `overlay/profiles/<p>/rootfs`,
   substitutes placeholders, renames `@SLUG@` paths, sets owners to root.
4. Wires the root filesystem (ZFS or UFS), locks root with
   `pw -R <stage> lock root`, and touches the `/firstboot` sentinel.
5. `pkg -r <stage> install -y <base list> <profile list>`.
6. Builds a GPT raw image with `makefs` and `mkimg` (UEFI and BIOS boot).
7. Adds the raw image, xz-compressed, to the stage as
   `/usr/local/share/<slug>/install/system.img.xz` and builds an ISO with
   the stock `src/release/<arch>/mkisoimages.sh`. The ISO starts
   `<slug>-install` on the console.
8. Writes `out/SHA256` with `sha256 -r`.

Output: `out/<profile>/<slug>-<profile>-<arch>.img`, `.iso`, and
`out/SHA256`.

Step 5 uses the package repositories configured **on the build host**.
To build against exactly the repositories your users get (upstream plus
your own), point pkg at a directory holding those repository files with
the global `-R` option, for example
`pkg -R ./repos.d -r <stage> install ...`. `-R` replaces the
`REPOS_DIR` search path (pkg(8), pkg 2.8), so the directory must hold
the upstream repository file as well as yours. The templates do not do
this yet, so it is a change you make in your fork's `build.sh`.

## NetBSD 11.0

Needs an unmodified NetBSD source tree (only `src/build.sh` has to exist;
`-s DIR` to point at it) and `PKG_PATH` pointing at a pkgsrc **binary**
repository for your architecture (upstream's is shown below). pkgsrc
calls amd64 `x86_64`; the build refuses a repository path whose
`NetBSD/<arch>/` part names the wrong architecture. Installing the
packages needs a NetBSD build host (see the table above).

```sh
PKG_PATH=https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/x86_64/11.0/All \
    ./build.sh -c product.conf -p both
```

What it runs:

1. `src/build.sh -U -m <machine> -O <obj> -T <tools> tools release` (the
   release sets).
2. Unpacks the sets into a stage. On the desktop profile the X sets are
   skipped: X11 comes from pkgsrc, so there is exactly one X11.
3. Copies the overlay, substitutes placeholders, writes owners and modes
   into the image spec (built from the upstream METALOG, so setuid bits
   and `/tmp` modes stay as upstream made them).
4. `pkg_add -P <stage>` for the package lists, with `PKG_RCD_SCRIPTS=YES`
   so package rc.d scripts land in `/etc/rc.d`.
5. A GPT image: EFI partition with the release's `bootx64.efi`, FFS root
   with `nbinstallboot`. Labels `<slug>esp` and `<slug>root`.
6. `out/SHA256`.

Output: `out/<profile>/<slug>-<profile>-<arch>.img` and `out/SHA256`. The
NetBSD template builds a raw image, not an ISO. Root on NetBSD is always
FFS; ZFS is a data pool only, created by hand with `<slug>-pool-create`.

## OpenBSD 8.0

OpenBSD has a built-in mechanism for this: the **site set**. Your overlay
becomes `site80.tgz`; the installer unpacks it over the new root and runs
`/install.site` in a chroot (`install.site(5)`). An `autoinstall(8)`
response file makes the install unattended.

```sh
./build.sh -c product.conf -n
./build.sh -c product.conf -r 8.0 -u operator -k operator.pub
./build.sh -c product.conf -r 8.0 -p both -u operator -k operator.pub -P operator.hash
```

`-u` and `-k` (the operator account and its SSH key) are required: root
is locked. `-P` (a bcrypt hash) is required for the desktop profile.

Output: `out/site80.tgz` and `out/install.conf` (for `-p both`, one
directory per profile) plus `SHA256`. The CI **Media** stage then puts
them on a copy of the stock install image with `ci/media.sh prepare
RELEASE ARCH`, run as root through a single `doas.conf` rule on an
installed copy of the script. See the template README, "The media stage".

`install.site` installs the package list with `pkg_add`, one package at a
time, writes any failures to `/etc/<slug>-pkg-failed`, warns in the motd
and exits non-zero, so a missing package is never silent.

The site set is not covered by OpenBSD's `SHA256.sig`, so the installer
asks whether to continue without verification; the response file answers
it. The exact question wording is release-specific: check it against the
installer of the release you ship.

## DragonFly 6.4.2

Builds on DragonFly, as root, with an unmodified source tree (with
`nrelease/`) and a DPorts tree (`DPORTS_PATH`, default `/usr/dports`).

```sh
DPORTS_PATH=/usr/dports ./build.sh -c product.conf -p both -u ci -k ./ci.pub
./build.sh -c product.conf --no-user           # an image nobody can log in to
```

What it runs: the stock `make -C /usr/src/nrelease release` with
`ROOTSKELS` (the upstream root skeleton, the GUI skeleton for the
desktop, then your staged overlay, in that order) and
`DPORTS_EXTRA_PACKAGES` (your package origins); then
`tools/post-customize.sh` in the release root (rc.conf merge, serial
getty, locking uid 0 accounts, mirroring `/etc` into `/etc.hdd`, the
first-boot sentinel); then `make mkiso mkimg`. The world is built once
for all profiles.

Output: `out/<profile>/<slug>-<profile>-<arch>.iso` (or `.img`),
`out/<profile>/ARTIFACT` (the path of the media), `out/SHA256`.

Package lists hold DPorts **origins** (`x11/xorg`), because `nrelease`
builds them from the DPorts tree with `dsynth`. If you would rather take
upstream binary packages, `nrelease` has a `binpkgs` modifier that takes
bare package names; the template does not use it. Check
`/usr/src/nrelease/Makefile` on your release.

## Firmware: every device, prefetched, verified, local

Rule: **nothing fetches firmware at install time or on first boot.** A
machine whose Wi-Fi needs firmware cannot download that firmware over
Wi-Fi. Everything a supported device needs is inside the image when it is
built, and the installer only copies what is on the media.

How to get there, per OS:

**FreeBSD**

- Where firmware comes from: packages. `drm-kmod` depends on the `gpu-firmware-kmod` meta-package (all GPU firmware); `wifi-firmware-kmod` is the meta-package for Wi-Fi firmware. `fwget(8)` installs firmware for the devices of the machine it runs on and needs the network
- How to put all of it in the image: list the meta-packages in the desktop `packages.list` (the template's desktop list already carries `drm-kmod`); do not rely on `fwget` on the target

**NetBSD**

- Where firmware comes from: mostly the base sets (`/libdata/firmware`); a few drivers need pkgsrc packages
- How to put all of it in the image: unpack all base sets the drivers need; add any pkgsrc firmware to `packages.list`. Check each driver's man page

**OpenBSD**

- Where firmware comes from: not in base; `fw_update(8)` fetches signed firmware packages, normally from the network after install
- How to put all of it in the image: download the firmware packages at build time, check them against OpenBSD's signed `SHA256.sig` with `signify -C`, carry them with their `SHA256.sig` in the site set, and have `install.site` run `fw_update -p <that directory> -a`, which checks `SHA256.sig` against `/etc/signify/openbsd-80-fw.pub` and each file's checksum. Do not pass the `.tgz` files as arguments: `fw_update` does not verify files named on the command line. The installer also adds `fw_update` to `/etc/rc.firsttime`, a network fetch on first boot: remove that line in `install.site`

**DragonFly**

- Where firmware comes from: mostly kernel modules in the base system; anything from DPorts goes in `packages.list`
- How to put all of it in the image: check the driver man pages; add DPorts firmware packages by origin

Verification: upstream package repositories are signed (`pkg` checks the
repository signature and each package checksum; OpenBSD packages and
firmware are signed with `signify`). Fetch only through the signed
repository, never from an unsigned mirror or a loose download.

### The firmware coverage gate

Add a gate to your build, after the package step and before the image is
made. None of the templates has it yet. It should:

1. List what the drivers in the image can ask for (on FreeBSD, the
   firmware modules the DRM and Wi-Fi drivers load; elsewhere, the files
   named in the driver man pages for the hardware you support).
2. List what the image actually contains (installed firmware packages and
   files).
3. Fail the build on any gap that is not in a checked-in allowlist, where
   every allowlist line has a reason ("no redistributable firmware",
   "driver not supported on this profile").
4. Write the list of firmware packages and versions next to the image, so
   the release notes can say what is covered.

Exempt the appliance profile only if it truly supports no Wi-Fi or GPU
hardware. A gate with an empty input must fail, not pass.

### Drivers

The desktop profile should carry every X driver and input driver upstream
packages, not just the one your machine needs: the media will meet
hardware you never tested. The FreeBSD and DragonFly desktop lists on
the templates' main branch do this (Xorg video drivers for amdgpu, ati,
intel, nv, ast, mga, vesa, scfb and dummy, plus qxl and vmware on
FreeBSD; libinput, evdev and other input drivers; on FreeBSD also
`drm-kmod` and the NVIDIA driver packages). The NetBSD and OpenBSD
desktop lists are short: extend them. Choosing a driver at boot is the system's job; shipping it is
yours.

Keep known-bad drivers off by name in your overlay (for example a
`_load="NO"` loader line or a module blocklist), and say so in the release
notes and the installer, rather than shipping a driver that hangs a
machine.

## Lessons that cost a release

- **`pkg install` can exit 0 with nothing installed** when no name
  matches. After the package step, check that the packages are really
  there (`pkg -r <stage> info <name>` for each listed name).
- **Do not trust a fast build.** A media step that "succeeds" in a few
  seconds produced nothing. Count the artifacts you expected.
- **Release builds are not always re-runnable.** `mkimg` refuses to
  overwrite; stale marker files make `make` skip steps. Start each
  release build from an empty output directory.
- **Never bake build-host facts into the image**: no host names, no
  `/home` paths, no hardware probes of the build machine. Run `strings`
  over the kernel, modules and media and grep for your hosts.
- **Record the inputs.** Every image should carry a manifest of the
  upstream release, the template commit, the overlay commit and the
  package versions it was built from.
- **Build from a clean tree.** Refuse to build from a working tree with
  uncommitted changes; a module once shipped from edits nobody committed.
- **Packaging memory, not cores, limits parallelism.** Large `pkg create`
  runs in parallel can be killed silently for lack of memory. Size the
  job count to memory.

## Check that it worked

- `out/SHA256` exists, and recomputing each file's checksum (`sha256 -r
  FILE` on FreeBSD, `sha256 FILE` on NetBSD, `sha256sum FILE` elsewhere)
  gives the same value.
- Every expected file is there: one image (and ISO, where the template
  makes one) per profile.
- The firmware gate passed and wrote its list.
- The image boots in a VM to a login prompt: `sh tests/boot-test.sh
  out/appliance/examplebsd-appliance-amd64.img appliance` (see
  [Stage 5](05-ci.md)).
