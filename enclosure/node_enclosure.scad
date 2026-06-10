// brickdup — sensor-node enclosure (parametric OpenSCAD scaffold)
// =================================================================
// STACKED layout — minimum footprint, battery-brick proportions:
//
//   z 2..12   1100 mAh bridge LiPo (40x25x10) flat on the floor
//   z 15..16  Heltec WiFi LoRa 32 V3 on four 13 mm corner towers,
//             directly above the cell (battery JST is on the board's
//             underside, so the lead run is tiny)
//   east bay  LEMO panel connector tail + divider; buck recess in the
//             bay floor.  Wires cross the bay rib's centre gap.
//
// Footprint is set by the Heltec (50.2 mm) + a 15 mm LEMO bay — the shell
// can't be shorter than that.  Outer ≈ 74 x 35 x 30 mm (plus small screw
// ears at the four corners).
//
// Wall features:  USB-C cutout (west), LEMO panel hole (east), SMA antenna
// hole (north wall, bay end), vent slots.  Lid: OLED window, PRG/RST holes,
// M2 screws into 4 external ear posts (no internal bosses — no room).
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
//     board's east end, over the buck.  A fat 1B body may graze the buck —
//     check depths; shift the buck recess or shorten lemo_z if so.
//   - LiPo side clearance is ~0.75 mm/side (cell measured 25.0 wide).  If
//     your cell runs fat, bump `pad` by 0.5 — never squeeze the pouch.
//   - The USB-C plug reaches through wall + ~2.5 mm of rim; the chamfered
//     mouth handles most cables, but check yours.
//   - Buttons sit ~12 mm below the lid — press with a pen for now, or design
//     a TPU plunger later (ENCLOSURE.md §4).

part = "both"; // [both, base, lid, assembly]

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

/* ---------------- east bay (LEMO tail + buck + divider) ---------------- */
bay_l = 15.0;   // depth along X

/* ---------------- connectors ---------------- */
usb_w = 10.0;  usb_h = 4.8;      // USB-C cutout (port ~9x3.2 + slip)  MEASURE
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
btn_d = 4.5;                   // access-hole diameter

/* ---------------- screws (M2 self-tap into ear posts) ---------------- */
ear_d       = 7.0;
screw_pilot = 1.7;   // M2 self-tap pilot in PETG
screw_clear = 2.4;   // clearance through lid
cb_d = 4.6;  cb_t = 1.2;   // pan-head counterbore

/* ================= derived layout (don't edit below casually) ========== */
hz_l = pcb_l + 1.0;                      // Heltec zone, 0.5 mm slip per side
hz_w = pcb_w + 1.0;

inner_l = pad + hz_l + rib + bay_l;          // ~69.8
inner_w = pad + hz_w + pad;                  // ~30.5
inner_h = standoff_h + pcb_t + comp_h + 2.0; // 26

outer_l = inner_l + 2*wall;
outer_w = inner_w + 2*wall;
base_h  = wall + inner_h;

bx = wall + pad + 0.5;            // PCB SW corner (board centred in its zone)
by = wall + pad + 0.5;
ribX    = wall + pad + hz_l;      // bay rib west face
bayX    = ribX + rib;             // east bay west edge
rim_top = wall + standoff_h + pcb_t + 2;   // rim cradles the PCB edge by 2 mm
lipoX   = wall + pad + 1;         // cell west edge

ear_pos = [ [-1.5, 7], [-1.5, outer_w - 7],
            [outer_l + 1.5, 7], [outer_l + 1.5, outer_w - 7] ];

