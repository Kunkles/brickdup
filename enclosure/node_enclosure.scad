// brickdup — sensor-node enclosure (parametric OpenSCAD scaffold)
// =================================================================
// STACKED layout — minimum footprint, battery-brick proportions:
//
//   z 2..12   1100 mAh bridge LiPo (40x25x10) flat on the floor
//   z 15..16  Heltec WiFi LoRa 32 V3 on four 13 mm corner towers,
//             directly above the cell (battery JST is on the board's
//             underside, so the lead run is tiny)
//   west bay  buck recess in the floor + the two west screw bosses; the
//             USB-C cable passes over the buck to reach the board
//   east bay  LEMO panel connector tail + divider + the two east bosses
//
// Footprint is set by the Heltec (50.2 mm) + the two end bays.  Outer
// ≈ 85 x 35 x 30 mm — all four M2 screws are now on internal corner
// bosses (no external ears).
//
// Wall features:  USB-C slot (west — see note below), LEMO panel hole
// (east), SMA antenna hole (north wall, bay end), vent slots.  Lid: OLED
// window, plunger bores, M2 screws into the 4 corner bosses.
//
// part = "both" renders base + lid in print orientation.
//
// Every value marked MEASURE is a best guess from ENCLOSURE.md — verify with
// calipers and a dry fit before the final print.  Print a fit test of the
// USB cutout + LEMO hole first (ENCLOSURE.md §7).
//
// Known scaffold compromises (check at dry fit, tune as needed):
//   - Assumes NO bottom-facing pin headers on the Heltec (Heltec ships them
//     unsoldered).  If yours are soldered pointing down, raise standoff_h
//     to ~22 and the shell grows ~9 mm taller.
//   - The LEMO tail (~20 mm behind the panel) runs at floor level under the
//     board's east end.  The buck now lives in the WEST bay, so nothing is
//     under the tail — but keep divider wire slack out of its way.
//   - LiPo side clearance is ~0.75 mm/side (cell measured 25.0 wide).  If
//     your cell runs fat, bump `pad` by 0.5 — never squeeze the pouch.
//   - The USB-C port sits ~15 mm behind the west wall (behind the west
//     bay), so the wall opening is an OVERMOLD-SIZED SLOT: the cable's
//     plastic body passes through the wall and into the bay (over the
//     buck — different heights, no clash).  MEASURE your cable's overmold
//     and size usb_w/usb_h to it +1 mm; chunky cables may not fit.
//   - Buttons are actuated by CAPTIVE PRINTED PLUNGERS (no exposed PCB):
//     each button gets a guide tube under the lid and a printed piston,
//     dropped in from the inside before the lid goes on.  The flared cone
//     keeps it captive; the tactile switch's own spring returns it.  Verify
//     `btn_top` (button cap height above the PCB) or the throw will be off.
//     Set plungers = false to fall back to plain access holes.

part = "both"; // [both, base, lid, plunger, assembly]

/* ---------------- global ---------------- */
wall   = 2.0;   // shell wall
lid_t  = 2.4;   // lid plate (screw counterbores live here)
tol    = 0.20;  // slip-fit clearance
fillet = 2.5;   // outer corner radius (XY)
rib    = 1.6;   // internal partition thickness
pad    = 2.0;   // margin between cavity wall and the board zone (= rim width)
$fn = 48;

/* ---------------- Heltec WiFi LoRa 32 V3 ---------------- */
pcb_l      = 50.2;  // MEASURE
pcb_w      = 25.5;  // MEASURE
pcb_t      = 1.0;
comp_h     = 10.0;  // tallest part above PCB (OLED/USB)  MEASURE
standoff_h = 13.0;  // tower height: LiPo (10) + 1 air + 2 wire room underneath

/* ---------------- bridge LiPo (MakerHawk 1100 mAh) ---------------- */
lipo_l = 40.0;  lipo_w = 25.0;  lipo_t = 10.0;   // measured

/* ---------------- buck (Pololu D24V10F5) ---------------- */
buck_l = 12.7;  buck_w = 10.2;   // MEASURE (datasheet 0.5" x 0.4")
buck_recess = 0.6;               // bay-floor recess to locate it (foam-tape it in)

