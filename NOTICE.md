# Third-party notices

This file covers the notices that apply to the whole tree. openGym's own `NOTICE.md` is kept
verbatim as `NOTICE.upstream` — do not edit it here, it is theirs.

## openGym

openGym — Copyright (C) 2026 Duarte Santos.

Licensed under the **GNU Affero General Public License v3.0 or later** (see `LICENSE`). This
repository is a derivative work and is offered under the same licence, because it contains
openGym's own code (`frontend/`, `api/`, the design, and the web bundle the app ships).

## App store exception

As an additional permission under section 7 of the AGPL v3.0, the copyright holder of openGym
permits distribution of the openGym mobile application through app store platforms (such as the
Apple App Store and Google Play) whose terms of service would otherwise be incompatible with the
AGPL, provided the corresponding source code remains available under the AGPL at the project
repository. This permission applies to the distribution channel only and does not otherwise limit
the license.

This build is signed with a personal Apple ID and installed directly. No store is involved.

## Body diagram geometry

The muscle outlines the body maps are drawn from (`frontend/src/lib/body-paths.js`) are derived
from [MuscleMap](https://github.com/melihcolpan/MuscleMap) by Melih Colpan, used under the
**MIT License**, reproduced in full in `NOTICE.upstream`.

## Exercise media — NOT under the AGPL

The stills and animations in `catalogue/media/` are © Aliaksandr Makatserchyk, Gym visual,
[gymvisual.com](https://gymvisual.com). They are licensed to openGym, are **not** covered by the
AGPL, and are **not** in this git repository — `catalogue/media/` is gitignored and the directory
is populated only by cloning `upstream/` for a local build.

Their notice, quoted from `catalogue/media/NOTICE.md`:

> The stills (`still/`) and animations (`clip/`) in this folder are licensed to openGym by Gym
> visual and are not covered by openGym's AGPL. © Aliaksandr Makatserchyk, Gym visual,
> gymvisual.com (reuse is governed by Gym visual's Terms & Conditions; obtain your own license
> there before reusing the media). NOTICE TO DEVELOPERS: The exercise animations included in this
> project are provided strictly for use within the openGym application. Third parties have no
> rights to reuse, extract, or integrate these media assets into independent apps, websites, or
> commercial products.

Those stills are staged into the local `.ipa` by `scripts/build-web.sh` and stay on the phone.
They are the reason this repository is not published: see README.md, "Licence and scope".

## jsQR

`src/native/barcode-scanning.js` decodes check-in QR codes with **jsQR**, Apache-2.0
(<https://github.com/cozmo/jsQR>). It is already a dependency of openGym and is listed in their
`NOTICE.md`; this shell reuses it rather than adding one.

## xtool

This repository is built with [xtool](https://github.com/xtool-org/xtool), MIT licensed. xtool is a
build tool and contributes no code to the resulting app.

## This shell

`ios-shell/`, `frontend/src/native/` and `scripts/` are the work of **Stanley Sujith Nelavala**,
and are offered under the AGPL-3.0-or-later that governs the rest of this tree.