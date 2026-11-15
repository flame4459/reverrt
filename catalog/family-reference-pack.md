# Family reference pack

One finished side elevation per family replaces every placeholder in that family.
3 ready, 0 need work, 67 missing.

Target: ~1200 x 800, side elevation, full bike, both wheels down, front wheel
to the right, plain background, no rider, no text, no watermark, no floor shadow.
Save exactly as the `ref_filename` below, then:

```sh
python3 Scripts/check_references.py      # validate (needs openpyxl)
python3 Scripts/family_refs.py report    # same, without the workbook
python3 Scripts/generate_bike_sprites.py --width 170 --scale 7
python3 Scripts/import_bike_sprites.py
```

The prompt in the wishlist is written for a text-to-image model. Generate
several candidates, pick the cleanest side elevation, and keep the bike's
actual livery; a generic fantasy bike is worse than the placeholder.

## Missing

### Aprilia — RS/RSV  (11 models)  
`bikes/refs/aprilia-rs-rsv.jpeg`

Examples: RS125, RS250, RSV Mille, RSV Mille R

> 8-bit pixel art sprite of a Aprilia RS/RSV motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Aprilia — Scarabeo/SR/Atlantic  (9 models)  
`bikes/refs/aprilia-scarabeo-sr-atlantic.jpeg`

Examples: Scarabeo 50, Scarabeo 125, Scarabeo 200, Scarabeo 500

> 8-bit pixel art sprite of a Aprilia Scarabeo/SR/Atlantic motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Aprilia — Tuono/Shiver  (8 models)  
`bikes/refs/aprilia-tuono-shiver.jpeg`

Examples: Tuono 1000 R, Tuono V4 1100, Tuono V4 1100 Factory, Tuono 660

> 8-bit pixel art sprite of a Aprilia Tuono/Shiver motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Aprilia — Pegaso/Caponord/Tuareg  (7 models)  
`bikes/refs/aprilia-pegaso-caponord-tuareg.jpeg`

Examples: Pegaso 650, Pegaso Strada, Caponord 1000 ETV, Caponord 1200

> 8-bit pixel art sprite of a Aprilia Pegaso/Caponord/Tuareg motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Aprilia — SXV/RXV  (2 models)  
`bikes/refs/aprilia-sxv-rxv.jpeg`

Examples: SXV 5.5, SXV 450

> 8-bit pixel art sprite of a Aprilia SXV/RXV motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### BMW — GS  (23 models)  
`bikes/refs/bmw-gs.jpeg`

Examples: R80GS, R100GS, R850GS, R1100GS

> 8-bit pixel art sprite of a BMW GS motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### BMW — R/K Touring  (23 models)  
`bikes/refs/bmw-r-k-touring.jpeg`

Examples: R1100RS, R1100RT, R1150RT, R1200RT

> 8-bit pixel art sprite of a BMW R/K Touring motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### BMW — R/K/S Naked  (18 models)  
`bikes/refs/bmw-r-k-s-naked.jpeg`

Examples: R1100R, R1150R, R1200R, R1250R

> 8-bit pixel art sprite of a BMW R/K/S Naked motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### BMW — S/M/HP  (11 models)  
`bikes/refs/bmw-s-m-hp.jpeg`

Examples: S1000RR, S1000R, S1000XR, M1000RR

> 8-bit pixel art sprite of a BMW S/M/HP motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### BMW — R nineT/R12  (8 models)  
`bikes/refs/bmw-r-ninet-r12.jpeg`

Examples: R nineT, R nineT Scrambler, R nineT Pure, R nineT Racer

> 8-bit pixel art sprite of a BMW R nineT/R12 motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### BMW — C/CE  (7 models)  
`bikes/refs/bmw-c-ce.jpeg`

Examples: C1, C600 Sport, C650 GT, C400X

> 8-bit pixel art sprite of a BMW C/CE motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### BMW — R18/R1200C  (5 models)  
`bikes/refs/bmw-r18-r1200c.jpeg`

