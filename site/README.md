# the site

`docs/` is generated. Edit `site/content.mjs`, then:

```sh
node site/build.mjs
```

The output is committed, so GitHub Pages needs no build step — Settings → Pages → deploy from
`main`, folder `/docs`. `docs/CNAME` holds the domain and `docs/.nojekyll` stops Jekyll touching
anything.

## why a generator

Twenty pages that share a masthead, a sidebar and a footer. The navigation is the part that rots
when a site is kept by hand, and it is also the first thing a reader notices. One file decides the
shape of the whole thing.

## where the drawings come from

`docs/assets/diagram.js` is a small SVG renderer — boxes, diamonds, arrows, and lane diagrams for
the two things that are really sequences. `docs/assets/data.js` holds one spec per drawing, laid
out by hand: the positions are the design, not the output of a layout algorithm.

Each page draws only the plates it declared a container for, so every page can load every asset.

`docs/assets/units.js` is the crate graph data, read from the four repositories rather than drawn
by hand. When a crate is added, that file is what changes.
