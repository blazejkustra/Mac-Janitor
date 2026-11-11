const TAU = Math.PI * 2;

const JUNK = [
  { name: 'claude/fix-auth-3f9a', gb: 2.3, kind: 'worktree' },
  { name: 'codex/refactor-api', gb: 1.8, kind: 'worktree' },
  { name: 'claude/dark-mode-71c2', gb: 2.9, kind: 'worktree' },
  { name: 'cursor/onboarding-e04b', gb: 1.6, kind: 'worktree' },
  { name: 'codex/flaky-tests-5d1e', gb: 2.1, kind: 'worktree' },
  { name: 'claude/migrate-db-a7f0', gb: 3.4, kind: 'worktree' },
  { name: 'node_modules', gb: 1.2, kind: 'deps' },
  { name: 'node_modules', gb: 0.94, kind: 'deps' },
  { name: 'node_modules', gb: 1.7, kind: 'deps' },
  { name: 'Pods', gb: 0.74, kind: 'deps' },
  { name: '.next', gb: 0.38, kind: 'build' },
  { name: 'DerivedData', gb: 4.1, kind: 'build' },
  { name: 'target', gb: 2.6, kind: 'build' },
  { name: 'dist', gb: 0.21, kind: 'build' },
  { name: '~/.gradle/caches', gb: 3.2, kind: 'cache' },
  { name: '~/.pnpm-store', gb: 2.4, kind: 'cache' },
  { name: '~/.cargo/registry', gb: 1.1, kind: 'cache' },
  { name: 'Yarn cache', gb: 0.86, kind: 'cache' },
  { name: 'node:20-bookworm', gb: 1.1, kind: 'docker' },
  { name: 'postgres:16', gb: 0.43, kind: 'docker' },
  { name: 'factory-runner:latest', gb: 2.7, kind: 'docker' },
  { name: '.agent-scratch/run-12', gb: 0.31, kind: 'scratch' },
  { name: '~/.claude/projects', gb: 0.62, kind: 'scratch' },
  { name: 'codex-tmp-8c1d', gb: 0.18, kind: 'scratch' },
  { name: 'Pixel_8_API_35', gb: 6.2, kind: 'system' },
  { name: 'Trash from October', gb: 1.9, kind: 'system' },
];

const GUARDS = [
  { badge: 'run', reason: 'An agent is still running here', done: 'Agent finished' },
  { badge: 'lock', reason: '2 commits not pushed yet', done: 'Pushed' },
  { badge: 'run', reason: 'Vite has files open in here', done: 'Vite closed' },
];

const TINTS = {
  worktree: ['#2c74a0', '#4b9bcb'],
  deps: ['#4888b2', '#6db0da'],
  build: ['#566b7e', '#7a90a4'],
  cache: ['#365f7c', '#5584a5'],
  docker: ['#2a6a90', '#3f8bb8'],
  scratch: ['#647789', '#8ea2b5'],
  system: ['#45566a', '#687c90'],
};

const MILESTONES = [
  { gb: 10, text: '10 GB. A whole Xcode.' },
  { gb: 25, text: '25 GB. Busy agents.' },
  { gb: 50, text: '50 GB. Your SSD breathes.' },
  { gb: 100, text: '100 GB. Fine, you win.' },
];

const LOCK_ICON = '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M4.5 7V5.2a3.5 3.5 0 0 1 7 0V7h.3c.66 0 1.2.54 1.2 1.2v5.6c0 .66-.54 1.2-1.2 1.2H4.2C3.54 15 3 14.46 3 13.8V8.2C3 7.54 3.54 7 4.2 7Zm1.8 0h3.4V5.2a1.7 1.7 0 0 0-3.4 0Z"/></svg>';

