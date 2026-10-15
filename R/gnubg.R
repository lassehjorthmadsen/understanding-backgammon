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

gnubg_exe <- function() {
  getOption("gnubg.exe", "/usr/games/gnubg")
}

# Run gnubg commands, return its output lines.
gnubg_run <- function(commands) {
  out <- system2(
    "wsl.exe",
    c("-e", "env", "TERM=dumb", gnubg_exe(), "-t", "-q"),
    input = commands, stdout = TRUE, stderr = TRUE
  )
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    stop("gnubg exited with status ", status, ":\n", paste(out, collapse = "\n"))
  }
  out
}

gnubg_hint_output <- function(xgid, plies, n = NULL) {
  # With n given, keep exactly n candidates at every search level, so all n
  # are evaluated at the full ply. gnubg's default filter evaluates only the
  # top few at full depth and ranks the rest on shallower, incomparable plies.
  filters <- if (!is.null(n) && plies > 0) {
    paste("set evaluation movefilter", plies, seq_len(plies) - 1, n, 0, 0)
  }
  gnubg_run(c(
    paste("set evaluation chequer eval plies", plies),
    paste("set evaluation cubedecision eval plies", plies),
    filters,
    paste("set xgid", xgid),
    if (is.null(n)) "hint" else paste("hint", n)
  ))
}

# "0.501 0.135 0.005 - 0.499 0.131 0.004" -> named numeric vector
parse_probs <- function(line) {
  x <- as.numeric(stringr::str_extract_all(line, "\\d\\.\\d+")[[1]])
  stats::setNames(x, c("win", "win_g", "win_bg", "lose", "lose_g", "lose_bg"))
}

#' Ranked checker plays for an XGID with dice rolled.
#'
#' Returns one row per candidate: rank, move (gnubg notation), equity,
#' equity difference to the best play, and the six outcome probabilities.
#' All `n` candidates are evaluated at `plies` (4-ply with n = 5 takes ~25 s).
gnubg_moves <- function(xgid, plies = 2, n = 5) {
  out <- gnubg_hint_output(xgid, plies, n)
  move_re <- "^\\s*(\\d+)\\.\\s+(Cubeful|Cubeless)\\s+(\\d+)-ply\\s+(.+?)\\s{2,}Eq\\.:\\s*([+-]?[\\d.]+)"
  idx <- which(stringr::str_detect(out, move_re))
  if (length(idx) == 0) {
    stop("No ranked moves in gnubg output (are dice set in the XGID?):\n",
         paste(out, collapse = "\n"))
  }
  m <- stringr::str_match(out[idx], move_re)
  probs <- do.call(rbind, lapply(out[idx + 1], parse_probs))
  equity <- as.numeric(m[, 6])
  tibble::tibble(
    rank   = as.integer(m[, 2]),
    move   = m[, 5],
    ply    = as.integer(m[, 4]),
    equity = equity,
    diff   = equity - equity[1],
    tibble::as_tibble(as.data.frame(probs))
  )
}

#' Print gnubg's checker-play analysis in eXtreme Gammon's text layout.
#'
#' For use under a board diagram; the chunk needs `comment: ""` (set globally
#' in `_common.R`) so knitr doesn't prefix each line with `##`.
show_moves <- function(xgid, n = 5, plies = 2) {
  moves <- gnubg_moves(xgid, plies = plies, n = n)
  pct <- function(x) sprintf("%.1f%%", 100 * x)
  width <- max(nchar(moves$move))
  for (i in seq_len(nrow(moves))) {
    m <- moves[i, ]
    diff <- if (i == 1) "" else sprintf(" (%+.3f)", m$diff)
    cat(sprintf("%d. %d-ply  %-*s  eq: %+.3f%s\n",
                m$rank, m$ply, width, m$move, m$equity, diff))
    cat(sprintf("   Player:   %s (G:%s B:%s)\n", pct(m$win), pct(m$win_g), pct(m$win_bg)))
    cat(sprintf("   Opponent: %s (G:%s B:%s)\n", pct(m$lose), pct(m$lose_g), pct(m$lose_bg)))
    if (i < nrow(moves)) cat("\n")
  }
  invisible(moves)
}

#' Cube decision for an XGID with no dice rolled (dice field `00`).
#'
#' Returns the cubeful equity of each action, with gnubg's verdict and
#' cubeless probabilities attached as attributes `proper_action` and `probs`.
gnubg_cube <- function(xgid, plies = 2) {
  out <- gnubg_hint_output(xgid, plies)
  if (!any(stringr::str_detect(out, "^Cube analysis"))) {
    stop("No cube analysis in gnubg output (is the player on roll allowed to double?):\n",
         paste(out, collapse = "\n"))
  }
  action_re <- "^\\s*(\\d)\\.\\s+(.+?)\\s{2,}([+-]?[\\d.]+)"
  m <- stringr::str_match(out, action_re)
  m <- m[!is.na(m[, 1]), , drop = FALSE]
  proper <- out[stringr::str_detect(out, "^Proper cube action:")]
  probs_line <- out[which(stringr::str_detect(out, "cubeless equity")) + 1]

  res <- tibble::tibble(
    rank   = as.integer(m[, 2]),
    action = m[, 3],
    equity = as.numeric(m[, 4]),
    diff   = as.numeric(m[, 4]) - as.numeric(m[1, 4])
  )
  attr(res, "proper_action") <- stringr::str_remove(proper, "^Proper cube action:\\s*")
  attr(res, "probs") <- parse_probs(probs_line)
  res
}
