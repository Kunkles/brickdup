// brickdup — sensor-node enclosure (parametric OpenSCAD)
// =================================================================
// Version: v11 (2026-06-20) — hosts the combined PSU PCB (40x20 mm custom
//          buck+divider board, see pcb/README.md): the buck floor-recess is
//          gone, the south channel is widened (ch_s 13.5 -> 20) to seat the
//          board on two M2 standoff bosses, and a notch is cut in the south
//          rib + retention lip so the board's 5V/SENSE/GND wires reach the
//          Heltec.  Box grows ~8 mm wider (outer ~76 x 63 x 27).  Only the
//          south side moves; the Heltec tray, the LEMO/SMA east wall and the
//          lid are unchanged.  Board I/O is JST-PH (J1 to the LEMO, J2 to the
//          Heltec); psu_gap_e holds the board's east edge back so J1 + its plug
//          clear the LEMO's rear cups (~15 mm, see the clearance echo).
//          v10 (2026-06-18) — east bay bumped to bay_l 20 (~10 mm clear
//          behind the LEMO).
//          v9 (2026-06-18) — east bay deepened (bay_l 12 → 18) so the LEMO's
//          rear solder cups/wires clear the board/tray.  Because USB,
//          buttons, OLED + board are all west-referenced, only the east wall
//          (LEMO/SMA) moves — lid is unchanged; box grows ~6 mm in length.
//          v8 (2026-06-18) — LEMO back to lemo_y 14 (the v7 scoot left no
//          room for the panel nut to spin on the back).
//          v7 (2026-06-18) — SMA flat opened to 5.9; LEMO scooted toward
//          the south wall (lemo_y 14 → 12.5).
//          v6 (2026-06-18) — LEMO double-D rotated 90°: flats now on the
//          left + right of the hole (were top/bottom).
//          v5 (2026-06-11) — LEMO and SMA swapped on the east wall:
//          LEMO's rear now faces the south channel for wire access; LEMO
//          hole 8.9 mm (measured, was the 12 mm guess) with its double-D
//          flats (8.2), SMA single flat (5.75); nub-side tray wall +1.5
//          and the snap nubs raised +1.5 to match the board's ride height
//          with the battery installed; USB hole shifted 1 mm south (the
//          port isn't quite on the board centreline).
//          v4 (2026-06-11) — battery pocket opened up to the calipered
//          cell (41.39x25.15x10.25): towers slimmed to 3 mm + pushed to
//          the ribs (42 mm clear span), end stop gone, tape retention.
//          v3 (2026-06-11) — post-print fit pass on the v2 print: button
//          height corrected from fit symptom (plunger pressed the switch
//          with the lid screwed tight), plunger flange slimmed to match,
//          tray length -1.
//          v2 (2026-06-10) — first measured revision: real board/buck/
//          LEMO dims, click-in board tray, captive button plungers.
//          (v1 = the pre-measurement scaffold, git history before this.)
//
// STACKED + SIDE-CHANNEL layout:
//
//   z 2..12   1100 mAh bridge LiPo (41.4x25.15x10.25) flat on the floor
//   z 18..19  Heltec WiFi LoRa 32 V3 on four 16 mm corner towers, directly
//             above the cell with ~5.75 mm clearance over it for the J2 wires
//             (battery JST is on the board's underside, so the lead run is tiny)
//   south ch  PSU PCB (40x20 buck+divider) on two M2 bosses + wire raceway
//   north ch  wire slack raceway (7 mm wide)
//   east bay  LEMO panel connector tail (the divider now lives on the PSU PCB)
//
// The board sits ~2.5 mm from the west wall, so USB-C is a normal
// chamfered port hole (~4 mm recess), not a deep slot.  All four M2
// screws are internal corner bosses, in the channel corners.  Channels
// open into the east bay, so wires run LEMO → channel → PSU board → Heltec
// (south-rib notch).  Outer ≈ 76 x 63 x 27 mm.
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
//     enlarge usb_w/usb_h if the nose is chunky.  The lid's lip is notched
//     above the port so the plug doesn't hit it.
//   - The LEMO body is 12 mm from the back of its flange (measured), so it
//     intrudes 10 mm past the 2 mm wall — and the bay is 20 mm deep, so its
//     rear cups/wires sit ~10 mm clear of the bay rib (board edge).  At the
//     SE position its rear lines up with the south channel, so the leads
//     run straight down the channel (toward the buck) with no sharp bend.
//   - LiPo: cell measured 41.39 x 25.15 x 10.25.  It sits between the
//     corner towers (42 mm clear span, ~0.65 mm/side width-wise), tape-
//     retained — no end stop, so the leads have free run to the bay-rib
//     gap.  Never squeeze the pouch.
//   - The board CLICKS into its tray: full-height cradle walls (2 mm past
//     the PCB top), a continuous chamfered lip on the south rib, and two
//     snap nubs on flex tabs on the north rib.  Assembly: tilt the south
//     edge under the lip's 45° mouth (~1.7 mm above the board), press the
//     north edge down past the nubs — pinned at 0.3 mm.  All overhangs are
//     45°, so it prints supportless.
//   - Buttons are actuated by CAPTIVE PRINTED PLUNGERS (no exposed PCB):
//     each button gets a guide tube under the lid and a printed piston,
//     dropped in from the inside before the lid goes on.  The flared cone
//     keeps it captive; the tactile switch's own spring returns it.  Verify
//     `btn_top` (button cap height above the PCB) or the throw will be off.
//     The guide-tube length is DERIVED from the under-lid headroom; with
//     comp_h = 4 the lid sits low, so the flange stack is slimmed to fit.
//     A console warning prints if the headroom is too small for the flange.
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
pcb_l      = 47.0;  // measured, then -1 after the v2 print (tray = pcb_l + 1)
tab_gap    = 18.0;  // bay-rib gap for the board's u.FL antenna tab (+ wires),
                    // centred on the board  MEASURE tab width/offset