Examples: R1200C, R18, R18 Classic, R18 B

> 8-bit pixel art sprite of a BMW R18/R1200C motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Ducati — Superbike  (21 models)  
`bikes/refs/ducati-superbike.jpeg`

Examples: 851, 888, 916, 748

> 8-bit pixel art sprite of a Ducati Superbike motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Ducati — Monster  (17 models)  
`bikes/refs/ducati-monster.jpeg`

Examples: Monster 400, Monster 600, Monster 750, Monster 900

> 8-bit pixel art sprite of a Ducati Monster motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Ducati — Diavel/Scrambler  (13 models)  
`bikes/refs/ducati-diavel-scrambler.jpeg`

Examples: Diavel, XDiavel, Diavel V4, Scrambler Icon

> 8-bit pixel art sprite of a Ducati Diavel/Scrambler motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Ducati — Supersport/ST  (11 models)  
`bikes/refs/ducati-supersport-st.jpeg`

Examples: Supersport 400, Supersport 600, Supersport 750, Supersport 900

> 8-bit pixel art sprite of a Ducati Supersport/ST motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Ducati — Multistrada/DesertX  (11 models)  
`bikes/refs/ducati-multistrada-desertx.jpeg`

Examples: Multistrada 620, Multistrada 1000DS, Multistrada 1100, Multistrada 1200

> 8-bit pixel art sprite of a Ducati Multistrada/DesertX motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Ducati — Hypermotard  (6 models)  
`bikes/refs/ducati-hypermotard.jpeg`

Examples: Hypermotard 1100, Hypermotard 796, Hypermotard 821, Hypermotard 939

> 8-bit pixel art sprite of a Ducati Hypermotard motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Ducati — Streetfighter  (4 models)  
`bikes/refs/ducati-streetfighter.jpeg`

Examples: Streetfighter 1098, Streetfighter 848, Streetfighter V4, Streetfighter V2

> 8-bit pixel art sprite of a Ducati Streetfighter motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Harley-Davidson — Softail  (20 models)  
`bikes/refs/harley-davidson-softail.jpeg`

Examples: FLSTF Fat Boy, Fat Boy 114, FLSTC Heritage Softail Classic, Heritage Classic 114

> 8-bit pixel art sprite of a Harley-Davidson Softail motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Harley-Davidson — Touring  (18 models)  
`bikes/refs/harley-davidson-touring.jpeg`

Examples: Road King FLHR, Road King Classic, Road King Special, Electra Glide Standard

> 8-bit pixel art sprite of a Harley-Davidson Touring motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Harley-Davidson — Sportster  (17 models)  
`bikes/refs/harley-davidson-sportster.jpeg`

Examples: XL883 Sportster, XL883 Hugger, XL883 Low, XL883 Iron

> 8-bit pixel art sprite of a Harley-Davidson Sportster motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Harley-Davidson — V-Rod/Street/Other  (10 models)  
`bikes/refs/harley-davidson-v-rod-street-other.jpeg`

Examples: VRSCA V-Rod, VRSCB V-Rod, VRSCD Night Rod, VRSCDX Night Rod Special

> 8-bit pixel art sprite of a Harley-Davidson V-Rod/Street/Other motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Harley-Davidson — Dyna  (9 models)  
`bikes/refs/harley-davidson-dyna.jpeg`

Examples: FXD Dyna Super Glide, FXDC Super Glide Custom, FXDX Super Glide Sport, FXDL Dyna Low Rider

> 8-bit pixel art sprite of a Harley-Davidson Dyna motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Harley-Davidson — Trikes  (3 models)  
`bikes/refs/harley-davidson-trikes.jpeg`

Examples: Tri Glide Ultra, Freewheeler, Street Glide Trike

> 8-bit pixel art sprite of a Harley-Davidson Trikes motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Harley-Davidson — Pan America  (3 models)  
`bikes/refs/harley-davidson-pan-america.jpeg`

