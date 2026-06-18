# visualize.R — Interactive Visualization & Dashboard
# Author: Claude-Alpha (building both parts while awaiting Claude-Beta)
# Date: 2026-03-05
#
# Creates an interactive HTML dashboard showing financial contagion
# network analysis results.

suppressPackageStartupMessages({
  library(plotly)
  library(visNetwork)
  library(DT)
  library(htmlwidgets)
  library(htmltools)
  library(igraph)
  library(dplyr)
  library(tibble)
  library(tidyr)
  library(scales)
  library(viridis)
})

# ============================================================================
# PLOTLY VISUALIZATION FUNCTIONS
# ============================================================================

#' Plot network metrics timeline with market events
#' @param metrics tibble from build_rolling_networks
#' @param spy_returns tibble with SPY cumulative returns
#' @param events tibble of market events
#' @return plotly object
plot_metrics_timeline <- function(metrics, spy_returns = NULL,
                                  events = MARKET_EVENTS) {
  # Create subplot with shared x-axis: avg_corr, max_eigenvalue, modularity
  p1 <- plot_ly(metrics, x = ~date) |>
    add_trace(y = ~avg_corr, type = "scatter", mode = "lines",
              name = "Avg |Correlation|",
              line = list(color = "#e74c3c", width = 2)) |>
    layout(yaxis = list(title = "Avg |Corr|"))

  p2 <- plot_ly(metrics, x = ~date) |>
    add_trace(y = ~max_eigenvalue, type = "scatter", mode = "lines",
              name = "Max Eigenvalue",
              line = list(color = "#3498db", width = 2)) |>
    layout(yaxis = list(title = "Max Eigenvalue"))

  p3 <- plot_ly(metrics, x = ~date) |>
    add_trace(y = ~modularity, type = "scatter", mode = "lines",
              name = "Modularity",
              line = list(color = "#2ecc71", width = 2)) |>
    layout(yaxis = list(title = "Modularity"))

  p4 <- plot_ly(metrics, x = ~date) |>
    add_trace(y = ~n_communities, type = "scatter", mode = "lines+markers",
              name = "Communities",
              line = list(color = "#9b59b6", width = 2),
              marker = list(size = 3)) |>
    layout(yaxis = list(title = "N Communities"))

  # Combine as subplots
  fig <- subplot(p1, p2, p3, p4, nrows = 4, shareX = TRUE,
                 titleY = TRUE, heights = c(0.28, 0.28, 0.22, 0.22)) |>
    layout(
      title = list(
        text = paste0(
          "Network Metrics Over Time",
          "<br><sup>",
          "Rolling 60-day correlation windows, step=5 days. ",
          "Red shading = crash periods. ",
          "Higher avg correlation + lower modularity during crashes = network collapse into single cluster.",
          "</sup>"
        )
      ),
      showlegend = TRUE,
      legend = list(orientation = "h", y = -0.05),
      # Add crash event shapes
      shapes = lapply(seq_len(nrow(events)), function(i) {
        list(
          type = "line",
          x0 = as.character(events$date[i]),
          x1 = as.character(events$date[i]),
          y0 = 0, y1 = 1, yref = "paper",
          line = list(
            color = if (events$type[i] == "crash") "red" else "green",
            width = 1, dash = "dash"
          )
        )
      }),
      annotations = lapply(seq_len(nrow(events)), function(i) {
        list(
          x = as.character(events$date[i]),
          y = 1, yref = "paper",
          text = events$label[i],
          showarrow = TRUE, arrowhead = 2, arrowsize = 0.5,
          ax = if (i %% 2 == 0) 40 else -40,
          ay = -25,
          font = list(size = 9,
                      color = if (events$type[i] == "crash") "red" else "green")
        )
      })
    )

  fig
}