pcb_w      = 25.5;  // MEASURE
pcb_t      = 1.0;
comp_h     = 4.0;   // tallest part above PCB (OLED/USB)  MEASURE
standoff_h = 16.0;  // tower height: LiPo (10.25) + ~5.75 mm above it so the J2
                    // plug + 3 wires can route up and over the LiPo to the Heltec
                    // pads (was 13; raised for connector/wire clearance). The
                    // cleaner fix (a horizontal wire trench between the south rib
                    // and the LiPo) is a dry-fit refinement once the parts are in hand.

/* ---------------- bridge LiPo (MakerHawk 1100 mAh) ---------------- */
lipo_l = 41.4;  lipo_w = 25.15;  lipo_t = 10.25; // measured (v2 print fit);
                                                 // length excludes the leads —
                                                 // they exit via the bay-rib gap

/* ---------------- PSU PCB (custom buck + divider, pcb/README.md) -------- */
psu_l = 40.0;   // PCB length, runs east-west along the south channel  MEASURE final
psu_w = 20.0;   // PCB width, north-south
psu_t = 1.6;    // PCB thickness (2-layer FR4)
psu_stand = 2.5;            // standoff height under the PCB (bottom clearance)
psu_clear = 1.0;            // slip clearance around the board in its bay
psu_holes   = [[5.0, 16.0], [35.0, 16.0]]; // M2 holes (board-local) on the south
                            // band — clear of the J2 (north) + J1 (east) connectors
psu_gap_e   = 3.5;          // gap from the board's east edge to the bay rib — keeps
                            // the J1 (LEMO) JST + its mating plug clear of the
                            // LEMO's rear solder cups (see clearance echo)
lemo_intrude = 10.0;        // LEMO body depth past the inner wall face (from v9 notes)

/* ---------------- channels & east bay ---------------- */
ch_s  = psu_w + 2*psu_clear;  // south channel hosts the PSU PCB (+ slip)
ch_n  = 7.0;    // north channel: divider / wire slack
bay_l = 20.0;   // east bay: LEMO tail (10 into cavity) + wire bend + divider.
                // Deeper than the tail needs (was 12) to keep the LEMO's rear
                // solder cups + wires well clear of the board/tray — ~10 mm of
                // open space behind the connector before the bay rib.

/* ---------------- connectors ---------------- */
usb_w = 12.0;  usb_h = 7.0;      // port hole, chamfered  MEASURE plug nose
usb_y_off = -1.0;                // port sits ~1 mm south of the board
                                 // centreline (print fit)
lemo_hole_d = 8.9;   // measured
lemo_nut = 13.0;     // panel-nut clearance width — sets the lid-lip relief over
                     // the LEMO so the lid seats without hitting the nut  MEASURE
lemo_flat = 8.2;     // measured across the LEMO's two flats (double-D hole,
                     // flats left + right since v6)
lemo_y = 14.0;       // LEMO at the SE spot (swapped with the SMA): its rear
lemo_z = 14.0;       // faces the open bay + south channel, so there's working
                     // room to solder and dress the leads.  Kept off the south
                     // wall so the panel nut has room to spin on the back.
