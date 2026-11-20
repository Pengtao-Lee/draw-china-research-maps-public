# Independent environment gate for draw-china-research-maps.
# Run from any working directory with:
#   Rscript scripts/check_map_dependencies.R

checks <- data.frame(
  dependency = character(),
  ok = logical(),
  detail = character(),
  stringsAsFactors = FALSE
)

add_check <- function(dependency, ok, detail) {
  checks <<- rbind(
    checks,
    data.frame(
      dependency = dependency,
      ok = isTRUE(ok),
      detail = detail,
      stringsAsFactors = FALSE
    )
  )
}

add_check(
  "R",
  TRUE,
  paste(R.version$major, R.version$minor, sep = ".")
)

required_packages <- c("jsonlite", "ggplot2", "ggspatial", "sf", "ragg")
for (package_name in required_packages) {
  installed <- requireNamespace(package_name, quietly = TRUE)
  detail <- if (installed) {
    as.character(utils::packageVersion(package_name))
  } else {
    "not installed"
  }
  add_check(
    paste0("R package: ", package_name),
    installed,
    detail
  )
}

cairo_ok <- isTRUE(capabilities()[["cairo"]]) &&
  exists("cairo_pdf", envir = asNamespace("grDevices"), inherits = FALSE)
add_check(
  "Cairo PDF",
  cairo_ok,
  if (cairo_ok) "grDevices::cairo_pdf available" else "Cairo PDF support unavailable"
)

required_commands <- c("Rscript", "pdffonts", "pdftoppm")
for (command_name in required_commands) {
  command_path <- unname(Sys.which(command_name))
  available <- nzchar(command_path)
  add_check(
    paste0("Command: ", command_name),
    available,
    if (available) command_path else "not found on PATH"
  )
}

print(checks, row.names = FALSE)

failed <- checks[!checks$ok, , drop = FALSE]
if (nrow(failed) > 0L) {
  cat("Dependency check failed. Install or expose the missing requirements before plotting.\n")
  quit(save = "no", status = 1L, runLast = FALSE)
}

cat("Dependency check passed.\n")
