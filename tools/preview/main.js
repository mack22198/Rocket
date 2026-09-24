// Draws the exported scene roughly the way Roblox would (flat approximations of its materials).
import * as THREE from "three";

const params = new URLSearchParams(location.search);
const view = params.get("view") || "overview";
const sceneFile = params.get("scene") || "scene.json";
const W = Number(params.get("w") || 1280), H = Number(params.get("h") || 720);

const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setSize(W, H);
renderer.setPixelRatio(1);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x8fc3ff);
scene.fog = new THREE.Fog(0xb9d8ff, 700, 2400);

scene.add(new THREE.HemisphereLight(0xdfefff, 0x4a5a40, 1.1));
const sun = new THREE.DirectionalLight(0xfff4e0, 2.4);
sun.position.set(260, 480, 200);
sun.castShadow = true;
sun.shadow.mapSize.set(4096, 4096);
const sc = sun.shadow.camera;
sc.left = -520; sc.right = 520; sc.top = 520; sc.bottom = -520; sc.near = 10; sc.far = 1600;
sun.shadow.bias = -0.0004;
scene.add(sun);
scene.add(sun.target);

function srgb(c) { return new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace); }

function wedgeGeometry(sx, sy, sz) {
  const x0 = -sx / 2, x1 = sx / 2, h = sy / 2, l = sz / 2;
  // triangle (y,z): bottom-front (-h,-l), bottom-back (-h,+l), top-back (+h,+l)
  const A = [-h, -l], B = [-h, l], C = [h, l];
  const v = (x, p) => [x, p[0], p[1]];
  const tris = [
    [v(x0, A), v(x0, C), v(x0, B)], [v(x1, A), v(x1, B), v(x1, C)], // sides
    [v(x0, A), v(x0, B), v(x1, B)], [v(x0, A), v(x1, B), v(x1, A)], // bottom
    [v(x0, B), v(x0, C), v(x1, C)], [v(x0, B), v(x1, C), v(x1, B)], // back
    [v(x0, A), v(x1, A), v(x1, C)], [v(x0, A), v(x1, C), v(x0, C)], // slope
  ];
  const pos = [];
  for (const t of tris) for (const p of t) pos.push(...p);
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}

function materialFor(p) {
  const color = srgb(p.col);
  const opacity = 1 - p.t;
  const transparent = p.t > 0.001;
  switch (p.m) {
    case "Neon":
      return new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(1.6), transparent, opacity });
    case "Glass":
      return new THREE.MeshStandardMaterial({ color, transparent: true, opacity: Math.min(opacity, 0.55), roughness: 0.05, metalness: 0.2, depthWrite: false });
    case "ForceField":
      return new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.35 * opacity, depthWrite: false });
    case "Metal": case "DiamondPlate": case "CorrodedMetal":
      return new THREE.MeshStandardMaterial({ color, metalness: 0.55, roughness: 0.35, transparent, opacity });
    case "Grass": case "Concrete": case "Slate": case "Sand": case "Fabric": case "Pebble": case "Ground":
      return new THREE.MeshStandardMaterial({ color, roughness: 1, metalness: 0, transparent, opacity });
    default:
      return new THREE.MeshStandardMaterial({ color, roughness: p.m === "SmoothPlastic" ? 0.45 : 0.6, metalness: p.r ? Math.min(0.8, p.r * 2) : 0, transparent, opacity });
  }
}

function geometryFor(p) {
  const [sx, sy, sz] = p.sz;
  switch (p.s) {
    case "Ball": return new THREE.SphereGeometry(Math.min(sx, sy, sz) / 2, 32, 20);
    case "Cylinder": {
      const g = new THREE.CylinderGeometry(Math.min(sy, sz) / 2, Math.min(sy, sz) / 2, sx, 40);
      g.rotateZ(-Math.PI / 2);
      return g;
    }
    case "Wedge": return wedgeGeometry(sx, sy, sz);
    case "Ellipsoid": {
      const g = new THREE.SphereGeometry(0.5, 32, 20);
      g.scale(sx, sy, sz);
      return g;
    }
    case "MeshCylinder": return new THREE.CylinderGeometry(sx / 2, sx / 2, sy, 32);
    default: return new THREE.BoxGeometry(sx, sy, sz);
  }
}

function matrixFor(cf) {
  const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = cf;
  return new THREE.Matrix4().set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
}

function signTexture(sign, wPx, hPx, pxPerStud) {
  const canvas = document.createElement("canvas");
  canvas.width = wPx; canvas.height = hPx;
  const ctx = canvas.getContext("2d");
  if (sign.bg) { ctx.fillStyle = `rgb(${sign.bg.map((v) => Math.round(v * 255)).join(",")})`; ctx.fillRect(0, 0, wPx, hPx); }
  // Roblox caps scaled text at 100 pixels of the SurfaceGui's own resolution.
  const cap = 100 * pxPerStud / (sign.pps || 50);
  for (const t of sign.texts) {
    const [rx, ry, rw, rh] = t.rect || [0, 0, 1, 1];
    const x = rx * wPx, y = ry * hPx, w = rw * wPx, h = rh * hPx;
    let size = Math.min(h * 0.82, cap);
    ctx.font = `bold ${size}px sans-serif`;
    while (ctx.measureText(t.text).width > w * 0.98 && size > 4) { size -= 1; ctx.font = `bold ${size}px sans-serif`; }
    ctx.fillStyle = `rgb(${t.col.map((v) => Math.round(v * 255)).join(",")})`;
    ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillText(t.text, x + w / 2, y + h / 2);
  }
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}

