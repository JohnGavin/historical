# detection_badge: not applicable (sharpe <= 0)

    Code
      cat(detection_badge("Value (HML)", sr = -0.2, avail = 62.5, under = NA, dmin = NA_real_,
        under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$html)
    Output
      <span class='pop-wrap det-badge napp' tabindex='0' aria-label='Detection: not applicable, Sharpe is not positive'><span class='pop-short'>&ndash; n/a</span><span class='pop-body'><strong>&ndash; Not applicable</strong><br>Sharpe &le; 0: the one-sided detection test has no positive effect to test for. Not applicable &mdash; not the same as unproven.<br><span class='pop-meaning'>Detection asks: is the sample long enough to reliably detect this Sharpe if it is real? (prospective power test, one-sided, &alpha;=0.05)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/726' target='_blank' rel='noopener'>#726</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/903' target='_blank' rel='noopener'>#903</a></span></span></span>

# detection_badge: not computed (defect -- positive Sharpe, no verdict)

    Code
      cat(detection_badge("Risk State", sr = 0.252, avail = NA_real_, under = NA,
        dmin = NA_real_, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$html)
    Output
      <span class='pop-wrap det-badge notcomputed' tabindex='0' aria-label='Detection: defect, verdict was not computed'><span class='pop-short'>&#10007; ERR</span><span class='pop-body'><strong>&#10007; NOT COMPUTED</strong><br>Positive Sharpe with NO detection verdict &mdash; this should never render live (QA gate S20, #726 item 3, is meant to block the build until it is fixed).<br><span class='pop-meaning'>Detection asks: is the sample long enough to reliably detect this Sharpe if it is real? (prospective power test, one-sided, &alpha;=0.05)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/726' target='_blank' rel='noopener'>#726</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/903' target='_blank' rel='noopener'>#903</a></span></span></span>

# detection_badge: fails the single test (underpowered)

    Code
      cat(detection_badge("Value (HML)", sr = 0.068, avail = 62.5, under = TRUE,
        dmin = 1337.1, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$html)
    Output
      <span class='pop-wrap det-badge underpowered' tabindex='0' aria-label='Detection: underpowered, needs 1337 years, 62 years available'><span class='pop-short'>&#9888; 62/1337y</span><span class='pop-body'><strong>&#9888; Underpowered</strong><br>Needs <b>1337.1 yr</b> at &alpha;=0.05, one-sided; <b>62.5 yr</b> available.<br>MT-corrected verdict not computed (k_eff unavailable for this strategy).<br><span class='pop-meaning'>Detection asks: is the sample long enough to reliably detect this Sharpe if it is real? (prospective power test, one-sided, &alpha;=0.05)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/726' target='_blank' rel='noopener'>#726</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/903' target='_blank' rel='noopener'>#903</a></span></span></span>

# detection_badge: passes single test, MT not computed

    Code
      cat(detection_badge("Avoid Worst", sr = 0.62, avail = 33.1, under = FALSE,
        dmin = 16.1, under_mt = NA, dmin_mt = NA_real_, keff = NA_real_)$html)
    Output
      <span class='pop-wrap det-badge detectable' tabindex='0' aria-label='Detection: detectable, needs 16 years, 33 years available'><span class='pop-short'>&#10003; 33/16y</span><span class='pop-body'><strong>&#10003; Detectable</strong><br>Needs <b>16.1 yr</b> at &alpha;=0.05, one-sided; <b>33.1 yr</b> available.<br>MT-corrected verdict not computed (k_eff unavailable for this strategy).<br><span class='pop-meaning'>Detection asks: is the sample long enough to reliably detect this Sharpe if it is real? (prospective power test, one-sided, &alpha;=0.05)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='avoid-worst-days.html' target='_blank' rel='noopener'>Avoid Worst dashboard &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/726' target='_blank' rel='noopener'>#726</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/903' target='_blank' rel='noopener'>#903</a></span></span></span>

# detection_badge: passes single, fails MT-correction

    Code
      cat(detection_badge("OLMAR-1", sr = 0.78, avail = 16.1, under = FALSE, dmin = 10.2,
        under_mt = TRUE, dmin_mt = 21.3, keff = 14.5)$html)
    Output
      <span class='pop-wrap det-badge mtfail' tabindex='0' aria-label='Detection: passes single test, fails multiple-testing correction, needs 21 years corrected'><span class='pop-short'>&#9670; 16/21y</span><span class='pop-body'><strong>&#9670; Fails MT-correction</strong><br>Passes the single test (needs <b>10.2 yr</b>; <b>16.1 yr</b> available) but FAILS once corrected for testing multiple strategies (needs <b>21.3 yr</b> corrected, k_eff=14.5).<br><span class='pop-meaning'>Detection asks: is the sample long enough to reliably detect this Sharpe if it is real? (prospective power test, one-sided, &alpha;=0.05)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/726' target='_blank' rel='noopener'>#726</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/903' target='_blank' rel='noopener'>#903</a></span></span></span>

# detection_badge: passes single and MT-correction

    Code
      cat(detection_badge("Avoid Worst", sr = 0.62, avail = 33.1, under = FALSE,
        dmin = 16.1, under_mt = FALSE, dmin_mt = 18, keff = 14.5)$html)
    Output
      <span class='pop-wrap det-badge detectable' tabindex='0' aria-label='Detection: detectable, passes single test and multiple-testing correction'><span class='pop-short'>&#10003; 33/16y</span><span class='pop-body'><strong>&#10003; Detectable</strong><br>Needs <b>16.1 yr</b> at &alpha;=0.05, one-sided (<b>18.0 yr</b> corrected for multiple testing, k_eff=14.5); <b>33.1 yr</b> available.<br><span class='pop-meaning'>Detection asks: is the sample long enough to reliably detect this Sharpe if it is real? (prospective power test, one-sided, &alpha;=0.05)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='avoid-worst-days.html' target='_blank' rel='noopener'>Avoid Worst dashboard &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/726' target='_blank' rel='noopener'>#726</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/903' target='_blank' rel='noopener'>#903</a></span></span></span>

# psr_badge: not applicable (sharpe <= 0)

    Code
      cat(psr_badge("Value (HML)", sr = -0.2, psr = NA_real_, psr_insuff = NA,
        psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$
        html)
    Output
      <span class='pop-wrap psr-badge napp' tabindex='0' aria-label='P(SR>0): not applicable, Sharpe is not positive'><span class='pop-short'>&ndash; n/a</span><span class='pop-body'><strong>&ndash; Not applicable</strong><br>Sharpe &le; 0: P(true Sharpe &gt; 0) is not a meaningful question when the point estimate itself is non-positive. Not applicable &mdash; not the same as unproven.<br><span class='pop-meaning'>P(SR&gt;0) asks: given what we observed, how confident are we the TRUE Sharpe is positive? (retrospective confidence, Bailey &amp; Lopez de Prado)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/851' target='_blank' rel='noopener'>#851</a></span></span></span>

# psr_badge: not computed (defect -- positive Sharpe, no verdict)

    Code
      cat(psr_badge("Risk State", sr = 0.252, psr = NA_real_, psr_insuff = NA,
        psr_mt = NA_real_, psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$
        html)
    Output
      <span class='pop-wrap psr-badge notcomputed' tabindex='0' aria-label='P(SR>0): defect, verdict was not computed'><span class='pop-short'>&#10007; ERR</span><span class='pop-body'><strong>&#10007; NOT COMPUTED</strong><br>Positive Sharpe with NO P(SR&gt;0) verdict &mdash; this should never render live (QA gate S40, #851, is meant to block the build until it is fixed).<br><span class='pop-meaning'>P(SR&gt;0) asks: given what we observed, how confident are we the TRUE Sharpe is positive? (retrospective confidence, Bailey &amp; Lopez de Prado)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/851' target='_blank' rel='noopener'>#851</a></span></span></span>

# psr_badge: fails the single test (insufficient)

    Code
      cat(psr_badge("Value (HML)", sr = 0.068, psr = 0.62, psr_insuff = TRUE, psr_mt = NA_real_,
        psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$html)
    Output
      <span class='pop-wrap psr-badge insufficient' tabindex='0' aria-label='P(SR>0): insufficient, 62.0% below the 95.0% threshold'><span class='pop-short'>&#9888; 62.0%</span><span class='pop-body'><strong>&#9888; Insufficient</strong><br>P(true Sharpe &gt; 0) = <b>62.0%</b>, below the <b>95.0%</b> bar.<br>MT-corrected verdict not computed (k_eff unavailable for this strategy).<br><span class='pop-meaning'>P(SR&gt;0) asks: given what we observed, how confident are we the TRUE Sharpe is positive? (retrospective confidence, Bailey &amp; Lopez de Prado)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/851' target='_blank' rel='noopener'>#851</a></span></span></span>

# psr_badge: passes single test, MT not computed

    Code
      cat(psr_badge("Avoid Worst", sr = 0.62, psr = 0.99, psr_insuff = FALSE, psr_mt = NA_real_,
        psr_mt_insuff = NA, threshold = THRESHOLD, keff = NA_real_)$html)
    Output
      <span class='pop-wrap psr-badge sufficient' tabindex='0' aria-label='P(SR>0): sufficient, 99.0% single test'><span class='pop-short'>&#10003; 99.0%</span><span class='pop-body'><strong>&#10003; Sufficient</strong><br>P(true Sharpe &gt; 0) = <b>99.0%</b> (single test), at or above the <b>95.0%</b> bar.<br>MT-corrected verdict not computed (k_eff unavailable for this strategy).<br><span class='pop-meaning'>P(SR&gt;0) asks: given what we observed, how confident are we the TRUE Sharpe is positive? (retrospective confidence, Bailey &amp; Lopez de Prado)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='avoid-worst-days.html' target='_blank' rel='noopener'>Avoid Worst dashboard &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/851' target='_blank' rel='noopener'>#851</a></span></span></span>

# psr_badge: passes single, fails MT-correction (Managed Futures disagreement case)

    Code
      cat(psr_badge("Managed Futures", sr = 0.477, psr = 0.981, psr_insuff = FALSE,
        psr_mt = 0.87, psr_mt_insuff = TRUE, threshold = THRESHOLD, keff = 14.5)$html)
    Output
      <span class='pop-wrap psr-badge mtfail' tabindex='0' aria-label='P(SR>0): passes single test, fails multiple-testing correction at 87.0%'><span class='pop-short'>&#9670; 87.0%</span><span class='pop-body'><strong>&#9670; Fails MT-correction</strong><br>Passes the single-test bar (<b>98.1%</b>) but FAILS once corrected for multiple testing (<b>87.0%</b>, below the <b>95.0%</b> bar, k_eff=14.5).<br><span class='pop-meaning'>P(SR&gt;0) asks: given what we observed, how confident are we the TRUE Sharpe is positive? (retrospective confidence, Bailey &amp; Lopez de Prado)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/851' target='_blank' rel='noopener'>#851</a></span></span></span>

# psr_badge: passes single and MT-correction

    Code
      cat(psr_badge("Avoid Worst", sr = 0.62, psr = 0.99, psr_insuff = FALSE, psr_mt = 0.97,
        psr_mt_insuff = FALSE, threshold = THRESHOLD, keff = 14.5)$html)
    Output
      <span class='pop-wrap psr-badge sufficient' tabindex='0' aria-label='P(SR>0): sufficient, 99.0% single test, 97.0% corrected'><span class='pop-short'>&#10003; 99.0%</span><span class='pop-body'><strong>&#10003; Sufficient</strong><br>P(true Sharpe &gt; 0): <b>99.0%</b> single-test, <b>97.0%</b> corrected for multiple testing (k_eff=14.5) &mdash; both at or above the <b>95.0%</b> bar.<br><span class='pop-meaning'>P(SR&gt;0) asks: given what we observed, how confident are we the TRUE Sharpe is positive? (retrospective confidence, Bailey &amp; Lopez de Prado)</span><br><span class='pop-links'><a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a> &middot; <a href='avoid-worst-days.html' target='_blank' rel='noopener'>Avoid Worst dashboard &#8599;</a> &middot; <a href='https://github.com/JohnGavin/historical/issues/851' target='_blank' rel='noopener'>#851</a></span></span></span>

