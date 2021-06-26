# emanote

[![AGPL](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://en.wikipedia.org/wiki/Affero_General_Public_License)
[![built with nix](https://img.shields.io/badge/Built_With-Nix-5277C3.svg?logo=nixos&labelColor=73C3D5)](https://builtwithnix.org)
[![FAIR](https://img.shields.io/badge/FAIR-pledge-blue)](https://www.fairforall.org/about/)
[![Matrix](https://img.shields.io/matrix/neuron:matrix.org)](https://app.element.io/#/room/#neuron:matrix.org "Chat on Matrix")
[![Liberapay](https://img.shields.io/liberapay/patrons/srid.svg?logo=liberapay)](https://liberapay.com/srid/donate "Donate using liberapay")

WIP: Spiritual successor to [neuron](https://neuron.zettel.page), based on [Ema](https://ema.srid.ca).

Create beautiful websites -- such as personal webpage, blog, wiki, Zettelkasten, notebook, knowledge-base, documentation, etc. from future-proof plain-text notes and arbitrary data -- with live preview that updates in real-time.

**Project Status**: Partially implemented enough to be usable for *certain* use-cases (see examples below). HTML templates are yet to be finalized (so do not customize your templates just yet), and most importantly folgezettel graph and visualization needs to be implemented to act as true neuron replacement (see tasks below).

## Installing NixOS

```bash
# Install Nix
curl -L https://nixos.org/nix/install | sh

# Enable cache (optionalish)
nix-env -iA cachix -f https://cachix.org/api/v1/install
cachix use srid
```

## Installing NixOS on MacOS

```bash
# Starting in macOS 10.15 (Catalina) the root filesystem is read-only. It will need an unencrypted APFS volume created to house the NixOS install
sh <(curl -L https://nixos.org/nix/install) --darwin-use-unencrypted-nix-store-volume
```
There are alternative [install](https://nixos.org/manual/nix/stable/#sect-macos-installation) methods but the unencrypted APFS volume is the most straight forward.


## Installing and using Emanote

```bash
# Install Emanote
nix-env -if https://github.com/srid/emanote/archive/refs/heads/master.tar.gz
# Or, from the Git repo: nix-env -if ./default.nix

# Run live server (PORT is optional and below is an example)
mkdir ~/notebook && cd ~/notebook
PORT=8001 emanote -C ~/notebook

# Generate static files
mkdir /tmp/output
emanote -C /path/to/notebook gen /tmp/output
```
