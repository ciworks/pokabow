/* ==========================================================================
   Polkabow landing page - progressive enhancement only.
   No dependencies. The page is fully readable with this file blocked; every
   effect here is additive and every animation is skipped when the visitor
   asks for reduced motion.
   ========================================================================== */
(function () {
  "use strict";

  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  var finePointer  = window.matchMedia("(hover: hover) and (pointer: fine)");

  /* ------------------------------------------------------------ mobile menu */
  function initNav() {
    var toggle = document.getElementById("nav-toggle");
    var menu = document.getElementById("nav-menu");
    if (!toggle || !menu) return;

    function setOpen(open) {
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
      menu.classList.toggle("is-open", open);
      var label = toggle.querySelector(".sr-only");
      if (label) label.textContent = open ? "Close menu" : "Open menu";
    }

    toggle.addEventListener("click", function () {
      setOpen(toggle.getAttribute("aria-expanded") !== "true");
    });

    // A chosen link should never leave the panel hanging open behind it.
    menu.addEventListener("click", function (event) {
      if (event.target.closest("a")) setOpen(false);
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") setOpen(false);
    });

    // Returning to a desktop width must clear the inline mobile state.
    window.addEventListener("resize", function () {
      if (window.innerWidth > 860) setOpen(false);
    });
  }

  /* --------------------------------------------------------- scroll reveals */
  function initReveals() {
    var items = document.querySelectorAll(".reveal");
    if (!items.length) return;

    if (reduceMotion.matches || !("IntersectionObserver" in window)) {
      items.forEach(function (el) { el.classList.add("is-visible"); });
      return;
    }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.15, rootMargin: "0px 0px -60px 0px" });

    items.forEach(function (el) { observer.observe(el); });
  }

  /* ------------------------------------------------------------- count-up */
  function countUp(el) {
    var target = parseInt(el.getAttribute("data-count-to"), 10);
    if (isNaN(target)) return;
    var suffix = el.getAttribute("data-suffix") || "";

    if (reduceMotion.matches) {
      el.textContent = format(target) + suffix;
      return;
    }

    var duration = 900;
    var start = null;

    function step(now) {
      if (start === null) start = now;
      var t = Math.min((now - start) / duration, 1);
      // Ease-out so the number settles rather than stopping dead.
      var eased = 1 - Math.pow(1 - t, 3);
      el.textContent = format(Math.round(target * eased)) + suffix;
      if (t < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }

  function format(value) {
    return value.toLocaleString("en-US");
  }

  /* ------------------------------------------------------- scoring tile wave */
  function initWave() {
    var wave = document.getElementById("wave");
    if (!wave) return;
    var score = wave.querySelector(".wave__score-num");

    function run() {
      if (reduceMotion.matches) {
        // No travel: the tiles sit still and the score is simply there.
        wave.classList.add("is-scored");
        if (score) score.textContent = "+" + format(24);
        return;
      }

      wave.classList.add("is-playing");

      // The score lands just as the last tile of the wave settles.
      window.setTimeout(function () {
        wave.classList.add("is-scored");
        if (score) {
          score.textContent = "+0";
          countUp(score);
        }
      }, 900);
    }

    if (!("IntersectionObserver" in window)) { run(); return; }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        observer.unobserve(entry.target);
        run();
      });
    }, { threshold: 0.45 });

    observer.observe(wave);
  }

  /* ----------------------------------------------------------- stat numbers */
  function initStats() {
    var values = document.querySelectorAll(".stat__value[data-count-to]");
    if (!values.length) return;

    if (!("IntersectionObserver" in window)) {
      values.forEach(countUp);
      return;
    }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        observer.unobserve(entry.target);
        countUp(entry.target);
      });
    }, { threshold: 0.5 });

    values.forEach(function (el) { observer.observe(el); });
  }

  /* --------------------------------------------------------- phone parallax */
  function initParallax() {
    var phone = document.querySelector("[data-parallax]");
    if (!phone) return;
    if (reduceMotion.matches || !finePointer.matches) return;

    var frame = null;
    var target = { x: 0, y: 0 };

    function apply() {
      frame = null;
      phone.style.setProperty("--px", target.x.toFixed(2));
      phone.style.setProperty("--py", target.y.toFixed(2));
      phone.style.setProperty("--ry", (target.x * 0.35).toFixed(2));
      phone.style.setProperty("--rx", (-target.y * 0.35).toFixed(2));
    }

    window.addEventListener("pointermove", function (event) {
      var cx = window.innerWidth / 2;
      var cy = window.innerHeight / 2;
      // Clamped so the tilt stays a suggestion rather than a lurch.
      target.x = Math.max(-14, Math.min(14, (event.clientX - cx) / cx * 14));
      target.y = Math.max(-14, Math.min(14, (event.clientY - cy) / cy * 14));
      if (frame === null) frame = requestAnimationFrame(apply);
    }, { passive: true });
  }

  function init() {
    initNav();
    initReveals();
    initWave();
    initStats();
    initParallax();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