/* ---------------- end bays ---------------- */
wbay  = 13.0;   // west bay: buck (sideways) + west bosses + USB reach-through
bay_l = 15.0;   // east bay: LEMO tail + divider + east bosses

/* ---------------- connectors ---------------- */
usb_w = 13.0;  usb_h = 8.0;      // overmold slot, not port-sized  MEASURE cable
lemo_hole_d = 12.0;  // MEASURE your shell: LEMO 0B panel ~9.1 mm (+ key flat),
                     // 1B ~12.1 mm.  Add the anti-rotation flat after measuring.
lemo_z = 9.0;        // hole centre height — keeps the tail below the board
sma_d = 6.5;         // SMA bulkhead pass-through  VERIFY (north wall, bay end)

/* ---------------- lid features (offsets from the PCB's SW corner) ------- */
oled_off_x = 16.0;   // MEASURE  (active area 21.7 x 11, roughly mid-board)
oled_off_y = 7.25;   // MEASURE
oled_w = 23.7;       // window = active area + ~1 mm margin per side
oled_h = 13.0;
prg_x = 8.0;   prg_y = 5.0;    // MEASURE  PRG/USER button centre
rst_x = 8.0;   rst_y = 20.5;   // MEASURE  RST button centre
btn_d = 4.5;                   // access-hole diameter (plungers = false only)

/* ---------------- button plungers (captive printed pistons) ------------- */
plungers = true;     // false = plain access holes instead
btn_top  = 1.7;      // button cap height above the PCB top  MEASURE
plunger_gap = 0.3;   // how proud of the lid the piston sits resting on the button
bore_d   = 6.4;      // bore through lid + guide tube
stem_d   = 6.0;      // piston body (what your finger presses)
flange_d = 9.0;      // captive flare (cones at 45° — supportless)
tip_d    = 4.0;      // contact face on the button cap
tube_od  = 9.4;      // guide tube under the lid
tube_len = 5.5;      // tube reach below the lid underside

/* ---------------- screws (M2 self-tap into corner bosses) ---------------- */
boss_d      = 6.0;
screw_pilot = 1.7;   // M2 self-tap pilot in PETG
screw_clear = 2.4;   // clearance through lid
cb_d = 4.6;  cb_t = 1.2;   // pan-head counterbore

/* ================= derived layout (don't edit below casually) ========== */
hz_l = pcb_l + 1.0;                      // Heltec zone, 0.5 mm slip per side
hz_w = pcb_w + 1.0;

inner_l = wbay + hz_l + rib + bay_l;         // ~80.8
inner_w = pad + hz_w + pad;                  // ~30.5
inner_h = standoff_h + pcb_t + comp_h + 2.0; // 26

outer_l = inner_l + 2*wall;
outer_w = inner_w + 2*wall;
base_h  = wall + inner_h;

bx = wall + wbay + 0.5;           // PCB SW corner (board centred in its zone)
by = wall + pad + 0.5;
ribW    = wall + wbay - rib;      // west rib (west bay | board zone), west face
ribX    = wall + wbay + hz_l;     // bay rib (board zone | east bay), west face
bayX    = ribX + rib;             // east bay west edge
rim_top = wall + standoff_h + pcb_t + 2;   // rim cradles the PCB edge by 2 mm
lipoX   = wall + wbay + 1;        // cell west edge
usb_y0  = outer_w/2 - usb_w/2;    // USB slot / west-rib gap edges
usb_y1  = outer_w/2 + usb_w/2;
usb_zc  = wall + standoff_h + pcb_t + 1.6; // USB port axis height

boss_pos = [ [5, 5], [5, outer_w - 5],
             [outer_l - 5, 5], [outer_l - 5, outer_w - 5] ];

btns    = [ [prg_x, prg_y], [rst_x, rst_y] ];
btn_z   = wall + standoff_h + pcb_t + btn_top;   // button cap top (z)
lid_top = base_h + lid_t;

echo(str("outer: ", outer_l, " x ", outer_w, " x ", base_h + lid_t,
         " mm"));
echo(str("inner: ", inner_l, " x ", inner_w, " x ", inner_h, " mm"));

