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

`ios-shell/`, `frontend/src/native/`, `scripts/` and the rest of this build's own work are by
**Stanley Sujith Nelavala**.

### Licence of the new work: GPL-3.0-or-later, in addition to the AGPL

The repository as a whole is AGPL-3.0-or-later, and it has to be: it contains openGym's code,
which is AGPL-3.0-or-later and nothing else. Putting GPL-3.0 alone on the tree would be a
downgrade of their licence and is not done here.

What **is** done: the new work above is **additionally** offered under **GPL-3.0-or-later**, so
anyone may take those files under either licence. AGPL-3.0 section 13 exists for exactly this —
it explicitly permits combining this work with GPLv3 — which makes the dual offer lawful rather
than a contradiction.

In short:

| What | Licence |
|---|---|
| `frontend/`, `api/`, `catalogue/`, `mcp/`, `web/`, `scripts/` as they came from openGym | AGPL-3.0-or-later, © Duarte Santos |
| This build's new work, and the AGPL terms as a whole | AGPL-3.0-or-later |
| This build's new work, on its own | **also GPL-3.0-or-later** |
| The `catalogue/media` images | not ours to licence — see above |

`LICENSE` is the AGPL text with the appendix filled in. The GPL text is at
<https://www.gnu.org/licenses/gpl-3.0.txt>; nothing in this repository needs it to be valid.