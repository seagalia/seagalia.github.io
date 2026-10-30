# seagalia.github.io

The Seagalia website, served by GitHub Pages from `main`. It also hosts Flock.

Plain HTML and CSS, no build step. Open `index.html` in a browser, or serve the folder:

```sh
python3 -m http.server 8000
```

## Layout

- `index.html` — the page
- `assets/site.css` — styles; color tokens match `flock/webui/src/styles.scss`
- `assets/logos/` — logos copied from the `seagalia-brand` exports (`*-dark.svg` = for dark backgrounds)
- `assets/fonts/` — Titillium Web, self-hosted (SIL OFL 1.1)
- `scripts/coast.py` — draws the coast illustration and inlines it into the page: `python3 scripts/coast.py index.html`

## Install script

`install.sh` installs any product released with the shared goreleaser config, for the user's OS and arch:

```sh
curl -fsSL https://seagalia.io/install.sh | sh -s -- vigie          # latest release
curl -fsSL https://seagalia.io/install.sh | sh -s -- flock v0.3.1   # given release
```

It verifies the archive against `checksums.txt` and installs to `/usr/local/bin` when it is writable, to `~/.local/bin`
otherwise (`~/bin` on windows), so it never asks for a password by default. Set `INSTALL_DIR` to choose another
directory, `sudo` is used only if it is not writable.

Its banner is the Seagalia lockup drawn in braille, regenerated when the logo changes with
`python3 scripts/banner.py install.sh` (needs `rsvg-convert`).
