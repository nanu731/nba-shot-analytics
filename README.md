# NSL Analytics

Narayan Lekhi's sports analytics portfolio. Each project starts with a sports
question and gives readers the data, method, interactive results, and analysis
code needed to examine it.

**[Visit the website](https://www.nslanalytics.com/)** ·
**[Explore NBA shot selection](https://www.nslanalytics.com/projects/nba-shot-selection-analytics/)** ·
**[Compare two players](https://www.nslanalytics.com/projects/nba-player-comparison/)**

This repository contains the website and its public presentation data. The R
models, source-data audits, and research live in
[nba-shot-analytics](https://github.com/nanu731/nba-shot-analytics).

## Available now

### NBA Shot Selection: Location Edition

How could a player's expected scoring change if some attempts moved toward
stronger supported areas of the court?

The explorer covers **2021–22 through 2025–26**, with a separate fitted model
for each season. It opens with LeBron James in 2025–26 and unchanged historical
shots. Choose a player and season, then request movement from 0% to 25% in 5%
steps. The display distinguishes the requested share from the amount the model
can achieve.

Three views show different parts of the same scenario:

| View | What you see |
| --- | --- |
| **Shot locations** | Recorded makes and misses at 0%; cyan hypothetical attempts and origin rings when shots move. |
| **Make-chance map** | Estimated shooting probability across court areas, with a fixed color scale and area inspection. |
| **Shot movement** | Aggregate attempts removed from areas and added to supported areas, using a shared bubble scale. These totals do not trace individual shot routes. |

Search accepts names with or without accents and punctuation, opens a scrollable
player list, and labels relocation evidence. A selected player persists across
seasons. If that player lacks an analysis, the page explains why and offers a
reset to LeBron and 2025–26.

Results include estimated extra points over the season, extra points per 100
attempts, a shot-selection score, and 90% model ranges. Contextual help links to
the Definitions, How the model works, and Formulas sections.

### Two-player comparison

The [comparison page](https://www.nslanalytics.com/projects/nba-player-comparison/)
places two players side by side on desktop and stacks them on mobile. Both use
one season, movement slider, and court-view selector. The first slot opens with
LeBron; the second waits for a selection. Duplicate selections are blocked.

Each player has current and relocated expected points per 100 attempts,
potential improvement, score, uncertainty, and evidence status. The comparison
uses each player's own historical shot mix; it does not rank overall talent,
name a winner, or calculate a head-to-head probability. Missing estimates stay
unavailable rather than becoming zero.

### Interpreting the estimates

The Location Edition uses a Bayesian spatial model that shares information
between neighboring court areas. Receiving areas need at least 10 attempts and
90% model probability of beating the player's current expected points per shot.
Each receiving area has a 50% final-volume cap. A single supported area can
produce an estimate when it has receiving capacity.

The score compares the historical mix with feasible movement at the fixed 25%
request. A higher score means less modeled room to improve that player's mix.
The 90% ranges describe uncertainty within the fitted model.

These are historical, hypothetical scenarios. The model holds shooting ability
fixed while attempts move and excludes defense, game situation, shot creation,
fatigue, and opponents' reactions. The estimates do not establish causal gains,
forecast real games, or supply coaching or betting advice. The project page
provides the full limitations and formulas.

## Data and repository boundaries

The website consumes the deterministic **v4** Location export under
`public/data/spatial-shot-selection/v4/`. It contains 1,507 analyzed
player-seasons across the five seasons, based on recorded NBA field-goal
attempts. Eligibility and relocation evidence are separate checks.

The browser loads the availability catalog, active-season index, and selected
player files as needed. Typing, changing court views, and moving the slider do
not download additional player files. Shot movement reuses the loaded payload;
comparison converts existing per-attempt summaries to per-100 units.

Research and data refreshes belong in the analytics repository. The website
renders its verified exports instead of fitting models. Historical files are
versioned snapshots, not a live NBA feed. Preserve unavailable values and export
contracts when integrating a new verified release.

## Direction and planned expansion

The Location Edition will remain available as its own project. **Context
Edition** will have a separate question, model, results, and website presentation:
does shot type and verified pre-shot situation improve expected scoring
prediction? Both research projects currently share the analytics repository.

Current priorities and conditional ideas, as of 13 October 2026:

- **UI and usability:** continue the Impeccable workflow and reader testing.
  The reviewed chart, search, comparison-layout, and unavailable-state repairs
  are already released. Physical-device and spoken screen-reader checks remain
  follow-up work.
- **Context research, paused:** the broad finish/creation model (M1) remains the
  selected baseline. Adding distance (M2) improved predictive log loss but failed
  the registered calibration gate. The game-context model (M3) is preregistered
  and unfitted; memory constraints stopped its training preflight. Analytics
  remains paused while UI work takes priority.
- **Further Location research:** sensitivity testing is complete in the
  analytics repository, with production defaults unchanged. Location-based
  archetype analysis is a possible later extension, not a current site feature.
- **Conditional Context extensions:** player-specific shot-family effects,
  verified field-goal/free-throw trip value, and historical volume limits need
  their own data and validation checks. Direct defense remains unavailable from
  the verified sources. Player-specific volume-efficiency curves are not
  supported by the current five-season evidence.

The research reserves 2026–27 for prospective confirmation. Planned work has no
promised release date. The [analytics repository](https://github.com/nanu731/nba-shot-analytics)
holds the research code and public methodological reports.

## Run locally

Use **Node.js 22.12.0 or newer** and npm. From the repository root:

```sh
npm ci
npm run dev -- --background
```

The development server normally opens at `http://localhost:4321`. Check or stop
the background server with `npm run astro -- dev status` and
`npm run astro -- dev stop`.

```sh
npm run build
npm run preview
```

The build writes static output to `dist/`. Preview serves that production build.
Fonts may require network access on the first build; visitors receive them from
the site's own origin.

Verify the public data contracts from the repository root:

```sh
node --experimental-strip-types scripts/verify-relocation-flow.mjs
node --experimental-strip-types scripts/verify-player-comparison.mjs
```

The flag supports the helpers' TypeScript imports on Node 22. These checks cover
payload integrity, movement totals, fractional attempts,
per-100 conversions, null handling, and comparison-loader behavior. They do not
replace browser checks or the analytics repository's statistical validation.
Saved browser checks and their review evidence are documented in
[UI refinement verification](docs/ui-refinement-verification.md).

## Stack and project guide

- **Astro 7**, static output, MDX project pages, Markdown blog posts, sitemap,
  and blog RSS.
- **Plain CSS** and browser JavaScript/TypeScript for interaction; SVG courts
  and versioned JSON power the NBA tools.
- **Fraunces, Source Serif 4, and IBM Plex Mono**, served from the site, with
  cream/green/rust/cyan chart and interface colors.
- **Vercel** at `www.nslanalytics.com`; the apex redirects to www. The site also
  serves through [Netlify](https://nlekhi.netlify.app/).

| Location | Purpose |
| --- | --- |
| `src/content/projects/` | Project write-ups and frontmatter. |
| `src/content/blog/` | Dated writing; the collection currently has no published posts. |
| `src/pages/` | Site routes, including the comparison page. |
| `src/components/`, `src/lib/` | Shared interface components and browser helpers. |
| `src/styles/global.css` | Shared color, spacing, and typography tokens. |
| `public/data/`, `public/plots/` | Public exports and static plot assets. |
| `scripts/` | Data-contract and browser verification helpers. |

The shared CSS tokens define the visual system. The
[UI verification record](docs/ui-refinement-verification.md) documents the
released refinements and remaining checks. The unlinked `/styleguide/` is a
design reference, excluded from the sitemap; it is not access-controlled.

Project frontmatter must follow `src/content.config.ts`. Set `draft: true` for
work that should appear in development but stay out of production. Publish
verified findings and explicit limitations; use TODO markers for missing author
content instead of inventing results or biography.

## Hosting and maintenance

The existing hosting connections deploy `main` using `npm run build` and
`dist/`. Review feature branches before release; a push to production can
trigger both hosts. `astro.config.mjs` defines the canonical www address.
`vercel.json` and `netlify.toml` contain the host security headers; Astro adds
per-page script/style hashes during the build.

Keep verified data and factual results intact during interface work. Run checks
appropriate to the change and inspect browser behavior when controls, charts,
or security policies change. The [security checklist](docs/security-checklist.md)
distinguishes released browser protections from account settings that still need
review. Keep credentials, environment files, private analytics artifacts, and
local tooling state out of Git and published output.

## Licence and credits

Site content and writing are © Narayan Lekhi. Fraunces uses the SIL Open Font
License; see [OFL.txt](src/assets/fonts/OFL.txt). This repository does not declare
a blanket open-source licence for the website or its analytical data.
