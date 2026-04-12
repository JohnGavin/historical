#' Standard plot theme for historicaldata visualisations
#'
#' Black background, white text and gridlines, high-contrast data colours.
#' Designed for dark-themed dashboards and vignettes.
#'
#' @param base_size Base font size (default 14)
#' @return A ggplot2 theme object
#' @export
#' @examples
#' library(ggplot2)
#' ggplot(mtcars, aes(wt, mpg)) + geom_point(colour = "#00BFFF") + hd_theme()
hd_theme <- function(base_size = 14) {
  ggplot2::theme_minimal(base_size = base_size) %+replace%
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "black", colour = NA),
      panel.background = ggplot2::element_rect(fill = "black", colour = NA),
      text = ggplot2::element_text(colour = "white"),
      axis.text = ggplot2::element_text(colour = "grey70"),
      axis.title = ggplot2::element_text(colour = "grey90"),
      plot.title = ggplot2::element_text(colour = "white", size = base_size + 2),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = "grey30"),
      legend.background = ggplot2::element_rect(fill = "black", colour = NA),
      legend.text = ggplot2::element_text(colour = "white"),
      legend.position = "bottom",
      strip.text = ggplot2::element_text(colour = "white")
    )
}

#' High-contrast colour palette for dark backgrounds
#'
#' 10 colours chosen for visibility on black backgrounds.
#'
#' @param n Number of colours (max 10)
#' @return Character vector of hex colours
#' @export
hd_palette <- function(n = 10) {
  pal <- c("#00BFFF", "#FF6347", "#32CD32", "#FFD700", "#FF69B4",
           "#00CED1", "#FFA500", "#BA55D3", "#7FFF00", "#FF4500")
  pal[seq_len(min(n, length(pal)))]
}
