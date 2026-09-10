# non-character/factor state aborts with an informative message

    Code
      hd_markov_transition(1:5)
    Condition
      Error in `hd_markov_transition()`:
      x `state` must be a character or factor vector.
      i Got class <integer>.

# a state series shorter than 2 aborts

    Code
      hd_markov_transition("only_one")
    Condition
      Error in `hd_markov_transition()`:
      x `state` must have at least 2 observations to estimate transitions.
      i Got length 1.

# a state series with only 1 distinct observed value aborts

    Code
      hd_markov_transition(c("low", "low", "low"))
    Condition
      Error in `hd_markov_transition()`:
      x The declared state vocabulary has fewer than 2 distinct states.
      i A Markov transition matrix needs >= 2 states to be meaningful. Got: "low".
      i hd_markov_transition() (per fail-loud-not-null.md) aborts rather than returning a degenerate 1x1 matrix.

# a state series with a value outside the declared vocabulary aborts

    Code
      hd_markov_transition(c("low", "high", "extreme"), states = c("low", "high"))
    Condition
      Error in `hd_markov_transition()`:
      x `state` contains value outside the declared vocabulary: "extreme".
      i Declared vocabulary: "low" and "high".
      i hd_markov_transition() (per fail-loud-not-null.md) never silently drops or coerces an unrecognised state.

# a declared states vocabulary with fewer than 2 entries aborts

    Code
      hd_markov_transition(c("low", "low"), states = "low")
    Condition
      Error in `hd_markov_transition()`:
      x The declared state vocabulary has fewer than 2 distinct states.
      i A Markov transition matrix needs >= 2 states to be meaningful. Got: "low".
      i hd_markov_transition() (per fail-loud-not-null.md) aborts rather than returning a degenerate 1x1 matrix.

# a malformed states argument aborts

    Code
      hd_markov_transition(c("low", "high"), states = c("low", "low"))
    Condition
      Error in `hd_markov_transition()`:
      x `states` must be a non-empty character vector with no duplicates or NAs.
      i Got "low" and "low".

# function signature is stable (catches API drift)

    Code
      args(hd_markov_transition)
    Output
      function (state, states = NULL) 
      NULL

