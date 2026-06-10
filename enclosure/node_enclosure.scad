// brickdup — sensor-node enclosure (parametric OpenSCAD scaffold)
// =================================================================
// STACKED + SIDE-CHANNEL layout:
//
//   z 2..12   1100 mAh bridge LiPo (40x25x10) flat on the floor
//   z 15..16  Heltec WiFi LoRa 32 V3 on four 13 mm corner towers,
//             directly above the cell (battery JST is on the board's
//             underside, so the lead run is tiny)
//   south ch  buck recess in the floor + wire raceway (11.5 mm wide)
//   north ch  divider / wire slack raceway (7 mm wide)
//   east bay  LEMO panel connector tail + divider
//
// The board sits ~2.5 mm from the west wall, so USB-C is a normal
// chamfered port hole (~4 mm recess), not a deep slot.  All four M2
// screws are internal corner bosses, in the channel corners.  Channels
// open into the east bay, so wires run LEMO → channel → buck → board
// without rib gaps.  Outer ≈ 73 x 52 x 30 mm.
//
// part = "both" renders base + lid + plungers in print orientation.
//
// Every value marked MEASURE is a best guess from ENCLOSURE.md — verify with
// calipers and a dry fit before the final print.  Print a fit test of the
// USB cutout + LEMO hole first (ENCLOSURE.md §7).
//
// Known scaffold compromises (check at dry fit, tune as needed):
//   - Assumes NO bottom-facing pin headers on the Heltec (Heltec ships them
//     unsoldered).  If yours are soldered pointing down, raise standoff_h
//     to ~22 and the shell grows ~9 mm taller.
//   - USB-C port face sits ~4 mm behind the outer wall.  The 12x7 chamfered
//     hole lets a plug nose seat through that on most cables — check yours;
//     enlarge usb_w/usb_h if the nose is chunky.
//   - The LEMO tail (~20 mm behind the panel) runs at floor level under the
//     board's east end and stops ~6 mm short of the LiPo.  If your LEMO
//     body is longer than ~25 mm, bump bay_l.
//   - LiPo side clearance is ~0.75 mm/side (cell measured 25.0 wide).  If
//     your cell runs fat, widen the board-zone ribs apart — never squeeze
//     the pouch.
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
pad    = 2.0;   // margin between west wall and the board zone (= rim width)
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
buck_recess = 0.6;               // floor recess to locate it (foam-tape it in)
buck_x = 20.0;                   // recess position along the south channel

/* ---------------- channels & east bay ---------------- */
ch_s  = 11.5;   // south channel: buck + wires (sized to the buck recess)
ch_n  = 7.0;    // north channel: divider / wire slack
bay_l = 14.0;   // east bay: LEMO tail + divider

/* ---------------- connectors ---------------- */
usb_w = 12.0;  usb_h = 7.0;      // port hole, chamfered  MEASURE plug nose
lemo_hole_d = 12.0;  // MEASURE your shell: LEMO 0B panel ~9.1 mm (+ key flat),
                     // 1B ~12.1 mm.  Add the anti-rotation flat after measuring.
lemo_z = 9.0;        // hole centre height — keeps the tail below the board
sma_d = 6.5;         // SMA bulkhead pass-through  VERIFY (east wall)
sma_y = 12.0;        // SMA centre (between the SE boss and the LEMO nut)

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

inner_l = pad + hz_l + rib + bay_l;            // ~68.8
inner_w = ch_s + rib + hz_w + rib + ch_n;      // ~48.2
inner_h = standoff_h + pcb_t + comp_h + 2.0;   // 26

outer_l = inner_l + 2*wall;
outer_w = inner_w + 2*wall;
base_h  = wall + inner_h;

bx = wall + pad + 0.5;            // PCB SW corner (board centred in its zone)
by = wall + ch_s + rib + 0.5;
ribS    = wall + ch_s;            // south rib (channel | board zone), south face
ribN    = ribS + rib + hz_w;      // north rib (board zone | channel), south face
ribX    = wall + pad + hz_l;      // bay rib (board zone | east bay), west face
rim_top = wall + standoff_h + pcb_t + 2;   // rim cradles the PCB edge by 2 mm
lipoX   = wall + pad + 1;         // cell west edge
pcb_yc  = by + pcb_w/2;           // board centreline: USB, LEMO + tail follow it
usb_zc  = wall + standoff_h + pcb_t + 1.6; // USB port axis height