sma_d = 6.5;         // SMA bulkhead pass-through  VERIFY (east wall)
sma_flat = 5.9;      // measured flat-to-round (single flat, on the bottom)
sma_z = 9.0;         // SMA takes the old LEMO spot: board centreline, low

/* ---------------- lid features (offsets from the PCB's SW corner) ------- */
oled_off_x = 20.0;   // MEASURE  (active area 21.7 x 11, roughly mid-board)
oled_off_y = 7.25;   // MEASURE
oled_w = 23.7;       // window = active area + ~1 mm margin per side
oled_h = 13.0;
prg_x = 4.5;   prg_y = 5.0;    // MEASURE  PRG/USER button centre
rst_x = 4.5;   rst_y = 20.5;   // MEASURE  RST button centre
btn_d = 4.5;                   // access-hole diameter (plungers = false only)

/* ---------------- button plungers (captive printed pistons) ------------- */
plungers = true;     // false = plain access holes instead
btn_top  = 3.2;      // button cap height above the PCB top — set from the v2
                     // print's fit (piston pressed the switch when the lid
                     // was screwed tight by ~1.5mm); VERIFY with calipers
plunger_gap = 0.3;   // how proud of the lid the piston sits resting on the button
bore_d   = 6.4;      // bore through lid + guide tube
stem_d   = 6.0;      // piston body (what your finger presses)
flange_d = 7.4;      // captive flare (cones at 45° — supportless), slimmed
flange_t = 0.3;      // flange land thickness
tip_d    = 4.0;      // contact face on the button cap
tube_od  = 9.4;      // guide tube under the lid (length derived below)

/* ---------------- screws (M2 self-tap into corner bosses) ---------------- */
boss_d      = 6.0;
screw_pilot = 1.7;   // M2 self-tap pilot in PETG
screw_clear = 2.4;   // clearance through lid
cb_d = 4.6;  cb_t = 1.2;   // pan-head counterbore

/* ================= derived layout (don't edit below casually) ========== */
hz_l = pcb_l + 1.0;                      // Heltec zone, 0.5 mm slip per side
hz_w = pcb_w + 1.0;

inner_l = pad + hz_l + rib + bay_l;            // ~68.8
inner_w = ch_s + rib + hz_w + rib + ch_n;      // ~50.2
inner_h = standoff_h + pcb_t + comp_h + 2.0;   // ~20

outer_l = inner_l + 2*wall;
outer_w = inner_w + 2*wall;
base_h  = wall + inner_h;

bx = wall + pad + 0.5;            // PCB SW corner (board centred in its zone)
by = wall + ch_s + rib + 0.5;
ribS    = wall + ch_s;            // south rib (channel | board zone), south face
ribN    = ribS + rib + hz_w;      // north rib (board zone | channel), south face
ribX    = wall + pad + hz_l;      // bay rib (board zone | east bay), west face
psu_x0  = ribX - psu_l - psu_gap_e; // PSU PCB SW corner (east edge faces the LEMO)
psu_y0  = wall + (ch_s - psu_w)/2;  // centred across the south channel
psu_lemo_clear = (wall + inner_l - lemo_intrude) - (psu_x0 + psu_l); // J1 <-> LEMO rear
board_top = wall + standoff_h + pcb_t;   // PCB top surface (z)
rim_top   = board_top + 2;               // cradle walls rise 2 mm past the PCB
pcb_yc  = by + pcb_w/2;           // board centreline: USB, LEMO + tail follow it
usb_zc  = wall + standoff_h + pcb_t + 1.6; // USB port axis height

boss_pos = [ [5, 5], [5, outer_w - 5],
             [outer_l - 5, 5], [outer_l - 5, outer_w - 5] ];

btns    = [ [prg_x, prg_y], [rst_x, rst_y] ];
btn_z   = wall + standoff_h + pcb_t + btn_top;   // button cap top (z)
lid_top = base_h + lid_t;

// plunger geometry, derived (all cones 45°):
flare_h = (flange_d - tip_d) / 2;    // tip → flange
taper_h = (flange_d - stem_d) / 2;   // flange → stem
// distance from the tip to where the upper taper measures bore_d — that
// point seating on the tube rim is what makes the piston captive
seat_h  = flare_h + flange_t + taper_h * (flange_d - bore_d)/(flange_d - stem_d);
// tube reaches down to leave ~0.3 mm of outward float at rest-on-button
tube_len = max(0, base_h - btn_z - seat_h - 0.3);
if (plungers && base_h - btn_z < seat_h + 0.2)
  echo("WARNING: not enough under-lid headroom for the plunger flange — increase comp_h or slim flange_d/flange_t/tip_d");

