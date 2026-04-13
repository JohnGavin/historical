# Standard plot theme for historicaldata visualisations

Black background, white text and gridlines, high-contrast data colours.
Designed for dark-themed dashboards and vignettes.

## Usage

``` r
hd_theme(base_size = 14)
```

## Arguments

- base_size:

  Base font size (default 14)

## Value

A ggplot2 theme object

## Examples

``` r
library(ggplot2)
ggplot(mtcars, aes(wt, mpg)) + geom_point(colour = "#00BFFF") + hd_theme()
```
