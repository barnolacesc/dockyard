const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const mobile = matchMedia('(max-width: 760px)').matches;
const videos = [...document.querySelectorAll('.lazy-video')];
const loadVideo = video => {
  for (const source of video.querySelectorAll('source[data-src]')) {
    source.src = source.dataset.src;
    source.removeAttribute('data-src');
  }
  video.load();
};
if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver(entries => entries.forEach(entry => {
    if (!entry.isIntersecting) return;
    loadVideo(entry.target);
    if (!reduced && (!mobile || entry.intersectionRatio > .6)) entry.target.play().catch(() => {});
    observer.unobserve(entry.target);
  }), {rootMargin: mobile ? '80px' : '320px', threshold: mobile ? .6 : .15});
  videos.forEach(video => observer.observe(video));
} else {
  videos.forEach(loadVideo);
}
if (reduced) document.querySelectorAll('video').forEach(video => { video.autoplay = false; video.pause(); });