const FOLDER_SVG = `
<svg viewBox="0 0 100 80" aria-hidden="true">
  <path class="back" d="M4 10a6 6 0 0 1 6-6h23.4a6 6 0 0 1 4.5 2.1L42 11h48a6 6 0 0 1 6 6v55a6 6 0 0 1-6 6H10a6 6 0 0 1-6-6Z"/>
  <rect class="paper" x="10" y="15" width="80" height="28" rx="3"/>
  <rect class="front" x="4" y="23" width="92" height="55" rx="7"/>
  <rect class="lip" x="7" y="23.5" width="86" height="2.2" rx="1.1"/>
  <g class="jt-eyes">
    <ellipse class="white" cx="38" cy="47" rx="6.4" ry="7.4"/>
    <ellipse class="white" cx="62" cy="47" rx="6.4" ry="7.4"/>
    <g class="jt-pupils">
      <circle class="pupil" cx="38" cy="48" r="3.5"/>
      <circle class="pupil" cx="62" cy="48" r="3.5"/>
    </g>
  </g>
  <path class="brow" d="M31 37.5l11 3.5M69 37.5l-11 3.5"/>
  <ellipse class="cheek" cx="27" cy="58" rx="4.5" ry="2.6"/>
  <ellipse class="cheek" cx="73" cy="58" rx="4.5" ry="2.6"/>
  <path class="mouth smile" d="M45 60q5 4.5 10 0"/>
  <path class="mouth flat" d="M45.5 62h9"/>
  <ellipse class="mouth gasp" cx="50" cy="62" rx="3" ry="3.6"/>
</svg>`;

const rand = (min, max) => min + Math.random() * (max - min);
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const pick = (list) => list[Math.floor(Math.random() * list.length)];

function formatSize(gb) {
  return gb < 1 ? `${Math.round(gb * 1000)} MB` : `${gb.toFixed(1)} GB`;
}

function formatCount(gb) {
  return gb < 100 ? gb.toFixed(1) : String(Math.round(gb));
}

function el(tag, className, html) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (html) node.innerHTML = html;
  return node;
}

function segmentHitsBox(ax, ay, bx, by, box) {
  const steps = Math.max(1, Math.ceil(Math.hypot(bx - ax, by - ay) / 8));
  for (let i = 0; i <= steps; i++) {
    const x = ax + ((bx - ax) * i) / steps;
    const y = ay + ((by - ay) * i) / steps;
    if (x > box.l && x < box.r && y > box.t && y < box.b) return true;
  }
  return false;
}

function pushOutOfRect(folder, rect) {
  const box = folder.box();
  const overlapX = Math.min(box.r - rect.l, rect.r - box.l);
  const overlapY = Math.min(box.b - rect.t, rect.b - box.t);
  if (overlapX <= 0 || overlapY <= 0) return;
  if (overlapX < overlapY) {
    const dir = folder.x < (rect.l + rect.r) / 2 ? -1 : 1;
    folder.x += dir * overlapX;
    folder.vx = dir * Math.abs(folder.vx);
    folder.heading = Math.atan2(folder.vy, dir);
  } else {
    const dir = folder.y < (rect.t + rect.b) / 2 ? -1 : 1;
    folder.y += dir * overlapY;
    folder.vy = dir * Math.abs(folder.vy);
    folder.heading = Math.atan2(dir, folder.vx);
  }
}

class Folder {
  constructor(toy, item, guard, x, y) {
    this.toy = toy;
    this.item = item;
    this.guard = guard;
    this.x = x;
    this.y = y;
    this.vx = 0;
    this.vy = 0;
    this.heading = rand(0, TAU);
    this.cruise = rand(18, 38);
    this.stride = rand(9, 12);
    this.walk = rand(0, TAU);
    this.hop = 0;
    this.tilt = 0;
    this.squash = 0;
    this.squashVel = 0;
    this.wobble = 0;
    this.lookX = 0;
    this.lookY = 0;
    this.age = 0;
    this.restUntil = 0;
    this.nextRest = rand(3, 7);
    this.nextBlink = rand(1, 4);
    this.blinkUntil = 0;
    this.scaredFor = 0;
    this.tipUntil = 0;
    this.nopeUntil = 0;
    this.refusedAt = -9;
    this.releaseAt = guard ? rand(16, 30) : Infinity;
    this.state = 'alive';
    this.stateTime = 0;
    this.flags = {};
    this.lastZ = -1;
    this.w = clamp((50 + Math.sqrt(item.gb) * 21) * toy.scale, 50, 106);
    this.h = this.w * 0.8;
    this.build();
  }

  build() {
    const [back, front] = TINTS[this.item.kind];
    this.colors = [back, front, front, '#ffffff', '#cfe8f7'];
    const node = el('button', 'jt-folder is-new');
    node.type = 'button';
    node.style.width = `${this.w}px`;
    node.style.setProperty('--back', back);
    node.style.setProperty('--front', front);
    node.setAttribute('aria-label', this.label());
    this.shadow = el('span', 'jt-shadow');
    this.pose = el('span', 'jt-pose');
    this.anim = el('span', 'jt-anim', FOLDER_SVG);
    this.pose.append(this.anim);
    if (this.guard) this.addGuard();
    const tag = el('span', 'jt-tag');
    tag.append(el('b', '', this.item.name), el('i', '', formatSize(this.item.gb)));
    node.append(this.shadow, this.pose, tag);
    this.node = node;
    this.tag = tag;
    this.pupils = node.querySelector('.jt-pupils');
    node.addEventListener('click', () => this.toy.strike(this));
    setTimeout(() => node.classList.remove('is-new'), 600);
  }

