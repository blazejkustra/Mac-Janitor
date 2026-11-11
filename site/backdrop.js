const PHOTOS = ['dunes', 'river', 'coast'];
const DEFAULT_PHOTO = PHOTOS[0];

function chosenPhoto() {
  const requested = new URLSearchParams(location.search).get('bg');
  return PHOTOS.includes(requested) ? requested : DEFAULT_PHOTO;
}

function swapPhoto(path, photo) {
  return path.replace(`/${DEFAULT_PHOTO}-`, `/${photo}-`);
}

function showPhoto(photo) {
  const picture = document.getElementById('backdrop');
  picture.querySelectorAll('source').forEach(source => {
    source.srcset = swapPhoto(source.srcset, photo);
  });
  const img = picture.querySelector('img');
  img.src = swapPhoto(img.src, photo);
}

const photo = chosenPhoto();
document.body.dataset.bg = photo;
if (photo !== DEFAULT_PHOTO) {
  showPhoto(photo);
}
