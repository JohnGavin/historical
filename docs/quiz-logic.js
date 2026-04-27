<script>
// Move quiz-app into main content area (include-after-body puts it after </main>)
(function() {
  var app = document.getElementById("quiz-app");
  var main = document.querySelector("main") || document.querySelector("#quarto-document-content") || document.querySelector(".content");
  if (app && main) main.appendChild(app);
})();

// Move build-info to instructions + results footers (hide from quiz questions)
(function() {
  var cells = document.querySelectorAll(".cell-output-display");
  var biHTML = "";
  cells.forEach(function(c) {
    if (c.textContent.indexOf("historicaldata") >= 0 || c.textContent.indexOf("Git") >= 0) {
      biHTML = c.innerHTML;
      c.style.display = "none";
    }
  });
  var f1 = document.getElementById("build-info-instructions");
  var f2 = document.getElementById("build-info-footer");
  if (f1 && biHTML) f1.innerHTML = biHTML;
  if (f2 && biHTML) f2.innerHTML = biHTML;
})();

// Render QR codes on instructions + results pages
(function() {
  var url = window.location.href.split("#")[0].split("?")[0];
  function renderQR(containerId) {
    var el = document.getElementById(containerId);
    if (!el || typeof qrcode === "undefined") return;
    var qr = qrcode(0, "M");
    qr.addData(url);
    qr.make();
    el.innerHTML = qr.createImgTag(4, 8) +
      "<br><span style='color:#666;font-size:0.75em;'>" + url + "</span>";
  }
  renderQR("qr-instructions");
  renderQR("qr-results");
})();

// ── State ───────────────────────────────────────────────────
var allRounds = [];
try { allRounds = JSON.parse(document.getElementById("quiz-data-json").textContent || "[]"); } catch(e) {}

var S = {
  difficulty: "mixed", nq: 5,
  rounds: [], current: 0,
  nCorrect: 0, answers: []
};
var plotLayout = {
  paper_bgcolor:"transparent", plot_bgcolor:"transparent",
  font:{color:"#ccc",size:11}, margin:{t:5,b:25,l:35,r:5},
  xaxis:{gridcolor:"#333",zeroline:false},
  yaxis:{gridcolor:"#333",title:"$1 growth",zeroline:false},
  showlegend:false
};

var GOOGLE_FORM_URL = "";
var GOOGLE_FORM_SCORE_FIELD = "entry.0";

// ── Event Listeners ─────────────────────────────────────────
document.querySelectorAll("#grp-diff .option-btn").forEach(function(btn) {
  btn.addEventListener("click", function() {
    S.difficulty = this.id.replace("diff-","");
    document.querySelectorAll("#grp-diff .option-btn").forEach(function(b){b.classList.remove("selected");});
    this.classList.add("selected");
  });
});
document.querySelectorAll("#grp-nq .option-btn").forEach(function(btn) {
  btn.addEventListener("click", function() {
    S.nq = parseInt(this.id.replace("nq-",""));
    document.querySelectorAll("#grp-nq .option-btn").forEach(function(b){b.classList.remove("selected");});
    this.classList.add("selected");
  });
});
document.getElementById("btn-start").addEventListener("click", startQuiz);
document.getElementById("btn-a").addEventListener("click", function(){ guess("A"); });
document.getElementById("btn-b").addEventListener("click", function(){ guess("B"); });
document.getElementById("btn-next").addEventListener("click", nextOrFinish);
document.getElementById("btn-prev").addEventListener("click", function(){ if(S.current>0){S.current--;renderRound();} });
document.getElementById("btn-retry").addEventListener("click", function(){ location.reload(); });
document.getElementById("btn-submit-score").addEventListener("click", submitScore);
document.getElementById("length-select").addEventListener("change", function(){
  if(S.answers[S.current] === null) updateCharts();
});

document.addEventListener("keydown", function(e) {
  if (e.key === "ArrowRight") nextOrFinish();
  if (e.key === "ArrowLeft" && S.current > 0) { S.current--; renderRound(); }
});

// ── Helpers ─────────────────────────────────────────────────
function cumGrowth(ret) { var c=[1]; for(var i=0;i<ret.length;i++) c.push(c[i]*(1+ret[i])); return c; }

function nextOrFinish() {
  if (S.current < S.rounds.length - 1) { S.current++; renderRound(); }
  else showResults();
}

