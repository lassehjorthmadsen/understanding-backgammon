# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Quarto **book** ("Understanding Backgammon") of personal study notes and example positions for improving at backgammon. Chapters are `.qmd` files rendered with knitr/R.

## R setup: positions and gnubg

Every chapter starts with a hidden chunk running `source("_common.R")`, which:

- loads the companion package **bglab** from the sibling checkout `../bglab` via `pkgload::load_all()` (same convention as `../bganalyses`; bglab is not installed as a package). Its `ggboard(xgid)` draws a position as a ggplot, and `gnuid2xgid(pos_id, match_id)` converts a gnubg Position ID + Match ID to an XGID (verified exact by round-tripping through gnubg's `set xgid` / `show board`). Positions are kept as XGIDs throughout; convert gnubg IDs with `gnuid2xgid()` at the top of the chunk.
- sources `R/gnubg.R`, which drives **GNU Backgammon 1.08 inside WSL** (`/usr/games/gnubg -t -q`, invoked as `wsl.exe -e ...`; override the path with `options(gnubg.exe = ...)`). The approach mirrors `\\wsl.localhost\Ubuntu\home\lasse\raccoon\raccoon\eval\gnubg_cli.py`, but positions go in as XGIDs via `set xgid` so the same string feeds both `ggboard()` and gnubg.
  - `gnubg_moves(xgid, plies = 2, n = 5)`: ranked checker plays (XGID must have dice).
  - `gnubg_cube(xgid, plies = 2)`: cubeful equities for No double / Double-take / Double-pass (XGID dice field `00`, player on roll must be able to double); gnubg's verdict and cubeless probabilities are in `attr(, "proper_action")` and `attr(, "probs")`.
  - `show_moves(xgid, n = 5, plies = 2)`: prints the checker analysis in XG's text layout under a diagram (relies on `comment: ""`, set in `_common.R`). The book uses `plies = 4` (~25 s per position for n = 5; freeze caches it).
  - Candidate count `n` sets gnubg's move filter so all `n` moves are evaluated at the full ply; gnubg's default filter would rank most candidates on shallower plies, which aren't comparable.
  - Each call is a fresh gnubg process (~0.4 s). Match length, score, cube and Jacoby come from the XGID; nothing overrides them.

Rendering therefore needs the `../bglab` checkout, WSL with gnubg, and the R packages `pkgload` and `ggforce` (plus bglab's other imports). bglab's `ggboard()` currently emits harmless ggplot2 warnings (`size` → `linewidth`, manual scale levels); use `#| warning: false` on board chunks.

## Commands

- Preview with live reload: `quarto preview`
- Full render (HTML into `_book/`): `quarto render`
- Render one chapter: `quarto render positional_checker.qmd`

There are no tests or linters.

## Structure and conventions

- `_quarto.yml` is the source of truth for chapter order and part grouping. A new `.qmd` file is not part of the book until it is added under `book.chapters` there.
- The book is organized as a 2×2 grid: **positional** vs. **technical** decisions (vision vs. counting), each split into **checker plays** and **cube plays**. `intro.qmd` explains this framing. Within checker-play chapters, `##` sections are *concepts* (e.g. splitting, hitting loose); within cube-play chapters, sections are position *themes*, and each aims to show typical positions for (a) a minimal double, (b) a solid double/solid take, (c) a minimal take.
- Front-matter chapters (`index.qmd`, `intro.qmd`) use `{.unnumbered}` headings; numbering is disabled globally anyway (`number-sections: false`).
- `execute.freeze: auto` is set, so code chunks are only re-run when their source file changes; results are cached in `_freeze/` (see Publishing).

## Publishing

Publishing is done locally, following the same convention as the companion project `../bganalyses`: run `quarto publish gh-pages`, which renders the book and pushes it to the `gh-pages` branch (site: https://lassehjorthmadsen.github.io/understanding-backgammon/). There is no CI; pushing to `main` does not publish.

`_freeze/` is committed so that rendered code output is preserved; commit it after rendering. `_book/` and `*.html` are gitignored.