  addGuard() {
    this.badge = el('span', `jt-badge ${this.guard.badge}`, this.guard.badge === 'lock' ? LOCK_ICON : '');
    this.anim.append(this.badge);
    this.tip = el('span', 'jt-tip', this.guard.reason);
    this.pose.append(this.tip);
  }

  label() {
    const size = formatSize(this.item.gb);
    return this.guard ? `${this.item.name}, ${size}. Kept: ${this.guard.reason}` : `Clean ${this.item.name}, ${size}`;
  }

  mount(parent) {
    parent.append(this.node);
    this.tagW = this.tag.offsetWidth;
    this.tagH = this.tag.offsetHeight;
    this.halfW = Math.max(this.w, this.tagW) / 2 + 4;
    const top = -this.h / 2;
    const bottom = this.h / 2 + 7 + this.tagH;
    this.boxDy = (top + bottom) / 2;
    this.halfH = (bottom - top) / 2 + 3;
    this.render();
  }

  box(pad = 0) {
    const cy = this.y + this.boxDy;
    return { l: this.x - this.halfW - pad, r: this.x + this.halfW + pad, t: cy - this.halfH - pad, b: cy + this.halfH + pad };
  }

  setFlag(name, on) {
    if (this.flags[name] === on) return;
    this.flags[name] = on;
    this.node.classList.toggle(name, on);
  }

  bump(strength) {
    this.squashVel += strength;
  }

  update(dt) {
    this.age += dt;
    this.stateTime += dt;
    if (this.state !== 'alive') return;
    if (this.age > this.releaseAt) this.release();
    this.steer(dt);
    this.flee(dt);
    this.integrate(dt);
    this.animateBody(dt);
    this.updateFace(dt);
  }

  steer(dt) {
    if (this.age > this.nextRest) {
      this.restUntil = this.age + rand(0.6, 1.8);
      this.nextRest = this.restUntil + rand(3, 8);
    }
    this.heading += rand(-1, 1) * 3 * dt;
    const resting = this.age < this.restUntil;
    const speed = resting ? 0 : this.cruise * this.toy.scale;
    const tx = Math.cos(this.heading) * speed;
    const ty = Math.sin(this.heading) * speed * 0.75;
    const ease = Math.min(1, dt * 2.2);
    this.vx += (tx - this.vx) * ease;
    this.vy += (ty - this.vy) * ease;
  }

  flee(dt) {
    const pointer = this.toy.pointer;
    this.scaredFor = Math.max(0, this.scaredFor - dt);
    if (this.guard || !pointer.active) return;
    const dx = this.x - pointer.x;
    const dy = this.y - pointer.y;
    const dist = Math.hypot(dx, dy) || 1;
    const range = 160 * this.toy.scale;
    if (dist > range) return;
    const push = (1 - dist / range) ** 2 * 1700 * this.toy.scale;
    this.vx += (dx / dist) * push * dt;
    this.vy += (dy / dist) * push * dt;
    if (this.scaredFor === 0) this.bump(-2.2);
    this.scaredFor = 0.45;
    this.restUntil = 0;
    this.heading = Math.atan2(dy, dx);
  }

  integrate(dt) {
    const limit = (this.scaredFor > 0 ? 210 : 70) * this.toy.scale;
    const speed = Math.hypot(this.vx, this.vy);
    if (speed > limit) {
      this.vx *= limit / speed;
      this.vy *= limit / speed;
    }
    this.x += this.vx * dt;
    this.y += this.vy * dt;
  }

  animateBody(dt) {
    const speed = Math.hypot(this.vx, this.vy);
    const effort = clamp(speed / (this.cruise * this.toy.scale), 0, 1);
    const pace = this.scaredFor > 0 ? 1.9 : 1;
    this.walk += dt * this.stride * pace * (0.35 + effort);
    this.hop = Math.abs(Math.sin(this.walk)) * 3.4 * this.toy.scale * effort * pace;
    this.squashVel += (-260 * this.squash - 13 * this.squashVel) * dt;
    this.squash += this.squashVel * dt;
    this.wobble = Math.max(0, this.wobble - dt * 1.6);
    const sway = Math.sin(this.walk) * 5 * effort;
    const lean = clamp(this.vx * 0.05, -9, 9);
    const shake = Math.sin(this.age * 48) * 16 * this.wobble ** 1.5;
    this.tilt = sway + lean + shake;
  }

