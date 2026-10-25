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
