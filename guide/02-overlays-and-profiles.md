<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Stage 2: overlays on unmodified upstream, and profiles

[Index](README.md) · Previous: [Stage 1](01-fork-and-name.md) · Next: [Stage 3: build media](03-build-media.md)

Your distribution is **the upstream system plus layers of your own
files and packages**. You never patch the upstream source tree, and you
never patch the ports tree (FreeBSD ports, pkgsrc, OpenBSD ports, DPorts).
Everything that makes ExampleBSD different is one of:

1. a file copied over the staged root (an **overlay**);
2. a package installed into the staged root (upstream's, or one of yours);
3. a supported build knob (on FreeBSD, `WITHOUT_` options in `src.conf`).

Why this matters: upstream security fixes and new releases arrive as
upstream builds them. You rebuild; you do not re-merge. The moment you
carry a patch to `src/`, every upstream release becomes a merge project.

## The layers

Every template has the same three layers:

```
overlay/
├── base/                    common to every image you build
│   ├── packages.list
│   └── rootfs/              copied over / first
└── profiles/
    ├── appliance/           headless
    │   ├── packages.list
    │   └── rootfs/          copied over / after base
    └── desktop/             X11 desktop
        ├── packages.list
        └── rootfs/
```

`build.sh` copies `overlay/base/rootfs/` first, then the profile's
`rootfs/` on top, so a profile file replaces a base file of the same path.
Package lists add up: base list plus profile list.

### Stacking more than one product

When you make a second product (say a server and a desktop from the same
base), do not copy the first product's overlay. Split it:

```
baseline overlay   reusable mechanisms every product wants
                   (repository config, CA bundle, first-boot logic, hardening)
   + product overlay   only what makes this product different
                       (branding, package deltas, product-only services)
```

Rules that came from getting this wrong:

- The order is fixed: upstream, then baseline, then product, then packages.
  The product layer only adds or replaces; it never has to undo a baseline
  file.
- When a second product needs something the first already has, move it
  down into the baseline in one change, and delete it from the first
  product in the same change. Two copies drift.
- The baseline must build and boot on its own. If it only works with one
  product on top, it is not a baseline.
- Product identity comes from the overlay and the media, not from a
  separate copy of upstream packages.

## Per-OS overlay rules

The same idea works everywhere, but each system reads configuration in its
own way. These are the rules the templates already enforce.

| | FreeBSD 16 | NetBSD 11.0 | OpenBSD 8.0 | DragonFly 6.4.2 |
|---|---|---|---|---|
| How the overlay reaches the system | copied into the staged root before `makefs`/`mkimg` | copied into the stage; owners and modes written into the METALOG spec for `nbmakefs -F` | packed as a **site set** (`site80.tgz`) that the installer unpacks; `/install.site` runs in a chroot | staged as `ROOTSKELS` for `nrelease`, then `tools/post-customize.sh` |
| Service settings | `/etc/rc.conf.d/<service>` (named after the service) | `/etc/rc.conf.d/<service>`, `name=YES` (no `_enable`) | one `/etc/rc.conf.local`; profiles append a fragment; `daemon_flags=` / `pkg_scripts` | `rc.conf` variables merged by the post-customize step |
| Package prefix | `/usr/local` | `/usr/pkg` | `/usr/local` | `/usr/local` |
| Package list holds | package names | pkgsrc package names | package names (installed by `install.site` with `pkg_add`) | DPorts **origins** (`category/port`) |
| Build knobs | `overlay/base/src.conf` as `SRCCONF` | none in the template | none | none |

Two traps worth knowing:

- An `rc.conf.d` fragment must be named after the **service** it
  configures. `rc(8)` reads `/etc/rc.conf.d/<service-name>`; a file named
  after your distribution is never read.
- DragonFly's release tooling snapshots `/etc` into `/etc.hdd` before the
  overlay is applied, and the installer copies `/etc.hdd` to the disk. The
  template's post-customize step mirrors your `/etc` files into `/etc.hdd`
  so they reach the installed system. Keep that step if you change the
  build.

## Profiles

| Profile | What it is |
|---------|------------|
| `appliance` | Headless. Serial console, `sshd` with keys only (`PermitRootLogin no`, `PasswordAuthentication no`), no extra packages. |
| `desktop` | X11 only: Xorg, Xfce and a display manager (LightDM on FreeBSD, NetBSD and DragonFly; `xenodm` on OpenBSD). `sshd` is off by default. |

`PROFILE=both` builds two images from one build. Add your own profile by
adding `overlay/profiles/<name>/` and teaching `build.sh` and the
`Jenkinsfile` the new name; keep `desktop` and `appliance` working, since
the tests use them.

## Root, users and the first boot

Every template ships with **root locked** and no default password. The
first account is made on the first boot, from a small `KEY=value` file
that the `firstboot_user` rc script parses (never sources):

```
USERNAME=alice
SSH_KEY=ssh-ed25519 AAAA... alice@example.org
PASSWORD_HASH=$6$...        # optional; crypt(3) $6$ or $2b$
WHEEL=yes
```

| | Config file | How the script runs once |
|---|---|---|
| FreeBSD | `/boot/firstboot-user.conf` | rc KEYWORD `firstboot` plus the `/firstboot` sentinel |
| NetBSD | `/etc/firstboot-user.conf` | the `/var/db/firstboot_user` sentinel |
| DragonFly | `/boot/firstboot-user.conf` | the config file is the guard; the `/firstboot` sentinel is removed when done |
| OpenBSD | not used: the installer creates the operator from `install.conf` (`-u`, `-k`, `-P` to `build.sh`) | n/a |

For CI images, bake a throwaway user with `./build.sh -c product.conf -u
ciuser -k ./ci.pub` (FreeBSD, NetBSD, DragonFly; NetBSD also takes `-H`
for a password hash file, DragonFly `-P`). For real installs, the
installer writes the same file from the user's answers. After the run the
file is renamed to `*.done` with mode 0600, because it may hold a password
hash.

## Branding

Keep artwork out of the template repository. Put it in a package of your
own (for example `examplebsd-artwork`) that installs to
`/usr/local/share/examplebsd/artwork/`, and point the configuration at
that path (the FreeBSD desktop profile's `branding.conf` documents the
contract). A package can be updated without rebuilding media; a file in
the overlay cannot.

## Configuration through packages, not copied files

An overlay file is frozen into the image. A file delivered by a package
can be fixed later with `pkg upgrade` / `pkg_add -u`. Use the overlay for
what must exist before the network is up (repository configuration,
keys, first-boot logic, rc settings). Use your own packages for
everything you expect to change (artwork, default desktop settings,
helper scripts). See [Stage 4](04-packages.md) for keeping those packages
few and small.

## Check that it worked

- `./build.sh -c product.conf -n -p both` shows the base `rootfs` copied
  before the profile `rootfs`, and lists the packages you expect.
- `tests/run-tests.sh` passes. It includes a leak check that refuses
  private addresses, e-mail addresses and the like in the tree.
- `git diff` against the template shows changes only under `overlay/`,
  `product.conf` and files you added. Nothing under an upstream tree.
