// brickdup — sensor-node enclosure (parametric OpenSCAD scaffold)
// =================================================================
// Houses, side by side on one floor (low-profile, velcro-on-brick friendly):
//
//   - Heltec WiFi LoRa 32 V3          south row, sits on 3 mm corner pads
//   - 1100 mAh bridge LiPo 40x25x10   north row, flat pocket, tape-retained
//   - Pololu D24V10F5 buck            shallow locating recess in the east bay
//   - voltage divider + wire slack    east bay + free corner of the LiPo row
//
// A 6 mm corridor between the two rows is the cable raceway (LiPo JST lead,
// divider wires) and carries two of the four screw bosses.
//
// Wall features:  USB-C cutout (west), LEMO panel hole + SMA antenna hole
// (east), vent slots (both long walls).  Lid: OLED window, PRG/RST holes,
// M2 screws into 4 bosses.
//
// part = "both" renders base + lid in print orientation, side by side.
//
// Every value marked MEASURE is a best guess from ENCLOSURE.md — verify with
// calipers and a dry fit before the final print.  Print a fit test of the
// USB cutout + LEMO hole first (ENCLOSURE.md §7).
//
// Known scaffold compromises (check at dry fit, tune as needed):
//   - No bosses at the west (USB-end) corners — the PCB sits too close to
//     that wall for one.  The lid lip + boss A hold that end; add external
//     screw tabs later if it gapes.
//   - The USB-C plug reaches through wall + ~2.5 mm of recess; the chamfered
//     mouth handles most cables, but check yours.
//   - Buttons sit ~12 mm below the lid — press with a pen for now, or design
//     a TPU plunger later (ENCLOSURE.md §4).
//   - The LEMO tail (~20-25 mm behind the panel) overhangs the bay into the
//     LiPo row's free east corner — that space must stay clear of wire slack.

part = "both"; // [both, base, lid, assembly]

/* ---------------- global ---------------- */
wall     = 2.0;   // shell wall
lid_t    = 2.4;   // lid plate (thicker: screw counterbores live here)
tol      = 0.20;  // slip-fit clearance
fillet   = 2.5;   // outer corner radius (XY)
rib      = 1.6;   // internal partition thickness
rib_h    = 8.0;   // internal partition height
pad      = 2.0;   // cavity margin so hardware clears the zones
corridor = 6.0;   // cable raceway between the two rows (also hosts bosses)
$fn = 48;

/* ---------------- Heltec WiFi LoRa 32 V3 ---------------- */
pcb_l      = 50.2;  // MEASURE
pcb_w      = 25.5;  // MEASURE
pcb_t      = 1.0;
comp_h     = 10.0;  // tallest part above PCB (OLED/USB)  MEASURE
standoff_h = 3.0;   // PCB floor clearance (wires/JST underneath)

/* ---------------- bridge LiPo (MakerHawk 1100 mAh) ---------------- */
lipo_l = 40.0;  lipo_w = 25.0;  lipo_t = 10.0;   // measured
lipo_clear = 1.0;   // all-round pocket clearance
lipo_lead  = 2.0;   // extra on the lead end (JST + strain relief)

/* ---------------- buck (Pololu D24V10F5) ---------------- */
buck_l = 12.7;  buck_w = 10.2;   // MEASURE (datasheet 0.5" x 0.4")
buck_recess = 0.6;               // floor recess to locate it (foam-tape it in)

/* ---------------- east bay (buck + divider + LEMO tail) ---------------- */
bay_l = 16.0;   // depth of the bay along X

/* ---------------- connectors ---------------- */
usb_w = 10.0;  usb_h = 4.8;      // USB-C cutout (port ~9x3.2 + slip)  MEASURE
lemo_hole_d = 12.0;  // MEASURE your shell: LEMO 0B panel ~9.1 mm (+ key flat),
                     // 1B ~12.1 mm.  Add the anti-rotation flat after measuring.
sma_d = 6.5;         // SMA bulkhead pass-through  VERIFY (skip if using a grommet)

/* ---------------- lid features (offsets from the PCB's SW corner) ------- */
oled_off_x = 16.0;   // MEASURE  (active area 21.7 x 11, roughly mid-board)
oled_off_y = 7.25;   // MEASURE
oled_w = 23.7;       // window = active area + ~1 mm margin per side
oled_h = 13.0;
prg_x = 8.0;   prg_y = 5.0;    // MEASURE  PRG/USER button centre
rst_x = 8.0;   rst_y = 20.5;   // MEASURE  RST button centre
btn_d = 4.5;                   // access-hole diameter

/* ---------------- screws (M2 self-tap into bosses) ---------------- */
boss_d      = 6.0;
screw_pilot = 1.7;   // M2 self-tap pilot in PETG
screw_clear = 2.4;   // clearance through lid
cb_d = 4.6;  cb_t = 1.2;   // pan-head counterbore

/* ================= derived layout (don't edit below casually) ========== */
hz_l = pcb_l + 1.0;                      // Heltec zone, 0.5 mm slip per side
hz_w = pcb_w + 1.0;
lp_l = lipo_l + 2*lipo_clear + lipo_lead;   // LiPo pocket incl. lead room
lp_w = lipo_w + 2*lipo_clear;

inner_l = pad + hz_l + rib + bay_l;                 // ~70.8
inner_w = pad + hz_w + corridor + lp_w + pad;       // ~63.5
inner_h = standoff_h + pcb_t + comp_h + 2.0;        // 16

outer_l = inner_l + 2*wall;
outer_w = inner_w + 2*wall;
base_h  = wall + inner_h;

