# the site

`site/` is the only source. `docs/` is generated from it and committed:

```sh
node site/build.mjs     # write docs/
sh site/deploy.sh       # publish docs/ to ai-nerv.com
```

ai-nerv.com is served by GitHub Pages from
[ai-nerv/ai-nerv.github.io](https://github.com/ai-nerv/ai-nerv.github.io), because GitHub will not
turn Pages off on an organisation's `<org>.github.io` repository, and a custom domain can belong to
only one repository. That repository holds nothing but what `deploy.sh` puts there: a build of this
directory, replaced wholesale, one commit naming the source it came from. Nothing there is edited by
hand. `docs/CNAME` holds the domain and `docs/.nojekyll` stops Jekyll touching anything.

## why a generator

Twenty pages that share a masthead, a sidebar and a footer. The navigation is the part that rots
when a site is kept by hand, and it is also the first thing a reader notices. One file decides the
shape of the whole thing.

## where the drawings come from

`docs/assets/` is the one part of `docs/` kept by hand rather than generated.

`docs/assets/diagram.js` is a small SVG renderer — boxes, diamonds, arrows, and lane diagrams for
the two things that are really sequences. `docs/assets/data.js` holds one spec per drawing, laid
out by hand: the positions are the design, not the output of a layout algorithm.

Each page draws only the plates it declared a container for, so every page can load every asset.

`docs/assets/units.js` is the crate graph data, read from the four repositories rather than drawn
by hand. When a crate is added, that file is what changes.
