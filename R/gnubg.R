# Query GNU Backgammon (the CLI build installed in WSL) from R.
#
# Each call starts a fresh `gnubg -t -q`, feeds it a command script on stdin and
# parses what it prints. Startup is ~0.4 s, which is fine for a book: chapters
# are frozen, so gnubg only runs when a chapter's source changes.
#
# Positions go in as XGIDs via `set xgid`, the same strings `ggboard()` draws, so
# a diagram and its analysis can never refer to different positions. The XGID
# also carries cube, score, match length and the Jacoby/beaver flags; nothing
# here overrides them.
#
# Every analysis function takes `plies` and an optional `trials`. Without
# `trials` the position is evaluated at `plies`; with it, it is rolled out for
# that many games, with both sides playing and cubing at `plies` inside the
# rollout (full cubeful rollouts with variance reduction, no truncation).

gnubg_exe <- function() {
  getOption("gnubg.exe", "/usr/games/gnubg")
}

# Run gnubg commands, return its output lines.
#
# Output is cached on disk, keyed on the exact command script (XGID, plies,
# move filter, rollout settings), so a deep evaluation or rollout runs once per
# position however often the chapter is re-rendered. Delete the cache directory
# to force re-evaluation, e.g. after upgrading gnubg.
gnubg_run <- function(commands) {
  cache_dir <- getOption("gnubg.cache_dir", "_gnubg_cache")
  cache_file <- file.path(cache_dir, paste0(rlang::hash(commands), ".rds"))
  if (file.exists(cache_file)) {
    return(readRDS(cache_file))
  }

  # Thread count changes speed, not results, so it stays out of the cache key
  threads <- getOption("gnubg.threads", parallel::detectCores())
  out <- system2(
    "wsl.exe",
    c("-e", "env", "TERM=dumb", gnubg_exe(), "-t", "-q"),
    input = c(paste("set threads", threads), commands),
    stdout = TRUE, stderr = TRUE
  )
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    stop("gnubg exited with status ", status, ":\n", paste(out, collapse = "\n"))
  }
  dir.create(cache_dir, showWarnings = FALSE)
  saveRDS(out, cache_file)
  out
}

# Marks the start of exported rollout results in gnubg's output
rollout_marker <- "@@ROLLOUT@@"

gnubg_analysis_output <- function(xgid, plies, n = NULL, trials = NULL) {
  # With n given, keep exactly n candidates at every search level, so all n
  # are evaluated at the full ply. gnubg's default filter evaluates only the
  # top few at full depth and ranks the rest on shallower, incomparable plies.
  filters <- if (!is.null(n) && plies > 0) {
    paste("set evaluation movefilter", plies, seq_len(plies) - 1, n, 0, 0)
  }
  hint <- c(
    paste("set evaluation chequer eval plies", plies),
    paste("set evaluation cubedecision eval plies", plies),
    filters,
    paste("set xgid", xgid),
    if (is.null(n)) "hint" else paste("hint", n)
  )
  if (is.null(trials)) {
    return(gnubg_run(hint))
  }

  # Rollouts run on gnubg's record of the current position, filled in by
  # `hint`. Their results are only printed by `export position text`, which
  # needs a file, so gnubg's embedded Python exports to a temp file and prints
  # it. A fixed seed makes rollouts reproducible.
  rollout <- if (is.null(n)) "analyse rollout cube" else paste("analyse rollout move", paste(seq_len(n), collapse = " "))
  out <- gnubg_run(c(
    paste("set rollout trials", trials),
    paste("set rollout chequerplay plies", plies),
    paste("set rollout cubedecision plies", plies),
    "set rollout seed 1",
    hint,
    rollout,
    paste0(">import gnubg, os, tempfile; f = tempfile.mktemp(); ",
           "gnubg.command('export position text ' + f); ",
           "print('", rollout_marker, "'); print(open(f).read()); os.remove(f)")
  ))
  start <- match(rollout_marker, out)
  if (is.na(start)) {
    stop("No rollout results in gnubg output:\n", paste(out, collapse = "\n"))
  }
  out[-seq_len(start)]
}

