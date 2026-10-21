---
sidebar_position: 21
---
# TLS Truststore

Pantavisor loads a set of root CA certificates for its HTTPS connections to
Pantahub. This layer ships them in the `ca-certificates-pv` package: a subset
of the Mozilla root bundle from the regular `ca-certificates` recipe, kept
small on purpose.

:::note
Not every request checks the server against these roots yet. Requests made
through libthttp (device registration, log upload, the first-boot object
upload) do. The newer
client used for most Pantahub API calls and object downloads loads the
certificates but does not check the server certificate.
:::

:::note
This truststore is only for TLS connections. It is separate from
`/etc/pantavisor/pvs/trust/`, which holds the keys used to check signatures on
revisions and containers.
:::

## Where it lands on the device

The certificates are installed as flat PEM files in `/etc/thttp/certs`
(`PV_LIBTHTTP_CERTSDIR`, set in `pantavisor.config`). Pantavisor reads every
file in that directory, so it must stay flat: no subdirectories, no hash
symlinks and no bundle file next to the single certificates.

On a device:

```
ls /etc/thttp/certs
```

When Pantavisor starts a Pantahub request it logs how many it loaded:

```
Found 20 http x509 certs in truststore: /etc/thttp/certs.
```

## What is in the default set

`ca-certificates-pv` keeps the roots listed in `CA_CERTIFICATES_PV`
(`recipes-pv/ca-certificates-pv/ca-certificates-pv.bb`): ISRG (Let's Encrypt),
Google Trust Services, Amazon, DigiCert, USERTrust and Sectigo, GlobalSign and
Go Daddy. It is built by copying the whole Mozilla directory and deleting every
certificate that is not in the list.

The build stops with a message if a listed root:

- is not in the Mozilla bundle any more,
- has expired, or
- uses a key type Pantavisor's mbedtls cannot read (anything other than RSA
  and EC P-256, P-384 or P-521). One such file would make every request fail.

## Add or remove a root

Names are the file names in the Mozilla directory, without `.crt`. To see
them, list the directory in the `ca-certificates-native` build:

```
ls build/tmp-scarthgap/sysroots-components/x86_64/ca-certificates-native/usr/share/ca-certificates/mozilla/
```

Add a root from `local.conf` or a distro include:

```
CA_CERTIFICATES_PV:append = " DigiCert_Trusted_Root_G4"
```

To use your own list, assign it instead (a plain `=` wins over the recipe
default):

```
CA_CERTIFICATES_PV = "ISRG_Root_X1 ISRG_Root_X2"
```

Rebuild the package and the image:

```
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml --target ca-certificates-pv
```

If you ship a rootfs manifest reference (see [Manifest Audit](manifest-audit.md)),
update the `/etc/thttp/certs/` lines in it; the audit reports them as drift.

## Use a different package

The package Pantavisor depends on is chosen by
`VIRTUAL-RUNTIME_pantavisor_certs`. Any package that fills `/etc/thttp/certs`
works. To go back to the two ISRG files shipped by libthttp:

```
VIRTUAL-RUNTIME_pantavisor_certs = "libthttp-certs"
```

## When ca-certificates is updated

A new `ca-certificates` release can add roots. To make sure none is missed
silently, the roots this package leaves out are listed in
`recipes-pv/ca-certificates-pv/files/excluded-certs.txt`. If the bundle and that
file differ, the build fails and lists the names:

```
ERROR: ca-certificates-pv-1.0-r0 do_compile: ca-certificates-pv: the roots in the Mozilla bundle changed since excluded-certs.txt was last reviewed.

New in the bundle (not in CA_CERTIFICATES_PV, not yet reviewed):
    Foo_Root_CA

What to do (run from the directory you start kas in):
  1. Look at each new root and decide whether Pantavisor devices need it.
  2. To ship it: add its name to CA_CERTIFICATES_PV in recipes-pv/ca-certificates-pv/ca-certificates-pv.bb (or your distro/BSP conf).
     If you ship some new roots and leave out others, add the shipped ones to CA_CERTIFICATES_PV first, rebuild, then do step 3 for the rest.
  3. To leave it out: cp build/tmp-scarthgap/work/all-poky-linux/ca-certificates-pv/1.0/build/excluded-certs.txt recipes-pv/ca-certificates-pv/files/excluded-certs.txt
  4. Commit the change and rebuild. Details: docs/overview/truststore.md
```

Review the new names, then do one of:

- Ship a root: add it to `CA_CERTIFICATES_PV`. Nothing else changes, because a
  root that was never in `excluded-certs.txt` is still absent from the
  left-out set.
- Leave a root out: run the `cp` command from the message (from the directory
  you start kas in) and commit the file.

If you ship some new roots and leave out others, add the shipped ones first,
rebuild, then run the `cp` for the rest.

Copying is also needed when a name that is already in `excluded-certs.txt`
leaves the left-out set, either because you moved it into `CA_CERTIFICATES_PV`
or because Mozilla dropped it. The message then says "Nothing to decide" and
shows the `cp` command to accept the change.

A BSP or distro layer that changes `CA_CERTIFICATES_PV` changes the left-out set
too. It ships its own `excluded-certs.txt` with a `ca-certificates-pv.bbappend`:

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
```

The error then names the file from your layer as the one to overwrite.

To skip only this check (for example while experimenting), set the following;
the build prints a warning:

```
CA_CERTIFICATES_PV_CHECK_EXCLUDED = "0"
```