echo(str("outer: ", outer_l, " x ", outer_w, " x ", base_h + lid_t,
         " mm (+ ear posts)"));
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

      // rim: cradles the PCB edges (west / south / north), board drops inside
      translate([wall, wall, wall])
        cube([pad, inner_w, rim_top - wall]);                       // west
      translate([wall, wall, wall])
        cube([ribX - wall, pad, rim_top - wall]);                   // south
      translate([wall, wall + pad + hz_w, wall])
        cube([ribX - wall, pad, rim_top - wall]);                   // north

      // bay rib — wide centre gap (y 10..24) passes the LEMO tail + wires
      translate([ribX, wall, wall]) cube([rib, 10 - wall, rim_top - wall]);
      translate([ribX, 24, wall])
        cube([rib, wall + inner_w - 24, rim_top - wall]);

      // PCB corner towers (board rests on these at standoff_h)
      for (p = [[bx - 0.5, by - 0.5], [bx + pcb_l - 3.5, by - 0.5],
                [bx - 0.5, by + pcb_w - 3.5],
                [bx + pcb_l - 3.5, by + pcb_w - 3.5]])
        translate([p[0], p[1], wall]) cube([4, 4, standoff_h]);

      // LiPo end stop (cell at x 5..45, under the board) — gap for the lead
      translate([lipoX + lipo_l + 1, wall + pad, wall])
        cube([rib, 12 - wall - pad, 8]);
      translate([lipoX + lipo_l + 1, 20, wall])
        cube([rib, wall + pad + hz_w - 20, 8]);

      // external screw ear posts (fused to the end walls)
      for (p = ear_pos)
        translate([p[0], p[1], 0]) cylinder(h = base_h, d = ear_d);
    }

    // ear pilot holes (M2 self-tap)
    for (p = ear_pos)
      translate([p[0], p[1], base_h - 8]) cylinder(h = 8.1, d = screw_pilot);

    // USB-C cutout, west wall + rim (+ chamfered mouth)
    translate([-0.1, by + pcb_w/2 - usb_w/2, wall + standoff_h + pcb_t - 0.8])
      cube([wall + pad + 0.2, usb_w, usb_h]);
    translate([-0.1, by + pcb_w/2 - usb_w/2 - 1.2, wall + standoff_h + pcb_t - 2.0])
      cube([1.2, usb_w + 2.4, usb_h + 2.4]);

    // LEMO panel hole, east wall, centred, low (tail runs under the board)
    translate([outer_l - wall - 0.1, outer_w/2, lemo_z])
      rotate([0, 90, 0]) cylinder(h = wall + 0.2, d = lemo_hole_d);
    // shallow floor relief so the LEMO nut clears (deepen if yours is fat)
    translate([wall + inner_l - 4, outer_w/2 - 9, wall - 0.8])
      cube([4.1, 18, 0.9]);

    // SMA bulkhead (antenna), north wall at the bay end — u.FL pigtail from
    // the board's east end bends ~90° to reach it
    translate([66, outer_w - wall - 0.1, 20])
      rotate([-90, 0, 0]) cylinder(h = wall + 0.2, d = sma_d);

    // vents — board level (above the rim): both long walls over the ESP,
    // plus the bay (south wall only; SMA owns the north bay wall)
    vent_row(30, 6);
    vent_row(30, 6, yw = outer_w - wall);
    vent_row(57, 3);

    // buck locating recess, bay floor, south side (under the LEMO tail —
    // see header note about 1B body clearance)
    translate([bayX + 0.7, 2.5, wall - buck_recess])
      cube([buck_l + 1, buck_w + 1, buck_recess + 0.1]);
  }
}

/* ================= lid (modelled in assembled position) ================= */
module lid() {
  difference() {
    union() {
      translate([0, 0, base_h]) rbox(outer_l, outer_w, lid_t, fillet);
      // ear pads over the posts
      for (p = ear_pos)
        translate([p[0], p[1], base_h]) cylinder(h = lid_t, d = ear_d);
      // locating lip, drops 3 mm into the cavity
      translate([0, 0, base_h - 3]) difference() {
        translate([wall + tol, wall + tol, 0])
          cube([inner_l - 2*tol, inner_w - 2*tol, 3]);
        translate([wall + tol + 1.6, wall + tol + 1.6, -0.1])
          cube([inner_l - 2*tol - 3.2, inner_w - 2*tol - 3.2, 3.2]);
      }
    }

    // screw holes + counterbores through the ear pads
    for (p = ear_pos) {
      translate([p[0], p[1], base_h - 0.1])
        cylinder(h = lid_t + 0.2, d = screw_clear);
      translate([p[0], p[1], base_h + lid_t - cb_t])
        cylinder(h = cb_t + 0.1, d = cb_d);
    }

    // OLED window (flush cutout; glue a 0.5–1 mm clear PETG window behind it)
    translate([bx + oled_off_x, by + oled_off_y, base_h - 0.1])
      cube([oled_w, oled_h, lid_t + 0.2]);

    // button access holes (PRG used constantly; RST occasionally)
    for (p = [[prg_x, prg_y], [rst_x, rst_y]])
      translate([bx + p[0], by + p[1], base_h - 0.1])
        cylinder(h = lid_t + 0.2, d = btn_d);
  }
}

/* ================= output ================= */
if (part == "base")     base();
if (part == "lid")      lid();
if (part == "assembly") { base(); color("steelblue", 0.5) lid(); }
if (part == "both") {
  base();
  // lid flipped flat for printing, parked south of the base
  translate([0, -12, base_h + lid_t]) rotate([180, 0, 0]) lid();
}
