/* Six-cell 2FA code widget for the local (server) variant.
   Handles single-digit cells, auto-advance, backspace-to-previous, and reports
   the assembled 6-digit code to Shiny as input$sm_2fa_code. */
$(function () {
  function collect() {
    var v = "";
    for (var i = 1; i <= 6; i++) {
      var el = document.getElementById("sm_2fa_" + i);
      if (el) v += (el.value || "").replace(/\D/g, "").slice(0, 1);
    }
    Shiny.setInputValue("sm_2fa_code", v, { priority: "event" });
    return v;
  }

  $(document).on("input", ".sm-2fa-cell", function () {
    var n = parseInt(this.id.split("_").pop(), 10);
    this.value = (this.value || "").replace(/\D/g, "").slice(0, 1);
    if (this.value && n < 6) {
      var nx = document.getElementById("sm_2fa_" + (n + 1));
      if (nx) nx.focus();
    }
    collect();
  });

  $(document).on("keydown", ".sm-2fa-cell", function (e) {
    var n = parseInt(this.id.split("_").pop(), 10);
    if (e.key === "Backspace" && !this.value && n > 1) {
      var pv = document.getElementById("sm_2fa_" + (n - 1));
      if (pv) pv.focus();
    }
  });

  /* Paste a full code into the first cell and spread it across all cells. */
  $(document).on("paste", ".sm-2fa-cell", function (e) {
    var data = (e.originalEvent || e).clipboardData.getData("text").replace(/\D/g, "").slice(0, 6);
    if (!data) return;
    e.preventDefault();
    for (var i = 0; i < 6; i++) {
      var el = document.getElementById("sm_2fa_" + (i + 1));
      if (el) el.value = data.charAt(i) || "";
    }
    collect();
  });

  function clearCells() {
    for (var i = 1; i <= 6; i++) {
      var el = document.getElementById("sm_2fa_" + i);
      if (el) el.value = "";
    }
    var first = document.getElementById("sm_2fa_1");
    if (first) first.focus();
    Shiny.setInputValue("sm_2fa_code", "", { priority: "event" });
  }

  function windowSeconds() {
    var t = document.getElementById("sm-2fa-timer");
    return t && t.dataset.window ? parseInt(t.dataset.window, 10) : 30;
  }

  function startTimer(seconds) {
    var t = document.getElementById("sm-2fa-timer");
    if (!t) return;
    if (window.__sm2faTimer) clearInterval(window.__sm2faTimer);
    var s = seconds;
    t.textContent = s;
    window.__sm2faTimer = setInterval(function () {
      s--;
      if (t) t.textContent = s;
      if (s <= 0) clearInterval(window.__sm2faTimer);
    }, 1000);
  }

  // Client-driven 2FA UX (no dependency on server custom messages):
  //  * entering the 2FA step (sm_stage -> "twofa"): clear cells, start countdown
  //  * any 2FA error shown (wrong / expired code): clear cells, keep countdown
  //  * clicking "Reenviar": clear cells, restart countdown
  $(document).on("shiny:value", function (e) {
    if (e.name === "sm_stage") {
      if (e.value === "twofa") { clearCells(); startTimer(windowSeconds()); }
    } else if (e.name === "sm_twofa_error") {
      if (e.value && ("" + e.value).length) clearCells();
    }
  });

  $(document).on("click", "#sm_2fa_resend", function () {
    clearCells();
    startTimer(windowSeconds());
  });
});
