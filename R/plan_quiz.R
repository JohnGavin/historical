# Plan: Real vs Simulated Time Series Quiz (#70)
#
# Pre-computes 20 quiz rounds: each round has one real strategy return
# series and one simulated series from a null environment.
# The user guesses which is real. Shorter visible windows earn bonus points.
#
# Depends on: fals_*_input targets (real strategy returns),
#             fals_vig_names (strategy names),
#             hd_null_env_* functions (null generators).

plan_quiz <- function() {
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

      # Collect real strategy returns
      real_inputs <- list(
        fals_avoid_worst_input,
        fals_drif_input,
        fals_fac_max_input,
        fals_rsc_input,
        fals_ltr_input
      )

      # Helper: sample T_obs contiguous returns from a strategy
      sample_real <- function(input_df, T_obs) {
        ret <- input_df$strategy_ret
        ret <- ret[!is.na(ret)]
        if (length(ret) <= T_obs) return(ret)
        start <- sample.int(length(ret) - T_obs, 1L)
        ret[start:(start + T_obs - 1L)]
      }

      rounds <- list()
      round_id <- 0L

      # ── Easy: White Noise ──────────────────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        strat_idx <- ((i - 1L) %% 5L) + 1L
        real_ret <- sample_real(real_inputs[[strat_idx]], T_obs)
        sim_list <- hd_null_env_white_noise(length(real_ret), M = 1L,
                                             seed = quiz_params$seed + round_id)
        sim_ret <- sim_list[[1]]
        # Match scale to real
        sim_ret <- sim_ret * (sd(real_ret) / sd(sim_ret))

        real_first <- sample(c(TRUE, FALSE), 1L)
        rounds[[round_id]] <- list(
          id          = round_id,
          difficulty  = "easy",
          real_name   = nms$long_name[strat_idx],
          null_env    = "White Noise",
          full_real   = as.numeric(real_ret),
          full_sim    = as.numeric(sim_ret),
          series_a    = if (real_first) as.numeric(real_ret) else as.numeric(sim_ret),
          series_b    = if (real_first) as.numeric(sim_ret) else as.numeric(real_ret),
          answer      = if (real_first) "A" else "B",
          real_source = paste0(nms$short_name[strat_idx], " returns"),
          sim_source  = "White Noise (iid Gaussian)"
        )
      }

      # ── Medium: GARCH(1,1) ─────────────────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        strat_idx <- ((i - 1L) %% 5L) + 1L
        real_ret <- sample_real(real_inputs[[strat_idx]], T_obs)
        sim_list <- hd_null_env_garch11(length(real_ret), M = 1L,
                                         seed = quiz_params$seed + round_id)
        sim_ret <- sim_list[[1]]
        sim_ret <- sim_ret * (sd(real_ret) / sd(sim_ret))

        real_first <- sample(c(TRUE, FALSE), 1L)
        rounds[[round_id]] <- list(
          id          = round_id,
          difficulty  = "medium",
          real_name   = nms$long_name[strat_idx],
          null_env    = "GARCH(1,1)",
          full_real   = as.numeric(real_ret),
          full_sim    = as.numeric(sim_ret),
          series_a    = if (real_first) as.numeric(real_ret) else as.numeric(sim_ret),
          series_b    = if (real_first) as.numeric(sim_ret) else as.numeric(real_ret),
          answer      = if (real_first) "A" else "B",
          real_source = paste0(nms$short_name[strat_idx], " returns"),
          sim_source  = "GARCH(1,1) volatility clustering"
        )
      }

      # ── Hard: GJR-GARCH ────────────────────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        strat_idx <- ((i - 1L) %% 5L) + 1L
        real_ret <- sample_real(real_inputs[[strat_idx]], T_obs)
        sim_list <- hd_null_env_gjr_garch(length(real_ret), M = 1L,
                                            seed = quiz_params$seed + round_id)
        sim_ret <- sim_list[[1]]
        sim_ret <- sim_ret * (sd(real_ret) / sd(sim_ret))

        real_first <- sample(c(TRUE, FALSE), 1L)
        rounds[[round_id]] <- list(
          id          = round_id,
          difficulty  = "hard",
          real_name   = nms$long_name[strat_idx],
          null_env    = "GJR-GARCH",
          full_real   = as.numeric(real_ret),
          full_sim    = as.numeric(sim_ret),
          series_a    = if (real_first) as.numeric(real_ret) else as.numeric(sim_ret),
          series_b    = if (real_first) as.numeric(sim_ret) else as.numeric(real_ret),
          answer      = if (real_first) "A" else "B",
          real_source = paste0(nms$short_name[strat_idx], " returns"),
          sim_source  = "GJR-GARCH (asymmetric leverage)"
        )
      }

      # ── Pseudo: time-reversed real data ─────────────────────────
      for (i in seq_len(n_per)) {
        round_id <- round_id + 1L
        strat_idx <- ((i - 1L) %% 5L) + 1L
        real_ret <- sample_real(real_inputs[[strat_idx]], T_obs)
        # "Simulated" = reversed real series
        sim_ret <- rev(real_ret)

        real_first <- sample(c(TRUE, FALSE), 1L)
        rounds[[round_id]] <- list(
          id          = round_id,
          difficulty  = "pseudo",
          real_name   = nms$long_name[strat_idx],
          null_env    = "Time-Reversed Real",
          full_real   = as.numeric(real_ret),
          full_sim    = as.numeric(sim_ret),
          series_a    = if (real_first) as.numeric(real_ret) else as.numeric(sim_ret),
          series_b    = if (real_first) as.numeric(sim_ret) else as.numeric(real_ret),
          answer      = if (real_first) "A" else "B",
          real_source = paste0(nms$short_name[strat_idx], " returns"),
          sim_source  = paste0("Time-reversed ", nms$short_name[strat_idx])
        )
      }

      # Shuffle round order
      rounds[sample(length(rounds))]
    }),

    targets::tar_target(quiz_json, {
      jsonlite::toJSON(quiz_rounds, auto_unbox = TRUE, digits = 6)
    })

  )
}