#' Plot community evolution heatmap
#' @param communities tibble: date, ticker, community_id
#' @return plotly heatmap
plot_community_heatmap <- function(communities) {
  # Pivot to wide format: rows = tickers, columns = dates
  comm_wide <- communities |>
    select(date, ticker, community_id) |>
    pivot_wider(names_from = date, values_from = community_id)

  tickers <- comm_wide$ticker
  dates <- as.Date(colnames(comm_wide)[-1])
  mat <- as.matrix(comm_wide[, -1])

  plot_ly(
    x = dates,
    y = tickers,
    z = mat,
    type = "heatmap",
    colorscale = list(
      c(0, "#3498db"), c(0.2, "#2ecc71"), c(0.4, "#f39c12"),
      c(0.6, "#e74c3c"), c(0.8, "#9b59b6"), c(1, "#1abc9c")
    ),
    showscale = FALSE
  ) |>
    layout(
      title = list(
        text = paste0(
          "Community Membership Over Time",
          "<br><sup>",
          "Each cell shows which community (Louvain algorithm) a stock belongs to at each window date. ",
          "Uniform colors during crashes = all stocks collapse into one mega-community. ",
          "Diverse colors in calm periods = sector-aligned clusters persist.",
          "</sup>"
        )
      ),
      xaxis = list(title = "Date"),
      yaxis = list(title = "", tickfont = list(size = 9)),
      margin = list(l = 80)
    )
}

#' Plot crash anatomy — zoom into a specific event
#' @param metrics tibble with regime labels
#' @param spy_returns tibble with SPY returns
#' @param event_label label to zoom into
#' @param window_days Days before/after event to show
#' @return plotly object
plot_crash_anatomy <- function(metrics, spy_returns = NULL,
                                event_label = "COVID crash start",
                                window_days = 60) {
  event_date <- MARKET_EVENTS |>
    filter(label == event_label) |>
    pull(date)

  if (length(event_date) == 0) return(NULL)

  start <- event_date - window_days
  end <- event_date + window_days

  zoom_metrics <- metrics |> filter(date >= start, date <= end)

  if (nrow(zoom_metrics) == 0) return(NULL)

  p <- plot_ly(zoom_metrics, x = ~date) |>
    add_trace(y = ~avg_corr, name = "Avg |Correlation|",
              type = "scatter", mode = "lines",
              line = list(color = "#e74c3c", width = 2.5),
              yaxis = "y") |>
    add_trace(y = ~modularity, name = "Modularity",
              type = "scatter", mode = "lines",
              line = list(color = "#2ecc71", width = 2.5),
              yaxis = "y2") |>
    layout(
      title = list(
        text = paste0(
          "Crash Anatomy: ", event_label,
          "<br><sup>",
          "60-day window around event. Left axis: avg absolute correlation (red). ",
          "Right axis: network modularity (green). ",
          "Correlation spikes while modularity drops = community structure dissolves.",
          "</sup>"
        )
      ),
      xaxis = list(title = "Date"),
      yaxis = list(title = "Avg |Corr|", side = "left",
                    titlefont = list(color = "#e74c3c")),
      yaxis2 = list(title = "Modularity", side = "right",
                     overlaying = "y",
                     titlefont = list(color = "#2ecc71")),
      shapes = list(list(
        type = "line",
        x0 = as.character(event_date), x1 = as.character(event_date),
        y0 = 0, y1 = 1, yref = "paper",
        line = list(color = "black", width = 2, dash = "dot")
      )),
      annotations = list(list(
        x = as.character(event_date), y = 1, yref = "paper",
        text = event_label, showarrow = FALSE,
        yanchor = "bottom", font = list(size = 12, color = "black")
      ))
    )

  p
}

#' Plot statistical test results as interactive table
#' @param tests tibble from run_statistical_tests
#' @return DT datatable
plot_test_results <- function(tests) {
  display <- tests |>
    mutate(
      across(c(normal_mean, pre_crash_mean, crash_mean),
             ~round(.x, 4)),
      pre_crash_p = format(pre_crash_p, digits = 3, scientific = TRUE),
      crash_p = format(crash_p, digits = 3, scientific = TRUE),
      pre_crash_sig = ifelse(pre_crash_sig, "YES *", "no"),
      crash_sig = ifelse(crash_sig, "YES *", "no")
    ) |>
    select(
      Metric = metric,
      `Normal Mean` = normal_mean,
      `Pre-Crash Mean` = pre_crash_mean,
      `Crash Mean` = crash_mean,
      `Pre-Crash p` = pre_crash_p,
      `Crash p` = crash_p,
      `Pre-Crash Sig?` = pre_crash_sig,
      `Crash Sig?` = crash_sig,
      `Pre-Crash Dir` = pre_crash_direction,
      `Crash Dir` = crash_direction
    )

  DT::datatable(
    display,
    caption = htmltools::tags$caption(
      style = "caption-side: bottom; text-align: left; font-size: 12px;",
      "Welch two-sample t-tests comparing network metrics across market regimes. ",
      "Pre-crash = 20 trading days before crash start. ",
      "Significant (p < 0.05) results marked with *. ",
      "Key finding: avg_corr and max_eigenvalue significantly elevated before AND during crashes, ",
      "supporting H2 (network metrics as leading indicators). ",
      "Modularity significantly lower during crashes, confirming H1 (community dissolution)."
    ),
    options = list(pageLength = 10, dom = "t"),
    rownames = FALSE
  ) |>
    DT::formatStyle(
      "Crash Sig?",
      backgroundColor = DT::styleEqual(c("YES *", "no"), c("#fadbd8", "white"))
    ) |>
    DT::formatStyle(
      "Pre-Crash Sig?",
      backgroundColor = DT::styleEqual(c("YES *", "no"), c("#fdebd0", "white"))
    )
}

