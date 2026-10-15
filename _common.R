# Shared setup, sourced at the top of every chapter.

# bglab (ggboard() etc.) straight from the sibling checkout, as in ../bganalyses
pkgload::load_all("../bglab", quiet = TRUE)

source("R/gnubg.R")

# Printed analysis (show_moves()) should read as plain text, not "## " output
knitr::opts_chunk$set(comment = "")