analysis_label <- function(plies, trials) {
  if (is.null(trials)) sprintf("%d-ply", plies) else sprintf("Rollout, %d games at %d-ply", trials, plies)
}

# "0.501 0.135 0.005 - 0.499 0.131 0.004" -> named numeric vector. Rollout lines
# carry cubeless/cubeful equities after the probabilities; those are dropped.
parse_probs <- function(line) {
  x <- as.numeric(stringr::str_extract_all(line, "\\d\\.\\d+")[[1]])[1:6]
  stats::setNames(x, c("win", "win_g", "win_bg", "lose", "lose_g", "lose_bg"))
}

# Standard error of the cubeful equity from a rollout's "[... CF  0.038]" line
parse_se <- function(line) {
  as.numeric(stringr::str_match(line, "CF\\s+([\\d.]+)")[, 2])
}

#' Ranked checker plays for an XGID with dice rolled.
#'
#' Returns one row per candidate: rank, move (gnubg notation), equity,
#' equity difference to the best play, its standard error (rollouts only) and
#' the six outcome probabilities. All `n` candidates are evaluated at `plies`
#' (4-ply with n = 5 takes ~25 s), or rolled out when `trials` is given.
gnubg_moves <- function(xgid, plies = 2, n = 5, trials = NULL) {
  out <- gnubg_analysis_output(xgid, plies, n, trials)
  # An export also lists candidates that weren't rolled out; keep rollouts only
  method <- if (is.null(trials)) "(?:Cubeful|Cubeless)\\s+\\d+-ply" else "Rollout"
  move_re <- paste0("^\\s*(\\d+)\\.\\s+", method, "\\s+(.+?)\\s{2,}Eq\\.:\\s*([+-]?[\\d.]+)")
  idx <- which(stringr::str_detect(out, move_re))
  if (length(idx) == 0) {
    stop("No ranked moves in gnubg output (are dice set in the XGID?):\n",
         paste(out, collapse = "\n"))
  }
  m <- stringr::str_match(out[idx], move_re)
  probs <- do.call(rbind, lapply(out[idx + 1], parse_probs))
  equity <- as.numeric(m[, 4])
  res <- tibble::tibble(
    rank   = seq_along(idx),
    move   = m[, 3],
    equity = equity,
    diff   = equity - equity[1],
    se     = if (is.null(trials)) NA_real_ else parse_se(out[idx + 2]),
    tibble::as_tibble(as.data.frame(probs))
  )
  attr(res, "method") <- analysis_label(plies, trials)
  res
}

#' Print gnubg's checker-play analysis in eXtreme Gammon's text layout.
#'
#' For use under a board diagram; the chunk needs `comment: ""` (set globally
#' in `_common.R`) so knitr doesn't prefix each line with `##`.
show_moves <- function(xgid, n = 5, plies = 2, trials = NULL) {
  moves <- gnubg_moves(xgid, plies = plies, n = n, trials = trials)
  pct <- function(x) sprintf("%.1f%%", 100 * x)
  width <- max(nchar(moves$move))
  cat(sprintf("Analyzed in %s\n\n", attr(moves, "method")))
  for (i in seq_len(nrow(moves))) {
    m <- moves[i, ]
    diff <- if (i == 1) "" else sprintf(" (%+.3f)", m$diff)
    se <- if (is.na(m$se)) "" else sprintf("  ±%.3f", m$se)
    cat(sprintf("%d. %-*s  eq: %+.3f%s%s\n", m$rank, width, m$move, m$equity, diff, se))
    cat(sprintf("   Player:   %s (G:%s B:%s)\n", pct(m$win), pct(m$win_g), pct(m$win_bg)))
    cat(sprintf("   Opponent: %s (G:%s B:%s)\n", pct(m$lose), pct(m$lose_g), pct(m$lose_bg)))
    if (i < nrow(moves)) cat("\n")
  }
  invisible(moves)
}

