const VIDEO = 'assets/demo.mp4';
const POSTER = 'assets/demo-poster.jpg';

const player = document.getElementById('player');
const frame = document.getElementById('frame');
const watch = document.getElementById('watch');

async function videoExists() {
  try {
    const response = await fetch(VIDEO, { method: 'HEAD' });
    return response.ok && (response.headers.get('content-type') || '').startsWith('video');
  } catch {
    return false;
  }
}

function open() {
  const video = document.createElement('video');
  video.src = VIDEO;
  video.poster = POSTER;
  video.controls = true;
  video.autoplay = true;
  video.playsInline = true;
  frame.replaceChildren(video);
  player.showModal();
}

function close() {
  player.close();
}

async function offerVideo() {
  if (!(await videoExists())) {
    return;
  }
  watch.hidden = false;
  if (location.hash === '#video') {
    open();
  }
}

watch.addEventListener('click', open);
document.getElementById('close').addEventListener('click', close);
player.addEventListener('click', event => {
  if (event.target === player) {
    close();
  }
});
player.addEventListener('close', () => frame.replaceChildren());

offerVideo();