boss_pos = [ [5, 5], [5, outer_w - 5],
             [outer_l - 5, 5], [outer_l - 5, outer_w - 5] ];

btns    = [ [prg_x, prg_y], [rst_x, rst_y] ];
btn_z   = wall + standoff_h + pcb_t + btn_top;   // button cap top (z)
lid_top = base_h + lid_t;

echo(str("outer: ", outer_l, " x ", outer_w, " x ", base_h + lid_t, " mm"));
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

      // channel ribs (stop at the bay, so channels open into it)
      translate([wall, ribS, wall]) cube([ribX - wall, rib, rim_top - wall]);
      translate([wall, ribN, wall]) cube([ribX - wall, rib, rim_top - wall]);

      // west rim band: cradles the board's USB edge (hole cut through it)
      translate([wall, ribS + rib, wall])
        cube([pad, hz_w, rim_top - wall]);

      // bay rib — centre gap passes the LEMO tail + wires under the board
      translate([ribX, ribS + rib, wall])
        cube([rib, pcb_yc - 7 - (ribS + rib), rim_top - wall]);
      translate([ribX, pcb_yc + 7, wall])
        cube([rib, ribN - (pcb_yc + 7), rim_top - wall]);

      // PCB corner towers (board rests on these at standoff_h)
      for (p = [[bx - 0.5, by - 0.5], [bx + pcb_l - 3.5, by - 0.5],
                [bx - 0.5, by + pcb_w - 3.5],
                [bx + pcb_l - 3.5, by + pcb_w - 3.5]])
        translate([p[0], p[1], wall]) cube([4, 4, standoff_h]);

      // LiPo end stop (cell under the board, against the west rim) — gap
      // for the lead, centred on the board
      translate([lipoX + lipo_l + 1, ribS + rib, wall])
        cube([rib, pcb_yc - 4 - (ribS + rib), 8]);
      translate([lipoX + lipo_l + 1, pcb_yc + 4, wall])
        cube([rib, ribN - (pcb_yc + 4), 8]);

      // internal corner screw bosses (channel corners, clear of everything)
      for (p = boss_pos)
        translate([p[0], p[1], wall]) cylinder(h = inner_h, d = boss_d);
    }

    // boss pilot holes (M2 self-tap)
    for (p = boss_pos)
      translate([p[0], p[1], base_h - 8]) cylinder(h = 8.1, d = screw_pilot);

    // USB-C port hole, west wall + rim (~4 mm recess), with a generous
    // 45° chamfered mouth so the plug nose seats
    translate([-0.1, pcb_yc - usb_w/2, usb_zc - usb_h/2])
      cube([wall + pad + 0.2, usb_w, usb_h]);
    translate([-0.1, pcb_yc - usb_w/2 - 1.5, usb_zc - usb_h/2 - 1.5])
      cube([1.5, usb_w + 3, usb_h + 3]);

    // LEMO panel hole, east wall, on the board centreline, low (tail runs
    // under the board, through the bay rib's gap)
    translate([outer_l - wall - 0.1, pcb_yc, lemo_z])
      rotate([0, 90, 0]) cylinder(h = wall + 0.2, d = lemo_hole_d);
    // shallow floor relief so the LEMO nut clears (deepen if yours is fat)
    translate([wall + inner_l - 4, pcb_yc - 9, wall - 0.8])
      cube([4.1, 18, 0.9]);

    // SMA bulkhead (antenna), east wall, south of the LEMO — u.FL pigtail
    // from the board's east end reaches it through the bay
    translate([outer_l - wall - 0.1, sma_y, 20])
      rotate([0, 90, 0]) cylinder(h = wall + 0.2, d = sma_d);

    // vents — both channel walls, above rib height so air crosses the ribs
    vent_row(25, 7);
    vent_row(25, 7, yw = outer_w - wall);

    // buck locating recess, south channel floor — wires run along the
    // channel: LEMO (east) → buck VIN, buck VOUT → board 5V pin
    translate([buck_x, wall + 0.2, wall - buck_recess])
      cube([buck_l + 1, buck_w + 1, buck_recess + 0.1]);
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