#' Cube decision for an XGID with no dice rolled (dice field `00`).
#'
#' Returns the cubeful equity of each action (with its standard error for
#' rollouts), with gnubg's verdict and cubeless probabilities attached as
#' attributes `proper_action` and `probs`.
gnubg_cube <- function(xgid, plies = 2, trials = NULL) {
  out <- gnubg_analysis_output(xgid, plies, trials = trials)
  if (!any(stringr::str_detect(out, "^Cube analysis"))) {
    stop("No cube analysis in gnubg output (is the player on roll allowed to double?):\n",
         paste(out, collapse = "\n"))
  }
  action_re <- "^\\s*(\\d)\\.\\s+(.+?)\\s{2,}([+-]?[\\d.]+)"
  m <- stringr::str_match(out, action_re)
  m <- m[!is.na(m[, 1]), , drop = FALSE]
  proper <- out[stringr::str_detect(out, "^Proper cube action:")]

  se <- NA_real_
  if (is.null(trials)) {
    probs_line <- out[which(stringr::str_detect(out, "cubeless equity")) + 1]
  } else {
    # "Rollout details:" is followed by the no-double rollout (cube label,
    # probabilities, standard errors), then the same three lines for double/take
    details <- which(out == "Rollout details:")
    probs_line <- out[details + 2]
    se_nd <- parse_se(out[details + 3])
    se_dt <- parse_se(out[details + 6])
    se <- dplyr::case_when(
      stringr::str_detect(m[, 3], "^No") ~ se_nd,
      stringr::str_detect(m[, 3], "take") ~ se_dt,
      .default = NA_real_
    )
  }

  res <- tibble::tibble(
    rank   = as.integer(m[, 2]),
    action = m[, 3],
    equity = as.numeric(m[, 4]),
    diff   = as.numeric(m[, 4]) - as.numeric(m[1, 4]),
    se     = se
  )
  attr(res, "proper_action") <- stringr::str_remove(proper, "^Proper cube action:\\s*")
  attr(res, "probs") <- parse_probs(probs_line)
  attr(res, "method") <- analysis_label(plies, trials)
  res
}

#' Print gnubg's cube analysis in eXtreme Gammon's text layout.
#'
#' The cube counterpart of `show_moves()`: winning chances, then the cubeful
#' equity of each action in XG's fixed order (no double, take, pass) with its
#' difference to the best action, then gnubg's verdict.
show_cube <- function(xgid, plies = 2, trials = NULL) {
  cube <- gnubg_cube(xgid, plies = plies, trials = trials)
  p <- attr(cube, "probs")
  pct <- function(x) sprintf("%.1f%%", 100 * x)

  # gnubg says "Redouble" when the cube is already turned; keep its wording
  kind <- dplyr::case_when(
    stringr::str_detect(cube$action, "^No") ~ 1L,
    stringr::str_detect(cube$action, "take") ~ 2L,
    stringr::str_detect(cube$action, "pass") ~ 3L
  )
  cube <- cube[order(kind), ]
  eq <- cube$equity
  best <- max(eq[1], min(eq[2], eq[3]))
  labels <- paste0(stringr::str_replace(cube$action, ", ", "/"), ":")
  width <- max(nchar(labels))

  cat(sprintf("Analyzed in %s\n", attr(cube, "method")))
  cat(sprintf("Player Winning Chances:   %s (G:%s B:%s)\n", pct(p["win"]), pct(p["win_g"]), pct(p["win_bg"])))
  cat(sprintf("Opponent Winning Chances: %s (G:%s B:%s)\n", pct(p["lose"]), pct(p["lose_g"]), pct(p["lose_bg"])))
  cat("\nCubeful Equities:\n")
  for (i in seq_len(nrow(cube))) {
    diff <- if (abs(eq[i] - best) < 5e-4) "" else sprintf(" (%+.3f)", eq[i] - best)
    se <- if (is.na(cube$se[i])) "" else sprintf("  ±%.3f", cube$se[i])
    cat(sprintf("       %-*s  %+.3f%s%s\n", width, labels[i], eq[i], diff, se))
  }
  cat(sprintf("\nBest Cube action: %s\n", attr(cube, "proper_action")))
  invisible(cube)
}