echo(str("outer: ", outer_l, " x ", outer_w, " x ", base_h + lid_t, " mm"));
echo(str("inner: ", inner_l, " x ", inner_w, " x ", inner_h, " mm"));
echo(str("PSU bay: ", psu_l, " x ", psu_w, " at SW (", psu_x0, ",", psu_y0,
         "), bosses top z=", wall + psu_stand));
echo(str("J1(LEMO) <-> LEMO rear clearance = ", psu_lemo_clear, " mm"));
echo(str("plunger: tube_len ", tube_len, ", stem ",
         lid_top + plunger_gap - btn_z - flare_h - flange_t - taper_h, " mm"));

/* ================= helpers ================= */
module rbox(l, w, h, r) {            // box rounded in XY
  hull() for (x = [r, l - r], y = [r, w - r])
    translate([x, y, 0]) cylinder(h = h, r = r);
}

module vent_row(x0, n, z = 13, h = 7, w = 1.4, pitch = 3.2, yw = 0) {
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

      // channel ribs (stop at the bay, so channels open into it).  The
      // board CLICKS into them: the south rib carries a continuous lip the
      // board's edge slides under, the north rib has two chamfered snap
      // nubs on flex tabs.  Assembly: tilt the south edge under the lip,
      // press the north edge down past the nubs.
      difference() {
        union() {
          translate([wall, ribS, wall])
            cube([ribX - wall, rib, rim_top - wall]);
          // nub-side wall runs 1.5 taller: with the battery pushing the
          // board up from below, its edge can't pop over the wall top
          translate([wall, ribN, wall])
            cube([ribX - wall, rib, rim_top + 1.5 - wall]);
          // south retention lip — 45° chamfered underside: the mouth sits
          // ~1.7 mm above the board so the tilted edge slides under, then
          // wedges toward snug at the wall face as the board levels
          hull() {
            translate([wall + pad, ribS, board_top + 1.7])
              cube([ribX - wall - pad, rib + 1.2, rim_top - board_top - 1.7]);
            translate([wall + pad, ribS, board_top + 0.5])
              cube([ribX - wall - pad, rib + 0.01, rim_top - board_top - 0.5]);
          }
          // north snap nubs — 45° lead-in above, flat underside raised to
          // match the board's battery-pushed ride height (+1.8 over the
          // nominal board top)
          for (x0 = [18, 42]) hull() {
            translate([x0, ribN - 1.3, board_top + 1.8])
              cube([4, 1.3 + rib, 0.1]);
            translate([x0, ribN, board_top + 3.0]) cube([4, rib, 0.1]);
          }
        }
        // slits flanking each nub so its rib section can flex outward
        for (x0 = [18, 42], dx = [-3.8, 6])
          translate([x0 + dx, ribN - 0.1, 6])
            cube([1.8, rib + 0.2, rim_top]);
      }

      // west rim band: cradles the board's USB edge (hole cut through it)
      translate([wall, ribS + rib, wall])
        cube([pad, hz_w, rim_top - wall]);

      // bay rib — centre gap clears the board's u.FL antenna tab, plus the
      // wires between the bay and the board zone
      translate([ribX, ribS + rib, wall])
        cube([rib, pcb_yc - tab_gap/2 - (ribS + rib), rim_top - wall]);
      translate([ribX, pcb_yc + tab_gap/2, wall])
        cube([rib, ribN - (pcb_yc + tab_gap/2), rim_top - wall]);

      // PCB corner towers (board rests on these at standoff_h) — 3 mm wide
      // and flush against the west rim / bay rib, so the clear span between
      // them (42 mm) takes the cell; no end stop, the cell is tape-retained
      for (p = [[bx - 0.5, by - 0.5], [bx + pcb_l - 2.5, by - 0.5],
                [bx - 0.5, by + pcb_w - 3.5],
                [bx + pcb_l - 2.5, by + pcb_w - 3.5]])
        translate([p[0], p[1], wall]) cube([3, 4, standoff_h]);

      // internal corner screw bosses (channel corners, clear of everything)
      for (p = boss_pos)
        translate([p[0], p[1], wall]) cylinder(h = inner_h, d = boss_d);

