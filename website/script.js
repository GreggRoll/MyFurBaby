"use strict";

const widgetExamples = {
  clock: { image: "assets/widget-clock.jpg", alt: "A rainbow giraffe mermaid beside the clock in a purple bedroom widget", caption: "Time for a cuddle. A clock with a colorful companion.", width: 772, height: 361 },
  quote: { image: "assets/widget-quote.jpg", alt: "A black poodle beside a daily quote in a cozy living room widget", caption: "A daily thought, with a little company. Quotes by ZenQuotes.", width: 698, height: 328 },
  pet: { image: "assets/widget-sterling.jpg", alt: "Sterling, a white tiger, sleeping in his own small widget", caption: "Their own little corner. Just your pet, and a sleepy cuddle.", width: 522, height: 526 }
};

document.querySelectorAll("[data-widget]").forEach(button => {
  button.addEventListener("click", () => {
    const example = widgetExamples[button.dataset.widget];
    const preview = document.getElementById("widget-preview");
    preview.src = example.image;
    preview.alt = example.alt;
    preview.width = example.width;
    preview.height = example.height;
    document.getElementById("widget-description").textContent = example.caption;
    document.getElementById("widget-figure").classList.toggle("pet", button.dataset.widget === "pet");
    document.querySelectorAll("[data-widget]").forEach(option => {
      const selected = option === button;
      option.classList.toggle("active", selected);
      option.setAttribute("aria-pressed", String(selected));
    });
  });
});

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let animationsPaused = reducedMotion.matches;
const motionButton = document.querySelector(".motion-toggle");
const demoImages = document.querySelectorAll(".animated-demo");
const visibleDemos = new Set();

function updateAnimationState() {
  demoImages.forEach(demo => {
    const source = !animationsPaused && visibleDemos.has(demo) ? demo.dataset.gif : demo.dataset.still;
    if (demo.getAttribute("src") !== source) demo.src = source;
  });
  motionButton.innerHTML = animationsPaused ? 'Play animations <span aria-hidden="true">▷</span>' : 'Pause animations <span aria-hidden="true">Ⅱ</span>';
  motionButton.setAttribute("aria-pressed", String(animationsPaused));
}

// Only load the GIFs as their demos enter view; stills also respect Reduce Motion.
if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => entry.isIntersecting ? visibleDemos.add(entry.target) : visibleDemos.delete(entry.target));
    updateAnimationState();
  }, { rootMargin: "100px" });
  demoImages.forEach(demo => observer.observe(demo));
} else {
  demoImages.forEach(demo => visibleDemos.add(demo));
}
motionButton.addEventListener("click", () => { animationsPaused = !animationsPaused; updateAnimationState(); });
reducedMotion.addEventListener("change", event => { animationsPaused = event.matches; updateAnimationState(); });
updateAnimationState();
document.getElementById("year").textContent = new Date().getFullYear();