  updateFace(dt) {
    if (this.age > this.nextBlink) {
      this.blinkUntil = this.age + 0.13;
      this.nextBlink = this.age + rand(2, 5.5);
    }
    this.setFlag('is-blink', this.age < this.blinkUntil);
    this.setFlag('is-scared', this.scaredFor > 0);
    this.setFlag('is-nope', this.age < this.nopeUntil);
    this.setFlag('is-tip', this.age < this.tipUntil);
    this.aimEyes(dt);
  }

  aimEyes(dt) {
    const pointer = this.toy.pointer;
    let tx = this.vx;
    let ty = this.vy;
    const dx = pointer.x - this.x;
    const dy = pointer.y - this.y;
    if (pointer.active && Math.hypot(dx, dy) < 340) {
      tx = dx;
      ty = dy;
    }
    const len = Math.hypot(tx, ty);
    const reach = len < 4 ? 0 : 2.6;
    const ease = Math.min(1, dt * 12);
    this.lookX += ((len ? tx / len : 0) * reach - this.lookX) * ease;
    this.lookY += ((len ? ty / len : 0) * reach * 0.8 - this.lookY) * ease;
  }

  refuse() {
    if (this.age - this.refusedAt < 0.9) {
      this.tipUntil = this.age + 1.4;
      return false;
    }
    this.refusedAt = this.age;
    this.wobble = 1;
    this.nopeUntil = this.age + 0.9;
    this.tipUntil = this.age + 1.8;
    this.bump(3);
    return true;
  }

  release() {
    this.releaseAt = Infinity;
    this.badge.classList.add('is-gone');
    this.tip.remove();
    this.toy.floatNote(this, this.guard.done);
    this.guard = null;
    this.tipUntil = 0;
    this.bump(4);
    this.node.setAttribute('aria-label', this.label());
  }

  pop() {
    this.state = 'popping';
    this.stateTime = 0;
    this.setFlag('is-tip', false);
    this.node.classList.add('is-popping');
  }

  fade() {
    this.state = 'fading';
    this.stateTime = 0;
    this.node.classList.add('is-fading');
  }