Examples: Pan America 1250, Pan America 1250 Special, Pan America 1250 ST

> 8-bit pixel art sprite of a Harley-Davidson Pan America motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Honda — Africa Twin/Transalp/NC  (18 models)  
`bikes/refs/honda-africa-twin-transalp-nc.jpeg`

Examples: XRV750 Africa Twin, CRF1000L Africa Twin, CRF1100L Africa Twin, Africa Twin Adventure Sports

> 8-bit pixel art sprite of a Honda Africa Twin/Transalp/NC motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Honda — Shadow/Rebel/VTX  (18 models)  
`bikes/refs/honda-shadow-rebel-vtx.jpeg`

Examples: Shadow VLX VT600C, Shadow VT1100C, Shadow Spirit 750 VT750DC, Shadow Aero VT750C

> 8-bit pixel art sprite of a Honda Shadow/Rebel/VTX motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Honda — Gold Wing/Valkyrie/ST  (13 models)  
`bikes/refs/honda-gold-wing-valkyrie-st.jpeg`

Examples: Gold Wing GL1500, Gold Wing GL1800, Gold Wing Tour DCT, Gold Wing F6B

> 8-bit pixel art sprite of a Honda Gold Wing/Valkyrie/ST motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Honda — Scooters  (10 models)  
`bikes/refs/honda-scooters.jpeg`

Examples: PCX 125/160, ADV150/160, SH125/150, SH350i

> 8-bit pixel art sprite of a Honda Scooters motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Honda — XR/CRF  (8 models)  
`bikes/refs/honda-xr-crf.jpeg`

Examples: XR650L, XR250L, XR400R, CRF250L

> 8-bit pixel art sprite of a Honda XR/CRF motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Honda — Mini/Cub  (8 models)  
`bikes/refs/honda-mini-cub.jpeg`

Examples: Grom, Monkey, Super Cub C125, CT125 Hunter Cub

> 8-bit pixel art sprite of a Honda Mini/Cub motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Indian — Chieftain/Roadmaster  (13 models)  
`bikes/refs/indian-chieftain-roadmaster.jpeg`

Examples: Chieftain, Chieftain Dark Horse, Chieftain Limited, Chieftain Elite

> 8-bit pixel art sprite of a Indian Chieftain/Roadmaster motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Indian — Scout  (8 models)  
`bikes/refs/indian-scout.jpeg`

Examples: Scout, Scout Sixty, Scout Bobber, Scout Bobber Twenty

> 8-bit pixel art sprite of a Indian Scout motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Indian — Chief  (5 models)  
`bikes/refs/indian-chief.jpeg`

Examples: Chief Classic, Chief Vintage, Chief Dark Horse, Chief Bobber

> 8-bit pixel art sprite of a Indian Chief motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Indian — FTR  (5 models)  
`bikes/refs/indian-ftr.jpeg`

Examples: FTR 1200, FTR S, FTR R Carbon, FTR Rally

> 8-bit pixel art sprite of a Indian FTR motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### KTM — Duke  (14 models)  
`bikes/refs/ktm-duke.jpeg`

Examples: 125 Duke, 200 Duke, 250 Duke, 390 Duke

> 8-bit pixel art sprite of a KTM Duke motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### KTM — Adventure  (11 models)  
`bikes/refs/ktm-adventure.jpeg`

Examples: 640 Adventure, 950 Adventure, 990 Adventure, 1050 Adventure

> 8-bit pixel art sprite of a KTM Adventure motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### KTM — RC  (5 models)  
`bikes/refs/ktm-rc.jpeg`

Examples: RC 125, RC 200, RC 390, RC8

> 8-bit pixel art sprite of a KTM RC motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### KTM — SM/Enduro  (5 models)  
`bikes/refs/ktm-sm-enduro.jpeg`

Examples: 690 SMC R, 690 Enduro R, 950 Supermoto, 990 SM

