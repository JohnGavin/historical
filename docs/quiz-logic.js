<script>
// Move quiz-app into main content area (include-after-body puts it after </main>)
(function() {
  var app = document.getElementById("quiz-app");
  var main = document.querySelector("main") || document.querySelector("#quarto-document-content") || document.querySelector(".content");
  if (app && main) main.appendChild(app);
})();

// Quiz logic — loaded after quiz-app.html and quiz-data-json
var allRounds = [];
try {
  var el = document.getElementById("quiz-data-json");
  if (el) allRounds = JSON.parse(el.textContent || "[]");
} catch(e) { console.error("Quiz data parse error:", e); }

var S = { difficulty:"mixed", nq:5, rounds:[], current:0, score:0, maxScore:0, answered:false, answers:[] };
var diffMult = {easy:1, medium:2, hard:3, pseudo:4};
var lenMult = {100:1, 50:1.5, 25:2, 15:3};
var plotLayout = {
  paper_bgcolor:"transparent", plot_bgcolor:"transparent",
  font:{color:"#ccc",size:11}, margin:{t:5,b:25,l:35,r:5},
  xaxis:{gridcolor:"#333",zeroline:false}, yaxis:{gridcolor:"#333",title:"$1 growth",zeroline:false},
  showlegend:false
};

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
document.getElementById("btn-next").addEventListener("click", nextRound);
document.getElementById("btn-finish").addEventListener("click", showResults);
document.getElementById("btn-retry").addEventListener("click", function(){ location.reload(); });
document.getElementById("length-select").addEventListener("change", function(){ if(!S.answered) updateCharts(); });

function cumGrowth(ret) { var c=[1]; for(var i=0;i<ret.length;i++) c.push(c[i]*(1+ret[i])); return c; }

function startQuiz() {
  var pool = S.difficulty==="mixed" ? allRounds.slice() :
    allRounds.filter(function(r){return r.difficulty===S.difficulty;});
  for(var i=pool.length-1;i>0;i--){var j=Math.floor(Math.random()*(i+1));var t=pool[i];pool[i]=pool[j];pool[j]=t;}
  S.rounds = pool.slice(0,Math.min(S.nq,pool.length));
  S.current=0; S.score=0; S.maxScore=0; S.answers=new Array(S.rounds.length).fill(null);
  document.getElementById("phase-instructions").style.display="none";
  document.getElementById("phase-quiz").style.display="block";
  document.getElementById("round-total").textContent=S.rounds.length;
  renderRound();
}

function renderRound() {
  var r=S.rounds[S.current]; S.answered=false;
  document.getElementById("round-num").textContent=S.current+1;
  var badge=document.getElementById("diff-badge");
  badge.className="quiz-difficulty "+r.difficulty;
  badge.textContent=r.difficulty.charAt(0).toUpperCase()+r.difficulty.slice(1)+" ("+diffMult[r.difficulty]+"x)";
  document.getElementById("btn-a").className="quiz-btn";
  document.getElementById("btn-b").className="quiz-btn";
  document.getElementById("btn-a").disabled=false;
  document.getElementById("btn-b").disabled=false;
  document.getElementById("btn-next").style.display="none";
  document.getElementById("btn-finish").style.display="none";
  document.getElementById("reveal").className="explanation-panel";
  updateScore(); updateCharts();
}

function updateCharts() {
  if(!S.rounds.length) return;
  var r=S.rounds[S.current], len=parseInt(document.getElementById("length-select").value);
  Plotly.react("chart-a",[{y:cumGrowth(r.series_a.slice(-len)),type:"scatter",mode:"lines",line:{color:"#4a90d9",width:2}}],
    plotLayout,{displayModeBar:false,scrollZoom:true});
  Plotly.react("chart-b",[{y:cumGrowth(r.series_b.slice(-len)),type:"scatter",mode:"lines",line:{color:"#e6a817",width:2}}],
    plotLayout,{displayModeBar:false,scrollZoom:true});
}

function updateScore() {
  document.getElementById("score").textContent=S.score;
  document.getElementById("max-score").textContent=S.maxScore;
}

