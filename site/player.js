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

function showVideo() {
  const video = document.createElement('video');
  video.src = VIDEO;
  video.poster = POSTER;
  video.controls = true;
  video.autoplay = true;
  video.playsInline = true;
  frame.replaceChildren(video);
}

function showComingSoon() {
  frame.replaceChildren(document.getElementById('soon').content.cloneNode(true));
}

async function open() {
  frame.replaceChildren();
  player.showModal();
  if (await videoExists()) {
    showVideo();
  } else {
    showComingSoon();
  }
}

function close() {
  player.close();
}

watch.addEventListener('click', open);
document.getElementById('close').addEventListener('click', close);
player.addEventListener('click', event => {
  if (event.target === player) {
    close();
  }
});
player.addEventListener('close', () => frame.replaceChildren());

if (location.hash === '#video') {
  open();
}
