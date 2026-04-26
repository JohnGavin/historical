# Plan: Real vs Simulated Time Series Quiz (#70)
#
# Pre-computes 20 quiz rounds with proper strategy labels, date ranges,
# and links to source vignettes.

plan_quiz <- function() {
  gh_base <- "https://johngavin.github.io/historical"

  list(

    targets::tar_target(quiz_params, {
      list(
        n_per_difficulty = 5L,
        T_obs            = 100L,
        seed             = 123L,
        length_options   = c(100L, 50L, 25L, 15L),
        length_multipliers = c(1, 1.5, 2, 3),
        difficulty_multipliers = c(easy = 1, medium = 2, hard = 3, pseudo = 4)
      )
    }),

    targets::tar_target(quiz_rounds, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      set.seed(quiz_params$seed)

      nms <- fals_vig_names
      T_obs <- quiz_params$T_obs
      n_per <- quiz_params$n_per_difficulty
      gh <- "https://johngavin.github.io/historical"

      # Strategy vignette URLs
      strat_urls <- c(
        avoid_worst = paste0(gh, "/avoid-worst-days.html"),
        drif        = paste0(gh, "/drif.html"),
        fac_max     = paste0(gh, "/factor-max.html"),
        rsc         = paste0(gh, "/leaderboard.html#falsification"),
        ltr         = paste0(gh, "/leaderboard.html#falsification")
      )

      real_inputs <- list(
        fals_avoid_worst_input,
        fals_drif_input,
        fals_fac_max_input,
        fals_rsc_input,
        fals_ltr_input
      )

      # Helper: sample T_obs contiguous returns WITH dates
      sample_real <- function(input_df, T_obs) {
        df <- input_df[!is.na(input_df$strategy_ret), ]
        if (nrow(df) <= T_obs) {
          return(list(ret = df$strategy_ret, dates = df$date))
        }
        start <- sample.int(nrow(df) - T_obs, 1L)
        idx <- start:(start + T_obs - 1L)
        list(ret = df$strategy_ret[idx], dates = df$date[idx])
      }

      # Helper: build one round
      make_round <- function(round_id, strat_idx, difficulty, null_env_label,
                              sim_ret, real_sample) {
        real_ret <- real_sample$ret
        dates <- real_sample$dates
        date_range <- paste0(format(min(dates), "%Y-%m"), " to ",
                              format(max(dates), "%Y-%m"))
        # Match scale
        if (sd(sim_ret) > 0) sim_ret <- sim_ret * (sd(real_ret) / sd(sim_ret))

        real_first <- sample(c(TRUE, FALSE), 1L)
        code <- nms$code_name[strat_idx]

        list(
          id          = round_id,
          difficulty  = difficulty,
          real_name   = nms$long_name[strat_idx],
          real_url    = strat_urls[code],
          null_env    = null_env_label,
          full_real   = as.numeric(real_ret),
          full_sim    = as.numeric(sim_ret),
          dates_from  = format(min(dates), "%Y-%m-%d"),
          dates_to    = format(max(dates), "%Y-%m-%d"),
          series_a    = if (real_first) as.numeric(real_ret) else as.numeric(sim_ret),
          series_b    = if (real_first) as.numeric(sim_ret) else as.numeric(real_ret),
          answer      = if (real_first) "A" else "B",
          real_source = paste0(nms$long_name[strat_idx], " (", date_range, ")"),
          sim_source  = null_env_label
        )
      }

      rounds <- list()
      round_id <- 0L

      # ── Easy: White Noise ──────────────────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        strat_idx <- ((i - 1L) %% 5L) + 1L
        real_s <- sample_real(real_inputs[[strat_idx]], T_obs)
        sim_list <- hd_null_env_white_noise(length(real_s$ret), M = 1L,
                                             seed = quiz_params$seed + round_id)
        rounds[[round_id]] <- make_round(
          round_id, strat_idx, "easy", "White Noise (iid Gaussian)",
          sim_list[[1]], real_s
        )
      }

      # ── Medium: GARCH(1,1) ─────────────────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        strat_idx <- ((i - 1L) %% 5L) + 1L
        real_s <- sample_real(real_inputs[[strat_idx]], T_obs)
        sim_list <- hd_null_env_garch11(length(real_s$ret), M = 1L,
                                         seed = quiz_params$seed + round_id)
        rounds[[round_id]] <- make_round(
          round_id, strat_idx, "medium", "GARCH(1,1) volatility clustering",
          sim_list[[1]], real_s
        )
      }

      # ── Hard: GJR-GARCH ────────────────────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        strat_idx <- ((i - 1L) %% 5L) + 1L
        real_s <- sample_real(real_inputs[[strat_idx]], T_obs)
        sim_list <- hd_null_env_gjr_garch(length(real_s$ret), M = 1L,
                                            seed = quiz_params$seed + round_id)
        rounds[[round_id]] <- make_round(
          round_id, strat_idx, "hard", "GJR-GARCH (asymmetric leverage)",
          sim_list[[1]], real_s
        )
      }

      # ── Pseudo: time-reversed real data ─────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        strat_idx <- ((i - 1L) %% 5L) + 1L
        real_s <- sample_real(real_inputs[[strat_idx]], T_obs)
        rounds[[round_id]] <- make_round(
          round_id, strat_idx, "pseudo",
          paste0("Time-reversed ", nms$short_name[strat_idx]),
          rev(real_s$ret), real_s
        )
      }

      # Shuffle
      rounds[sample(length(rounds))]
    }),

    targets::tar_target(quiz_json, {
      jsonlite::toJSON(quiz_rounds, auto_unbox = TRUE, digits = 6)
    })

  )
}
