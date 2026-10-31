<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Stage 6: release and publish

[Index](README.md) · Previous: [Stage 5](05-ci.md) · Next: [Stage 7: operations](07-operations.md)

A release is a green CI run, published. You never rebuild for the release
and you never copy files by hand: you publish the artifacts of a build
that already passed, by its build number.

The order never changes: **build, boot test, installer test, prove the
product works, then publish.**

## 1. Name the artifacts

```
ExampleBSD-<version>-<profile>-<arch>-<build>.iso
ExampleBSD-<version>-<profile>-<arch>-<build>.img
```

Never publish a file called `...-latest.iso`. "Latest" is a pointer in
`latest.json` (below), not a file name: a file name that means different
bits on different days breaks every checksum anyone wrote down.

## 2. Checksums and signatures

The templates write `out/SHA256`. For a release, sign the checksum file,
so one signature covers every artifact. `signify(1)` (in OpenBSD base;
on FreeBSD the `signify` package) is small and simple:

```sh
signify -G -n -c "examplebsd release key" -p examplebsd-release.pub -s examplebsd-release.sec
signify -S -e -s examplebsd-release.sec -m SHA256 -x SHA256.sig
```

Users verify the files they downloaded with (the checksum list is embedded in
`SHA256.sig` by `-e` at signing time, so no `-m` is needed):

```sh
signify -C -p examplebsd-release.pub -x SHA256.sig examplebsd-desktop-amd64.img
```

Without file names, `signify -C` checks every file listed in the signature
and fails on any that is missing from the directory.

`signify -C` reads checksum lines in the BSD format
(`SHA256 (file) = hash`, the output of OpenBSD's `sha256(1)`), which is
also what `sha256 FILE` prints on FreeBSD. FreeBSD's `sha256 -r` (what
the FreeBSD template writes) and `sha256sum` print `hash file` instead;
produce the BSD format for the signed file. On other systems, check what
your `sha256` prints before you sign. OpenPGP detached signatures (`gpg --detach-sign`) work
too, if your users expect them.

The release signing key is not the package signing key. Keep both
private keys on the signing host only, and publish both public keys on
your site, in your overlay, and in the release notes.

## 3. latest.json: a machine-readable media index

One small JSON document tells your site, your installer and anyone's
scripts what the current media are. It describes media only; package
repositories have their own catalogues.

```json
{
  "schema_version": 1,
  "product": "ExampleBSD",
  "generated_at": "2026-10-31T12:00:00Z",
  "channel": "release",
  "status": "stable",
  "notice": "",
  "architectures": [
    {
      "arch": "amd64",
      "build_number": "142",
      "build_type": "release",
      "built_at": "2026-10-30T22:10:00Z",
      "published_at": "2026-10-31T12:00:00Z",
      "iso": {
        "kind": "iso",
        "format": "iso",
        "filename": "ExampleBSD-16.0-1-desktop-amd64-142.iso",
        "size_bytes": 2147483648,
        "sha256": "<64 hex digits>",
        "url": "https://download.example.org/16.0/ExampleBSD-16.0-1-desktop-amd64-142.iso",
        "sha256_url": "https://download.example.org/16.0/SHA256",
        "torrent_url": null
      },
      "artifacts": [
        { "kind": "iso", "format": "iso", "filename": "...", "size_bytes": 0, "sha256": "...",
          "url": "...", "sha256_url": "...", "torrent_url": null },
        { "kind": "vm", "format": "raw", "filename": "...", "size_bytes": 0, "sha256": "...",
          "url": "...", "sha256_url": "...", "torrent_url": null }
      ]
    }
  ]
}
```

Rules that keep it useful:

- **Generate it from the artifacts**, never by hand: sizes and checksums
  are read from the files of the build being published.
- **Pin the schema.** Write a JSON Schema for it, validate every new
  document against it, and bump `schema_version` when fields change.
  Readers ignore keys they do not know.
- **`iso` mirrors the primary ISO row of `artifacts`** exactly. A new kind
  of media is a new row in `artifacts`, not a new key.
- **`arch` uses one spelling** (`amd64`, `aarch64`), the same as in the
  file names.
- **Publish it last**, after the files it points at are reachable: write
  `latest.next.json`, check every URL returns the right length and
  checksum, then rename it to `latest.json`.
- **Republishing the same bits** changes only a timestamp, never the
  build number.

## 4. Release notes

Each release gets a short page with:

- the upstream release it is built on (FreeBSD 16.0, NetBSD 11.0,
  OpenBSD 8.0, DragonFly 6.4.2) and the template and overlay commits;
- the files, their sizes and SHA256, and how to verify them;
- what was tested (VMs, installer paths, real hardware by model) and what
  was not;
- the firmware coverage list and any known gaps from the gate's
  allowlist;
- known problems, including drivers you deliberately keep off;
- the package repository URL and its public key.

Say what it is and what it does. Do not promise "it just works". No
operator details in screenshots (addresses, network names, location
data).

## 5. Upload and announce

- Upload the media, `SHA256`, `SHA256.sig` and `latest.json` to any static
  HTTPS host (`https://download.example.org/`). Copy new files, verify
  them, and only then remove old ones; keep the previous release
  available.
- Check by content, not by status code: a web server that answers 200
  with an error page for a missing file passes a status check. Compare
  length and checksum.
- If you use the wtfbsd publish flow (`PUBLISH_METHOD`, `PUBLISH_TARGET`
  in `product.conf`), the publish step uploads the release metadata and
  `SHA256` with a token kept only as a Jenkins credential. See Phase 5 in
  wtfbsd/agents `AGENTS.md`, and check the target's own documentation for
  the endpoint.

## 6. Mirrors and torrents (optional)

- Mirrors are plain copies of the download tree. `latest.json` URLs can be
  relative, so a mirror works without editing it.
- Torrents suit large media. Never torrent package repositories or their
  catalogues; package clients do not speak BitTorrent, and a stale
  catalogue in a swarm is worse than none.

## 7. The project site

A static site is enough: what ExampleBSD is, download cards rendered
**from `latest.json`** (never hand-edited), the verification steps, the
public keys, the release notes, and where to report problems. Show the
build date of the media on the download page. Build the site in CI and
fail the site build if a download card names a file that is not
published.

## Check that it worked

- `signify -C -p examplebsd-release.pub -x SHA256.sig` passes on a fresh
  download of every file.
- `latest.json` validates against your schema, and every URL in it
  returns a file with the listed size and checksum.
- The site shows the new release, generated from `latest.json`.