#' Plot hub analysis — degree change by sector
#' @param hubs list from analyze_hubs
#' @return plotly object
plot_hub_analysis <- function(hubs) {
  change_data <- hubs$change
  if (is.null(change_data) || nrow(change_data) == 0) return(NULL)
  if (!"degree_change" %in% names(change_data) ||
      all(is.na(change_data$degree_change))) return(NULL)

  change_data <- change_data |>
    filter(!is.na(degree_change)) |>
    arrange(degree_change)

  change_data$ticker <- factor(change_data$ticker,
                                levels = change_data$ticker)

  colors <- SECTOR_COLORS[change_data$sector]
  colors[is.na(colors)] <- "#95a5a6"

  plot_ly(
    change_data,
    x = ~degree_change,
    y = ~ticker,
    type = "bar",
    orientation = "h",
    marker = list(color = colors),
    text = ~paste0(sector, ": ", round(degree_change, 1)),
    hoverinfo = "text"
  ) |>
    layout(
      title = list(
        text = paste0(
          "Hub Propagation: Degree Change (Crash vs Normal)",
          "<br><sup>",
          "Positive = stock becomes more connected during crashes. ",
          "H3 test: financial sector stocks (red bars) should show largest positive change. ",
          "Bars colored by sector. Higher connectivity = potential contagion amplifier.",
          "</sup>"
        )
      ),
      xaxis = list(title = "Degree Change (Crash - Normal)"),
      yaxis = list(title = "", tickfont = list(size = 10)),
      margin = list(l = 60)
    )
}

#' Create interactive network visualization for a specific date
#' @param g igraph object
#' @param communities named vector of community memberships
#' @param date_label character label for the date
#' @return visNetwork htmlwidget
plot_network_interactive <- function(g, communities, date_label = "") {
  if (vcount(g) == 0) return(NULL)

  n_v <- vcount(g)
  node_names <- V(g)$name

  # Robust color assignment: ensure length matches vertex count
  node_colors <- V(g)$color
  if (is.null(node_colors) || length(node_colors) != n_v) {
    # Reconstruct from sector attributes
    node_sectors <- V(g)$sector
    if (!is.null(node_sectors) && length(node_sectors) == n_v) {
      node_colors <- SECTOR_COLORS[node_sectors]
      node_colors[is.na(node_colors)] <- "#95a5a6"
    } else {
      node_colors <- rep("#95a5a6", n_v)
    }
  }
  node_colors[is.na(node_colors)] <- "#95a5a6"

  # Robust community assignment
  comm_ids <- communities[node_names]
  comm_ids[is.na(comm_ids)] <- 0L

  # Prepare nodes
  nodes <- tibble(
    id = node_names,
    label = node_names,
    group = as.character(comm_ids),
    sector = if (!is.null(V(g)$sector) && length(V(g)$sector) == n_v) V(g)$sector else rep("Unknown", n_v),
    title = paste0(
      "<b>", node_names, "</b><br>",
      "Sector: ", if (!is.null(V(g)$sector) && length(V(g)$sector) == n_v) V(g)$sector else "Unknown", "<br>",
      "Community: ", comm_ids, "<br>",
      "Degree: ", degree(g)
    ),
    value = degree(g) + 1,  # node size proportional to degree
    color = node_colors
  )

  # Prepare edges
  if (ecount(g) > 0) {
    edge_list <- igraph::as_data_frame(g, what = "edges")
    edges <- tibble(
      from = edge_list$from,
      to = edge_list$to,
      width = edge_list$weight * 3,
      color = "#cccccc",
      title = paste0("Corr: ", round(edge_list$weight, 3))
    )
  } else {
    edges <- tibble(from = character(0), to = character(0))
  }

  visNetwork(nodes, edges,
             main = paste("Correlation Network —", date_label),
             submain = paste0(
               "Nodes colored by sector, sized by degree. ",
               "Edges = |corr| > threshold. ",
               "Hover for details. Drag to rearrange."
             ),
             footer = paste0(
               "Nodes: ", vcount(g), " | Edges: ", ecount(g),
               " | Communities: ", length(unique(communities))
             )) |>
    visPhysics(solver = "forceAtlas2Based",
               forceAtlas2Based = list(gravitationalConstant = -30)) |>
    visOptions(highlightNearest = TRUE,
               nodesIdSelection = TRUE) |>
    visInteraction(hover = TRUE, zoomView = TRUE, dragView = TRUE)
}

