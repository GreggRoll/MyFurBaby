"use strict";

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let animationsPaused = reducedMotion.matches;
let autoplayBlocked = false;
const motionButtons = document.querySelectorAll(".motion-toggle");
const videos = document.querySelectorAll("video[data-animation]");
const visibleVideos = new Set();

function updateMotionButtons() {
  const stopped = animationsPaused || autoplayBlocked;
  motionButtons.forEach(button => {
    button.innerHTML = stopped ? 'Play animations <span aria-hidden="true">▷</span>' : 'Pause animations <span aria-hidden="true">Ⅱ</span>';
    button.setAttribute("aria-pressed", String(stopped));
  });
}

function updateVideo(video) {
  if (animationsPaused || document.hidden || !visibleVideos.has(video)) {
    video.pause();
    return;
  }
  // Set properties as well as HTML attributes for iPhone autoplay.
  video.muted = true;
  video.defaultMuted = true;
  video.playsInline = true;
  if (!video.paused) return;
  const playback = video.play();
  if (playback) playback.catch(error => {
    // Changing examples or leaving the viewport can cancel an in-flight play.
    if (error.name === "AbortError") return;
    if (error.name === "NotAllowedError") {
      autoplayBlocked = true;
      updateMotionButtons();
    }
  });
}

function updateAnimationState() {
  videos.forEach(updateVideo);
  updateMotionButtons();
}

// Stop offscreen recordings; resume them when they return to view.
if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) visibleVideos.add(entry.target);
      else visibleVideos.delete(entry.target);
      updateVideo(entry.target);
    });
  }, { threshold: 0.05 });
  videos.forEach(video => observer.observe(video));
} else {
  videos.forEach(video => visibleVideos.add(video));
}
motionButtons.forEach(button => button.addEventListener("click", () => {
  if (autoplayBlocked && !animationsPaused) autoplayBlocked = false;
  else animationsPaused = !animationsPaused;
  updateAnimationState();
}));
reducedMotion.addEventListener("change", event => {
  animationsPaused = event.matches;
  autoplayBlocked = false;
  updateAnimationState();
});
document.addEventListener("visibilitychange", updateAnimationState);

const widgetExamples = {
  clock: { clip: "assets/widget-clock.mp4", poster: "assets/widget-clock.jpg", label: "A rainbow giraffe mermaid playing beside the clock in a purple bedroom widget", caption: "Time for a cuddle. A clock with a colorful companion.", width: 772, height: 361 },
  quote: { clip: "assets/widget-quote.mp4", poster: "assets/widget-quote.jpg", label: "A black poodle playing beside a daily quote in a cozy living room widget", caption: "A daily thought, with a little company. Quotes by ZenQuotes.", width: 698, height: 328 },
  pet: { clip: "assets/widget-sterling.mp4", poster: "assets/widget-sterling.jpg", label: "Sterling, a white tiger, snoring in his own small widget", caption: "Their own little corner. Just your pet, and a sleepy cuddle.", width: 522, height: 526 }
};

document.querySelectorAll("[data-widget]").forEach(button => {
  button.addEventListener("click", () => {
    const example = widgetExamples[button.dataset.widget];
    const preview = document.getElementById("widget-preview");
    preview.pause();
    preview.poster = example.poster;
    preview.src = example.clip;
    preview.setAttribute("aria-label", example.label);
    preview.width = example.width;
    preview.height = example.height;
    preview.load();
    document.getElementById("widget-description").textContent = example.caption;
    document.getElementById("widget-figure").classList.toggle("pet", button.dataset.widget === "pet");
    document.querySelectorAll("[data-widget]").forEach(option => {
      const selected = option === button;
      option.classList.toggle("active", selected);
      option.setAttribute("aria-pressed", String(selected));
    });
    updateVideo(preview);
  });
});

videos.forEach(video => video.addEventListener("loadeddata", () => updateVideo(video)));
updateAnimationState();
document.getElementById("year").textContent = new Date().getFullYear();