> 8-bit pixel art sprite of a KTM SM/Enduro motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Kawasaki — Ninja ZX  (25 models)  
`bikes/refs/kawasaki-ninja-zx.jpeg`

Examples: Ninja 125, Ninja 250R EX250, Ninja 300, Ninja 400

> 8-bit pixel art sprite of a Kawasaki Ninja ZX motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Kawasaki — Z/ER/ZRX  (25 models)  
`bikes/refs/kawasaki-z-er-zrx.jpeg`

Examples: Z125 Pro, Z250, Z400, Z500

> 8-bit pixel art sprite of a Kawasaki Z/ER/ZRX motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Kawasaki — Vulcan/Eliminator  (17 models)  
`bikes/refs/kawasaki-vulcan-eliminator.jpeg`

Examples: Eliminator ZL600, Eliminator 125, Eliminator 400, Vulcan VN500

> 8-bit pixel art sprite of a Kawasaki Vulcan/Eliminator motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Kawasaki — Versys/KLR  (11 models)  
`bikes/refs/kawasaki-versys-klr.jpeg`

Examples: Versys 300, Versys 650, Versys 1000, Versys-X 300

> 8-bit pixel art sprite of a Kawasaki Versys/KLR motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Kawasaki — Concours/GTR  (3 models)  
`bikes/refs/kawasaki-concours-gtr.jpeg`

Examples: Concours ZG1000, Concours 14, GTR1400

> 8-bit pixel art sprite of a Kawasaki Concours/GTR motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Royal Enfield — Classic/Bullet  (14 models)  
`bikes/refs/royal-enfield-classic-bullet.jpeg`

Examples: Bullet 350 UCE, Bullet 350, Bullet 500, Classic 350

> 8-bit pixel art sprite of a Royal Enfield Classic/Bullet motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Royal Enfield — Twins  (5 models)  
`bikes/refs/royal-enfield-twins.jpeg`

Examples: Interceptor 650, Continental GT 650, Continental GT 535, Bear 650

> 8-bit pixel art sprite of a Royal Enfield Twins motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Royal Enfield — Himalayan/Scram  (4 models)  
`bikes/refs/royal-enfield-himalayan-scram.jpeg`

Examples: Himalayan 411, Himalayan 450, Scram 411, Scram 440

> 8-bit pixel art sprite of a Royal Enfield Himalayan/Scram motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Suzuki — GSX-S/SV/Bandit  (25 models)  
`bikes/refs/suzuki-gsx-s-sv-bandit.jpeg`

Examples: GSX-S125, GSX-S750, GSX-S950, GSX-S1000

> 8-bit pixel art sprite of a Suzuki GSX-S/SV/Bandit motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Suzuki — Intruder/Boulevard  (20 models)  
`bikes/refs/suzuki-intruder-boulevard.jpeg`

Examples: VS700 Intruder, VS750 Intruder, VS800 Intruder, VS1400 Intruder

> 8-bit pixel art sprite of a Suzuki Intruder/Boulevard motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Suzuki — GSX-R  (12 models)  
`bikes/refs/suzuki-gsx-r.jpeg`

Examples: GSX-R600, GSX-R750, GSX-R1000, GSX-R1000R

> 8-bit pixel art sprite of a Suzuki GSX-R motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Suzuki — V-Strom  (9 models)  
`bikes/refs/suzuki-v-strom.jpeg`

Examples: V-Strom 250, DL650 V-Strom, DL1000 V-Strom, V-Strom 1000

> 8-bit pixel art sprite of a Suzuki V-Strom motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Suzuki — DR/DR-Z  (7 models)  
`bikes/refs/suzuki-dr-dr-z.jpeg`

Examples: DR350, DR650SE, DR-Z400S, DR-Z400SM

> 8-bit pixel art sprite of a Suzuki DR/DR-Z motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Suzuki — Hayabusa  (4 models)  
`bikes/refs/suzuki-hayabusa.jpeg`

Examples: Hayabusa GSX1300R Gen 1, Hayabusa GSX1300R Gen 2, Hayabusa GSX1300R Gen 3, GSX1400