      // PSU PCB standoff bosses — the board screws down onto these (M2 self-tap).
      // Board is inserted with its KiCad TOP edge (the J2 / Heltec side) toward
      // the enclosure NORTH so J2 faces the Heltec and J1 faces the LEMO (east).
      // KiCad measures Y downward, OpenSCAD upward, so flip Y: psu_w - h[1].
      for (h = psu_holes)
        translate([psu_x0 + h[0], psu_y0 + (psu_w - h[1]), wall])
          cylinder(h = psu_stand, d = boss_d);
    }

    // boss pilot holes (M2 self-tap)
    for (p = boss_pos)
      translate([p[0], p[1], base_h - 8]) cylinder(h = 8.1, d = screw_pilot);

    // USB-C port hole, west wall + rim (~4 mm recess), with a 45° chamfered
    // mouth so the plug nose seats (chamfer kept below the wall's top edge)
    translate([-0.1, pcb_yc + usb_y_off - usb_w/2, usb_zc - usb_h/2])
      cube([wall + pad + 0.2, usb_w, usb_h]);
    translate([-0.1, pcb_yc + usb_y_off - usb_w/2 - 1.0, usb_zc - usb_h/2 - 1.0])
      cube([1.0, usb_w + 2, usb_h + 2]);

    // LEMO panel hole, east wall, SE position — the 10 mm tail stays in the
    // bay and its rear lines up with the south channel for wire access.
    // Double-D: 8.9 dia with both flats (8.2 across) on the LEFT + RIGHT
    // (rotated 90° from top/bottom)
    intersection() {
      translate([outer_l - wall - 0.1, lemo_y, lemo_z])
        rotate([0, 90, 0]) cylinder(h = wall + 0.2, d = lemo_hole_d);
      translate([outer_l - wall - 0.2, lemo_y - lemo_flat/2,
                 lemo_z - lemo_hole_d/2])
        cube([wall + 0.4, lemo_flat, lemo_hole_d]);
    }

    // SMA bulkhead (antenna), east wall, board centreline, low — u.FL
    // pigtail from the board's east end reaches it through the bay.
    // Single flat on the bottom (5.9 flat-to-round)
    intersection() {
      translate([outer_l - wall - 0.1, pcb_yc, sma_z])
        rotate([0, 90, 0]) cylinder(h = wall + 0.2, d = sma_d);
      translate([outer_l - wall - 0.2, pcb_yc - sma_d/2,
                 sma_z + sma_d/2 - sma_flat])
        cube([wall + 0.4, sma_d, sma_flat]);
    }

    // vents — both channel walls (kept below the wall top / lid lip)
    vent_row(25, 7);
    vent_row(25, 7, yw = outer_w - wall);

    // PSU PCB: notch the south rib + retention lip so the board's
    // 5V/SENSE/GND wires reach the Heltec (board sits south of the rib;
    // the Heltec sits north of it), and pilot the two M2 standoff bosses.
    translate([psu_x0 + 5, ribS - 0.1, wall])
      cube([12, rib + 2.0, rim_top]);                 // notch over J2 (board X~6-14)
    for (h = psu_holes)
      translate([psu_x0 + h[0], psu_y0 + (psu_w - h[1]), wall - 0.1])
        cylinder(h = psu_stand + 0.2, d = screw_pilot);
  }
}

/* ================= lid (modelled in assembled position) ================= */
module lid() {
  difference() {
    union() {
      translate([0, 0, base_h]) rbox(outer_l, outer_w, lid_t, fillet);
      // plunger guide tubes under the lid
      if (plungers && tube_len > 0)
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

    // lip notch over the USB port — the low lid puts the lip in the plug's
    // path, so clear it across the port width (tracks usb_y_off)
    translate([-0.1, pcb_yc + usb_y_off - usb_w/2, base_h - 3.1])
      cube([wall + pad + 0.2, usb_w, 3.2]);

    // lip notch over the LEMO nut (east wall) — the panel nut rides up near the
    // lid lip; relieve the lip across the nut width so the lid seats fully
    // (parametric version of the manual shave from the first print).
    translate([outer_l - wall - 2, lemo_y - lemo_nut/2, base_h - 3.1])
      cube([wall + 2.1, lemo_nut, 3.2]);

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
// bottom rim (~0.3 mm of float) — it cannot escape; pushed, it clicks the
// switch.  The switch spring returns it.
module plunger() {                       // local frame: tip face at z = 0
  len = lid_top + plunger_gap - btn_z;   // tip on button → top proud of lid
  cylinder(h = flare_h, d1 = tip_d, d2 = flange_d);
  translate([0, 0, flare_h]) cylinder(h = flange_t, d = flange_d);
  translate([0, 0, flare_h + flange_t])
    cylinder(h = taper_h, d1 = flange_d, d2 = stem_d);
  translate([0, 0, flare_h + flange_t + taper_h])
    cylinder(h = len - flare_h - flange_t - taper_h, d = stem_d);
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