  render() {
    const x = this.x - this.w / 2;
    const y = this.y - this.h / 2;
    this.node.style.transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0)`;
    const sx = 1 + this.squash * 0.03;
    const sy = 1 - this.squash * 0.03;
    this.pose.style.transform = `translateY(${(-this.hop).toFixed(2)}px) rotate(${this.tilt.toFixed(2)}deg) scale(${sx.toFixed(3)}, ${sy.toFixed(3)})`;
    this.shadow.style.transform = `scale(${(1 - this.hop / 22).toFixed(3)})`;
    this.pupils.setAttribute('transform', `translate(${this.lookX.toFixed(2)} ${this.lookY.toFixed(2)})`);
    const z = Math.round(this.y / 4);
    if (z !== this.lastZ) {
      this.lastZ = z;
      this.node.style.zIndex = String(10 + z);
    }
  }
}

class Particle {
  constructor(x, y, color, share, scale) {
    const angle = rand(0, TAU);
    const speed = rand(120, 380) * scale;
    this.x = x;
    this.y = y;
    this.vx = Math.cos(angle) * speed;
    this.vy = Math.sin(angle) * speed - 60 * scale;
    this.size = rand(3, 7) * scale;
    this.spin = rand(-12, 12);
    this.turn = rand(0, TAU);
    this.color = color;
    this.share = share;
    this.age = 0;
    this.delay = rand(0.12, 0.3);
  }

  update(dt, target) {
    this.age += dt;
    this.turn += this.spin * dt;
    const dx = target.x - this.x;
    const dy = target.y - this.y;
    const dist = Math.hypot(dx, dy) || 1;
    if (this.age < this.delay) {
      this.vx *= 1 - dt * 4;
      this.vy *= 1 - dt * 4;
    } else {
      const pull = 1100 + this.age * 1800;
      const ease = Math.min(1, dt * (4 + this.age * 6));
      this.vx += ((dx / dist) * pull - this.vx) * ease;
      this.vy += ((dy / dist) * pull - this.vy) * ease;
    }
    this.x += this.vx * dt;
    this.y += this.vy * dt;
    this.fade = clamp(dist / 70, 0.25, 1);
    return dist < 16;
  }

  draw(ctx) {
    const size = this.size * this.fade;
    ctx.save();
    ctx.translate(this.x, this.y);
    ctx.rotate(this.turn);
    ctx.fillStyle = this.color;
    ctx.fillRect(-size / 2, -size / 2, size, size);
    ctx.restore();
  }
}

class JanitorToy {
  constructor(root) {
    this.root = root;
    this.field = root.querySelector('.jt-field');
    this.canvas = root.querySelector('.jt-canvas');
    this.ctx = this.canvas.getContext('2d');
    this.sink = root.querySelector('.jt-sink');
    this.countEl = root.querySelector('.jt-count');
    this.hintEl = root.querySelector('.jt-hint');
    this.events = root.dataset.events ? root.closest(root.dataset.events) : root;
    this.reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.touchFirst = matchMedia('(hover: none)').matches;
    this.folders = [];
    this.particles = [];
    this.pointer = { x: -999, y: -999, lastX: -999, lastY: -999, active: false, touch: false };
    this.freed = 0;
    this.shown = 0;
    this.kept = new Set();
    this.milestone = 0;
    this.deck = [];
    this.spawnIn = 0.2;
    this.sinkScale = 0;
    this.sinkVel = 0;
    this.sinkOpen = false;
    this.cleaned = 0;
    this.visible = true;
    this.pageVisible = !document.hidden;
    this.frame = this.frame.bind(this);
    this.measure();
    this.setHint(this.startHint());
    document.fonts?.ready.then(() => this.reserveHintWidth());
    this.bindPointer();
    this.bindLifecycle();
    this.seed();
  }

  startHint() {
    if (this.reduced) return this.root.dataset.hintClick || 'Click a folder to clean it up.';
    if (this.touchFirst) return this.root.dataset.hintTouch || 'Tap or swipe across a folder.';
    return this.root.dataset.hint || 'Hover a folder to clean it up.';
  }

  allHints() {
    const data = this.root.dataset;
    const hints = [data.hint, data.hintTouch, data.hintClick, data.hintAfter, data.hintKept];
    return [...hints, ...MILESTONES.map((m) => m.text)].filter(Boolean);
  }

  reserveHintWidth() {
    if (!this.hintEl) return;
    const probe = this.hintEl.cloneNode(false);
    probe.style.cssText = 'position: absolute; visibility: hidden; width: auto; max-width: none;';
    this.hintEl.after(probe);
    const widths = this.allHints().map((text) => {
      probe.textContent = text;
      return probe.getBoundingClientRect().width;
    });
    probe.remove();
    this.hintEl.style.width = `${Math.ceil(Math.max(...widths))}px`;
  }

  measure() {
    this.reserveHintWidth();
    const rect = this.root.getBoundingClientRect();
    this.width = rect.width;
    this.height = rect.height;
    this.scale = clamp(0.62 + rect.width / 2400, 0.76, 1);
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(rect.width * ratio);
    this.canvas.height = Math.round(rect.height * ratio);
    this.ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    this.obstacles = this.avoidNodes().map((node) => this.relativeRect(node, rect, 10));
    const sinkRect = this.sink.getBoundingClientRect();
    this.sinkPoint = { x: sinkRect.left + sinkRect.width / 2 - rect.left, y: sinkRect.top + sinkRect.height * 0.45 - rect.top };
    const blocked = this.obstacles.reduce((sum, r) => sum + (r.r - r.l) * (r.b - r.t), 0);
    const free = Math.max(0, rect.width * rect.height - blocked);
    this.cap = clamp(Math.round(free / (36000 * this.scale * this.scale)), 4, 16);
    this.rectRoot = rect;
  }

  avoidNodes() {
    const inside = [...this.root.querySelectorAll('[data-avoid]')];
    const outside = this.root.dataset.avoid ? [...document.querySelectorAll(this.root.dataset.avoid)] : [];
    return [...inside, ...outside];
  }

  relativeRect(node, base, pad) {
    const r = node.getBoundingClientRect();
    return { l: r.left - base.left - pad, r: r.right - base.left + pad, t: r.top - base.top - pad, b: r.bottom - base.top + pad };
  }

  bindPointer() {
    const target = this.events;
    target.addEventListener('pointermove', (e) => this.onPointer(e, false));
    target.addEventListener('pointerdown', (e) => this.onPointer(e, true));
    target.addEventListener('pointerup', (e) => this.onPointerEnd(e));
    target.addEventListener('pointercancel', (e) => this.onPointerEnd(e));
    target.addEventListener('pointerleave', (e) => this.onPointerEnd(e));
  }

  onPointer(event, pressed) {
    const isTouch = event.pointerType !== 'mouse';
    if (isTouch && !pressed && !this.pointer.active) return;
    const rect = this.root.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    const restart = !this.pointer.active || pressed;
    this.pointer.lastX = restart ? x : this.pointer.x;
    this.pointer.lastY = restart ? y : this.pointer.y;
    this.pointer.x = x;
    this.pointer.y = y;
    this.pointer.active = true;
    this.pointer.touch = isTouch;
    if (!this.reduced) this.checkHits();
  }

  onPointerEnd(event) {
    if (event.type === 'pointerup' && event.pointerType === 'mouse') return;
    this.pointer.active = false;
    this.pointer.x = -999;
    this.pointer.y = -999;
  }

  bindLifecycle() {
    new ResizeObserver(() => this.measure()).observe(this.root);
    this.avoidNodes().forEach((node) => new ResizeObserver(() => this.measure()).observe(node));
    new IntersectionObserver(([entry]) => {
      this.visible = entry.isIntersecting;
      this.syncRunning();
    }).observe(this.root);
    document.addEventListener('visibilitychange', () => {
      this.pageVisible = !document.hidden;
      this.syncRunning();
    });
    setTimeout(() => this.measure(), 900);
    this.syncRunning();
  }

  syncRunning() {
    const shouldRun = this.visible && this.pageVisible;
    if (shouldRun && !this.running) {
      this.running = true;
      this.last = performance.now();
      requestAnimationFrame(this.frame);
    }
    if (!shouldRun) this.running = false;
  }

  seed() {
    const count = Math.round(this.cap * 0.75);
    for (let i = 0; i < count; i++) {
      setTimeout(() => this.spawn(), this.reduced ? 0 : 150 + i * 110);
    }
    this.spawnIn = this.reduced ? 4 : 2.5;
  }

  drawItem() {
    const onScreen = new Set(this.folders.map((f) => f.item));
    if (this.needsGuard()) return pick(JUNK.filter((j) => (j.kind === 'worktree' || j.kind === 'deps') && !onScreen.has(j)));
    for (let tries = 0; tries < JUNK.length * 2; tries++) {
      if (!this.deck.length) this.deck = [...JUNK].sort(() => Math.random() - 0.5);
      const item = this.deck.pop();
      if (!onScreen.has(item)) return item;
    }
    return pick(JUNK);
  }

  needsGuard() {
    const guarded = this.folders.filter((f) => f.guard && f.state === 'alive').length;
    return guarded < (this.cap >= 8 ? 2 : 1);
  }

  spawn() {
    if (this.alive().length >= this.cap) return;
    const guard = this.needsGuard() ? pick(GUARDS) : null;
    const item = this.drawItem();
    const folder = new Folder(this, item, guard, 0, 0);
    folder.mount(this.field);
    if (!this.placeFolder(folder)) {
      folder.node.remove();
      return;
    }
    folder.render();
    this.folders.push(folder);
    if (!this.reduced) this.puff(folder.x, folder.y);
  }

  placeFolder(folder) {
    for (let tries = 0; tries < 40; tries++) {
      folder.x = rand(folder.halfW + 8, this.width - folder.halfW - 8);
      folder.y = rand(folder.h / 2 + 40, this.height - folder.halfH * 2);
      const box = folder.box(6);
      const clear = this.obstacles.every((r) => box.r < r.l || box.l > r.r || box.b < r.t || box.t > r.b);
      const roomy = this.folders.every((f) => Math.abs(f.x - folder.x) > f.halfW + folder.halfW || Math.abs(f.y + f.boxDy - folder.y - folder.boxDy) > f.halfH + folder.halfH);
      const away = Math.hypot(folder.x - this.pointer.x, folder.y - this.pointer.y) > 180;
      if (clear && roomy && away) return true;
    }
    return false;
  }

  alive() {
    return this.folders.filter((f) => f.state === 'alive');
  }

  frame(now) {
    if (!this.running) return;
    const dt = Math.min((now - this.last) / 1000, 1 / 30);
    this.last = now;
    this.tickSpawner(dt);
    if (this.reduced) {
      this.tickReduced(dt);
    } else {
      this.tickMotion(dt);
    }
    this.tickCounter(dt);
    requestAnimationFrame(this.frame);
  }

  tickSpawner(dt) {
    this.spawnIn -= dt;
    if (this.spawnIn > 0) return;
    this.spawn();
    const sparse = this.alive().length < this.cap * 0.5;
    this.spawnIn = this.reduced ? rand(3, 5) : sparse ? rand(0.4, 0.8) : rand(1.3, 2.6);
  }

  tickMotion(dt) {
    this.checkHits();
    this.folders.forEach((f) => f.update(dt));
    this.keepInside();
    this.separate();
    this.folders.forEach((f) => f.render());
    this.finishPops();
    this.tickParticles(dt);
    this.tickSink(dt);
  }

  tickReduced(dt) {
    this.folders.forEach((f) => {
      f.age += dt;
      f.stateTime += dt;
      if (f.state !== 'alive') return;
      if (f.age > f.releaseAt) f.release();
      f.setFlag('is-tip', f.age < f.tipUntil);
      f.setFlag('is-nope', f.age < f.nopeUntil);
    });
    this.finishPops();
  }

  checkHits() {
    const p = this.pointer;
    if (!p.active) return;
    this.alive().forEach((f) => {
      if (segmentHitsBox(p.lastX, p.lastY, p.x, p.y, f.box(-2))) this.strike(f);
    });
    p.lastX = p.x;
    p.lastY = p.y;
  }

  strike(folder) {
    if (folder.state !== 'alive') return;
    if (folder.guard) {
      if (folder.refuse()) this.noteKept(folder);
      return;
    }
    this.cleaned++;
    if (this.reduced) {
      folder.fade();
      this.addFreed(folder.item.gb);
    } else {
      folder.pop();
      this.floatText(folder.x, folder.y - folder.h / 2, `+${formatSize(folder.item.gb)}`);
    }
    if (this.cleaned === 1) this.setHint(this.root.dataset.hintAfter || 'Agents keep making more. Keep going.');
  }

  noteKept(folder) {
    if (this.kept.has(folder)) return;
    this.kept.add(folder);
    if (this.kept.size === 1) this.setHint(this.root.dataset.hintKept || 'Folders an agent still uses stay put.');
  }

  finishPops() {
    this.folders = this.folders.filter((f) => {
      if (f.state === 'popping' && !f.emitted && f.stateTime > 0.08) this.burst(f);
      const done = (f.state === 'popping' && f.stateTime > 0.22) || (f.state === 'fading' && f.stateTime > 0.3);
      if (done) f.node.remove();
      return !done;
    });
  }

  burst(folder) {
    folder.emitted = true;
    const count = clamp(Math.round(12 + Math.sqrt(folder.item.gb) * 9), 12, 34);
    const share = folder.item.gb / count;
    for (let i = 0; i < count; i++) {
      const x = folder.x + rand(-0.42, 0.42) * folder.w;
      const y = folder.y + rand(-0.36, 0.36) * folder.h;
      this.particles.push(new Particle(x, y, pick(folder.colors), share, this.scale));
    }
  }

  tickParticles(dt) {
    const hadParticles = this.particles.length > 0;
    this.particles = this.particles.filter((p) => {
      const arrived = p.update(dt, this.sinkPoint);
      if (arrived) this.swallow(p.share);
      return !arrived;
    });
    if (hadParticles) this.drawParticles();
  }

  drawParticles() {
    this.ctx.clearRect(0, 0, this.width, this.height);
    this.particles.forEach((p) => p.draw(this.ctx));
  }

  swallow(share) {
    this.addFreed(share);
    this.sinkVel += 1.4;
  }

  tickSink(dt) {
    this.sinkVel += (-320 * this.sinkScale - 16 * this.sinkVel) * dt;
    this.sinkScale += this.sinkVel * dt;
    const s = clamp(1 + this.sinkScale * 0.12, 0.85, 1.25);
    this.sink.style.transform = `scale(${s.toFixed(3)}, ${(2 - s).toFixed(3)})`;
    const near = this.particles.some((p) => p.age > p.delay && Math.hypot(p.x - this.sinkPoint.x, p.y - this.sinkPoint.y) < 160);
    if (near !== this.sinkOpen) {
      this.sinkOpen = near;
      this.sink.classList.toggle('is-open', near);
    }
  }

  keepInside() {
    const pad = 6;
    this.alive().forEach((f) => {
      const top = f.h / 2 + (f.guard ? 44 : pad);
      const bottom = this.height - (f.halfH * 2 - f.h / 2) - pad;
      if (f.x < f.halfW + pad) this.bounceWall(f, 'x', f.halfW + pad, 1);
      if (f.x > this.width - f.halfW - pad) this.bounceWall(f, 'x', this.width - f.halfW - pad, -1);
      if (f.y < top) this.bounceWall(f, 'y', top, 1);
      if (f.y > bottom) this.bounceWall(f, 'y', bottom, -1);
      this.obstacles.forEach((r) => pushOutOfRect(f, r));
    });
  }

  bounceWall(folder, axis, limit, dir) {
    folder[axis] = limit;
    const velKey = axis === 'x' ? 'vx' : 'vy';
    if (Math.sign(folder[velKey]) !== dir) {
      folder[velKey] = Math.abs(folder[velKey]) * dir * 0.6;
      folder.heading = axis === 'x' ? Math.atan2(Math.sin(folder.heading), dir) : Math.atan2(dir, Math.cos(folder.heading));
    }
  }

  separate() {
    const list = this.alive();
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) this.collide(list[i], list[j]);
    }
  }

  collide(a, b) {
    const dx = b.x - a.x;
    const dy = b.y + b.boxDy - (a.y + a.boxDy);
    const overlapX = a.halfW + b.halfW - Math.abs(dx);
    const overlapY = a.halfH + b.halfH - Math.abs(dy);
    if (overlapX <= 0 || overlapY <= 0) return;
    const axis = overlapX < overlapY ? 'x' : 'y';
    const dir = Math.sign(axis === 'x' ? dx : dy) || 1;
    const amount = Math.min(axis === 'x' ? overlapX : overlapY, 6) / 2;
    const velKey = axis === 'x' ? 'vx' : 'vy';
    a[axis] -= dir * amount;
    b[axis] += dir * amount;
    const closing = (a[velKey] - b[velKey]) * dir;
    if (closing <= 6) return;
    const swap = a[velKey];
    a[velKey] = b[velKey] * 0.8 - dir * 18;
    b[velKey] = swap * 0.8 + dir * 18;
    a.heading += Math.PI * 0.6;
    b.heading -= Math.PI * 0.6;
    const hit = clamp(closing / 14, 1, 5);
    a.bump(hit);
    b.bump(hit);
    a.blinkUntil = a.age + 0.18;
    b.blinkUntil = b.age + 0.18;
  }

  addFreed(gb) {
    this.freed += gb;
    if (this.reduced) this.shown = this.freed;
    this.checkMilestone();
  }

  checkMilestone() {
    const next = MILESTONES[this.milestone];
    if (!next || this.freed < next.gb - 0.001) return;
    this.milestone++;
    this.setHint(next.text);
    this.countEl.classList.remove('is-milestone');
    void this.countEl.offsetWidth;
    this.countEl.classList.add('is-milestone');
  }

  tickCounter(dt) {
    const gap = this.freed - this.shown;
    this.shown = Math.abs(gap) < 0.01 ? this.freed : this.shown + gap * (1 - Math.exp(-dt * 7));
    const text = formatCount(this.shown);
    if (text !== this.countText) {
      this.countText = text;
      this.countEl.textContent = text;
    }
  }

  setHint(text) {
    if (!this.hintEl || this.hintEl.textContent === text) return;
    this.hintEl.classList.add('is-swap');
    setTimeout(() => {
      this.hintEl.textContent = text;
      this.hintEl.classList.remove('is-swap');
    }, this.hintEl.textContent ? 220 : 0);
  }

  floatText(x, y, text, extra = '') {
    const node = el('span', `jt-float ${extra}`, '');
    node.textContent = text;
    node.style.left = `${x}px`;
    node.style.top = `${y}px`;
    this.field.append(node);
    node.addEventListener('animationend', () => node.remove());
  }

  floatNote(folder, text) {
    this.floatText(folder.x, folder.y - folder.h / 2 - 10, text, 'note');
  }

  puff(x, y) {
    const node = el('span', 'jt-puff');
    node.style.left = `${x}px`;
    node.style.top = `${y}px`;
    this.field.append(node);
    node.addEventListener('animationend', () => node.remove());
  }
}

document.querySelectorAll('[data-janitor-toy]').forEach((root) => new JanitorToy(root));
