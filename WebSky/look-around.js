// Tatvaum app addition (not part of the original design page): "Look around" mode.
// The camera flies into Earth and then follows the phone's orientation, so each planet, sign and star
// appears in the direction it was in the sky at the birth moment, as seen from the birthplace.
//
// Needs: window.__sky = { THREE, camera, controls, scene, earth } (exposed by the app when it loads the
// page), window.__TATVAUM_BIRTH = { utc, lat, lon, place }, and the app bridge window.TatvaumApp
// (startLook / stopLook), which streams the phone's rotation matrix to window.__skyLookSet.
(function () {
  var D2R = Math.PI / 180;
  var L = null;            // state while looking around
  var horizon = null;      // horizon ring and N/E/S/W markers (built once)
  var M = null;            // columns: east/north/up components of the scene's x, y, z axes

  function birth() { return window.__TATVAUM_BIRTH || {}; }
  window.__skyLookAvailable = function () {
    var b = birth();
    return !!(window.__sky && window.TatvaumApp && b.utc != null && b.lat != null && b.lon != null);
  };

  // Scene (ecliptic of date: plane XZ, north +Y, lon counter-clockwise from above) -> east, north, up
  // at the birthplace and birth moment.
  function frame() {
    var b = birth(), jd = b.utc / 86400000 + 2440587.5, T = (jd - 2451545.0) / 36525;
    var gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * T * T;
    var theta = (gmst + b.lon) * D2R, eps = (23.4392911 - 0.0130042 * T) * D2R, phi = b.lat * D2R;
    var ce = Math.cos(eps), se = Math.sin(eps), ct = Math.cos(theta), st = Math.sin(theta), cp = Math.cos(phi), sp = Math.sin(phi);
    function toEnu(sx, sy, sz) {
      var X = sx, ye = -sz, ze = sy;                       // ecliptic cartesian
      var Y = ye * ce - ze * se, Z = ye * se + ze * ce;    // equatorial
      var h = ct * X + st * Y;
      return [-st * X + ct * Y, Z * cp - h * sp, Z * sp + h * cp];
    }
    return [toEnu(1, 0, 0), toEnu(0, 1, 0), toEnu(0, 0, 1)];
  }
  function enuToScene(e, n, u, r) {
    return new window.__sky.THREE.Vector3(
      (M[0][0] * e + M[0][1] * n + M[0][2] * u) * r,
      (M[1][0] * e + M[1][1] * n + M[1][2] * u) * r,
      (M[2][0] * e + M[2][1] * n + M[2][2] * u) * r);
  }

  function textSprite(THREE, text, color) {
    var c = document.createElement('canvas'); c.width = c.height = 128;
    var g = c.getContext('2d');
    g.font = '700 64px Inter, system-ui, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.shadowColor = 'rgba(0,0,0,0.9)'; g.shadowBlur = 12; g.fillStyle = color; g.fillText(text, 64, 64);
    var s = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(c), depthWrite: false, fog: false, transparent: true }));
    s.scale.setScalar(14);
    return s;
  }
  function buildHorizon() {
    var THREE = window.__sky.THREE, R = 150, g = new THREE.Group(), pts = [];
    for (var i = 0; i <= 256; i++) { var a = i / 256 * 2 * Math.PI; pts.push(enuToScene(Math.sin(a), Math.cos(a), 0, R)); }
    g.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts),
      new THREE.LineBasicMaterial({ color: 0x7bd88f, transparent: true, opacity: 0.55, fog: false })));
    [['N', 0, '#ff8a8a'], ['E', 90, '#f5c66b'], ['S', 180, '#e6e8ff'], ['W', 270, '#e6e8ff']].forEach(function (c) {
      var s = textSprite(THREE, c[0], c[2]), a = c[1] * D2R;
      s.position.copy(enuToScene(Math.sin(a), Math.cos(a), 0.06, R - 10));
      g.add(s);
    });
    var z = textSprite(THREE, '↑', '#9aa0c8'); z.position.copy(enuToScene(0, 0, 1, R - 10)); g.add(z);
    window.__sky.scene.add(g);
    return g;
  }

  function overlay(on) { document.body.classList.toggle('looking', on); }
  function setNote(text) { var n = document.getElementById('tvLookNote'); if (n) n.textContent = text; }

  window.__skyLookStart = function () {
    if (L || !window.__skyLookAvailable()) return;
    var S = window.__sky, THREE = S.THREE;
    if (!M) M = frame();
    if (!horizon) horizon = buildHorizon();
    horizon.visible = true;
    L = { t0: performance.now(), fromPos: S.camera.position.clone(), fromQuat: S.camera.quaternion.clone(),
          fov: S.camera.fov, target: new THREE.Quaternion(), hasTarget: false, exiting: false };
    S.controls.enabled = false;
    window.__skyLooking = true;
    S.earth.visible = false;
    S.earth.children.forEach(function (c) { c.visible = false; });
    S.camera.fov = 65; S.camera.updateProjectionMatrix();
    overlay(true);
    var b = birth();
    setNote('Hold your phone up and turn around · your birth sky' + (b.place ? ' from ' + b.place : ''));
    window.TatvaumApp.startLook();
  };

  window.__skyLookStop = function () {
    if (!L || L.exiting) return;
    window.TatvaumApp.stopLook();
    var S = window.__sky;
    L.exiting = true; L.t0 = performance.now();
    L.backFrom = S.camera.position.clone(); L.backQuat = S.camera.quaternion.clone();
    overlay(false);
  };

  // Called by the app with the phone's rotation matrix (row-major, device -> east/north/up).
  window.__skyLookSet = function (r) {
    if (!L || L.exiting) return;
    var THREE = window.__sky.THREE, a = [];
    // camera axes in scene space = M^T · R   (M maps scene -> east/north/up)
    for (var i = 0; i < 3; i++) for (var j = 0; j < 3; j++)
      a[i * 3 + j] = M[i][0] * r[j] + M[i][1] * r[3 + j] + M[i][2] * r[6 + j];
    var m = new THREE.Matrix4().set(a[0], a[1], a[2], 0, a[3], a[4], a[5], 0, a[6], a[7], a[8], 0, 0, 0, 0, 1);
    L.target.setFromRotationMatrix(m);
    if (!L.hasTarget) setNote('Point your phone around · your birth sky' + (birth().place ? ' from ' + birth().place : ''));
    L.hasTarget = true;
  };

  window.__skyLookUnavailable = function () {
    setNote('This phone has no motion sensor, so look-around isn\'t available.');
    setTimeout(window.__skyLookStop, 2500);
  };

  function ease(t) { return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2; }

  // Runs every frame just before the page renders.
  window.__skyLookFrame = function () {
    if (!L) return;
    var S = window.__sky, cam = S.camera;
    if (!L.exiting) {
      var e = ease(Math.min(1, (performance.now() - L.t0) / 1400));
      cam.position.copy(L.fromPos).multiplyScalar(1 - e);              // fly into Earth
      if (L.hasTarget) {
        if (e < 1) cam.quaternion.copy(L.fromQuat).slerp(L.target, e);
        else cam.quaternion.slerp(L.target, 0.25);                       // smooth sensor noise
      }
      return;
    }
    var k = ease(Math.min(1, (performance.now() - L.t0) / 1100));
    cam.position.copy(L.backFrom).lerp(L.fromPos, k);                   // fly back out
    cam.quaternion.copy(L.backQuat).slerp(L.fromQuat, k);
    if (k >= 1) {
      cam.fov = L.fov; cam.updateProjectionMatrix();
      S.earth.visible = true;
      S.earth.children.forEach(function (c) { c.visible = true; });
      if (horizon) horizon.visible = false;
      S.controls.enabled = true;
      window.__skyLooking = false;
      L = null;
    }
  };
})();