> 8-bit pixel art sprite of a Suzuki Hayabusa motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Suzuki — Burgman  (4 models)  
`bikes/refs/suzuki-burgman.jpeg`

Examples: Burgman 125, Burgman 200, Burgman 400, Burgman 650

> 8-bit pixel art sprite of a Suzuki Burgman motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Triumph — Tiger  (16 models)  
`bikes/refs/triumph-tiger.jpeg`

Examples: Tiger 885i, Tiger 955i, Tiger 1050, Tiger 800

> 8-bit pixel art sprite of a Triumph Tiger motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Triumph — Daytona/Sprint  (15 models)  
`bikes/refs/triumph-daytona-sprint.jpeg`

Examples: Daytona 750, Daytona 900, Daytona 1200, T595 Daytona

> 8-bit pixel art sprite of a Triumph Daytona/Sprint motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Triumph — Bonneville  (15 models)  
`bikes/refs/triumph-bonneville.jpeg`

Examples: Bonneville 790/865, Bonneville T100, Bonneville T120, Bonneville SE

> 8-bit pixel art sprite of a Triumph Bonneville motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Triumph — Rocket/Thunderbird  (14 models)  
`bikes/refs/triumph-rocket-thunderbird.jpeg`

Examples: Rocket III, Rocket 3 R, Rocket 3 GT, Thunderbird 900

> 8-bit pixel art sprite of a Triumph Rocket/Thunderbird motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Triumph — Speed/Street Triple  (13 models)  
`bikes/refs/triumph-speed-street-triple.jpeg`

Examples: Trident 750, Trident 900, Speed Triple, Speed Triple 1050

> 8-bit pixel art sprite of a Triumph Speed/Street Triple motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Yamaha — FZ/MT/XSR  (23 models)  
`bikes/refs/yamaha-fz-mt-xsr.jpeg`

Examples: FZ1, FZ6, FZ6R, FZ8

> 8-bit pixel art sprite of a Yamaha FZ/MT/XSR motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Yamaha — Virago/V-Star/Road Star  (21 models)  
`bikes/refs/yamaha-virago-v-star-road-star.jpeg`

Examples: XV250 Virago, V-Star 250, XV535 Virago, V-Star 650 XVS650

> 8-bit pixel art sprite of a Yamaha Virago/V-Star/Road Star motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Yamaha — YZF-R  (14 models)  
`bikes/refs/yamaha-yzf-r.jpeg`

Examples: YZF-R1, YZF-R1M, YZF-R1S, YZF-R6

> 8-bit pixel art sprite of a Yamaha YZF-R motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Yamaha — XT/WR/TW  (9 models)  
`bikes/refs/yamaha-xt-wr-tw.jpeg`

Examples: XT600E, XT660R, XT660X, XT250

> 8-bit pixel art sprite of a Yamaha XT/WR/TW motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Yamaha — Ténéré/TDM  (8 models)  
`bikes/refs/yamaha-t-n-r-tdm.jpeg`

Examples: TDM850, TDM900, XTZ750 Super Ténéré, XTZ660 Ténéré

> 8-bit pixel art sprite of a Yamaha Ténéré/TDM motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Yamaha — TMAX/XMAX/Zuma  (8 models)  
`bikes/refs/yamaha-tmax-xmax-zuma.jpeg`

Examples: TMAX, XMAX 125/250/300/400, NMAX 125/155, Zuma 50/125

> 8-bit pixel art sprite of a Yamaha TMAX/XMAX/Zuma motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite

### Yamaha — FJ/Tracer  (6 models)  
`bikes/refs/yamaha-fj-tracer.jpeg`

Examples: FJ1200, FJR1300, Tracer 700, Tracer 900

> 8-bit pixel art sprite of a Yamaha FJ/Tracer motorcycle, retro NES-style 16-colour palette, chunky clean pixels, side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, no shadow on the floor, game-ready sprite