/* ================= helpers ================= */
module rbox(l, w, h, r) {            // box rounded in XY
  hull() for (x = [r, l - r], y = [r, w - r])
    translate([x, y, 0]) cylinder(h = h, r = r);
}

module vent_row(x0, n, z = 16, h = 9, w = 1.4, pitch = 3.2, yw = 0) {
  // yw = 0 cuts the south wall; yw = outer_w - wall cuts the north wall
  for (i = [0 : n - 1])
    translate([x0 + i*pitch, yw - 0.1, z]) cube([w, wall + 0.2, h]);
}

/* ================= base ================= */
module base() {
  difference() {
    union() {
      // shell
      difference() {
        rbox(outer_l, outer_w, base_h, fillet);
        translate([wall, wall, wall]) cube([inner_l, inner_w, inner_h + 1]);
      }

      // rim: cradles the PCB edges, board drops inside.  West side is a rib
      // (west bay | board zone) gapped for the USB plug + buck output wires
      translate([ribW, wall, wall])
        cube([rib, usb_y0 - wall, rim_top - wall]);
      translate([ribW, usb_y1, wall])
        cube([rib, wall + inner_w - usb_y1, rim_top - wall]);
      translate([ribW, wall, wall])
        cube([ribX - ribW, pad, rim_top - wall]);                   // south
      translate([ribW, wall + pad + hz_w, wall])
        cube([ribX - ribW, pad, rim_top - wall]);                   // north

      // bay rib — wide centre gap (y 10..24) passes the LEMO tail + wires
      translate([ribX, wall, wall]) cube([rib, 10 - wall, rim_top - wall]);
      translate([ribX, 24, wall])
        cube([rib, wall + inner_w - 24, rim_top - wall]);

      // PCB corner towers (board rests on these at standoff_h)
      for (p = [[bx - 0.5, by - 0.5], [bx + pcb_l - 3.5, by - 0.5],
                [bx - 0.5, by + pcb_w - 3.5],
                [bx + pcb_l - 3.5, by + pcb_w - 3.5]])
        translate([p[0], p[1], wall]) cube([4, 4, standoff_h]);

      // LiPo end stop (cell sits just east of the west rib, under the
      // board) — gap for the lead
      translate([lipoX + lipo_l + 1, wall + pad, wall])
        cube([rib, 12 - wall - pad, 8]);
      translate([lipoX + lipo_l + 1, 20, wall])
        cube([rib, wall + pad + hz_w - 20, 8]);

      // internal corner screw bosses (live in the end bays, clear of the
      // board, LiPo, LEMO tail, and buck)
      for (p = boss_pos)
        translate([p[0], p[1], wall]) cylinder(h = inner_h, d = boss_d);
    }

    // boss pilot holes (M2 self-tap)
    for (p = boss_pos)
      translate([p[0], p[1], base_h - 8]) cylinder(h = 8.1, d = screw_pilot);

    // USB-C slot, west wall: sized for the cable OVERMOLD, which passes
    // through the wall and across the west bay to the recessed port
    translate([-0.1, usb_y0, usb_zc - usb_h/2])
      cube([wall + 0.2, usb_w, usb_h]);
    translate([-0.1, usb_y0 - 1.2, usb_zc - usb_h/2 - 1.2])
      cube([1.2, usb_w + 2.4, usb_h + 2.4]);

    // LEMO panel hole, east wall, centred, low (tail runs under the board)
    translate([outer_l - wall - 0.1, outer_w/2, lemo_z])
      rotate([0, 90, 0]) cylinder(h = wall + 0.2, d = lemo_hole_d);
    // shallow floor relief so the LEMO nut clears (deepen if yours is fat)
    translate([wall + inner_l - 4, outer_w/2 - 9, wall - 0.8])
      cube([4.1, 18, 0.9]);

    // SMA bulkhead (antenna), north wall at the east bay — u.FL pigtail from
    // the board's east end bends ~90° to reach it
    translate([bayX + 5, outer_w - wall - 0.1, 20])
      rotate([-90, 0, 0]) cylinder(h = wall + 0.2, d = sma_d);

    // vents — board level (above the rim): both long walls over the ESP,
    // plus the east bay (south wall only; SMA owns the north bay wall)
    vent_row(42, 6);
    vent_row(42, 6, yw = outer_w - wall);
    vent_row(68, 3);

    // buck locating recess, west bay floor, sideways, centred between the
    // bosses — the USB cable passes well above it
    translate([wall + 0.1, outer_w/2 - (buck_l + 1)/2, wall - buck_recess])
      cube([buck_w + 1, buck_l + 1, buck_recess + 0.1]);
  }
}