function guess(choice) {
  if(S.answered) return; S.answered=true;
  var r=S.rounds[S.current], correct=(choice===r.answer);
  var len=parseInt(document.getElementById("length-select").value);
  var pts=diffMult[r.difficulty]*lenMult[len];
  S.maxScore+=pts; if(correct) S.score+=pts; S.answers[S.current]=choice;
  document.getElementById("btn-a").disabled=true;
  document.getElementById("btn-b").disabled=true;
  if(r.answer==="A"){document.getElementById("btn-a").classList.add("quiz-btn-correct");if(choice==="B")document.getElementById("btn-b").classList.add("quiz-btn-wrong");}
  else{document.getElementById("btn-b").classList.add("quiz-btn-correct");if(choice==="A")document.getElementById("btn-a").classList.add("quiz-btn-wrong");}

  var v=correct?"<span style='color:#1a9850;font-weight:bold'>Correct!</span>":"<span style='color:#d73027;font-weight:bold'>Wrong.</span>";
  document.getElementById("reveal-text").innerHTML=v+" Series "+r.answer+" was real.<br><b>Real:</b> "+r.real_source+"<br><b>Simulated:</b> "+r.sim_source+"<br><b>Points:</b> "+(correct?"+"+pts:"0")+" (difficulty "+diffMult[r.difficulty]+"x, length "+lenMult[len]+"x)";
  document.getElementById("reveal").className="explanation-panel show";

  Plotly.react("reveal-chart",[
    {y:cumGrowth(r.full_real),type:"scatter",mode:"lines",line:{color:"#2ecc71",width:2},name:"Real: "+r.real_source},
    {y:cumGrowth(r.full_sim),type:"scatter",mode:"lines",line:{color:"#e74c3c",width:2,dash:"dash"},name:"Sim: "+r.sim_source}
  ],Object.assign({},plotLayout,{showlegend:true,legend:{orientation:"h",x:0.5,xanchor:"center",y:-0.2,font:{color:"#ccc"}}}),{displayModeBar:false});

  updateScore();
  if(S.current<S.rounds.length-1) document.getElementById("btn-next").style.display="inline-block";
  else document.getElementById("btn-finish").style.display="inline-block";
}

function nextRound(){S.current++;renderRound();}

function showResults() {
  document.getElementById("phase-quiz").style.display="none";
  document.getElementById("phase-results").style.display="block";
  var pct=S.maxScore>0?Math.round(S.score/S.maxScore*100):0;
  document.getElementById("final-pct").textContent=pct+"%";
  document.getElementById("final-score-detail").textContent=S.score+" / "+S.maxScore+" points ("+S.rounds.length+" rounds)";
  var diffs=["easy","medium","hard","pseudo"];
  var html="<table style='width:100%;color:#ddd;border-collapse:collapse;'><tr style='border-bottom:1px solid #444;'><th style='text-align:left;padding:6px;'>Difficulty</th><th>Correct</th><th>Total</th><th>Rate</th></tr>";
  diffs.forEach(function(d){
    var rds=S.rounds.filter(function(r){return r.difficulty===d;});
    if(!rds.length) return;
    var ok=rds.filter(function(r){var i=S.rounds.indexOf(r);return S.answers[i]===r.answer;}).length;
    html+="<tr style='border-bottom:1px solid #333;'><td style='padding:6px;'><span class='quiz-difficulty "+d+"'>"+d.charAt(0).toUpperCase()+d.slice(1)+"</span></td><td style='text-align:center;'>"+ok+"</td><td style='text-align:center;'>"+rds.length+"</td><td style='text-align:center;'>"+Math.round(ok/rds.length*100)+"%</td></tr>";
  });
  html+="</table>";
  document.getElementById("results-breakdown").innerHTML=html;
}

document.addEventListener("keydown",function(e){
  if(e.key==="ArrowRight"&&S.answered){if(S.current<S.rounds.length-1)nextRound();else showResults();}
});

if(!allRounds.length) document.getElementById("phase-instructions").innerHTML="<p>Quiz data not available. Run tar_make() first.</p>";
</script>