bx = wall + pad + 0.5;          // PCB SW corner (board centred in its zone)
by = wall + pad + 0.5;
ribY  = wall + pad + hz_w;      // corridor south rib, south face
lipoY = ribY + corridor;        // corridor north rib, north face = LiPo pocket edge
ribX  = wall + pad + hz_l;      // bay rib (Heltec row | east bay), west face
bayX  = ribX + rib;             // east bay west edge
lipoX = wall + pad;             // LiPo pocket west edge
gap_x0 = 36;  gap_x1 = 46;      // corridor-rib gap: LiPo JST lead crossing

boss_pos = [
  [5,           ribY + corridor/2],   // A — west wall, in the corridor
  [28,          ribY + corridor/2],   // B — mid corridor
  [outer_l - 5, 5],                   // C — east bay, SE corner
  [outer_l - 5, outer_w - 5],         // D — LiPo-row free corner, NE
];

echo(str("outer: ", outer_l, " x ", outer_w, " x ", base_h + lid_t, " mm"));
echo(str("inner: ", inner_l, " x ", inner_w, " x ", inner_h, " mm"));

/* ================= helpers ================= */
module rbox(l, w, h, r) {            // box rounded in XY
  hull() for (x = [r, l - r], y = [r, w - r])
    translate([x, y, 0]) cylinder(h = h, r = r);
}

module vent_row(x0, n, z = wall + 3, h = 9, w = 1.4, pitch = 3.2, yw = 0) {
  // yw = 0 cuts the south wall; yw = outer_w - wall cuts the north wall
  for (i = [0 : n - 1])
    translate([x0 + i*pitch, yw - 0.1, z]) cube([w, wall + 0.2, h]);
}

module xrib(y, x0, x1) { translate([x0, y, wall]) cube([x1 - x0, rib, rib_h]); }
module yrib(x, y0, y1) { translate([x, y0, wall]) cube([rib, y1 - y0, rib_h]); }

/* ================= base ================= */
module base() {
  difference() {
    rbox(outer_l, outer_w, base_h, fillet);

    // cavity
    translate([wall, wall, wall]) cube([inner_l, inner_w, inner_h + 1]);

    // USB-C cutout, west wall, centred on the PCB (+ chamfered mouth)
    translate([-0.1, by + pcb_w/2 - usb_w/2, wall + standoff_h + pcb_t - 0.8])
      cube([wall + pad + 0.2, usb_w, usb_h]);
    translate([-0.1, by + pcb_w/2 - usb_w/2 - 1.2, wall + standoff_h + pcb_t - 2.0])
      cube([1.2, usb_w + 2.4, usb_h + 2.4]);

    // LEMO panel hole, east wall, centred — battery leads (VBAT/GND) enter here
    translate([outer_l - wall - 0.1, outer_w/2, wall + inner_h/2])
      rotate([0, 90, 0]) cylinder(h = wall + 0.2, d = lemo_hole_d);

    // SMA bulkhead (antenna), east wall, Heltec-row side
    translate([outer_l - wall - 0.1, by + pcb_w/2, wall + inner_h/2])
      rotate([0, 90, 0]) cylinder(h = wall + 0.2, d = sma_d);

    // vents — south wall: over the ESP module + over the buck bay
    vent_row(30, 6);
    vent_row(59, 4);
    // vents — north wall: LiPo-row free east area only (not over the cell)
    vent_row(52, 5, yw = outer_w - wall);

    // buck locating recess in the bay floor (foam-tape the buck into it)
    translate([bayX + 1.5, by + 4, wall - buck_recess])
      cube([buck_l + 1, buck_w + 1, buck_recess + 0.1]);
  }

  // screw bosses (pilot-holed for M2 self-tappers)
  for (p = boss_pos)
    translate([p[0], p[1], wall]) difference() {
      cylinder(h = inner_h, d = boss_d);
      translate([0, 0, inner_h - 8]) cylinder(h = 8.1, d = screw_pilot);
    }

  // corridor ribs (south + north), gapped at x 36..46 for the JST-lead crossing
  xrib(ribY,        wall, gap_x0);  xrib(ribY,        gap_x1, wall + inner_l);
  xrib(lipoY - rib, wall, gap_x0);  xrib(lipoY - rib, gap_x1, wall + inner_l);

  // bay rib (Heltec row | east bay) — gap at y 12..20 for 5V/GND/GPIO7 wires
  yrib(ribX, wall, 12);
  yrib(ribX, 20, ribY);

  // LiPo end rib — gap at y 46..56 routes the lead toward the corridor gap
  yrib(lipoX + lp_l, lipoY, 46);
  yrib(lipoX + lp_l, 56, wall + inner_w);

  // PCB corner pads (board rests on these, 3 mm off the floor)
  for (p = [[bx - 0.5, by - 0.5], [bx + pcb_l - 3.5, by - 0.5],
            [bx - 0.5, by + pcb_w - 3.5], [bx + pcb_l - 3.5, by + pcb_w - 3.5]])
    translate([p[0], p[1], wall]) cube([4, 4, standoff_h]);
}

/* ================= lid (modelled in assembled position) ================= */
module lid() {
  difference() {
    union() {
      translate([0, 0, base_h]) rbox(outer_l, outer_w, lid_t, fillet);
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

    // screw holes + counterbores
    for (p = boss_pos) {
      translate([p[0], p[1], base_h - 3.2])
        cylinder(h = lid_t + 3.4, d = screw_clear);
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
  translate([0, -8, base_h + lid_t]) rotate([180, 0, 0]) lid();
}