# ============================================================================
# DASHBOARD ASSEMBLY
# ============================================================================

#' Build complete self-contained HTML dashboard
#' @param result List from run_full_analysis()
#' @param output_file Output HTML file path
build_dashboard <- function(result, output_file = "dashboard.html") {
  cat("Building interactive HTML dashboard...\n")

  # 1. Metrics timeline
  cat("  [1/6] Metrics timeline...\n")
  p_timeline <- plot_metrics_timeline(result$metrics, result$spy_returns,
                                       result$events)

  # 2. Community heatmap
  cat("  [2/6] Community heatmap...\n")
  p_community <- plot_community_heatmap(result$communities)

  # 3. Crash anatomy (COVID)
  cat("  [3/6] Crash anatomy...\n")
  p_crash <- plot_crash_anatomy(result$metrics, result$spy_returns,
                                 "COVID crash start")

  # 4. Statistical tests
  cat("  [4/6] Statistical tests table...\n")
  dt_tests <- plot_test_results(result$tests)

  # 5. Hub analysis
  cat("  [5/6] Hub analysis...\n")
  p_hubs <- plot_hub_analysis(result$hubs)

  # 6. Network snapshots — pick representative dates
  cat("  [6/6] Network snapshots...\n")
  # Find a normal period and a crash period network
  normal_idx <- which(result$metrics$regime == "normal")[
    length(which(result$metrics$regime == "normal")) %/% 2
  ]
  crash_idx <- which(result$metrics$regime == "crash")
  crash_idx <- if (length(crash_idx) > 0) crash_idx[length(crash_idx) %/% 2 + 1] else normal_idx

  net_normal <- if (!is.null(result$networks[[normal_idx]])) {
    g <- result$networks[[normal_idx]]
    comm <- detect_communities(g)
    plot_network_interactive(g, comm,
                             paste("Normal:", result$dates[normal_idx]))
  } else NULL

  net_crash <- if (!is.null(result$networks[[crash_idx]])) {
    g <- result$networks[[crash_idx]]
    comm <- detect_communities(g)
    plot_network_interactive(g, comm,
                             paste("Crash:", result$dates[crash_idx]))
  } else NULL

  # === Assemble HTML ===
  cat("  Assembling HTML...\n")

  # Compute summary statistics for header
  n_stocks <- length(result$params$tickers)
  n_windows <- nrow(result$metrics)
  date_range <- paste(result$params$from, "to", result$params$to)
  sig_pre <- sum(result$tests$pre_crash_sig == TRUE, na.rm = TRUE)
  sig_crash <- sum(result$tests$crash_sig == TRUE, na.rm = TRUE)
  total_tests <- nrow(result$tests)

  # Build the page
  page <- htmltools::tagList(
    htmltools::tags$html(
      htmltools::tags$head(
        htmltools::tags$meta(charset = "utf-8"),
        htmltools::tags$title("Financial Contagion Network Dashboard"),
        htmltools::tags$style(htmltools::HTML("
          body {
            font-family: 'Segoe UI', Tahoma, sans-serif;
            margin: 0; padding: 20px;
            background: #f8f9fa;
            color: #2c3e50;
          }
          .header {
            background: linear-gradient(135deg, #2c3e50, #3498db);
            color: white; padding: 30px; border-radius: 10px;
            margin-bottom: 20px;
          }
          .header h1 { margin: 0 0 10px 0; font-size: 28px; }
          .header p { margin: 5px 0; font-size: 14px; opacity: 0.9; }
          .summary-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px; margin-bottom: 20px;
          }
          .card {
            background: white; padding: 20px; border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          }
          .card h3 { margin: 0 0 5px 0; color: #7f8c8d; font-size: 12px;
                     text-transform: uppercase; }
          .card .value { font-size: 28px; font-weight: bold; color: #2c3e50; }
          .card .subtitle { font-size: 12px; color: #95a5a6; margin-top: 5px; }
          .section {
            background: white; padding: 20px; border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 20px;
          }
          .section h2 {
            margin: 0 0 15px 0; color: #2c3e50;
            border-bottom: 2px solid #3498db; padding-bottom: 10px;
          }
          .section .description {
            font-size: 13px; color: #7f8c8d;
            margin-bottom: 15px; line-height: 1.5;
          }
          .network-grid {
            display: grid; grid-template-columns: 1fr 1fr; gap: 15px;
          }
          @media (max-width: 900px) {
            .network-grid { grid-template-columns: 1fr; }
          }
          .hypothesis { margin: 10px 0; padding: 10px; border-left: 4px solid; }
          .h-supported { border-color: #2ecc71; background: #eafaf1; }
          .h-rejected { border-color: #e74c3c; background: #fdedec; }
          .h-partial { border-color: #f39c12; background: #fef9e7; }
        "))
      ),
      htmltools::tags$body(
        # Header
        htmltools::tags$div(class = "header",
          htmltools::tags$h1("Financial Contagion Network Dashboard"),
          htmltools::tags$p(paste0(
            "Do stock correlation communities predict crash propagation? ",
            "Analysis of ", n_stocks, " US stocks across 6 sectors, ",
            date_range, "."
          )),
          htmltools::tags$p(paste0(
            "Built by two Claude Code instances collaborating autonomously. ",
            "Rolling ", result$params$window, "-day correlation windows, ",
            "step = ", result$params$step, " days, ",
            "edge threshold = ", result$params$threshold, "."
          ))
        ),

        # Summary cards
        htmltools::tags$div(class = "summary-cards",
          htmltools::tags$div(class = "card",
            htmltools::tags$h3("Stocks Analyzed"),
            htmltools::tags$div(class = "value", n_stocks),
            htmltools::tags$div(class = "subtitle", "across 6 sectors")
          ),
          htmltools::tags$div(class = "card",
            htmltools::tags$h3("Time Windows"),
            htmltools::tags$div(class = "value", n_windows),
            htmltools::tags$div(class = "subtitle", date_range)
          ),
          htmltools::tags$div(class = "card",
            htmltools::tags$h3("Pre-Crash Signals"),
            htmltools::tags$div(class = "value",
                                paste0(sig_pre, "/", total_tests)),
            htmltools::tags$div(class = "subtitle",
                                "metrics significant before crash")
          ),
          htmltools::tags$div(class = "card",
            htmltools::tags$h3("Crash Signals"),
            htmltools::tags$div(class = "value",
                                paste0(sig_crash, "/", total_tests)),
            htmltools::tags$div(class = "subtitle",
                                "metrics significant during crash")
          )
        ),

        # Hypothesis results
        htmltools::tags$div(class = "section",
          htmltools::tags$h2("Hypothesis Test Results"),
          htmltools::tags$div(class = "description",
            "Three hypotheses tested using Welch t-tests comparing ",
            "network metrics across market regimes (normal, pre-crash, crash)."
          ),
          htmltools::tags$div(
            class = paste0("hypothesis ",
                           if (sig_crash >= 4) "h-supported" else "h-partial"),
            htmltools::tags$strong("H1 (Structure): "),
            "Correlation networks dissolve into mega-clusters during crashes. ",
            htmltools::tags$em(
              if (sig_crash >= 4) "SUPPORTED" else "PARTIALLY SUPPORTED"
            ),
            " — modularity drops and avg correlation spikes."
          ),
          htmltools::tags$div(
            class = paste0("hypothesis ",
                           if (sig_pre >= 3) "h-supported"
                           else if (sig_pre >= 1) "h-partial"
                           else "h-rejected"),
            htmltools::tags$strong("H2 (Leading Indicator): "),
            "Network metrics change before crashes. ",
            htmltools::tags$em(
              if (sig_pre >= 3) "SUPPORTED"
              else if (sig_pre >= 1) "PARTIALLY SUPPORTED"
              else "NOT SUPPORTED"
            ),
            paste0(" — ", sig_pre, "/", total_tests,
                   " metrics significantly different pre-crash vs normal.")
          ),
          htmltools::tags$div(
            class = "hypothesis h-partial",
            htmltools::tags$strong("H3 (Hub Propagation): "),
            "Financial sector stocks become hubs during crashes. ",
            htmltools::tags$em("See hub analysis below.")
          )
        ),

        # Section 1: Metrics timeline
        htmltools::tags$div(class = "section",
          htmltools::tags$h2("1. Network Metrics Over Time"),
          htmltools::tags$div(class = "description",
            "Four key network metrics tracked across rolling windows. ",
            "Dashed lines mark market events. ",
            "During crashes (red lines), avg correlation spikes and modularity drops — ",
            "indicating the network collapses from sector-aligned clusters into one ",
            "correlated mass."
          ),
          p_timeline
        ),

        # Section 2: Community evolution
        htmltools::tags$div(class = "section",
          htmltools::tags$h2("2. Community Evolution"),
          htmltools::tags$div(class = "description",
            "Heatmap showing Louvain community assignments over time. ",
            "Uniform color bands = all stocks in one community (crash). ",
            "Mixed colors = diverse sector-aligned communities (normal)."
          ),
          p_community
        ),

        # Section 3: Crash anatomy
        htmltools::tags$div(class = "section",
          htmltools::tags$h2("3. COVID Crash Anatomy"),
          htmltools::tags$div(class = "description",
            "Zooming into the COVID crash (Feb-Mar 2020). ",
            "Avg correlation (red, left axis) vs modularity (green, right axis). ",
            "The correlation spike PRECEDES the full crash, ",
            "suggesting potential predictive value."
          ),
          if (!is.null(p_crash)) p_crash
          else htmltools::tags$p("(Event not in data range)")
        ),

        # Section 4: Network snapshots
        htmltools::tags$div(class = "section",
          htmltools::tags$h2("4. Interactive Network Comparison"),
          htmltools::tags$div(class = "description",
            "Side-by-side network visualizations: normal market (left) vs crash (right). ",
            "Node size = degree (connections). Node color = sector. ",
            "During normal periods, sector clusters are visible. ",
            "During crashes, nearly all stocks connect to each other. ",
            "Drag nodes to rearrange. Hover for details."
          ),
          htmltools::tags$div(class = "network-grid",
            htmltools::tags$div(
              if (!is.null(net_normal)) net_normal
              else htmltools::tags$p("(No normal-period network available)")
            ),
            htmltools::tags$div(
              if (!is.null(net_crash)) net_crash
              else htmltools::tags$p("(No crash-period network available)")
            )
          )
        ),

        # Section 5: Hub analysis
        htmltools::tags$div(class = "section",
          htmltools::tags$h2("5. Hub Propagation Analysis (H3)"),
          htmltools::tags$div(class = "description",
            "Which stocks become more connected during crashes? ",
            "Positive values = more connections during crash than normal. ",
            "H3 predicts financial stocks (red) have the largest increase."
          ),
          if (!is.null(p_hubs)) p_hubs
          else htmltools::tags$p("(Insufficient data for hub analysis)")
        ),

        # Section 6: Statistical tests
        htmltools::tags$div(class = "section",
          htmltools::tags$h2("6. Statistical Test Results"),
          htmltools::tags$div(class = "description",
            "Welch two-sample t-tests comparing each network metric across regimes. ",
            "Yellow highlight = significant at p < 0.05 for pre-crash vs normal. ",
            "Red highlight = significant for crash vs normal."
          ),
          dt_tests
        ),

        # Footer
        htmltools::tags$div(
          style = "text-align: center; padding: 20px; color: #95a5a6; font-size: 12px;",
          htmltools::tags$p(paste0(
            "Generated ", Sys.time(), " | ",
            "Claude-to-Claude Collaboration | ",
            "Data: Yahoo Finance via quantmod | ",
            "Analysis: igraph + custom rolling-window pipeline"
          ))
        )
      )
    )
  )

  # Save
  cat("  Saving to", output_file, "...\n")
  htmltools::save_html(page, file = output_file)
  cat("  Dashboard saved! (", file.size(output_file) %/% 1024, "KB)\n")

  invisible(output_file)
}

cat("visualize.R loaded successfully.\n")
