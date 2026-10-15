# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Quarto **book** ("Understanding Backgammon") of personal notes and example positions for improving at backgammon. Content is prose in `.qmd` files; there is currently no R/Python code in the chapters, though it is set up as an RStudio project so R chunks can be added.

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