const res = await fetch(sceneFile);
const data = await res.json();
const meshes = [];
for (const p of data.parts) {
  if (p.t >= 0.99) { meshes.push(null); continue; }
  const mesh = new THREE.Mesh(geometryFor(p), materialFor(p));
  mesh.matrixAutoUpdate = false;
  mesh.matrix.copy(matrixFor(p.cf));
  mesh.castShadow = p.m !== "Neon" && p.t < 0.5;
  mesh.receiveShadow = true;
  scene.add(mesh);
  meshes.push(mesh);
}
for (const sign of (Array.isArray(data.guis) ? data.guis : [])) {
  const p = data.parts[sign.part - 1];
  const [sx, sy, sz] = p.sz;
  const faces = {
    Front: { w: sx, h: sy, off: new THREE.Vector3(0, 0, -sz / 2 - 0.05), rot: new THREE.Euler(0, Math.PI, 0) },
    Back: { w: sx, h: sy, off: new THREE.Vector3(0, 0, sz / 2 + 0.05), rot: new THREE.Euler(0, 0, 0) },
    Left: { w: sz, h: sy, off: new THREE.Vector3(-sx / 2 - 0.05, 0, 0), rot: new THREE.Euler(0, -Math.PI / 2, 0) },
    Right: { w: sz, h: sy, off: new THREE.Vector3(sx / 2 + 0.05, 0, 0), rot: new THREE.Euler(0, Math.PI / 2, 0) },
    Top: { w: sx, h: sz, off: new THREE.Vector3(0, sy / 2 + 0.05, 0), rot: new THREE.Euler(-Math.PI / 2, 0, 0) },
  };
  const f = faces[sign.face];
  if (!f) continue;
  const pxPerStud = Math.min(24, 4096 / Math.max(f.w, f.h));
  const tex = signTexture(sign, Math.max(64, Math.round(f.w * pxPerStud)), Math.max(32, Math.round(f.h * pxPerStud)), pxPerStud);
  const plane = new THREE.Mesh(new THREE.PlaneGeometry(f.w, f.h), new THREE.MeshBasicMaterial({ map: tex, transparent: !sign.bg }));
  const local = new THREE.Matrix4().compose(f.off, new THREE.Quaternion().setFromEuler(f.rot), new THREE.Vector3(1, 1, 1));
  plane.matrixAutoUpdate = false;
  plane.matrix.copy(matrixFor(p.cf).multiply(local));
  scene.add(plane);
}
for (const l of (Array.isArray(data.lights) ? data.lights : [])) {
  const p = data.parts[l.part - 1];
  const light = new THREE.PointLight(srgb(l.col), l.b * 40, l.range, 1.5);
  light.position.set(p.cf[0], p.cf[1], p.cf[2]);
  scene.add(light);
}
for (const t of (Array.isArray(data.terrain) ? data.terrain : [])) {
  const colors = { Grass: 0x5da84a, Water: 0x3a86c8, Sand: 0xd9c38c, Rock: 0x8a8f96, Ground: 0x7a6a4f, LeafyGrass: 0x4f9a3c, Asphalt: 0x3c3f45 };
  const mat = t.material === "Water"
    ? new THREE.MeshStandardMaterial({ color: colors.Water, roughness: 0.1, metalness: 0.1, transparent: true, opacity: 0.85 })
    : new THREE.MeshStandardMaterial({ color: colors[t.material] || 0x777777, roughness: 1 });
  let geo;
  if (t.kind === "ball") geo = new THREE.SphereGeometry(t.radius, 32, 16);
  else geo = new THREE.BoxGeometry(t.size[0], t.size[1], t.size[2]);
  const mesh = new THREE.Mesh(geo, mat);
  mesh.matrixAutoUpdate = false;
  mesh.matrix.copy(matrixFor(t.cf));
  mesh.receiveShadow = true;
  scene.add(mesh);
}

const views = {
  overview: { pos: [-40, 330, -560], at: [0, 10, 0], fov: 50 },
  aerial: { pos: [0, 420, 1], at: [0, 0, 0], fov: 60 },
  kickoff: { pos: [58, 8.5, -85], at: [0, 6, 0], fov: 78 },
  midfield: { pos: [-30, 14, -20], at: [20, 6, 90], fov: 78 },
  goal: { pos: [0, 16, 95], at: [0, 12, 165], fov: 70 },
  goalInside: { pos: [20, 10, -120], at: [0, 12, -175], fov: 70 },
  corner: { pos: [40, 28, 70], at: [100, 6, 140], fov: 70 },
  wallRide: { pos: [95, 40, -40], at: [110, 30, 60], fov: 70 },
  stands: { pos: [60, 30, 40], at: [-200, 60, -20], fov: 70 },
  lobby: { pos: [206, 60, 12], at: [0, 25, 0], fov: 70 },
  lobbyShowroom: { pos: [178, 62, -28], at: [220, 55, 8], fov: 70 },
  lobbyFromField: { pos: [-40, 22, 0], at: [194, 62, 0], fov: 70 },
  outside: { pos: [620, 240, -700], at: [40, 40, 0], fov: 50 },
  ball: { pos: [12, 9, -14], at: [0, 6, 0], fov: 45 },
  cars: { pos: [40, 14, 560], at: [40, 2, 600], fov: 45 },
  carsClose: { pos: [8, 6, 588], at: [8, 2, 600], fov: 45 },
};
const v = views[view] || views.overview;
const camera = new THREE.PerspectiveCamera(v.fov, W / H, 0.5, 5000);
camera.position.set(...(params.get("pos") ? params.get("pos").split(",").map(Number) : v.pos));
camera.lookAt(new THREE.Vector3(...(params.get("at") ? params.get("at").split(",").map(Number) : v.at)));
renderer.render(scene, camera);
window.__ready = true;
