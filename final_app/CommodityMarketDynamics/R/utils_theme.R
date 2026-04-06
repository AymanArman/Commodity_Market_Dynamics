# Applies the global plotly theme to any plotly object.
# Sets plot_bgcolor, paper_bgcolor, axis line color (#210000), font family
# (Times New Roman). Major gridlines are very translucent and thin; minor
# gridlines are hidden. Every plotly chart in the app must be piped through
# this function before returning.
#
# Parameters:
#   p - a plotly htmlwidget object
# Returns: the modified plotly object
#
# Example: plot_ly(x = 1:5, y = 1:5) |> apply_theme()
apply_theme <- function(p) {
  axis_style <- list(
    linecolor     = "#210000",
    zerolinecolor = "rgba(33,0,0,0.25)",
    # Major gridlines: very translucent, thin
    showgrid      = TRUE,
    gridcolor     = "rgba(33,0,0,0.08)",
    gridwidth     = 0.5,
    # Minor gridlines: hidden
    minor         = list(showgrid = FALSE)
  )

  p |>
    plotly::layout(
      plot_bgcolor  = "#fffff2",
      paper_bgcolor = "#fffff2",
      font          = list(family = "Times New Roman"),
      xaxis         = axis_style,
      yaxis         = axis_style
    )
}
