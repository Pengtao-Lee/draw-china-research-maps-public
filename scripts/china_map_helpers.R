# Reusable helpers for publication-ready China thematic maps.
# Dependencies: jsonlite; inset clipping uses sf.

as_admin_code <- function(value, width = 6L) {
  value <- as.character(value)
  numeric_code <- grepl("^[0-9]+$", value)
  value[numeric_code] <- sprintf(
    paste0("%0", width, "d"),
    as.integer(value[numeric_code])
  )
  value
}

extract_feature_coordinates <- function(
  feature,
  feature_index,
  source_code,
  map_code_width = 6L
) {
  code6 <- as_admin_code(feature$properties$code, 6L)
  map_code <- substr(code6, 1L, map_code_width)
  map_name <- if (!is.null(feature$properties$fullname)) {
    as.character(feature$properties$fullname)
  } else {
    as.character(feature$properties$name)
  }
  geometry_type <- feature$geometry$type
  coordinates <- feature$geometry$coordinates

  polygons <- if (identical(geometry_type, "Polygon")) {
    list(coordinates)
  } else if (identical(geometry_type, "MultiPolygon")) {
    coordinates
  } else {
    stop("Unsupported geometry type: ", geometry_type)
  }

  feature_rows <- vector("list", length(polygons))
  for (polygon_index in seq_along(polygons)) {
    rings <- polygons[[polygon_index]]
    ring_rows <- vector("list", length(rings))
    for (ring_index in seq_along(rings)) {
      coordinate_matrix <- do.call(rbind, rings[[ring_index]])
      if (ncol(coordinate_matrix) < 2L) {
        stop("Invalid coordinate pair in ", source_code, ": ", code6)
      }
      ring_rows[[ring_index]] <- data.frame(
        longitude = as.numeric(coordinate_matrix[, 1L]),
        latitude = as.numeric(coordinate_matrix[, 2L]),
        feature_code = code6,
        map_code = map_code,
        map_name = map_name,
        polygon_id = paste(source_code, feature_index, polygon_index, sep = "_"),
        ring_id = paste(
          source_code,
          feature_index,
          polygon_index,
          ring_index,
          sep = "_"
        ),
        point_order = seq_len(nrow(coordinate_matrix)),
        stringsAsFactors = FALSE
      )
    }
    feature_rows[[polygon_index]] <- do.call(rbind, ring_rows)
  }
  do.call(rbind, feature_rows)
}

read_china_geojson <- function(path, source_code, map_code_width = 6L) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required.")
  }
  object <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (!identical(object$type, "FeatureCollection")) {
    stop("Not a GeoJSON FeatureCollection: ", path)
  }
  rows <- lapply(
    seq_along(object$features),
    function(index) {
      extract_feature_coordinates(
        object$features[[index]],
        index,
        source_code,
        map_code_width
      )
    }
  )
  do.call(rbind, rows)
}

# GeoJSON.CN v1.6.x reports GCJ-02 coordinates. GCJ-02 has no standard EPSG
# datum operation, so do not replace this with st_transform(..., "EPSG:4326").
# This is the deterministic iterative inverse of the usual WGS-84 -> GCJ-02
# forward formula. It is an approximation because the official inverse is not
# publicly specified; retain the source coordinates for auditability.
gcj02_outside_china <- function(longitude, latitude) {
  !is.finite(longitude) | !is.finite(latitude) |
    longitude < 72.004 | longitude > 137.8347 |
    latitude < 0.8293 | latitude > 55.8271
}

