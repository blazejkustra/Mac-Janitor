const FOOTAGE = ['sailboat', 'dandelion', 'moon'];

const params = new URLSearchParams(location.search);
const choice = FOOTAGE.includes(params.get('bg')) ? params.get('bg') : FOOTAGE[0];
document.body.dataset.bg = choice;

const backdrop = document.getElementById('backdrop');
document.getElementById('poster').src = `assets/footage/${choice}.jpg`;

function wantsStill() {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const saveData = navigator.connection && navigator.connection.saveData;
  return reduced || saveData;
}

function playLoop() {
  const small = matchMedia('(max-width: 720px)').matches;
  const video = document.createElement('video');
  video.src = `assets/footage/${choice}${small ? '-720' : ''}.mp4`;
  video.muted = true;
  video.loop = true;
  video.autoplay = true;
  video.playsInline = true;
  video.setAttribute('aria-hidden', 'true');
  video.addEventListener('playing', () => video.classList.add('playing'), { once: true });
  backdrop.appendChild(video);
}

if (!wantsStill()) {
  playLoop();
}
