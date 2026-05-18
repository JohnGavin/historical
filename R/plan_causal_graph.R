# Plan: Expert Causal DAG for strategy/factor/macro relationships (#80 Phase 1)
#
# Encodes the causal assumptions underlying the portfolio:
#   - Fama-French factors (HML, SMB, Mom, RMW, CMA) as exogenous nodes
#   - Macro signals (VIX, VVIX, Fed rate, Inflation) → regime states
#   - Regime states → overlay signals → returns
#   - Factor crowding / premium decay as structural decay paths
#   - Portfolio outcomes (return, drawdown, Sharpe)
#
# Uses igraph for graph representation and computes partial-correlation
# tests of 5 key conditional independence implications.
#
# References: Pearl (2009) Causality; Hauser & Buhlmann (2012).

plan_causal_graph <- function() {
  list(

    # ── Parameters: node positions + edge list ─────────────────────
    targets::tar_target(cg_params, {
      list(
        # ── Edge list (directed causal claims) ─────────────────────
        edges = rbind(
          # Factors → Strategy signals
          c("HML",              "DRIF_signal"),
          c("SMB",              "DRIF_signal"),
          c("Mom",              "DRIF_signal"),
          c("RMW",              "DRIF_signal"),
          c("HML",              "FacMAX_signal"),
          c("SMB",              "FacMAX_signal"),
          c("Mom",              "FacMAX_signal"),
          c("Mom",              "LTR_signal"),
          c("SMB",              "LTR_signal"),
          # Crisis transmission: VIX affects value factor (violated implication)
          c("VIX_level", "HML"),
          # Macro → Regime
          c("VIX_level",        "Vol_regime"),
          c("VIX_term_struct",  "Vol_regime"),
          c("VVIX",             "Vol_regime"),
          c("Fed_rate",         "Rate_regime"),
          c("Inflation",        "Rate_regime"),
          # Regime → Overlay signals
          c("Vol_regime",       "RSC_signal"),
          c("Vol_regime",       "VIX_overlay_signal"),
          # Rate_regime → macro strategy
          c("Rate_regime",      "LTR_signal"),
          # Signals → Returns
          c("DRIF_signal",      "DRIF_return"),
          c("FacMAX_signal",    "FacMAX_return"),
          c("LTR_signal",       "LTR_return"),
          c("RSC_signal",       "Market_return"),
          c("VIX_overlay_signal", "Market_return"),
          c("Mkt_RF",           "Market_return"),
          c("Mkt_RF",           "DRIF_return"),
          c("Mkt_RF",           "FacMAX_return"),
          c("Mkt_RF",           "LTR_return"),
          # Structural decay
          c("Factor_crowding",  "Premium_decay"),
          c("Premium_decay",    "FacMAX_return"),
          c("Premium_decay",    "DRIF_return"),
          # Returns → Portfolio
          c("DRIF_return",      "Portfolio_return"),
          c("FacMAX_return",    "Portfolio_return"),
          c("LTR_return",       "Portfolio_return"),
          c("Market_return",    "Portfolio_return"),
          c("Rebalance_cost",   "Portfolio_return"),
          # Portfolio → Outcomes
          c("Portfolio_return", "Sharpe"),
          c("Portfolio_return", "Max_drawdown"),
          c("Vol_regime",       "Max_drawdown")
        ),
        # Node layer labels (used for vertex colouring in plot)
        node_layers = list(
          factor    = c("HML", "SMB", "Mom", "RMW", "CMA", "Mkt_RF"),
          macro     = c("VIX_level", "VIX_term_struct", "VVIX",
                        "Fed_rate", "Inflation"),
          regime    = c("Vol_regime", "Rate_regime"),
          signal    = c("DRIF_signal", "FacMAX_signal", "LTR_signal",
                        "RSC_signal", "VIX_overlay_signal"),
          `return`  = c("DRIF_return", "FacMAX_return", "LTR_return",
                        "Market_return"),
          outcome   = c("Portfolio_return", "Max_drawdown", "Sharpe"),
          structural = c("Factor_crowding", "Premium_decay", "Rebalance_cost")
        ),
        # ── Conditional independence implications to test ───────────
        implications = list(
          list(
            label = "DRIF_return ⊥ LTR_return | Mkt_RF",
            x = "DRIF_return",
            y = "LTR_return",
            z = c("Mkt_RF")
          ),
          list(
            label = "VIX_level ⊥ DRIF_return | Vol_regime",
            x = "VIX_level",
            y = "DRIF_return",
            z = c("Vol_regime")
          ),
          list(
            label = "HML ⊥ VIX_level",
            x = "HML",
            y = "VIX_level",
            z = character(0)
          ),
          list(
            label = "FacMAX_return ⊥ LTR_return | Mom + SMB",
            x = "FacMAX_return",
            y = "LTR_return",
            z = c("Mom", "SMB")
          ),
          list(
            label = "Fed_rate ⊥ DRIF_return | Rate_regime",
            x = "Fed_rate",
            y = "DRIF_return",
            z = c("Rate_regime")
          )
        )
      )
    }),

    # ── Build the igraph DAG ────────────────────────────────────────
    targets::tar_target(cg_dag, {
      library(igraph)

      el <- cg_params$edges
      g <- igraph::graph_from_edgelist(el, directed = TRUE)

      # Attach layer attribute to each vertex
      for (layer_name in names(cg_params$node_layers)) {
        nodes <- cg_params$node_layers[[layer_name]]
        for (nd in nodes) {
          if (nd %in% igraph::V(g)$name) {
            igraph::V(g)[nd]$layer <- layer_name
          }
        }
      }

      list(
        graph        = g,
        n_nodes      = igraph::vcount(g),
        n_edges      = igraph::ecount(g),
        is_dag       = igraph::is_dag(g),
        node_names   = igraph::V(g)$name,
        edge_list    = igraph::as_edgelist(g)
      )
    }),

    # ── Assemble test data for conditional independence tests ───────
    targets::tar_target(cg_test_data, {
      library(dplyr)

      # ── Fama-French factors (monthly, %) → proportions ───────────
      ff5 <- hd_factors(dataset = "FF5", frequency = "monthly") |>
        dplyr::mutate(date = as.Date(date),
                      value = value / 100) |>
        dplyr::select(date, factor_name, value)

      # Mom only available daily — compound to monthly
      mom <- hd_factors(dataset = "Mom", frequency = "daily") |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::filter(factor_name == "Mom") |>
        dplyr::mutate(ym = format(date, "%Y-%m")) |>
        dplyr::summarise(
          value = (prod(1 + value / 100) - 1),
          .by = c(ym, factor_name)
        ) |>
        dplyr::mutate(date = as.Date(paste0(ym, "-01"))) |>
        dplyr::select(date, factor_name, value)

      factors_wide <- dplyr::bind_rows(ff5, mom) |>
        dplyr::filter(factor_name %in%
                        c("HML", "SMB", "Mom", "Mkt-RF", "RF")) |>
        tidyr::pivot_wider(names_from = factor_name,
                           values_from = value) |>
        dplyr::rename(Mkt_RF = `Mkt-RF`)

      # ── VIX (daily → monthly mean) ───────────────────────────────
      vix_monthly <- hd_macro("VIXCLS") |>
        dplyr::mutate(date = as.Date(date),
                      ym   = format(date, "%Y-%m")) |>
        dplyr::summarise(VIX_level = mean(value, na.rm = TRUE),
                         .by = ym) |>
        dplyr::mutate(date = as.Date(paste0(ym, "-01"))) |>
        dplyr::select(date, VIX_level)

      # ── Fed funds rate (daily → monthly mean) ────────────────────
      fed_monthly <- tryCatch({
        hd_macro("FEDFUNDS") |>
          dplyr::mutate(date = as.Date(date),
                        ym   = format(date, "%Y-%m")) |>
          dplyr::summarise(Fed_rate = mean(value, na.rm = TRUE),
                           .by = ym) |>
          dplyr::mutate(date = as.Date(paste0(ym, "-01"))) |>
          dplyr::select(date, Fed_rate)
      }, error = function(e) {
        cli::cli_warn("FEDFUNDS not available: {conditionMessage(e)}")
        NULL
      })

      # ── Strategy returns from falsification bridge targets ────────
      # Strategy dates may be mid-month (15th) — normalise to 1st of month
      drif_ret <- fals_drif_input |>
        dplyr::mutate(date = as.Date(paste0(format(as.Date(date), "%Y-%m"), "-01"))) |>
        dplyr::select(date, DRIF_return = strategy_ret)

      fac_max_ret <- fals_fac_max_input |>
        dplyr::mutate(date = as.Date(paste0(format(as.Date(date), "%Y-%m"), "-01"))) |>
        dplyr::select(date, FacMAX_return = strategy_ret)

      ltr_ret <- fals_ltr_input |>
        dplyr::mutate(date = as.Date(paste0(format(as.Date(date), "%Y-%m"), "-01"))) |>
        dplyr::select(date, LTR_return = strategy_ret)

      # ── Build Vol_regime proxy: VIX > 20 = high ──────────────────
      # (1 = high vol, 0 = low vol)
      vix_regime <- vix_monthly |>
        dplyr::mutate(Vol_regime = as.numeric(VIX_level > 20))

      # ── Build Rate_regime proxy: Fed > median = high ──────────────
      rate_regime <- if (!is.null(fed_monthly)) {
        med_fed <- median(fed_monthly$Fed_rate, na.rm = TRUE)
        fed_monthly |>
          dplyr::mutate(Rate_regime = as.numeric(Fed_rate > med_fed))
      } else {
        NULL
      }

      # ── Inner join on common dates ────────────────────────────────
      base <- factors_wide |>
        dplyr::inner_join(vix_regime, by = "date") |>
        dplyr::inner_join(drif_ret,   by = "date") |>
        dplyr::inner_join(fac_max_ret, by = "date") |>
        dplyr::inner_join(ltr_ret,    by = "date")

      if (!is.null(rate_regime)) {
        base <- base |>
          dplyr::left_join(rate_regime |>
                             dplyr::select(date, Rate_regime, Fed_rate),
                           by = "date")
      } else {
        base <- base |>
          dplyr::mutate(Rate_regime = NA_real_,
                        Fed_rate    = NA_real_)
      }

      base |>
        dplyr::arrange(date) |>
        dplyr::filter(dplyr::if_all(
          c("Mkt_RF", "HML", "SMB", "Mom",
            "VIX_level", "DRIF_return", "FacMAX_return", "LTR_return"),
          ~ !is.na(.)))
    }),

    # ── Test conditional independence implications ──────────────────
    targets::tar_target(cg_test_implications, {
      library(dplyr)

      # Partial correlation: residualise X and Y on Z, then correlate
      partial_cor <- function(df, x_col, y_col, z_cols) {
        x_vec <- df[[x_col]]
        y_vec <- df[[y_col]]

        if (length(z_cols) == 0) {
          # Marginal correlation (no conditioning)
          cor(x_vec, y_vec, use = "complete.obs")
        } else {
          # Check all Z columns are present
          missing_z <- setdiff(z_cols, names(df))
          if (length(missing_z) > 0) return(NA_real_)

          # Drop rows with any NA in x, y, or z
          keep <- stats::complete.cases(df[, c(x_col, y_col, z_cols)])
          if (sum(keep) < 20) return(NA_real_)

          sub <- df[keep, ]
          Z  <- as.matrix(sub[, z_cols, drop = FALSE])
          rx <- stats::residuals(stats::lm(sub[[x_col]] ~ Z))
          ry <- stats::residuals(stats::lm(sub[[y_col]] ~ Z))
          cor(rx, ry)
        }
      }

      implications <- cg_params$implications

      results <- purrr::map_dfr(implications, function(impl) {
        # Map DAG node names to column names in test data
        col_map <- c(
          DRIF_return   = "DRIF_return",
          LTR_return    = "LTR_return",
          FacMAX_return = "FacMAX_return",
          Mkt_RF        = "Mkt_RF",
          HML           = "HML",
          SMB           = "SMB",
          Mom           = "Mom",
          VIX_level     = "VIX_level",
          Vol_regime    = "Vol_regime",
          Rate_regime   = "Rate_regime",
          Fed_rate      = "Fed_rate"
        )

        x_col <- col_map[impl$x]
        y_col <- col_map[impl$y]
        z_cols <- col_map[impl$z]
        z_cols <- z_cols[!is.na(z_cols)]

        # Skip if any required column is absent or all-NA
        req_cols <- c(x_col, y_col, z_cols)
        req_cols <- req_cols[!is.na(req_cols)]
        available <- req_cols %in% names(cg_test_data) &
          vapply(req_cols, function(cn) {
            if (!cn %in% names(cg_test_data)) return(FALSE)
            any(!is.na(cg_test_data[[cn]]))
          }, logical(1))

        if (!all(available)) {
          return(dplyr::tibble(
            label         = impl$label,
            partial_cor   = NA_real_,
            status        = "skipped (data unavailable)",
            holds         = NA
          ))
        }

        pc <- partial_cor(cg_test_data, x_col, y_col, z_cols)

        status <- dplyr::case_when(
          is.na(pc)          ~ "skipped (insufficient data)",
          abs(pc) < 0.05     ~ "holds (|r| < 0.05)",
          abs(pc) < 0.15     ~ "marginal (0.05 ≤ |r| < 0.15)",
          TRUE               ~ "violated (|r| ≥ 0.15)"
        )

        dplyr::tibble(
          label       = impl$label,
          partial_cor = round(pc, 4),
          status      = status,
          holds       = !is.na(pc) & abs(pc) < 0.15
        )
      })

      list(
        results         = results,
        n_implications  = nrow(results),
        n_tested        = sum(!is.na(results$partial_cor)),
        n_holds         = sum(results$holds, na.rm = TRUE),
        n_violated      = sum(!results$holds & !is.na(results$holds)),
        n_skipped       = sum(is.na(results$holds))
      )
    }),

    # ── Pre/post-2010 split test for HML ⊥ VIX ────────────────────
    targets::tar_target(cg_test_split, {
      library(dplyr)

      d <- cg_test_data
      if (nrow(d) < 48) return(list(pre = NULL, post = NULL, comparison = NULL))

      split_date <- as.Date("2010-01-01")
      d_pre  <- d |> filter(date < split_date)
      d_post <- d |> filter(date >= split_date)

      # Partial correlation helper (same as in cg_test_implications)
      partial_cor <- function(x, y, z_mat) {
        if (length(x) < 20 || all(is.na(x)) || all(is.na(y))) return(NA_real_)
        if (is.null(z_mat) || ncol(z_mat) == 0) return(cor(x, y, use = "complete.obs"))
        complete <- complete.cases(cbind(x, y, z_mat))
        if (sum(complete) < 20) return(NA_real_)
        x <- x[complete]; y <- y[complete]; z_mat <- z_mat[complete, , drop = FALSE]
        rx <- residuals(lm(x ~ z_mat))
        ry <- residuals(lm(y ~ z_mat))
        cor(rx, ry)
      }

      # Test the key violated implication (HML ⊥ VIX) in each period
      test_period <- function(dat, label) {
        if (nrow(dat) < 20) return(tibble::tibble(period = label, n = nrow(dat),
                                                   hml_vix_r = NA_real_))
        r <- partial_cor(dat$HML, dat$VIX_level, NULL)
        tibble::tibble(period = label, n = nrow(dat), hml_vix_r = round(r, 3))
      }

      pre  <- test_period(d_pre, "Pre-2010")
      post <- test_period(d_post, "2010+")
      full <- test_period(d, "Full")

      comparison <- bind_rows(pre, post, full)

      list(
        comparison = comparison,
        strengthened = !is.na(post$hml_vix_r) && !is.na(pre$hml_vix_r) &&
                       abs(post$hml_vix_r) > abs(pre$hml_vix_r)
      )
    }),

    # ── Plot the DAG ────────────────────────────────────────────────
    targets::tar_target(cg_plot, {
      library(igraph)
      library(ggplot2)

      g <- cg_dag$graph

      # Layer → colour mapping (dark theme)
      layer_colours <- c(
        factor     = "#4e9af1",   # blue
        macro      = "#f1c84e",   # gold
        regime     = "#f17c4e",   # orange
        signal     = "#a14ef1",   # purple
        `return`   = "#4ef18a",   # green
        outcome    = "#f14e6e",   # red
        structural = "#888888"    # grey
      )

      node_layer <- igraph::V(g)$layer
      node_layer[is.na(node_layer)] <- "structural"
      vertex_colour <- layer_colours[node_layer]

      # Approximate y-layout by layer depth
      y_map <- c(
        factor     = 6,
        macro      = 5,
        regime     = 4,
        signal     = 3,
        `return`   = 2,
        outcome    = 1,
        structural = 3.5
      )
      y_pos <- y_map[node_layer]

      # x-position: spread within each layer
      x_pos <- stats::ave(
        seq_along(igraph::V(g)),
        node_layer,
        FUN = function(idx) {
          n <- length(idx)
          seq(1, n) / (n + 1)
        }
      )

      lay <- cbind(x_pos, y_pos)

      p <- ggplot2::ggplot() +
        ggplot2::theme_void() +
        ggplot2::theme(
          plot.background  = ggplot2::element_rect(fill = "#0a0a0a", colour = NA),
          panel.background = ggplot2::element_rect(fill = "#0a0a0a", colour = NA),
          plot.title       = ggplot2::element_text(colour = "#ffffff",
                                                   size = 14, face = "bold",
                                                   hjust = 0.5),
          plot.subtitle    = ggplot2::element_text(colour = "#aaaaaa",
                                                   size = 9, hjust = 0.5),
          legend.text      = ggplot2::element_text(colour = "#cccccc",
                                                   size = 8),
          legend.title     = ggplot2::element_text(colour = "#cccccc",
                                                   size = 9),
          legend.background = ggplot2::element_rect(fill = "#0a0a0a",
                                                    colour = NA)
        )

      # Build edges data frame
      edge_df <- as.data.frame(igraph::as_edgelist(g),
                               stringsAsFactors = FALSE)
      names(edge_df) <- c("from", "to")
      vdf <- data.frame(name = igraph::V(g)$name,
                        x = lay[, 1],
                        y = lay[, 2],
                        layer = node_layer,
                        stringsAsFactors = FALSE)

      edge_plot <- dplyr::left_join(edge_df,
                                    vdf[, c("name", "x", "y")],
                                    by = c("from" = "name")) |>
        dplyr::rename(x_from = x, y_from = y) |>
        dplyr::left_join(vdf[, c("name", "x", "y")],
                         by = c("to" = "name")) |>
        dplyr::rename(x_to = x, y_to = y)

      p <- p +
        ggplot2::geom_segment(
          data = edge_plot,
          ggplot2::aes(x = x_from, y = y_from,
                       xend = x_to, yend = y_to),
          colour = "#CC0000", alpha = 0.55,
          arrow = ggplot2::arrow(length = ggplot2::unit(0.008, "npc"),
                                 type = "closed"),
          linewidth = 0.4
        ) +
        ggplot2::geom_point(
          data = vdf,
          ggplot2::aes(x = x, y = y, colour = layer),
          size = 4
        ) +
        ggplot2::geom_text(
          data = vdf,
          ggplot2::aes(x = x, y = y + 0.15,
                       label = gsub("_", " ", name)),
          colour = "#ffffff", size = 2.5, hjust = 0.5
        ) +
        ggplot2::scale_colour_manual(values = layer_colours,
                                     name = "Layer") +
        ggplot2::labs(
          title    = "Expert Causal DAG",
          subtitle = paste0(
            cg_dag$n_nodes, " nodes | ",
            cg_dag$n_edges, " edges | ",
            "DAG: ", cg_dag$is_dag
          )
        )

      p
    }),

    # ── Dynamic caption ─────────────────────────────────────────────
    targets::tar_target(cg_caption, {
      r    <- cg_test_implications$results
      hold <- cg_test_implications$n_holds
      viol <- cg_test_implications$n_violated
      skip <- cg_test_implications$n_skipped

      # Add split test info if available
      split <- cg_test_split
      if (!is.null(split$comparison)) {
        split_text <- paste0(
          " HML-VIX correlation by period: ",
          paste(split$comparison$period, "r=", split$comparison$hml_vix_r,
                "(n=", split$comparison$n, ")", collapse = "; "), "."
        )
      } else {
        split_text <- ""
      }

      paste0(
        "Causal DAG for the portfolio: ",
        cg_dag$n_nodes, " nodes and ",
        cg_dag$n_edges, " directed edges, ",
        "encoding causal assumptions across factors, macro signals, ",
        "regime states, strategy signals, returns, and portfolio outcomes. ",
        "DAG validity (acyclic): ", cg_dag$is_dag, ". ",
        "Five conditional independence implications were tested via partial correlation: ",
        hold, " hold (|r| < 0.15), ",
        viol, " violated (|r| ≥ 0.15), ",
        skip, " skipped (data unavailable). ",
        "Implications with |r| ≥ 0.15 suggest the causal structure ",
        "requires revision. ",
        split_text,
        "Source: R/plan_causal_graph.R."
      )
    })

  )
}
