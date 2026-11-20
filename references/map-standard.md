# China research map standard

This reference contains the detailed boundary, geometry, layout, audit, and export rules for `$draw-china-research-maps`. Read it from the main skill when a task reaches the corresponding stage.

## Contents

- [Boundary provenance and city input](#boundary-provenance-and-city-input)
- [National outer outline](#national-outer-outline)
- [Geography reconciliation](#geography-reconciliation)
- [Projection and coordinate conversion](#projection-and-coordinate-conversion)
- [Chinese text and PDF validation](#chinese-text-and-pdf-validation)
- [North-arrow construction](#north-arrow-construction)
- [Scale-bar and inset layout](#scale-bar-and-inset-layout)
- [Figure-language convention](#figure-language-convention)
- [Polygon construction](#polygon-construction)
- [Comparative maps](#comparative-maps)
- [Figure titles and captions](#figure-titles-and-captions)
- [Reproducible outputs](#reproducible-outputs)

## Boundary provenance and city input

- Tested provider: GeoJSON.CN atlas, `https://geojson.cn/data/atlas/china`.
- Tested release: version 1.6.3, boundary date 2025-12-14, reported source coordinate system GCJ-02.
- The data-processing workflow covers provinces and prefecture/city units. Use the local-boundary styling helpers when county polygons are already available.
- Treat every current GeoJSON.CN 1.6.x API geometry as GCJ-02. Preserve raw coordinates and convert them to WGS-84 before projection, polygon union, overlay, distance calculation, or plotting.
- Include the 31 mainland province-level files plus `710000`, `810000`, and `820000` for Taiwan, Hong Kong, and Macau when producing the national map.
- Store the authorized, untouched inputs outside the skill repository under a versioned directory such as `map_raw/geojson_cn_v1.6.3/`.
- Record the actual version, boundary date, URL, access date, response hash, and source CRS; do not silently refresh a cached raw boundary during replication.

The API pattern is:

```text
https://geojson.cn/api/china/{version}/{files}.json
```

For a city-level map, use the six-digit province-code file, not a direct city-code URL:

```text
https://geojson.cn/api/china/{version}/{province_code}.json
```

The matching file list is:

```text
https://geojson.cn/api/china/{version}/_meta.json
```

The verified Guangdong example is `https://geojson.cn/api/china/1.6.3/440000.json`. It returned HTTP 200 on 2026-08-13 and contained 21 city features, including code `440300` for Shenzhen. Verify that a downloaded response is a non-empty GeoJSON `FeatureCollection`, that each feature has `Polygon` or `MultiPolygon` geometry, and that each `properties$code` is a six-digit code.

Obtain the versioned files under the provider's terms. Read the local province-code file for city boundaries:

```r
raw_dir <- file.path("map_raw", "geojson_cn_v1.6.3")
city_geometry <- read_china_geojson(
  file.path(raw_dir, "440000.json"),
  source_code = "440000",
  map_code_width = 6L
)
```

Keep six-digit city codes by default. Set `map_code_width = 4L` only when the analytical table intentionally uses a four-digit city prefix, and document that reduction in the crosswalk. Do not mutate the analytical identifier.

The documented county-level path is `https://geojson.cn/api/china/{version}/{province_code}/{city_code}.json`. The anonymous test of `440000/440300.json` returned HTTP 403 (`无数据访问权限`). County downloads and geographic reconciliation are outside the bundled workflow. The local-border styling helpers accept prepared county polygons.

## National outer outline

The `100000.json` endpoint is a `FeatureCollection` containing coded province-level features, not one top-level national polygon. Use it as the authoritative source collection, but do not draw the collection directly in near-black because that would also draw province internal boundaries.

The response also embeds the maritime ten-segment line as one `MultiLineString` feature named `十段线` (`fullname` `中国南海十段线`; feature 35 of the verified 1.6.3 response). `read_china_geojson()` only accepts `Polygon`/`MultiPolygon` geometry, so it cannot parse the raw response as a whole: select the polygon features first (for example `features[vapply(features, function(f) f$geometry$type %in% c("Polygon", "MultiPolygon"), logical(1))]`) and save them to a cleaned file before parsing. Keep the ten-segment feature's coordinates from the same pinned response; they supply the maritime line in both panels.

1. Use a local, authorized copy of the unmodified `100000.json` and record its version, release date, source CRS, and access date.
2. Select the polygon features required for the map and preserve polygon parts, rings, vertex order, and raw GCJ-02 coordinates.
3. Convert every source vertex to WGS-84 with the documented iterative inverse before spatial union.
4. Union the converted coded geometries, decompose the result into polygon parts, and save each dissolved polygon's `exterior` ring as a separate `outline_id`. Do not include `interior` rings in the near-black outline layer.
5. Use `china_boundary_lines()` to split the largest exterior ring at the two coastal ends of the land border. Locate the cuts on the projected outline using the QGIS template anchors (108.03°E, 21.56°N and 124.18°E, 39.84°N). The longer mainland arc is the land border. Use the other arc and the island exteriors as coastline.
6. Draw two concentric lilac strokes (`#C6C8E0`, `#AAA6C8`) under the land fill along the land border. Draw the dark land-border stroke above the fill, and a thinner blue stroke (`#069AC5`) along the coastline. Use separate paths for disconnected exteriors. In the inset, clip the classified paths to the geographic window before projection so the window edges have no coastline stroke.

Record `national_outline_source_url`, `national_outline_source_file`, the union method, CRS conversion, exterior ring filter, and the land-border and coastline styles in metadata. Inspect both transitions at the coast and verify that the lilac casing follows the land border.

Read the ten-segment line from the same local national file used for the province polygons. The helper finds the `十段线` feature, validates its ten line parts, preserves their source coordinates, and returns coordinates converted to WGS-84 and projected for both panels.

```r
national_path <- file.path("map_raw", "geojson_cn_v1.6.3", "100000.json")
line <- ten_segment_line(national_path, source_coordinate_system = "GCJ-02")
```

Use `china_border_strokes()` for the land border and `china_maritime_border_strokes()` for the maritime line, with the same width factor within each panel. Follow the QGIS convention of orienting the maritime marks using the inland reference point at 114°E, 14.5°N. Draw the two lilac bands on the opposite, seaward side only, matching the visible widths of the land-border bands. Preserve each segment as a separate path and inspect its separation after export. In Chinese-language figures, label the inset `南海诸岛` and describe it as `南海诸岛（十段线）`. In English-language figures, use `Nanhai Zhudao` and `Nanhai Zhudao (ten-segment line)`.

## Geography reconciliation

Maintain three separate fields:

- `analytical_code`: stable code defining the observation used in analysis;
- `map_code`: current polygon used only for display;
- `mapping_reason`: direct match, one-to-one change, many-to-one merger, or unresolved.

Never mutate `analytical_code` to make a join succeed. For a many-to-one display reduction, calculate the displayed outcome from component numerators and denominators when possible. Otherwise use the correct exposure or population weight and disclose it.

Before plotting, export a coverage table and assert:

1. The analytical table is unique at its stated unit and period.
2. Every expected analytical code has exactly one mapping decision.
3. Every mapped code exists in the pinned boundary files.
4. Unexpected unmatched codes equal zero.
5. Counts of analytical units and displayed polygons are both reported.

## Projection and coordinate conversion

Use a spherical Albers equal-area projection for the mainland:

```text
central meridian 105°E
latitude of origin 0°
standard parallels 25°N and 47°N
```

Use a separate Albers projection for the South China Sea inset:

```text
central meridian 115°E
latitude of origin 0°
standard parallels 7°N and 20°N
```

The separate projection and extent prevent low-latitude maritime geometry from making the mainland look abnormally wide and flat. After projecting, use equal x/y scale with `coord_fixed(ratio = 1)`.

GCJ-02 is not handled by simply assigning `EPSG:4326`. Before any Albers projection or spatial operation, apply the deterministic iterative inverse of the standard WGS-84-to-GCJ-02 forward formula supplied in `scripts/china_map_helpers.R`. Use the tested stopping tolerance `1e-7` degrees and maximum iteration count `20`. Verify the result by applying the forward formula and checking the GCJ-02 round-trip residual. Record source CRS (`GCJ-02`), target CRS (`WGS-84`), method, tolerance, iteration limit, and conversion scope in `map_metadata.csv`.

Do not use `sf::st_transform(..., "EPSG:4326")` as a substitute for the inverse. Do not union GCJ-02 polygons and then mix the result with unconverted WGS-84 geometry; convert all source vertices under the same rule first. Stop when a source boundary is declared in another CRS.

For the main extent, begin with longitude 73–135°E and latitude 17–54°N, then pad projected limits. Keep the existing main-map extent when drawing the ten-segment line. Pass the projected paths and their segment IDs to `china_maritime_border_strokes()`, and let the main panel clip paths at its borders. Use the separate inset projection for the southern view.

## Chinese text and PDF validation

Use two explicit font families and do not let the graphics device choose a fallback:

```r
figure_cjk_font <- "SimSun"          # 宋体; required for Chinese text on Windows
figure_latin_font <- "Times New Roman" # English, Latin letters, and numbers
```

Use SimSun for Chinese labels such as `南海诸岛`. Use Times New Roman for English labels, numeric legend ticks, and scale text such as `500 km` and `1,000 km`. Use explicit font runs where a label needs both families. If SimSun is missing on Windows, install or register it before rendering. Document any fallback on other platforms.

Export vector PDF figures with `grDevices::cairo_pdf(fallback_resolution = 600)` or a higher fallback resolution. Inspect the font table with `pdffonts` and require embedded entries for the families used. Render the PDF with `pdftoppm` and check the printed characters and layout. Record the font families and export device in map metadata.

## North-arrow construction

Place a compact `ggspatial::annotation_north_arrow()` on every main map panel with `which_north = "grid"` and `location = "tl"`. Grid north is the vertical upward direction of the rendered plotting region; do not calculate a local true-north vector or use a custom projected arrow. Use a built-in `ggspatial` style, set its font and colors explicitly, and keep it away from the legend, scale bar, and South China Sea inset.

Use the required grid-north form:

```r
ggspatial::annotation_north_arrow(
  which_north = "grid", location = "tl",
  height = grid::unit(0.72, "cm"), width = grid::unit(0.72, "cm"),
  pad_x = grid::unit(0.15, "cm"), pad_y = grid::unit(0.15, "cm"),
  style = ggspatial::north_arrow_orienteering(...)
)
```

The built-in style labels the arrow `N`. Record the layer, `grid` orientation, style, label, `tl` location, dimensions, and padding in map metadata. Verify that the arrow is visible, not clipped, and does not cover important geometry.

## Scale-bar and inset layout

Use `ggspatial::annotation_scale()` for the main-map scale bar. Use projected distances and label the bar in kilometres with a rounded length that is a multiple of 5. Hide the built-in side label and center its replacement just above the bar. Use a physical offset so the visible gap stays small in single and multi-panel exports. For the 1,000 km reference bar:

```r
bar_height <- grid::unit(0.25, "cm")
scale_bar_layer <- ggspatial::annotation_scale(
  plot_unit = "m", location = "bl", width_hint = 0.20, height = bar_height,
  pad_x = grid::unit(scale_bar_x_pad_fraction, "npc"),
  pad_y = grid::unit(scale_bar_y_pad_fraction, "npc"),
  text_col = "transparent",
  text_family = figure_latin_font
)

scale_label_layer <- ggplot2::annotation_custom(
  grid::textGrob(
    "1,000 km",
    x = grid::unit(scale_bar_x_pad_fraction + 500000 / diff(main_x_range), "npc"),
    y = grid::unit(scale_bar_y_pad_fraction, "npc") + bar_height + grid::unit(3.5, "pt"),
    just = c("centre", "bottom"),
    gp = grid::gpar(fontfamily = figure_latin_font, fontsize = 11.5, col = "#222222")
  )
)
```

Place the scale bar to the right of the South China Sea inset. Derive horizontal padding from the inset's right edge plus a small gap and vertical padding from the inset's bottom edge so their bottom edges align. Use the actual projected main panel x-range for `main_x_range`. Check on export that the label matches the drawn scale length and sits close above the bar. Record the label position and gap, scale length, units, and padding in metadata.

### South China Sea inset

Use the WGS-84 window 105–127°E and 2°N–23°26′N, with the northern edge on the Tropic of Cancer. Clip polygons and maritime paths to that window before projecting. Insert intersection vertices where paths and rings cross the window edge. The inset shows every portion of the source line inside the window. Use `south_sea_inset_geometry()` and `south_sea_inset_line()` for clipping.

Fit the panel to the projected polygon and maritime vertices. For comparable maps, pool their geometries and use one panel extent. `south_sea_panel_limits()` aligns the top frame edge with the highest projected vertex and pads the left, right, and bottom edges by 2.5% of the shorter projected span by default. Keep `coord_fixed(expand = FALSE)` so the panel uses those limits directly.

Draw one outer frame around the map panel and its 23 pt header, with a single horizontal divider at their shared edge. Use the same solid stroke for the frame and divider. Place the 12 pt inset place label on the left and a 500 km scale bar on the right. Center the 11.5 pt Times New Roman scale label above the bar with a 2 pt offset in grid coordinates. Allow enough width for the label and bar as a unit. The scale bar occupies `500000 / diff(inset_limits$x)` of the panel width, so it scales with the inset. Set `南海诸岛` in SimSun with 1 pt of added spacing between characters. Use the Latin font for `Nanhai Zhudao`.

For the bottom-left layout, use `south_sea_inset_box()` for the initial width and bottom edge, and align the left edge to the westernmost projected main-map vertex retained by the main extent. Set the box height using the **inset** projected height-to-width ratio when the main map uses an equal x/y scale. Draw the borderless inset first and overlay `south_sea_header()` in the same data-coordinate box. Give the inset plot zero outer margin so the box and frame coincide. Keep the inset frame clear of the main map's land-border casing.

```r
# Clip the WGS-84 geometries, then use the resulting inset projection.
inset_geo <- south_sea_inset_geometry(main_geo)
inset_line <- south_sea_inset_line(line)
# Build inset_map with inset_geo polygons and the styled inset_line paths grouped by path_id.
# For comparable maps, supply pooled inset geometry to the limits helper.
inset_limits <- south_sea_panel_limits(inset_geo, inset_line)

inset_map <- inset_map +
  ggplot2::coord_fixed(xlim = inset_limits$x, ylim = inset_limits$y, expand = FALSE) +
  ggplot2::theme(
    panel.background = ggplot2::element_rect(fill = "white", colour = NA),
    panel.border = ggplot2::element_blank(),
    legend.position = "none",
    plot.margin = grid::unit(rep(0, 4), "pt")
  )

box <- south_sea_inset_box(main_limits$x, main_limits$y)
width <- box$xmax - box$xmin
main_keep <- with(main_geo, longitude >= 73 & longitude <= 135 &
                  latitude >= 17 & latitude <= 54)
box$xmin <- min(main_geo$main_x[main_keep])
box$xmax <- box$xmin + width
box$ymax <- box$ymin + width * diff(inset_limits$y) / diff(inset_limits$x)

main_map <- main_map +
  ggplot2::annotation_custom(
    ggplot2::ggplotGrob(inset_map),
    xmin = box$xmin, xmax = box$xmax, ymin = box$ymin, ymax = box$ymax
  ) +
  ggplot2::annotation_custom(
    south_sea_header("南海诸岛", inset_limits$x, "SimSun"),
    xmin = box$xmin, xmax = box$xmax, ymin = box$ymin, ymax = box$ymax
  )
```

Keep the separate 1,000 km main-map bar to the right of the inset. Compute its padding from the inset edges and the actual main panel ranges from `ggplot_build()`, so the main bar and inset frame can share a bottom alignment.

Inspect the borders in PNG and rendered PDF. Verify that the top frame edge touches the northern cut, the left, right, and bottom edges clear the geometry, and the header uses a single shared divider across the full inset width. Check that the visible maritime paths, place label, and scale bar fit at the smallest output size. Record the geographic window, projected limits, geometric padding, scale lengths, header placement, label spacing, and number of inset segments in map metadata.

## Figure-language convention

Choose the figure language before plotting and apply it consistently to map labels, legends, and delivery notes. For Chinese-language figures, use exactly `南海诸岛`; for English-language figures, use exactly `Nanhai Zhudao`. Do not use Chinese characters in an otherwise English figure. Keep the ten-segment maritime-line description consistent with the selected language.

## Polygon construction

GeoJSON `Polygon` and `MultiPolygon` features contain polygon parts and rings. Preserve `polygon_id`, `ring_id`, and vertex order. In `ggplot2::geom_polygon`, map `group` to polygon part and `subgroup` to ring, then set `rule = "evenodd"`. This avoids connecting separate islands and preserves holes.

Build polygon features in projected metres with `admin_polygon_features()`. For provincial strokes, use `province_internal_edges()` to reconcile small seams between adjoining source polygons. The reference map uses a tolerance of 0.02% of the projected panel width. Draw a solid white province stroke over the dark, southeast-offset shadow from `province_shadow_bands()`, regardless of the adjacent fill. The translucent vector bands are clipped to the original dissolved land. Keep exterior and maritime lines in their own layers.

For city or county polygons, build local linework with `admin_shared_edges()`. Calculate each area's displayed color from the same fill scale used for the map, including the missing-data color. Pass the colors indexed by map code to `admin_edge_colours()`. It chooses black or white to maximize contrast on the weaker side of each shared edge. Draw the resulting stroke once as a thin solid line without a shadow, then overlay the province styling. Apply the same rule in the South China Sea inset when the relevant edges are visible.

## Comparative maps

- Use identical class breaks and palette semantics across level maps from different years.
- Use a diverging scale centered at zero for changes.
- Show missing or excluded units in neutral gray and explain the gray category.
- Keep legend position, page dimensions, and inset position identical across panels.
- Size the thematic legend's color bar, title, and tick labels together. In the reference layout, use 13 pt for the title and 11.5 pt for tick labels. Draw the gradient as vector rectangles. Enclose the entire legend in a solid frame with the same color and stroke width as the South China Sea inset. Set a 10 pt bottom margin on the legend title and use `add_right_colorbar_divider()` on the assembled ggplot2 or patchwork gtable. It draws a full-width line midway through the title margin using the frame's stroke.
- In the reference layout, align the right-side legend's left edge with the projected horizontal midpoint of the northernmost segment of the ten-segment line. Convert that x-coordinate to a fraction of the main panel and left-justify the inside legend at that anchor. Share the legend across comparison maps by displaying it in the right-hand panel. Trim excess whitespace on both sides while retaining the full legend and a gap to the map.
- Keep scale-bar position, length, units, label-above-bar placement, and styling identical across panels.
- Keep the grid-north-arrow location, label, size, padding, style, and orientation identical across panels.
- Keep source/target coordinate systems, conversion method, tolerance, and converted geometry fields identical across panels.
- Derive bins before joining to polygon vertices so each polygon has one stable class.

## Figure titles and captions

Do not render a figure title, subtitle, caption, source note, or explanatory footnote anywhere in an exported figure. This applies to individual panels and combined maps in all formats. Keep map labels, north arrows, scale labels, and the legend within the figure. Verify the exported image and remind the user in the delivery message to add their own figure title and caption in the manuscript. Provide panel order and missing-value or aggregation details in the delivery message when they will help the user write the caption.

## Reproducible outputs

Export each standalone map and each combined comparison in all three formats with matching basenames and physical dimensions. Include a combined comparison figure when multiple years or outcomes are shown.

- PNG at an effective resolution of at least 600 dpi at the intended manuscript size.
- Vector PDF with embedded fonts.
- Vector SVG exported directly from the plot with `svglite::svglite()`. Keep geometry as vector elements and text as text. Open the SVG in a browser or vector editor with the specified fonts installed and check the Chinese glyphs, scale labels, legend and inset placement.

Save the following audit files.

- `map_code_coverage.csv` with source and mapped codes, match status, and reason.
- `map_metadata.csv` with source URL, boundary version/date, source and target coordinate systems, conversion method/tolerance/iteration limit, projection parameters, main and inset scale-bar lengths/units/label positions/placement methods/padding, grid-north-arrow layer/style/label/position/size/padding, CJK font (`SimSun`), Latin font (`Times New Roman`), inset geographic filter, projected limits, geometry-to-frame padding, inset place label and scale placement, inset alignment rule, maritime-line source (`十段线` feature of the pinned `100000.json`), analytical-unit count, displayed-polygon count, and the export device for each format.

Apply the 600 dpi minimum to rasterized content in every output format, including raster layers embedded in PDF or SVG. For a full-image raster at width `width_mm`, render at least `ceiling(width_mm * 600 / 25.4)` pixels across. Use `ragg::agg_png(res = 600)` or a higher resolution and verify the saved pixel dimensions and resolution tag. Preserve vector paths and text in vector exports and verify embedded raster resolution if present. Confirm legibility at the intended manuscript size and record the raster resolution in metadata.

Check the PNG at the intended paper width. The reference checks use 85 mm and 120 mm for single maps and 180 mm for full-width maps, including comparisons. Measure final text size and inspect the legend, scale labels, inset place label, and fine administrative lines at that width. Revise the layout or font sizes if details are too small at final size.

Run only saved scripts. Keep source boundaries and raw research data separate from intermediate joins and output figures. Visually inspect the PNG, rendered PDF, and SVG for covered geography, clipped legends, a distorted aspect ratio, missing glyphs, and misplaced insets.
