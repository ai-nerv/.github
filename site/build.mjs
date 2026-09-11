// Builds docs/ from the page sources beside this file.
//
// A generator rather than twenty hand-kept copies of the same shell: the navigation is the thing
// that rots when a site is written by hand, and it is also the thing a reader notices first.
// Run it with `node site/build.mjs`; the output is committed, so GitHub Pages needs no build step.

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { SECTIONS, PAGES } from "./content.mjs";

const OUT = "docs";

/** Where a page sits, relative to another page. */
function href(from, to) {
  const up = relative(dirname(from || "index.html"), dirname(to)) || ".";
  const path = `${up}/${to.split("/").pop()}`.replace(/^\.\//, "");
  return path === "index.html" && dirname(from) === dirname(to) ? "index.html" : path;
}

/** The path back to the site root from a page. */
function root(at) {
  const depth = at.split("/").length - 1;
  return depth === 0 ? "." : "..".concat("/..".repeat(depth - 1));
}

/** The top bar, with the current section marked. */
function topbar(page) {
  const r = root(page.at);
  const links = SECTIONS.map((s) => {
    const here = s.key === page.section ? " aria-current=\"page\"" : "";
    return `<a href="${r}/${s.home}"${here}>${s.name}</a>`;
  }).join("\n        ");
  return `  <header class="top">
    <div class="bar">
      <a class="brand" href="${r}/index.html" aria-label="nerv, home">
        <img class="mark" src="${r}/assets/logo/nerv.svg" alt="" width="30" height="30">
        <span><b>nerv</b><i>ネルフ</i></span>
      </a>
      <nav>
        ${links}
      </nav>
      <div class="ghost">
        <a href="https://github.com/ai-nerv">github</a>
      </div>
    </div>
  </header>`;
}

/** The section's own page list. */
function sidebar(page) {
  const section = SECTIONS.find((s) => s.key === page.section);
  if (!section || section.key === "home") return "";
  const mine = PAGES.filter((p) => p.section === page.section);
  const items = mine
    .map((p) => {
      const here = p.at === page.at ? " aria-current=\"page\"" : "";
      return `      <li><a href="${href(page.at, p.at)}"${here}>${p.nav}</a></li>`;
    })
    .join("\n");
  return `  <aside>
    <h5><span class="en">${section.name}</span><span class="jp">${section.jp ?? ""}</span></h5>
    <ul>
${items}
    </ul>
  </aside>`;
}

/** Previous and next, within a section. */
function walk(page) {
  const mine = PAGES.filter((p) => p.section === page.section);
  const i = mine.findIndex((p) => p.at === page.at);
  const back = i > 0 ? mine[i - 1] : null;
  const on = i >= 0 && i < mine.length - 1 ? mine[i + 1] : null;
  if (!back && !on) return "";
  const left = back
    ? `<a href="${href(page.at, back.at)}"><span class="lbl">back</span>${back.nav}</a>`
    : "<span></span>";
  const right = on
    ? `<a href="${href(page.at, on.at)}"><span class="lbl">next</span>${on.nav}</a>`
    : "<span></span>";
  return `      <div class="next">${left}${right}</div>`;
}

function html(page) {
  const r = root(page.at);
  const aside = sidebar(page);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${page.title} — nerv</title>
<meta name="description" content="${page.blurb}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Anton&family=Barlow+Condensed:wght@500;600;700&family=IBM+Plex+Mono:wght@400;500;600&family=Noto+Sans+JP:wght@400;700&display=swap">
<link rel="stylesheet" href="${r}/assets/style.css">
</head>
<body>
${topbar(page)}
  <div class="wrap${aside ? "" : " wide"}">
${aside}
    <main>
${page.logo
        ? `      <div class="hero">
        <img src="${r}/assets/logo/${page.logo}.svg" alt="the ${page.logo} mark" width="96" height="96">
        <div class="who"><h1>${page.title}</h1></div>
      </div>
      <p class="lede">${page.blurb}</p>`
        : `      <h1>${page.title}</h1>
      <p class="lede">${page.blurb}</p>`}
${page.body}
${walk(page)}
    </main>
  </div>
  <footer class="foot">
    <div class="in">
      <span class="jp">人類補完計画</span>
      <span>magi · casper · melchior · balthasar</span>
      <span>four repositories, no shared code</span>
      <a href="https://github.com/ai-nerv/magi">magi</a>
      <a href="https://github.com/ai-nerv/casper">casper</a>
      <a href="https://github.com/ai-nerv/melchior">melchior</a>
      <a href="https://github.com/ai-nerv/balthasar">balthasar</a>
    </div>
  </footer>
<script src="${r}/assets/diagram.js"></script>
<script src="${r}/assets/data.js"></script>
<script src="${r}/assets/units.js"></script>
</body>
</html>
`;
}

let written = 0;
for (const page of PAGES) {
  const path = join(OUT, page.at);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, html(page));
  written += 1;
}
// A sitemap and a robots.txt, because this is a real site on a real domain.
const DOMAIN = "https://ai-nerv.com";
const urls = PAGES.map(
  (p) => `  <url><loc>${DOMAIN}/${p.at}</loc></url>`,
).join("\n");
writeFileSync(
  join(OUT, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`,
);
writeFileSync(join(OUT, "robots.txt"), `User-agent: *\nAllow: /\nSitemap: ${DOMAIN}/sitemap.xml\n`);

// GitHub Pages serves this for anything that is not there.
writeFileSync(
  join(OUT, "404.html"),
  html({
    at: "404.html",
    section: "home",
    title: "Not here",
    blurb: "That page does not exist. The map is a good place to start again.",
    body: `      <ul class="plain">
        <li><a href="index.html">the overview</a> — what the four programs are</li>
        <li><a href="architecture/index.html">the map</a> — how they connect</li>
        <li><a href="guides/install.html">install</a> — get the binaries</li>
        <li><a href="reference/wire.html">the wire</a> — enough to write a peer</li>
      </ul>`,
  }),
);

console.log(`${written} pages, a sitemap and a 404 written to ${OUT}/`);