gcj02_transform_lat <- function(x, y) {
  result <- -100 + 2 * x + 3 * y + 0.2 * y^2 +
    0.1 * x * y + 0.2 * sqrt(abs(x))
  result <- result + (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3
  result <- result + (20 * sin(y * pi) + 40 * sin(y / 3 * pi)) * 2 / 3
  result + (160 * sin(y / 12 * pi) + 320 * sin(y * pi / 30)) * 2 / 3
}

gcj02_transform_lon <- function(x, y) {
  result <- 300 + x + 2 * y + 0.1 * x^2 +
    0.1 * x * y + 0.1 * sqrt(abs(x))
  result <- result + (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3
  result <- result + (20 * sin(x * pi) + 40 * sin(x / 3 * pi)) * 2 / 3
  result + (150 * sin(x / 12 * pi) + 300 * sin(x / 30 * pi)) * 2 / 3
}

wgs84_to_gcj02 <- function(longitude, latitude) {
  longitude <- as.numeric(longitude)
  latitude <- as.numeric(latitude)
  output_longitude <- longitude
  output_latitude <- latitude
  inside <- !gcj02_outside_china(longitude, latitude)
  if (any(inside)) {
    x <- longitude[inside] - 105
    y <- latitude[inside] - 35
    delta_latitude <- gcj02_transform_lat(x, y)
    delta_longitude <- gcj02_transform_lon(x, y)
    latitude_radians <- latitude[inside] * pi / 180
    magic <- 1 - 0.00669342162296594323 * sin(latitude_radians)^2
    sqrt_magic <- sqrt(magic)
    delta_latitude <- (delta_latitude * 180) /
      ((6378245 * (1 - 0.00669342162296594323)) /
        (magic * sqrt_magic) * pi)
    delta_longitude <- (delta_longitude * 180) /
      (6378245 / sqrt_magic * cos(latitude_radians) * pi)
    output_latitude[inside] <- latitude[inside] + delta_latitude
    output_longitude[inside] <- longitude[inside] + delta_longitude
  }
  data.frame(longitude = output_longitude, latitude = output_latitude)
}

gcj02_to_wgs84 <- function(
  longitude, latitude, tolerance_deg = 1e-7, max_iterations = 20L
) {
  longitude <- as.numeric(longitude)
  latitude <- as.numeric(latitude)
  output_longitude <- longitude
  output_latitude <- latitude
  inside <- !gcj02_outside_china(longitude, latitude)
  if (any(inside)) {
    target_longitude <- longitude[inside]
    target_latitude <- latitude[inside]
    initial <- wgs84_to_gcj02(target_longitude, target_latitude)
    candidate_longitude <- 2 * target_longitude - initial$longitude
    candidate_latitude <- 2 * target_latitude - initial$latitude
    for (iteration in seq_len(max_iterations)) {
      forward <- wgs84_to_gcj02(candidate_longitude, candidate_latitude)
      residual_longitude <- forward$longitude - target_longitude
      residual_latitude <- forward$latitude - target_latitude
      candidate_longitude <- candidate_longitude - residual_longitude
      candidate_latitude <- candidate_latitude - residual_latitude
      if (max(c(abs(residual_longitude), abs(residual_latitude))) <=
          tolerance_deg) {
        break
      }
    }
    output_longitude[inside] <- candidate_longitude
    output_latitude[inside] <- candidate_latitude
  }
  data.frame(longitude = output_longitude, latitude = output_latitude)
}

convert_to_wgs84 <- function(
  longitude, latitude, source_coordinate_system = "GCJ-02",
  tolerance_deg = 1e-7, max_iterations = 20L
) {
  if (identical(source_coordinate_system, "GCJ-02")) {
    return(gcj02_to_wgs84(
      longitude, latitude, tolerance_deg, max_iterations
    ))
  }
  if (source_coordinate_system %in% c("WGS-84", "WGS84")) {
    return(data.frame(
      longitude = as.numeric(longitude), latitude = as.numeric(latitude)
    ))
  }
  stop(
    "Unsupported source coordinate system: ", source_coordinate_system,
    ". Add and document an explicit transformation before plotting."
  )
}

albers_project <- function(
  longitude,
  latitude,
  central_meridian,
  latitude_origin,
  standard_parallel_1,
  standard_parallel_2,
  radius = 6371008.8
) {
  radians <- pi / 180
  lambda <- longitude * radians
  phi <- latitude * radians
  lambda_0 <- central_meridian * radians
  phi_0 <- latitude_origin * radians
  phi_1 <- standard_parallel_1 * radians
  phi_2 <- standard_parallel_2 * radians
  n <- 0.5 * (sin(phi_1) + sin(phi_2))
  c_constant <- cos(phi_1)^2 + 2 * n * sin(phi_1)
  rho <- radius * sqrt(c_constant - 2 * n * sin(phi)) / n
  rho_0 <- radius * sqrt(c_constant - 2 * n * sin(phi_0)) / n
  theta <- n * (lambda - lambda_0)
  data.frame(x = rho * sin(theta), y = rho_0 - rho * cos(theta))
}

project_china_geometry <- function(
  data, source_coordinate_system = "GCJ-02",
  tolerance_deg = 1e-7, max_iterations = 20L
) {
  converted <- convert_to_wgs84(
    data$longitude, data$latitude, source_coordinate_system,
    tolerance_deg, max_iterations
  )
  if (identical(source_coordinate_system, "GCJ-02")) {
    data$longitude_gcj02 <- data$longitude
    data$latitude_gcj02 <- data$latitude
  }
  data$longitude <- converted$longitude
  data$latitude <- converted$latitude
  main <- albers_project(
    data$longitude,
    data$latitude,
    central_meridian = 105,
    latitude_origin = 0,
    standard_parallel_1 = 25,
    standard_parallel_2 = 47
  )
  inset <- albers_project(
    data$longitude,
    data$latitude,
    central_meridian = 115,
    latitude_origin = 0,
    standard_parallel_1 = 7,
    standard_parallel_2 = 20
  )
  data$main_x <- main$x
  data$main_y <- main$y
  data$inset_x <- inset$x
  data$inset_y <- inset$y
  data
}

range_with_padding <- function(values, padding_share = 0.015) {
  value_range <- range(values, na.rm = TRUE)
  padding <- diff(value_range) * padding_share
  c(value_range[1] - padding, value_range[2] + padding)
}

china_main_limits <- function(data) {
  keep <- data$longitude >= 73 & data$longitude <= 135 &
    data$latitude >= 17 & data$latitude <= 54
  x_limits <- range_with_padding(data$main_x[keep], 0.012)
  x_limits[2] <- x_limits[2] + 0.025 * diff(x_limits)
  list(
    x = x_limits,
    y = range_with_padding(data$main_y[keep], 0.012)
  )
}

south_sea_inset_box <- function(main_x_limits, main_y_limits) {
  list(
    xmin = main_x_limits[1] + 0.055 * diff(main_x_limits),
    xmax = main_x_limits[1] + 0.229 * diff(main_x_limits),
    ymin = main_y_limits[1] + 0.005 * diff(main_y_limits),
    ymax = main_y_limits[1] + 0.310 * diff(main_y_limits)
  )
}

south_sea_geographic_window <- function() {
  # Work in the WGS-84 longitude/latitude plane so the north edge follows the
  # parallel at 23 degrees 26 minutes rather than a geodesic between corners.
  sf::st_as_sfc(sf::st_bbox(c(xmin = 105, ymin = 2, xmax = 127, ymax = 23 + 26 / 60)))
}

admin_polygon_features <- function(geometry, x_col, y_col) {
  parts <- split(geometry, geometry$polygon_id)
  shapes <- lapply(parts, function(part) {
    rings <- split(part, factor(part$ring_id, levels = unique(part$ring_id)))
    sf::st_polygon(lapply(rings, function(ring) {
      as.matrix(ring[, c(x_col, y_col)])
    }))
  })
  sf::st_sf(
    map_code = vapply(parts, function(part) part$map_code[[1L]], character(1)),
    geometry = sf::st_make_valid(sf::st_sfc(shapes)), agr = "constant"
  )
}

# Split only the mainland exterior at the coastal ends of its land border.
# The endpoint coordinates and longer-arc rule follow the QGIS template.
china_boundary_lines <- function(provinces) {
  areas <- admin_polygon_features(provinces, "longitude", "latitude")
  land <- sf::st_cast(sf::st_union(sf::st_geometry(areas)), "POLYGON")
  mainland <- which.max(as.numeric(sf::st_area(land)))
  ring <- land[[mainland]][[1L]]
  project <- function(lon, lat) as.matrix(albers_project(lon, lat, 105, 0, 25, 47))
  xy <- project(ring[, 1L], ring[, 2L])
  starts <- seq_len(nrow(ring) - 1L)
  start_xy <- xy[starts, , drop = FALSE]
  steps <- xy[starts + 1L, , drop = FALSE] - start_xy
  lengths <- sqrt(rowSums(steps^2))
  chainage <- c(0, cumsum(lengths))

  cut_at <- function(lon, lat) {
    target <- project(lon, lat)[1L, ]
    offsets <- sweep(start_xy, 2L, target, function(start, point) point - start)
    along <- pmin(1, pmax(0, rowSums(offsets * steps) / pmax(lengths^2, .Machine$double.eps)))
    segment <- which.min(rowSums((offsets - along * steps)^2))
    fraction <- along[segment]
    list(
      segment = segment,
      distance = chainage[segment] + fraction * lengths[segment],
      point = ring[segment, ] + fraction * (ring[segment + 1L, ] - ring[segment, ])
    )
  }
  first <- cut_at(108.03, 21.56)
  second <- cut_at(124.18, 39.84)
  if (first$distance > second$distance) {
    swapped <- first
    first <- second
    second <- swapped
  }
  stopifnot(first$segment < second$segment)
  middle <- starts[starts > first$segment & starts <= second$segment]
  wrap <- c(starts[starts > second$segment], starts[starts <= first$segment])
  arcs <- list(
    rbind(first$point, ring[middle, , drop = FALSE], second$point),
    rbind(second$point, ring[wrap, , drop = FALSE], first$point)
  )
  forward_length <- second$distance - first$distance
  arc_lengths <- c(forward_length, tail(chainage, 1L) - forward_length)
  land_arc <- which.max(arc_lengths)
  stopifnot(arc_lengths[land_arc] > 14e6, arc_lengths[land_arc] < 25e6)
  coast_rings <- c(arcs[-land_arc], lapply(land[-mainland], function(island) island[[1L]]))
  sf::st_sf(
    kind = c("land_border", rep("coastline", length(coast_rings))),
    geometry = sf::st_sfc(lapply(c(arcs[land_arc], coast_rings), sf::st_linestring)),
    agr = "constant"
  )
}

china_boundary_paths <- function(lines, inset = FALSE, window = south_sea_geographic_window()) {
  if (inset) lines <- sf::st_intersection(lines, window)
  lines <- lines[which(sf::st_dimension(lines) == 1L), ]
  if (any(sf::st_geometry_type(lines) == "GEOMETRYCOLLECTION")) {
    lines <- sf::st_collection_extract(lines, "LINESTRING")
  }
  lines <- sf::st_cast(lines, "MULTILINESTRING")
  lines <- sf::st_cast(lines, "LINESTRING", warn = FALSE)
  paths <- admin_edge_paths(lines)
  projected <- if (inset) {
    albers_project(paths$x, paths$y, 115, 0, 7, 20)
  } else {
    albers_project(paths$x, paths$y, 105, 0, 25, 47)
  }
  paths$x <- projected$x
  paths$y <- projected$y
  paths$kind <- lines$kind[paths$path_id]
  paths
}

china_border_style <- function(width_scale) {
  list(
    colour = c("#C6C8E0", "#AAA6C8", "#25212D"),
    linewidth = width_scale * c(2.95, 1.65, 0.37)
  )
}

china_border_strokes <- function(paths, width_scale = 1) {
  style <- china_border_style(width_scale)
  Map(
    function(colour, linewidth, lineend) {
      ggplot2::geom_path(
        data = paths, ggplot2::aes(x = x, y = y, group = path_id),
        colour = colour, linewidth = linewidth, linejoin = "round", lineend = lineend
      )
    },
    style$colour,
    style$linewidth,
    c("round", "round", "butt")
  )
}

# Draw a fixed physical-width band on the seaward side of every dash. The
# land casing is painted beneath the land fill, which exposes half its width.
china_maritime_border_strokes <- function(paths, limits, inland, width_scale = 1) {
  style <- china_border_style(width_scale)
  marks <- lapply(split(paths[, c("x", "y")], paths$path_id), function(path) {
    coordinates <- as.matrix(path)
    heading <- coordinates[nrow(coordinates), ] - coordinates[1L, ]
    to_inland <- unlist(inland) - colMeans(coordinates)
    if (heading[1L] * to_inland[2L] - heading[2L] * to_inland[1L] < 0) {
      coordinates <- coordinates[rev(seq_len(nrow(coordinates))), , drop = FALSE]
    }
    cbind(
      (coordinates[, 1L] - limits$x[1L]) / diff(limits$x),
      (coordinates[, 2L] - limits$y[1L]) / diff(limits$y)
    )
  })
  halo <- grid::gTree(
    marks = marks, colours = style$colour[1:2],
    # grid line width 1 is 1/96 inch. Use its radius for the single-sided fill.
    band_inches = style$linewidth[1:2] * ggplot2::.pt / (2 * 96),
    cl = "china_maritime_halo"
  )
  list(
    ggplot2::annotation_custom(halo),
    china_border_strokes(paths, width_scale)[[3L]]
  )
}

makeContent.china_maritime_halo <- function(x) {
  lines <- sf::st_sfc(lapply(x$marks, function(mark) {
    sf::st_linestring(cbind(
      grid::convertX(grid::unit(mark[, 1L], "npc"), "inches", valueOnly = TRUE),
      grid::convertY(grid::unit(mark[, 2L], "npc"), "inches", valueOnly = TRUE)
    ))
  }))
  bands <- Map(function(width, colour) {
    # Each path is oriented with the inland reference to its left.
    polygon <- sf::st_cast(sf::st_buffer(lines, -width, singleSide = TRUE), "MULTIPOLYGON")
    coordinates <- sf::st_coordinates(polygon)
    feature <- coordinates[, "L3"]
    part <- coordinates[, "L2"]
    ring <- coordinates[, "L1"]
    grid::pathGrob(
      coordinates[, "X"], coordinates[, "Y"],
      id = as.integer(interaction(feature, part, ring)),
      pathId = as.integer(interaction(feature, part)),
      rule = "evenodd", default.units = "inches",
      gp = grid::gpar(fill = colour, col = NA)
    )
  }, x$band_inches, x$colours)
  grid::setChildren(x, do.call(grid::gList, bands))
}

admin_unit_geometries <- function(areas) {
  by_code <- split(sf::st_geometry(areas), areas$map_code)
  setNames(sf::st_sfc(lapply(by_code, function(parts) sf::st_union(parts)[[1L]])), names(by_code))
}

# Node the source boundaries and retain linework shared by distinct areas.
# A coast, external border, or point contact has no internal edge to draw.
admin_shared_edges <- function(areas) {
  units <- admin_unit_geometries(areas)
  boundaries <- sf::st_boundary(units)
  pieces <- sf::st_intersection(boundaries)
  adjacent <- attr(pieces, "idx")
  shared <- which(lengths(adjacent) >= 2L & sf::st_dimension(pieces) == 1L)
  edges <- sf::st_sf(
    adjacent_codes = I(lapply(adjacent[shared], function(index) names(units)[index])),
    geometry = pieces[shared], agr = "constant"
  )
  if (any(sf::st_geometry_type(edges) == "GEOMETRYCOLLECTION")) {
    edges <- sf::st_collection_extract(edges, "LINESTRING")
  }
  if (nrow(edges) == 0L) return(sf::st_cast(edges, "LINESTRING"))
  # Rejoin fragments with the same adjacent units before rendering.
  groups <- split(seq_len(nrow(edges)), vapply(edges$adjacent_codes, paste, "", collapse = ","))
  merged <- lapply(groups, function(index) {
    combined <- sf::st_combine(sf::st_geometry(edges)[index])
    sf::st_line_merge(sf::st_cast(combined, "MULTILINESTRING"))[[1L]]
  })
  edges <- sf::st_sf(
    adjacent_codes = I(lapply(groups, function(index) edges$adjacent_codes[[index[1L]]])),
    geometry = sf::st_cast(sf::st_sfc(merged), "MULTILINESTRING"), agr = "constant"
  )
  sf::st_cast(edges, "LINESTRING", warn = FALSE)
}

province_internal_edges <- function(areas, land, seam_tolerance = 250) {
  units <- admin_unit_geometries(areas)
  borders <- sf::st_boundary(units)
  buffered <- sf::st_buffer(units, dist = seam_tolerance, nQuadSegs = 4)
  nearby <- sf::st_intersects(borders, buffered)
  # Close subpixel seams in the land mask and trim its outer edge to keep
  # neighboring coasts and shorelines out of the province linework.
  interior <- sf::st_buffer(
    sf::st_buffer(land, dist = seam_tolerance, nQuadSegs = 4),
    dist = -1.1 * seam_tolerance, nQuadSegs = 4
  )
  pairs <- lapply(seq_along(nearby), function(index) {
    neighbors <- nearby[[index]][nearby[[index]] > index]
    sf::st_intersection(borders[index], buffered[neighbors])
  })
  pieces <- do.call(c, pairs)
  shared <- sf::st_intersection(sf::st_union(pieces), interior)
  if (any(sf::st_geometry_type(shared) == "GEOMETRYCOLLECTION")) {
    shared <- sf::st_collection_extract(shared, "LINESTRING")
  }
  lines <- sf::st_line_merge(sf::st_cast(shared, "MULTILINESTRING"))
  sf::st_as_sf(sf::st_cast(lines, "LINESTRING"))
}

admin_edge_paths <- function(edges) {
  if (nrow(edges) == 0L) {
    return(data.frame(x = numeric(), y = numeric(), path_id = integer()))
  }
  coords <- sf::st_coordinates(edges)
  data.frame(x = coords[, "X"], y = coords[, "Y"], path_id = coords[, "L1"])
}

# Assign one stroke per shared edge by maximizing contrast on its weakest side.
admin_edge_colours <- function(edges, fills_by_code) {
  srgb <- t(grDevices::col2rgb(fills_by_code)) / 255
  linear <- ifelse(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055)^2.4)
  luminance <- setNames(drop(linear %*% c(0.2126, 0.7152, 0.0722)), names(fills_by_code))
  vapply(edges$adjacent_codes, function(codes) {
    light <- range(luminance[codes])
    black_contrast <- (light[1L] + 0.05) / 0.05
    white_contrast <- 1.05 / (light[2L] + 0.05)
    if (black_contrast >= white_contrast) "#000000" else "#FFFFFF"
  }, character(1))
}

# Draw several translucent vector bands offset to the southeast. Intersect
# each band with dissolved land so the shadow ends at the coast or land border.
province_shadow_bands <- function(edges, land, panel_width) {
  linework <- sf::st_union(sf::st_geometry(edges))
  radius <- panel_width * 0.0017
  shifted <- linework + radius * c(0.38, -0.42)
  widths <- radius * c(1.35, 0.82, 0.42)
  opacity <- c(0.09, 0.14, 0.18)
  do.call(rbind, lapply(seq_along(widths), function(index) {
    band <- sf::st_buffer(shifted, dist = widths[index], nQuadSegs = 6,
                          endCapStyle = "FLAT")
    band <- sf::st_intersection(band, land)
    band <- sf::st_cast(band, "MULTIPOLYGON")
    coords <- sf::st_coordinates(band)
    data.frame(
      x = coords[, "X"], y = coords[, "Y"],
      polygon_id = paste(index, coords[, "L3"], coords[, "L2"], sep = "_"),
      ring_id = coords[, "L1"], opacity = opacity[index]
    )
  }))
}

south_sea_inset_geometry <- function(geometry, window = south_sea_geographic_window()) {
  areas <- admin_polygon_features(geometry, "longitude", "latitude")
  clipped <- sf::st_intersection(areas, window)
  clipped <- clipped[sf::st_dimension(clipped) == 2L, ]
  if (any(sf::st_geometry_type(clipped) == "GEOMETRYCOLLECTION")) {
    clipped <- sf::st_collection_extract(clipped, "POLYGON")
  }
  # Normalize mixed single/multipart results before splitting into polygons.
  clipped <- sf::st_cast(clipped, "MULTIPOLYGON")
  clipped <- sf::st_cast(clipped, "POLYGON", warn = FALSE)
  if (nrow(clipped) == 0L) stop("No polygon geometry in the South China Sea inset.")
  coords <- sf::st_coordinates(clipped)
  projected <- albers_project(coords[, "X"], coords[, "Y"], 115, 0, 7, 20)
  data.frame(
    map_code = clipped$map_code[coords[, "L2"]],
    polygon_id = coords[, "L2"],
    ring_id = coords[, "L1"],
    inset_x = projected$x, inset_y = projected$y
  )
}

south_sea_inset_line <- function(line, window = south_sea_geographic_window()) {
  segments <- split(line, line$segment_id)
  paths <- lapply(segments, function(segment) {
    sf::st_linestring(as.matrix(segment[, c("longitude", "latitude")]))
  })
  lines <- sf::st_sf(
    segment_id = as.integer(names(segments)),
    geometry = sf::st_sfc(paths), agr = "constant"
  )
  clipped <- sf::st_intersection(lines, window)
  clipped <- clipped[sf::st_dimension(clipped) == 1L, ]
  if (any(sf::st_geometry_type(clipped) == "GEOMETRYCOLLECTION")) {
    clipped <- sf::st_collection_extract(clipped, "LINESTRING")
  }
  clipped <- sf::st_cast(clipped, "MULTILINESTRING")
  clipped <- sf::st_cast(clipped, "LINESTRING", warn = FALSE)
  coords <- sf::st_coordinates(clipped)
  projected <- albers_project(coords[, "X"], coords[, "Y"], 115, 0, 7, 20)
  data.frame(
    segment_id = clipped$segment_id[coords[, "L1"]],
    path_id = coords[, "L1"],
    inset_x = projected$x, inset_y = projected$y
  )
}

# Use a common projected extent for all comparable inset panels.
south_sea_panel_limits <- function(geometry, maritime, padding_share = 0.025) {
  x <- range(c(geometry$inset_x, maritime$inset_x))
  y <- range(c(geometry$inset_y, maritime$inset_y))
  span <- min(diff(x), diff(y))
  stopifnot(is.finite(span), span > 0, is.finite(padding_share), padding_share > 0)
  padding <- span * padding_share
  list(x = x + c(-padding, padding), y = c(y[1] - padding, y[2]))
}

# Draw this grob over the title-free, borderless inset in the same viewport.
# One outer frame and one divider enclose the map and header together.
south_sea_header <- function(title, inset_x_limits, title_family,
                             label_family = "Times New Roman", scale_km = 500) {
  bar_fraction <- 1000 * scale_km / diff(inset_x_limits)
  stopifnot(is.finite(bar_fraction), bar_fraction > 0, bar_fraction < 1)
  title_size <- 12
  title_x <- grid::unit(3, "pt")
  if (identical(title, "南海诸岛")) {
    title <- strsplit(title, "", fixed = TRUE)[[1L]]
    # SimSun's full-width characters advance by one em, plus 1 pt of spacing.
    title_x <- title_x + grid::unit((seq_along(title) - 1L) * (title_size + 1), "pt")
  }
  bar_width <- grid::unit(bar_fraction, "npc")
  bar_top <- grid::unit(1, "npc") + grid::unit(8, "pt")
  bar_height <- grid::unit(2.5, "pt")
  frame_top <- grid::unit(1, "npc")
  header_height <- grid::unit(23, "pt")
  colour <- "#222222"
  scale_label <- grid::textGrob(
    paste0(format(scale_km, big.mark = ",", trim = TRUE), " km"),
    y = bar_top + grid::unit(2, "pt"), just = c("centre", "bottom"),
    gp = grid::gpar(fontfamily = label_family, fontsize = 11.5, col = colour)
  )
  scale_width <- grid::unit.pmax(bar_width, grid::grobWidth(scale_label))
  scale_label$x <- grid::unit(1, "npc") - grid::unit(3, "pt") - scale_width / 2
  frame_style <- grid::gpar(col = colour, fill = NA, lwd = 0.45 * ggplot2::.pt, lty = "solid")
  grid::grobTree(
    grid::rectGrob(
      x = grid::unit(0, "npc"), y = frame_top,
      width = grid::unit(1, "npc"), height = header_height,
      just = c("left", "bottom"), gp = grid::gpar(fill = "white", col = NA)
    ),
    grid::rectGrob(
      x = grid::unit(0, "npc"), y = grid::unit(0, "npc"),
      width = grid::unit(1, "npc"), height = frame_top + header_height,
      just = c("left", "bottom"), gp = frame_style
    ),
    grid::segmentsGrob(
      x0 = grid::unit(0, "npc"), x1 = grid::unit(1, "npc"),
      y0 = frame_top, y1 = frame_top, gp = frame_style
    ),
    grid::textGrob(
      title, x = title_x, y = frame_top + header_height / 2,
      just = c("left", "centre"),
      gp = grid::gpar(fontfamily = title_family, fontsize = title_size, col = colour)
    ),
    grid::rectGrob(
      x = scale_label$x, y = bar_top,
      width = bar_width, height = bar_height, just = c("centre", "top"),
      gp = grid::gpar(fill = colour, col = NA)
    ),
    scale_label
  )
}

# Add the divider after ggplot2 or patchwork has assembled the right-side guides.
# The legend title's bottom margin provides space on both sides of the divider.
add_right_colorbar_divider <- function(plot_grob, clearance_pt = 5) {
  # Patchwork nests inside guides in their panels when it keeps the aspect ratio.
  for (panel_index in grep("^panel;.*guide-box-inside", plot_grob$layout$name)) {
    plot_grob$grobs[[panel_index]] <- add_right_colorbar_divider(
      plot_grob$grobs[[panel_index]], clearance_pt
    )
  }
  box_indices <- grep("^guide-box(-right|-inside)?(-[0-9]+)?$", plot_grob$layout$name)
  for (box_index in box_indices) {
    box <- plot_grob$grobs[[box_index]]
    if (!inherits(box, "gtable")) next
    for (guide_index in which(box$layout$name == "guides")) {
      guide <- box$grobs[[guide_index]]
      cells <- match(c("title", "bar", "background"), guide$layout$name)
      if (anyNA(cells)) next
      frame_style <- guide$grobs[[cells[3L]]]$gp
      if (is.null(frame_style$col) || is.na(frame_style$col)) next

      divider_y <- grid::unit(clearance_pt, "pt")
      box$grobs[[guide_index]] <- gtable::gtable_add_grob(
        guide,
        grid::segmentsGrob(
          x0 = 0, x1 = 1, y0 = divider_y, y1 = divider_y, gp = frame_style
        ),
        t = guide$layout$b[cells[1L]], l = 1L, r = length(guide$widths),
        clip = "off", name = "title-divider"
      )
    }
    plot_grob$grobs[[box_index]] <- box
  }
  plot_grob
}

# Read the ten-segment line from the user's local, unmodified national GeoJSON.
ten_segment_line <- function(
  national_geojson_path, source_coordinate_system = "GCJ-02",
  tolerance_deg = 1e-7, max_iterations = 20L
) {
  if (missing(national_geojson_path) || !is.character(national_geojson_path) ||
      length(national_geojson_path) != 1L || is.na(national_geojson_path) ||
      !file.exists(national_geojson_path) || dir.exists(national_geojson_path)) {
    stop("Provide a local national GeoJSON file (100000.json) that you are authorized to use.")
  }
  national <- jsonlite::fromJSON(national_geojson_path, simplifyVector = FALSE)
  if (!is.list(national) || !identical(national$type, "FeatureCollection") ||
      !is.list(national$features)) {
    stop("Expected a GeoJSON FeatureCollection in: ", national_geojson_path)
  }
  marks <- Filter(function(feature) {
    is.list(feature) && is.list(feature$properties) &&
      identical(feature$properties$name, "十段线")
  }, national$features)
  if (length(marks) != 1L || !is.list(marks[[1L]]$geometry) ||
      !identical(marks[[1L]]$geometry$type, "MultiLineString")) {
    stop("Expected one MultiLineString feature named 十段线 in: ", national_geojson_path)
  }
  coordinates <- marks[[1L]]$geometry$coordinates
  if (!is.list(coordinates) || length(coordinates) != 10L) {
    stop("The 十段线 feature must have exactly ten line parts: ", national_geojson_path)
  }
  line <- do.call(rbind, lapply(seq_along(coordinates), function(index) {
    segment <- coordinates[[index]]
    if (!is.list(segment) || length(segment) < 2L) {
      stop("The 十段线 part ", index, " must contain at least two points.")
    }
    points <- t(vapply(segment, function(point) {
      xy <- unlist(point, use.names = FALSE)
      if (!is.numeric(xy) || length(xy) < 2L || !all(is.finite(xy[1:2])) ||
          abs(xy[1L]) > 180 || abs(xy[2L]) > 90) {
        stop("Invalid longitude/latitude pair in 十段线 part ", index, ".")
      }
      xy[1:2]
    }, numeric(2L)))
    if (nrow(unique(points)) < 2L) {
      stop("The 十段线 part ", index, " has zero length.")
    }
    data.frame(longitude = points[, 1L], latitude = points[, 2L], segment_id = index)
  }))
  project_china_geometry(line, source_coordinate_system, tolerance_deg, max_iterations)
}

audit_map_crosswalk <- function(analytical_codes, map_codes, available_codes) {
  audit <- unique(data.frame(
    analytical_code = as.character(analytical_codes),
    map_code = as.character(map_codes),
    stringsAsFactors = FALSE
  ))
  audit$map_matched <- audit$map_code %in% as.character(available_codes)
  audit
}
