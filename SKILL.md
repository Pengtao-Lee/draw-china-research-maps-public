---
name: draw-china-research-maps
description: Create reproducible, publication-ready thematic maps of China from regional research data in R, using GeoJSON.CN 1.6.x GCJ-02 boundaries with mandatory WGS-84 conversion, administrative-code reconciliation, versioned GeoJSON boundaries, an Albers equal-area projection, Taiwan/Hong Kong/Macau coverage, a ggspatial grid-north arrow, and a lower-left South China Sea inset labeled 南海诸岛 in Chinese figures or Nanhai Zhudao in English figures with the current ten-segment line. Use for Chinese province- or prefecture/city-level choropleths, maps comparing years or changes, fixing stretched China maps, auditing historical-to-current geographic codes, or standardizing China-map scripts and metadata for economics research. Styling county lines requires prepared county polygons.
---

# Draw China Research Maps

Produce China research maps whose data joins, boundary vintages, projection, maritime inset, and output metadata can be defended and reproduced. Keep raw research data immutable and perform every transformation in a saved R script before execution.

## Current scope

The workflow reads user-supplied GeoJSON.CN 1.6.x files, converts GCJ-02 coordinates to WGS-84, and covers province-level and prefecture/city-level maps. Use local data the user is authorized to use and share only under the data provider's terms. Apply the local-boundary styling rules to county polygons that the caller already supplies in a reconciled, projected form.

## Resource routing

1. Run the independent environment gate before boundary work:

   ```text
   Rscript scripts/check_map_dependencies.R
   ```

   Stop if it reports a failure. It checks R, `jsonlite`, `ggplot2`, `ggspatial`, `sf`, `ragg`, Cairo PDF support, `pdffonts`, and `pdftoppm`.
2. Read [`references/map-standard.md`](references/map-standard.md) before preparing boundary inputs, reconciling geographic codes, changing the projection, constructing the national outline, placing the South China Sea inset, or exporting Chinese-language PDF figures. That file is the single detailed source for boundary provenance, layout, and export checks.
3. Source [`scripts/china_map_helpers.R`](scripts/china_map_helpers.R) from the project-local plotting script. It provides GeoJSON parsing, GCJ-02→WGS-84 conversion, Albers projection, border and coastline styling, inset geometry and layout, and the legend divider.

Keep complete data preparation and plotting in a saved project-local `.R` script, then run it with `Rscript`. Do not rely on undocumented interactive state.

## Required workflow

1. Inspect the research table without altering it. Identify the geographic code, time, outcome, weight, and unit of observation. Preserve geographic codes as zero-padded character strings.
2. Run the dependency gate and record the boundary provider, version, release date, source CRS, source URLs, access date, and raw-file hashes. Pass the user's local unmodified `100000.json` to `ten_segment_line()` to extract the `十段线` feature. For city-level inputs, use the local files described in `references/map-standard.md`.
3. Build an explicit source-code-to-map-code crosswalk. Distinguish historical administrative changes from map-only reductions. Never overwrite the analytical geographic identifier.
4. Audit the join before plotting. Export analytical code, mapped code, match status, mapping reason, and boundary name. Stop if an expected code is unmatched or duplicated.
5. Aggregate only when multiple analytical regions map to one current polygon. Use a substantively valid weight and document it. Do not average rates without weights unless equal weighting is the estimand.
6. Preserve raw GCJ-02 longitude and latitude fields, convert every boundary vertex to WGS-84 before projection or spatial operations, and verify the forward round-trip residual.
7. Use the Albers projection, national outer outline, polygon-ring grouping, South China Sea inset, grid-north arrow, scale bar, figure-language convention, and PDF font checks specified in `references/map-standard.md`. Clip the inset at the Tropic of Cancer and align the top frame edge with the highest projected vertex. Pad the left, right, and bottom edges equally. Draw the maritime paths within the existing main-map frame. Use a bordered header the width of the inset with the inset's top frame edge as the shared divider. Place the 500 km scale bar to the right of the inset place label, with its label close above the bar. Inspect the borders on the exported map. Use SimSun (宋体) for Chinese text and Times New Roman for English, Latin, and numeric segments.
8. Draw shared provincial borders as solid white lines with a dark vector shadow clipped to land, regardless of the adjacent fill colors. Draw each shared city or county edge once, as a thin unshadowed black or white line chosen from the adjacent fill colors. Use a framed right-side legend with a title divider and follow the alignment and spacing rules in `references/map-standard.md`. Hold scales, labels, and layout fixed across comparable maps. Use a diverging palette centered at zero for changes.
9. Save PNG at an effective resolution of at least 600 dpi at the intended manuscript size, vector PDF, `map_code_coverage.csv`, and `map_metadata.csv`. Apply the 600 dpi minimum to rasterized content in every output format. Export each figure and comparison panel without a figure title, subtitle, or caption. Inspect every figure at its final manuscript size.

## City-level boundary input

For a city-level map, load the authorized local six-digit province-code GeoJSON.CN file and keep the matching `_meta.json` for provenance as described in [`map-standard.md`](references/map-standard.md#boundary-provenance-and-city-input). Guangdong's source file is:

```text
https://geojson.cn/api/china/1.6.3/440000.json
```

It returned HTTP 200 and 21 city features on 2026-08-13. Preserve the untouched response in a versioned raw-boundary directory. Use the helper's default `map_code_width = 6L` so codes such as `440300` remain six digits. Set `map_code_width = 4L` only when a documented analytical crosswalk intentionally uses a four-digit prefix.

The GeoJSON.CN county endpoint is outside the bundled workflow. County line styling is available for prepared county geometries through the shared local-boundary helpers.

## Non-negotiable checks

- Require one row per analytical unit-period before aggregation and zero unexpected unmatched analytical codes.
- Report analytical-unit counts and displayed-boundary counts separately.
- Preserve polygon parts, rings, and vertex order; never connect separate islands or polygon parts.
- Restrict current boundary input to GeoJSON.CN 1.6.x GCJ-02 and convert it to WGS-84 before projection, union, overlay, distance calculation, or plotting. Do not silently mix another source CRS.
- Derive the national outline from dissolved exterior rings. Use matching dark strokes and one-sided lilac casing for the land border and the maritime ten-segment line in each panel. Place casing outside the land footprint and on the seaward side of the maritime line. Use a thin blue stroke for the coastline.
- Verify the scale bars, label-above-bar placement, grid-north arrow, inset alignment, Taiwan coverage, mixed-font assignments, and Chinese PDF font embedding according to `map-standard.md`.
- Treat the map as descriptive evidence. Do not infer causal effects from spatial color patterns.

## Delivery

Report the source coordinate system (`GCJ-02`), target coordinate system (`WGS-84`), conversion method and tolerance, boundary vintage, projection parameters, both scale-bar lengths/units/label positions, north-arrow method/label/position, CJK and Latin font families, crosswalk reductions, coverage rate, inset extent/margins/alignment rule, and output paths. In the delivery message, remind the user to add their own figure title and caption in the manuscript. Provide panel order, missing-value meaning, or aggregation details outside the image as needed for the caption.