// ── Start ───────────────────────────────────────────────────
function startQuiz() {
  var pool = S.difficulty === "mixed" ? allRounds.slice() :
    allRounds.filter(function(r){ return r.difficulty === S.difficulty; });
  for (var i=pool.length-1; i>0; i--) { var j=Math.floor(Math.random()*(i+1)); var t=pool[i]; pool[i]=pool[j]; pool[j]=t; }
  S.rounds = pool.slice(0, Math.min(S.nq, pool.length));
  S.current = 0; S.nCorrect = 0;
  S.answers = new Array(S.rounds.length).fill(null);
  document.getElementById("phase-instructions").style.display = "none";
  document.getElementById("phase-quiz").style.display = "block";
  document.getElementById("round-total").textContent = S.rounds.length;
  document.getElementById("total-count").textContent = S.rounds.length;
  renderRound();
}

// ── Render Round ────────────────────────────────────────────
function renderRound() {
  var r = S.rounds[S.current];
  var wasAnswered = (S.answers[S.current] !== null);
  document.getElementById("round-num").textContent = S.current + 1;

  // Difficulty badge AFTER round number
  var badge = document.getElementById("diff-badge");
  badge.className = "quiz-difficulty " + r.difficulty;
  badge.textContent = r.difficulty.charAt(0).toUpperCase() + r.difficulty.slice(1);

  // Reset choice buttons
  document.getElementById("btn-a").className = "quiz-btn";
  document.getElementById("btn-b").className = "quiz-btn";
  document.getElementById("btn-a").disabled = wasAnswered;
  document.getElementById("btn-b").disabled = wasAnswered;

  // Back button: visible if not first round (use visibility to keep layout stable)
  document.getElementById("btn-prev").style.visibility = (S.current > 0) ? "visible" : "hidden";

  // Next button: always visible, label changes on last round
  var nextBtn = document.getElementById("btn-next");
  if (S.current >= S.rounds.length - 1) {
    nextBtn.innerHTML = "Finish";
  } else {
    nextBtn.innerHTML = "Next &rarr;";
  }

  if (wasAnswered) {
    var choice = S.answers[S.current];
    if (r.answer === "A") { document.getElementById("btn-a").classList.add("quiz-btn-correct"); if(choice==="B") document.getElementById("btn-b").classList.add("quiz-btn-wrong"); }
    else { document.getElementById("btn-b").classList.add("quiz-btn-correct"); if(choice==="A") document.getElementById("btn-a").classList.add("quiz-btn-wrong"); }
    showReveal(r, choice === r.answer);
  } else {
    document.getElementById("reveal").className = "explanation-panel";
  }

  updateScore();
  updateCharts();
}

function updateCharts() {
  if (!S.rounds.length) return;
  var r = S.rounds[S.current];
  var len = parseInt(document.getElementById("length-select").value);
  Plotly.react("chart-a", [{y:cumGrowth(r.series_a.slice(-len)), type:"scatter", mode:"lines", line:{color:"#4a90d9",width:2}}],
    plotLayout, {displayModeBar:false, scrollZoom:true});
  Plotly.react("chart-b", [{y:cumGrowth(r.series_b.slice(-len)), type:"scatter", mode:"lines", line:{color:"#e6a817",width:2}}],
    plotLayout, {displayModeBar:false, scrollZoom:true});
}

function updateScore() {
  document.getElementById("correct-count").textContent = S.nCorrect;
}

// ── Guess ───────────────────────────────────────────────────
function guess(choice) {
  if (S.answers[S.current] !== null) return;
  S.answers[S.current] = choice;
  var r = S.rounds[S.current];
  var correct = (choice === r.answer);
  if (correct) S.nCorrect++;

  document.getElementById("btn-a").disabled = true;
  document.getElementById("btn-b").disabled = true;
  if (r.answer === "A") { document.getElementById("btn-a").classList.add("quiz-btn-correct"); if(choice==="B") document.getElementById("btn-b").classList.add("quiz-btn-wrong"); }
  else { document.getElementById("btn-b").classList.add("quiz-btn-correct"); if(choice==="A") document.getElementById("btn-a").classList.add("quiz-btn-wrong"); }

  showReveal(r, correct);
  updateScore();
}

function showReveal(r, correct) {
  var v = correct ? "<span style='color:#1a9850;font-weight:bold'>Correct!</span>" : "<span style='color:#d73027;font-weight:bold'>Wrong.</span>";
  var realLink = r.real_url ? "<a href='" + r.real_url + "' target='_blank' style='color:#6c9bd2;'>" + r.real_source + "</a>" : r.real_source;
  document.getElementById("reveal-text").innerHTML = v + " Series " + r.answer + " was real.<br>" +
    "<b>Real:</b> " + realLink + "<br>" +
    "<b>Simulated:</b> " + r.sim_source;
  document.getElementById("reveal").className = "explanation-panel show";

  Plotly.react("reveal-chart", [
    {y:cumGrowth(r.full_real), type:"scatter", mode:"lines", line:{color:"#2ecc71",width:2}, name:"Real: " + r.real_name},
    {y:cumGrowth(r.full_sim), type:"scatter", mode:"lines", line:{color:"#e74c3c",width:2,dash:"dash"}, name:"Sim: " + r.null_env}
  ], Object.assign({}, plotLayout, {showlegend:true, legend:{orientation:"h",x:0.5,xanchor:"center",y:-0.2,font:{color:"#ccc"}}}),
  {displayModeBar:false});
}