/* ================= lid (modelled in assembled position) ================= */
module lid() {
  difference() {
    union() {
      translate([0, 0, base_h]) rbox(outer_l, outer_w, lid_t, fillet);
      // plunger guide tubes under the lid
      if (plungers)
        for (p = btns)
          translate([bx + p[0], by + p[1], base_h - tube_len])
            cylinder(h = tube_len, d = tube_od);
      // locating lip, drops 3 mm into the cavity
      translate([0, 0, base_h - 3]) difference() {
        translate([wall + tol, wall + tol, 0])
          cube([inner_l - 2*tol, inner_w - 2*tol, 3]);
        translate([wall + tol + 1.6, wall + tol + 1.6, -0.1])
          cube([inner_l - 2*tol - 3.2, inner_w - 2*tol - 3.2, 3.2]);
      }
    }

    // boss clearance notches in the lip
    for (p = boss_pos)
      translate([p[0], p[1], base_h - 3.1]) cylinder(h = 3.2, d = boss_d + 1);

    // screw holes + counterbores over the bosses
    for (p = boss_pos) {
      translate([p[0], p[1], base_h - 3.2])
        cylinder(h = lid_t + 3.4, d = screw_clear);
      translate([p[0], p[1], base_h + lid_t - cb_t])
        cylinder(h = cb_t + 0.1, d = cb_d);
    }

    // OLED window (flush cutout; glue a 0.5–1 mm clear PETG window behind it)
    translate([bx + oled_off_x, by + oled_off_y, base_h - 0.1])
      cube([oled_w, oled_h, lid_t + 0.2]);

    // button access: plunger bores through plate + tube, or plain holes
    for (p = btns)
      if (plungers)
        translate([bx + p[0], by + p[1], base_h - tube_len - 0.1])
          cylinder(h = tube_len + lid_t + 0.2, d = bore_d);
      else
        translate([bx + p[0], by + p[1], base_h - 0.1])
          cylinder(h = lid_t + 0.2, d = btn_d);
  }
}

/* ================= button plunger (print 2; drop in from inside) ======== */
// Modelled at rest-on-button position.  Stack, tip to top: contact face,
// 45° flare out to the captive flange, 45° taper back to the stem, stem
// proud of the lid.  Pulled outward, the upper taper seats on the tube's
// bottom rim (~0.2 mm of float) — it cannot escape; pushed, it clicks the
// switch.  The switch spring returns it.
module plunger() {                       // local frame: tip face at z = 0
  flare = (flange_d - tip_d) / 2;        // 45° cone heights
  taper = (flange_d - stem_d) / 2;
  len   = lid_top + plunger_gap - btn_z; // tip on button → top proud of lid
  cylinder(h = flare, d1 = tip_d, d2 = flange_d);
  translate([0, 0, flare]) cylinder(h = 0.8, d = flange_d);
  translate([0, 0, flare + 0.8]) cylinder(h = taper, d1 = flange_d, d2 = stem_d);
  translate([0, 0, flare + 0.8 + taper])
    cylinder(h = len - flare - 0.8 - taper, d = stem_d);
}

/* ================= output ================= */
if (part == "base")     base();
if (part == "lid")      lid();
if (part == "plunger")  plunger();
if (part == "assembly") {
  base();
  color("steelblue", 0.5) lid();
  if (plungers)
    color("tomato") for (p = btns)
      translate([bx + p[0], by + p[1], btn_z]) plunger();
}
if (part == "both") {
  base();
  // lid flipped flat for printing, parked south of the base
  translate([0, -12, base_h + lid_t]) rotate([180, 0, 0]) lid();
  // plungers printed tip-up (stem face on the bed; cones are 45° = supportless)
  if (plungers)
    for (i = [0, 1])
      translate([outer_l + 12 + i * 15, -20, lid_top + plunger_gap - btn_z])
        rotate([180, 0, 0]) plunger();
}