// ── Results ─────────────────────────────────────────────────
function showResults() {
  document.getElementById("phase-quiz").style.display = "none";
  document.getElementById("phase-results").style.display = "block";

  var pct = S.rounds.length > 0 ? Math.round(S.nCorrect / S.rounds.length * 100) : 0;
  document.getElementById("final-pct").textContent = pct + "%";
  document.getElementById("final-score-detail").textContent = S.nCorrect + " / " + S.rounds.length + " correct";

  // Breakdown by difficulty
  var diffs = ["easy","medium","hard","pseudo"];
  var html = "<table style='width:100%;color:#ddd;border-collapse:collapse;'>" +
    "<tr style='border-bottom:1px solid #444;'><th style='text-align:left;padding:6px;'>Difficulty</th><th>Correct</th><th>Total</th><th>Rate</th></tr>";
  diffs.forEach(function(d) {
    var rds = []; var oks = 0;
    S.rounds.forEach(function(r, i) { if(r.difficulty === d) { rds.push(i); if(S.answers[i] === r.answer) oks++; } });
    if (!rds.length) return;
    html += "<tr style='border-bottom:1px solid #333;'><td style='padding:6px;'><span class='quiz-difficulty " + d + "'>" +
      d.charAt(0).toUpperCase() + d.slice(1) + "</span></td><td style='text-align:center;'>" + oks +
      "</td><td style='text-align:center;'>" + rds.length + "</td><td style='text-align:center;'>" +
      Math.round(oks / rds.length * 100) + "%</td></tr>";
  });
  html += "</table>";
  document.getElementById("results-breakdown").innerHTML = html;

  // Detail table
  var detail = "<h3 style='color:#6c9bd2;margin-top:16px;'>Round Details</h3><table style='width:100%;color:#ddd;border-collapse:collapse;'>" +
    "<tr style='border-bottom:1px solid #444;'><th style='padding:6px;text-align:left;'>#</th><th style='text-align:left;'>Real Data</th>" +
    "<th style='text-align:left;'>Null Model</th><th>Answer</th><th>Result</th></tr>";
  S.rounds.forEach(function(r, i) {
    var ans = S.answers[i];
    var correct = (ans === r.answer);
    var skipped = (ans === null);
    var icon = skipped ? "—" : (correct ? "&#10004;" : "&#10008;");
    var color = skipped ? "#666" : (correct ? "#1a9850" : "#d73027");
    var link = r.real_url ? "<a href='" + r.real_url + "' target='_blank' style='color:#6c9bd2;'>" + r.real_name + "</a>" : r.real_name;
    detail += "<tr style='border-bottom:1px solid #333;'><td style='padding:6px;'>" + (i+1) + "</td>" +
      "<td>" + link + "</td><td>" + r.null_env + "</td>" +
      "<td style='text-align:center;'>" + (ans || "skipped") + "</td>" +
      "<td style='text-align:center;color:" + color + ";'>" + icon + "</td></tr>";
  });
  detail += "</table>";
  document.getElementById("results-detail").innerHTML = detail;
}

// ── Submit Score ────────────────────────────────────────────
function submitScore() {
  var statusEl = document.getElementById("submit-status");
  if (!GOOGLE_FORM_URL) {
    statusEl.textContent = "Score submission not yet configured.";
    statusEl.style.color = "#e6a817";
    return;
  }
  var pct = S.rounds.length > 0 ? Math.round(S.nCorrect / S.rounds.length * 100) : 0;
  var data = new FormData();
  data.append(GOOGLE_FORM_SCORE_FIELD, JSON.stringify({
    score: S.nCorrect, total: S.rounds.length, pct: pct,
    difficulty: S.difficulty, nq: S.nq,
    timestamp: new Date().toISOString()
  }));
  fetch(GOOGLE_FORM_URL, { method: "POST", mode: "no-cors", body: data })
    .then(function() { statusEl.textContent = "Score submitted!"; statusEl.style.color = "#1a9850"; })
    .catch(function() { statusEl.textContent = "Submission failed."; statusEl.style.color = "#d73027"; });
  document.getElementById("btn-submit-score").disabled = true;
}

// ── Init ────────────────────────────────────────────────────
if (!allRounds.length) {
  document.getElementById("phase-instructions").innerHTML = "<p>Quiz data not available. Run <code>tar_make()</code> first.</p>";
}
</script>
