#!/usr/bin/env python3
"""S.W.I.S.H puzzle generator — builds original Scandinavian-style arrowword
puzzles from an original word/clue list. Outputs JSON puzzle packs."""

import json, random, os, sys

# ---------------------------------------------------------------- word list
# All clues below are original, written for this game.
WORDS = [
# 3 letters
("ANT","Tiny picnic crasher"),("APE","Jungle swinger"),("ASH","Fireplace remains"),
("BAT","Cave flier"),("BEE","Honey maker"),("BOW","Tied ribbon"),("BOX","Parcel"),
("BUS","City transport"),("CAB","Street taxi"),("CAN","Aluminum container"),
("CAP","Bottle topper"),("CAR","Road runner"),("CAT","Purring pet"),
("COW","Moo source"),("CUP","Coffee holder"),("DOG","Loyal barker"),
("DOT","Sentence ender"),("EGG","Omelet start"),("ELM","Shade tree"),
("FAN","Breeze maker"),("FOG","Pea-soup air"),("FOX","Sly critter"),
("GAS","Pump purchase"),("HAT","Head topper"),("HAY","Barn feed"),
("HEN","Egg layer"),("ICE","Skating surface"),("INK","Pen fluid"),
("JAR","Preserve holder"),("KEY","Lock mate"),("KITE","Wind rider"),
("LOG","Campfire fuel"),("MAP","Lost driver's aid"),("MUD","Rainy-day mess"),
("NAP","Couch snooze"),("NET","Goal mesh"),("OAR","Canoe pusher"),
("OIL","Squeak stopper"),("OWL","Wise night bird"),("PAN","Sizzle maker"),
("PEN","Ink writer"),("PIE","A la mode treat"),("PIG","Muddy oinker"),
("POT","Stew vessel"),("RAT","Alley scurrier"),("ROD","Fishing pole"),
("RUG","Floor cover"),("SAW","Carpenter's tool"),("SKI","Snow slider"),
("SOAP","Bubble maker"),("SOCK","Foot warmer"),("SUN","Daytime star"),
("TEA","Steeped drink"),("TENT","Camp shelter"),("TIE","Neckwear"),
("TIN","Can metal"),("VAN","Band vehicle"),("VASE","Flower holder"),
("WAX","Candle stuff"),("WEB","Spider home"),("YARN","Knitter's supply"),
# 4 letters
("ANCHOR","Ship stopper"),("APPLE","Orchard fruit"),("ARROW","Bow projectile"),
("AVOCADO","Guacamole fruit"),("BADGE","Scout's award"),("BALL","Catch toy"),
("BARN","Hay hotel"),("BEACH","Sandy shore"),("BEARD","Chin curtain"),
("BELL","Chime"),("BIRD","Feathered flier"),("BOAT","Water ride"),
("BREAD","Sandwich base"),("BRICK","Wall block"),("BRIDGE","River crosser"),
("BRUSH","Paint applier"),("CABLE","Wire bundle"),("CACTUS","Spiky desert plant"),
("CAKE","Birthday treat"),("CANDLE","Wax light"),("CASTLE","Royal fortress"),
("CHAIR","Seat"),("CHEESE","Pizza topping"),("CHERRY","Sundae topper"),
("CHESS","Board battle"),("CLOCK","Time teller"),("CLOUD","Sky puff"),
("COAST","Shore"),("COMET","Tailed traveler"),("CORAL","Reef builder"),
("CRAYON","Wax color stick"),("DANCE","Rhythm move"),("DESERT","Sandy expanse"),
("DICE","Cube rollers"),("DIVER","Deep explorer"),("DOOR","Room entry"),
("DRUM","Beat keeper"),("EAGLE","Soaring hunter"),("ENGINE","Motor"),
("FENCE","Yard border"),("FLAME","Fire tongue"),("FROST","Window ice"),
("GARAGE","Car bedroom"),("GARDEN","Flower plot"),("GHOST","Spooky spirit"),
("GLASS","Window pane"),("GLOVE","Hand warmer"),("GRAPE","Wine fruit"),
("HEART","Love symbol"),("HONEY","Bee gold"),("HORSE","Gallop animal"),
("HOTEL","Traveler lodging"),("IGLOO","Ice house"),("ISLAND","Ocean dot"),
("JACKET","Cool-day wear"),("JUNGLE","Dense wilds"),("KAYAK","Paddle craft"),
("KOALA","Eucalyptus muncher"),("LADDER","Climb aid"),("LAMP","Desk light"),
("LEMON","Sour citrus"),("LIGHT","Bulb output"),("LION","Jungle king"),
("MAGNET","Fridge sticker holder"),("MANGO","Tropical treat"),("MARBLE","Glass shooter"),
("MASK","Costume cover"),("MEDAL","Winner's prize"),("MIRROR","Reflection glass"),
("MOON","Night light"),("MOUNTAIN","Peak"),("MUSEUM","Artifact hall"),
("NAPKIN","Lap cloth"),("NIGHT","Day's opposite"),("NOVEL","Long story"),
("OCEAN","Vast water"),("ONION","Tearjerker veggie"),("ORANGE","Citrus color fruit"),
("ORCHID","Fancy bloom"),("OVEN","Baking box"),("PAINT","Wall color"),
("PANDA","Bamboo muncher"),("PAPER","Write sheet"),("PARROT","Talking bird"),
("PASTA","Italian dinner"),("PEACH","Fuzzy fruit"),("PEARL","Oyster gem"),
("PENCIL","Wooden writer"),("PHOTO","Snapshot"),("PIANO","Keyed instrument"),
("PILLOW","Head rest"),("PIRATE","Treasure hunter"),("PIZZA","Cheesy pie"),
("PLANT","Green grower"),("PLATE","Dinner disc"),("POCKET","Jean holder"),
("PORCH","House stoop"),("PUDDLE","Rain pool"),("PUPPY","Young dog"),
("QUILT","Patchwork blanket"),("RADIO","Airwave box"),("RAINBOW","Sky arc"),
("RIVER","Flowing water"),("ROBOT","Metal helper"),("ROCKET","Space launcher"),
("SADDLE","Horse seat"),("SANDWICH","Lunch stack"),("SATURN","Ringed planet"),
("SCARF","Neck warmer"),("SHELL","Beach find"),("SHOVEL","Dig tool"),
("SNAKE","Slithering reptile"),("SNOWMAN","Winter figure"),("SOCCER","Goal sport"),
("SPIDER","Eight-legged weaver"),("SPOON","Soup scoop"),("STAMP","Mail sticker"),
("STARFISH","Five-armed sea creature"),("STATUE","Stone figure"),("STORM","Wild weather"),
("STREAM","Babbling water"),("SUBWAY","Underground train"),("SUGAR","Sweet crystals"),
("SWING","Playground glider"),("SWORD","Knight's blade"),("TABLE","Dinner platform"),
("TACO","Folded feast"),("TIGER","Striped hunter"),("TOAST","Browned bread"),
("TORNADO","Twisting terror"),("TOWER","Tall structure"),("TRAIN","Rail rider"),
("TREASURE","Buried riches"),("TRUCK","Hauling vehicle"),("TRUMPET","Brass blaster"),
("TUNNEL","Underground passage"),("TURTLE","Slow shell-wearer"),("UMBRELLA","Rain shield"),
("UNICORN","Horned myth"),("VOLCANO","Lava mountain"),("WALLET","Cash keeper"),
("WATCH","Wrist timepiece"),("WATERFALL","Cliff cascade"),("WHALE","Giant swimmer"),
("WINDOW","Wall viewer"),("WIZARD","Spell caster"),("ZEBRA","Striped equine"),
# 5 letters
("AIRPLANE","Sky bus"),("ALARM","Wake-up ringer"),("ARCADE","Game hall"),
("ATLAS","Map book"),("BALLOON","Party floater"),("BANANA","Peel fruit"),
("BANJO","Twangy strings"),("BASKET","Hoop holder"),("BEACON","Signal light"),
("BEAVER","Dam builder"),("BICYCLE","Two-wheeler"),("BLANKET","Cozy cover"),
("BLIZZARD","Snowy blast"),("BREEZE","Gentle wind"),("BRIDGE","Span over water"),
("CAMEL","Desert humped walker"),("CAMERA","Photo taker"),("CANYON","Deep gorge"),
("CARPET","Floor fabric"),("CARROT","Orange veggie"),("CASTLE","Moat mansion"),
("CHALK","Blackboard writer"),("CHEETAH","Speedy cat"),("CHERRY","Pie fruit"),
("CHIME","Gentle bell"),("CIRCUS","Big-top show"),("CLOVER","Lucky leaf"),
("COBRA","Hooded snake"),("COMET","Icy sky visitor"),("COMPASS","Direction finder"),
("CORAL","Ocean garden"),("COUGAR","Mountain cat"),("CRANE","Construction lifter"),
("CRATER","Moon dent"),("CRAYON","Color stick"),("CRICKET","Chirping hopper"),
("DAGGER","Short blade"),("DAISY","Cheerful bloom"),("DELTA","River mouth"),
("DIARY","Secret keeper"),("DINGO","Wild Aussie dog"),("DIVING","Pool plunge"),
("DONUT","Glazed ring"),("DRAGON","Fire breather"),("EASEL","Artist stand"),
("EMBER","Glowing coal"),("FABLE","Moral story"),("FERRY","Harbor crosser"),
("FIDDLE","Folk violin"),("FLAMINGO","Pink wader"),("FOREST","Tree crowd"),
("FOSSIL","Ancient remains"),("FROSTY","Winter's nickname"),("GECKO","Wall-climbing lizard"),
("GEYSER","Erupting spring"),("GIRAFFE","Tall spotty browser"),("GLACIER","Ice river"),
("GLOBE","Round map"),("GOBLIN","Mischievous imp"),("GRAVITY","What goes up bringer-downer"),
("GUITAR","Six-string strummer"),("HARBOR","Ship haven"),("HATCHET","Small axe"),
("HEATER","Cold chaser"),("HELMET","Head guard"),("HERMIT","Crab or loner"),
("HIKING","Trail trekking"),("HIPPO","River horse"),("HONEYBEE","Pollen collector"),
("HURDLE","Track jumper"),("IGLOO","Snow dome"),("ISLAND","Castaway's home"),
("IVORY","Tusk material"),("JELLY","Wobbly spread"),("JOKER","Wild card"),
("JUNGLE","Canopy chaos"),("KARATE","Bare-hand art"),("KETCHUP","Fry dip"),
("KITTY","Young cat"),("KOALA","Tree-hugging marsupial"),("LADDER","Rung climber"),
("LAGOON","Shallow bay"),("LANTERN","Portable glow"),("LAPTOP","Portable computer"),
("LASER","Focused beam"),("LEMON","Zesty citrus"),("LLAMA","Andean pack animal"),
("LOCUST","Swarming hopper"),("LOGIC","Sound reasoning"),("LUGGAGE","Travel bags"),
("LUNAR","Moon-related"),("MAGIC","Sleight of hand"),("MAGNET","Attraction master"),
("MAMMOTH","Ice-age giant"),("MANTIS","Praying predator"),("MAPLE","Syrup tree"),
("MARBLE","Rolling glass ball"),("MEDAL","Podium prize"),("MELON","Summer fruit"),
("METEOR","Shooting star"),("MIRROR","Look who's there"),("MOBILE","Hanging art"),
("MONKEY","Barrel dweller"),("MOSQUE","Minaret house of worship"),("MOTEL","Roadside rest"),
("MOUNTAIN","Hiker's goal"),("MOUSE","Cheese nibbler"),("MUFFIN","Baked cup"),
("MUMMY","Wrapped ancient"),("MURAL","Wall art"),("NACHO","Cheesy chip"),
("NEBULA","Star nursery"),("NEWSPAPER","Daily read"),("NINJA","Shadow warrior"),
("OASIS","Desert watering hole"),("OCTOPUS","Eight-armed escape artist"),("OLIVE","Martini garnish"),
("ONION","Layered crybaby"),("OPERA","Grand singing drama"),("ORBIT","Satellite path"),
("ORCHARD","Fruit tree farm"),("OTTER","Playful river mammal"),("OXCART","Beast-drawn wagon"),
("OXYGEN","Breath of life"),("PADDLE","Canoe driver"),("PALACE","Royal residence"),
("PANDA","Bamboo-loving bear"),("PANEL","Flat section"),("PAPAYA","Tropical melon"),
("PARADE","Marching celebration"),("PARCHMENT","Ancient paper"),("PARROT","Mimicking bird"),
("PASTRY","Flaky treat"),("PATCH","Mended spot"),("PEBBLE","Tiny stone"),
("PELICAN","Pouch-beaked diver"),("PENGUIN","Tuxedo waddler"),("PETAL","Flower piece"),
("PHARAOH","Egyptian king"),("PHOTO","Captured moment"),("PIANO","Eighty-eight keys"),
("PICKLE","Briny cucumber"),("PICNIC","Outdoor feast"),("PILLOW","Dream support"),
("PIRATE","Arrrg Matey"),("PISTON","Engine pumper"),("PIZZA","Slice of heaven"),
("PLANK","Walk it, pirate"),("PLAZA","Open square"),("POCKET","Secret stash spot"),
("PODIUM","Winner's stand"),("POETRY","Rhyming art"),("POLAR","Arctic kind"),
("PONCHO","Rain cape"),("POPCORN","Movie muncher"),("PORCH","Evening sit spot"),
("POSTER","Wall decoration"),("POTATO","Spud"),("POULTRY","Farm birds"),
("PRAIRIE","Grassland sea"),("PRISM","Light splitter"),("PUPPET","String performer"),
("PUZZLE","Brain teaser"),("PYTHON","Big constrictor"),("QUARTZ","Crystal common"),
("QUEUE","Waiting line"),("QUILT","Stitched comfort"),("RABBIT","Hopping burrower"),
("RACCOON","Masked bandit"),("RADAR","Blip detector"),("RAFTING","Rapid rider"),
("RAINBOW","Colorful sky bow"),("RANCH","Cattle spread"),("RAVEN","Clever black bird"),
("RECIPE","Cook's guide"),("RELAY","Baton race"),("RHINO","Horned tank"),
("RIDDLE","Puzzling question"),("RIVER","Nature's highway"),("ROAST","Oven-browned meat"),
("ROBIN","Red-breasted singer"),("ROBOT","Beep-boop worker"),("RODEO","Bronco show"),
("ROOSTER","Dawn crower"),("ROUTE","Planned path"),("ROWBOAT","Oar-powered craft"),
("RULER","Straight measurer"),("SADDLE","Rider's seat"),("SAFARI","Wildlife expedition"),
("SALAD","Leafy bowl"),("SALMON","Upstream swimmer"),("SATELLITE","Orbiting observer"),
("SAUCER","Cup's companion"),("SAXOPHONE","Jazzy brass"),("SCARF","Bundled neck"),
("SCHOOL","Learning place"),("SCOOTER","Kick-and-glide ride"),("SCUBA","Deep dive gear"),
("SEAGULL","Beach scavenger"),("SEASHELL","Shore treasure"),("SEASON","Quarter of the year"),
("SEEDLING","Baby plant"),("SENTRY","Watchful guard"),("SERVER","Data waiter"),
("SHADOW","Sun blocker"),("SHARK","Ocean's jaws"),("SHIELD","Defender's plate"),
("SHOVEL","Hole digger"),("SHRIMP","Tiny cocktail"),("SIESTA","Midday snooze"),
("SIGNAL","Attention getter"),("SILVER","Second-place metal"),("SINGER","Melody maker"),
("SKATING","Blade gliding"),("SKETCH","Rough drawing"),("SKIER","Slope slider"),
("SKULL","Head bone"),("SKUNK","Stinky sprayer"),("SLEDGE","Heavy hammer"),
("SLEEPER","Train berth"),("SLOTH","Slowpoke mammal"),("SMOKE","Fire's breath"),
("SNAIL","Slow shell carrier"),("SNAKE","Legless slitherer"),("SNORKEL","Surface breather"),
("SNOWBOARD","Winter shredder"),("SOCCER","World's game"),("SODA","Fizzy drink"),
("SOLAR","Sun-powered"),("SONAR","Underwater ears"),("SOUVENIR","Trip keepsake"),
("SPARROW","Common chirper"),("SPHINX","Riddling statue"),("SPIDER","Web spinner"),
("SPONGE","Soak-up square"),("SPOON","Cereal lifter"),("SPORTS","Game time"),
("SPRING","Bounce season"),("SQUID","Ten-armed swimmer"),("STABLE","Horse home"),
("STADIUM","Fan arena"),("STAGE","Performer platform"),("STAIRS","Step climber"),
("STAPLER","Paper pincher"),("STARTLE","Surprise jump"),("STATUE","Sculpted figure"),
("STEAM","Boiling breath"),("STEEL","Strong alloy"),("STENCIL","Pattern tracer"),
("STEREO","Surround sound"),("STETHOSCOPE","Heartbeat listener"),("STICKER","Peel-and-place"),
("STINGER","Bee's business end"),("STITCH","Sewing loop"),("STONE","Rock solid"),
("STOOL","Backless seat"),("STORAGE","Keep-it place"),("STORM","Tempest"),
("STOVE","Cooktop"),("STREAM","Gentle flow"),("STREET","Paved path"),
("STRETCH","Limber move"),("STRIPES","Tiger's marks"),("STROLLER","Baby wheels"),
("STUDENT","Learner"),("STUDIO","Creative space"),("STUMP","Tree leftover"),
("SUBMARINE","Deep diver"),("SUGAR","Sweet tooth fuel"),("SUNDAE","Scoop celebration"),
("SUNFLOWER","Tall yellow bloom"),("SUNRISE","Daybreak"),("SUNSET","Dusk show"),
("SUPERHERO","Cape crusader"),("SURFER","Wave rider"),("SUSHI","Raw artistry"),
("SWAMP","Mucky wetland"),("SWAN","Graceful glider"),("SWEATER","Cozy knit"),
("SWIMMING","Pool activity"),("SWINGSET","Playground classic"),("SWORD","Blade of legend"),
# 6 letters (sample)
("ACROBAT","Flipping performer"),("ACTION","Movie excitement"),("ADOBE","Sun-dried brick"),
("AGATE","Banded gemstone"),("ALMOND","Nutty snack"),("AMBER","Fossilized resin"),
("ANCHOR","Harbor holder"),("ANGEL","Halo wearer"),("ANTHEM","Song of pride"),
("APRICOT","Golden stone fruit"),("ARCHER","Bow master"),("ARMORY","Weapon store"),
("ARROW","Straight shooter"),("ASTRONAUT","Space traveler"),("ATTIC","Top-floor storage"),
("AUTHOR","Book writer"),("AUTUMN","Falling-leaf season"),("AVALANCHE","Snowy slide"),
("AWNING","Shade flap"),("BADGER","Burrowing mammal"),("BAGEL","Hole-y breakfast"),
("BALCONY","Railing outlook"),("BALLOON","Hot-air floater"),("BANANA","Monkey's favorite"),
("BANNER","Waving sign"),("BARREL","Wooden cask"),("BASKET","Woven carrier"),
("BATTERY","Power cell"),("BEACON","Guiding light"),("BEAVER","Toothy engineer"),
("BEETLE","Armored bug"),("BELUGA","White whale"),("BICYCLE","Pedal pusher"),
("BISHOP","Diagonal mover"),("BITTER","Unsweet taste"),("BLANKET","Warm cover"),
("BLAZER","Sporty jacket"),("BLENDER","Smoothie maker"),("BLIZZARD","Whiteout"),
("BLOSSOM","Flower burst"),("BONFIRE","Big blaze"),("BONNET","Old-fashioned hat"),
("BOOKLET","Small book"),("BORDER","Boundary line"),("BOTTLE","Drink holder"),
("BOULDER","Big rock"),("BOUQUET","Flower bunch"),("BOWLING","Pin toppler"),
("BRANCH","Tree arm"),("BRANDY","Aged spirit"),("BRASS","Trumpet metal"),
("BREEZE","Soft wind"),("BRICK","Mason's block"),("BRIDAL","Wedding-related"),
("BRIDGE","Gap crosser"),("BRONZE","Third-place metal"),("BUBBLE","Soapy sphere"),
("BUCKET","Water pail"),("BUDGET","Spending plan"),("BUFFALO","Plains grazer"),
("BUILDER","Construction pro"),("BUNGEE","Cord jumper"),("BUNKER","Golf sand trap"),
("BURGER","Grilled patty"),("BURROW","Underground home"),("BUTTER","Toast spread"),
("BUTTON","Shirt fastener"),("CABIN","Woods retreat"),("CABLE","Thick wire"),
("CACTUS","Prickly survivor"),("CADDIE","Golf helper"),("CAMERA","Lens box"),
("CAMPUS","College grounds"),("CANARY","Yellow songbird"),("CANDLE","Flickering light"),
("CANOES","Paddled boats"),("CANYON","River-carved deep"),("CARBON","Diamond element"),
("CARPET","Rug"),("CARROT","Bunny's favorite"),("CARTON","Milk box"),
("CARVE","Whittle"),("CASTLE","King's home"),("CATTLE","Moo herd"),
("CAVERN","Big cave"),("CELERY","Crunchy stalk"),("CELLAR","Underground storage"),
("CEREAL","Morning bowl"),("CHAIN","Linked metal"),("CHALET","Alpine lodge"),
("CHALK","Classroom writer"),("CHAPEL","Small church"),("CHARGE","Power up"),
("CHARIOT","Horse-drawn racer"),("CHEESE","Say it for photos"),("CHERRY","Red pie fruit"),
("CHESS","Checkmate game"),("CHICKEN","Clucking bird"),("CHIMNEY","Smoke stack"),
("CHISEL","Carving tool"),("CIRCLE","Round shape"),("CIRCUS","Clown show"),
("CITADEL","Fortress"),("PLANET","Orbiting world"),
]

# ------------------------------------------------------- layout algorithm
COLS, ROWS = 8, 12
ACROSS, DOWN = "across", "down"

# Across words need a clue cell to their left, so cap length at COLS-1.
# Drop duplicate words (keep first clue) so no word is placed twice.
_seen = set()
_deduped = []
for _w, _c in WORDS:
    if _w not in _seen:
        _seen.add(_w)
        _deduped.append((_w, _c))
WORDS = [(w, c) for (w, c) in _deduped if len(w) <= COLS - 1]

def can_place(grid, word, r, c, d):
    dr, dc = (0, 1) if d == ACROSS else (1, 0)
    if d == ACROSS and c == 0:
        return None
    if d == DOWN and r == 0:
        return None
    n = len(word)
    cells = []
    crossings = 0
    for i, ch in enumerate(word):
        rr, cc = r + dr * i, c + dc * i
        if not (0 <= rr < ROWS and 0 <= cc < COLS):
            return None
        g = grid[rr][cc]
        if g == "#":
            return None
        if g is not None and g != ch:
            return None
        if g == ch:
            crossings += 1
        cells.append((rr, cc))
    # clue cell must be free of letters
    qr, qc = (r, c - 1) if d == ACROSS else (r - 1, c)
    q = grid[qr][qc]
    if q is not None and q != "#":
        return None
    # no accidental touching: perpendicular neighbors of fresh cells must be empty
    for (rr, cc) in cells:
        if grid[rr][cc] is not None:
            continue
        if d == ACROSS:
            for nr, nc in ((rr - 1, cc), (rr + 1, cc)):
                if 0 <= nr < ROWS and grid[nr][nc] not in (None, "#"):
                    return None
        else:
            for nr, nc in ((rr, cc - 1), (rr, cc + 1)):
                if 0 <= nc < COLS and grid[nr][nc] not in (None, "#"):
                    return None
    # cells before start / after end must not be letters
    br, bc = r - dr, c - dc
    if 0 <= br < ROWS and 0 <= bc < COLS and grid[br][bc] not in (None, "#"):
        return None
    er, ec = r + dr * n, c + dc * n
    if 0 <= er < ROWS and 0 <= ec < COLS and grid[er][ec] not in (None, "#"):
        return None
    return crossings

def do_place(grid, word, r, c, d):
    dr, dc = (0, 1) if d == ACROSS else (1, 0)
    for i, ch in enumerate(word):
        grid[r + dr * i][c + dc * i] = ch
    qr, qc = (r, c - 1) if d == ACROSS else (r - 1, c)
    grid[qr][qc] = "#"

def build_once(words):
    grid = [[None] * COLS for _ in range(ROWS)]
    placed = []  # (word, clue, r, c, d)
    pool = words[:]
    random.shuffle(pool)
    # seed: a long word across the middle
    seed = max(pool, key=lambda w: len(w[0]))
    pool.remove(seed)
    w, clue = seed
    r0 = ROWS // 2
    c0 = max(1, (COLS - len(w)) // 2)
    if can_place(grid, w, r0, c0, ACROSS) is not None:
        do_place(grid, w, r0, c0, ACROSS)
        placed.append((w, clue, r0, c0, ACROSS))
    # greedy passes
    for _pass in range(6):
        random.shuffle(pool)
        progress = False
        for cand in pool[:]:
            w, clue = cand
            best = None  # (crossings, r, c, d)
            for d in (ACROSS, DOWN):
                # try crossing each existing letter cell
                tries = []
                for (pw, _, pr, pc, pd) in placed:
                    pdr, pdc = (0, 1) if pd == ACROSS else (1, 0)
                    for j, pch in enumerate(pw):
                        jr, jc = pr + pdr * j, pc + pdc * j
                        for i, ch in enumerate(w):
                            if ch != pch:
                                continue
                            dr, dc = (0, 1) if d == ACROSS else (1, 0)
                            if d == pd:
                                continue  # must cross, not overlap parallel
                            rr, cc = jr - dr * i, jc - dc * i
                            tries.append((rr, cc))
                for (rr, cc) in tries:
                    x = can_place(grid, w, rr, cc, d)
                    if x is not None and x >= 1:
                        if best is None or x > best[0]:
                            best = (x, rr, cc, d)
            if best:
                _, rr, cc, d = best
                do_place(grid, w, rr, cc, d)
                placed.append((w, clue, rr, cc, d))
                pool.remove(cand)
                progress = True
        if not progress:
            break
    return grid, placed

def score_layout(grid, placed):
    letters = sum(1 for row in grid for g in row if g not in (None, "#"))
    return (len(placed), letters)

def finalize(grid, placed, pid, title):
    # build clue cells
    clues = {}  # (r,c) -> {"a": clue or None, "d": clue or None}
    for (w, clue, r, c, d) in placed:
        qr, qc = (r, c - 1) if d == ACROSS else (r - 1, c)
        e = clues.setdefault((qr, qc), {"a": None, "d": None})
        e["a" if d == ACROSS else "d"] = clue
    cells = []
    letter_positions = []
    for r in range(ROWS):
        for c in range(COLS):
            g = grid[r][c]
            if g == "#":
                e = clues.get((r, c), {"a": None, "d": None})
                cells.append({"k": "c", "ca": e["a"], "cd": e["d"]})
            elif g is None:
                cells.append({"k": "x"})
            else:
                cells.append({"k": "l", "s": g})
                letter_positions.append(len(cells) - 1)
    # blue bonus squares: 3 random letter cells
    for idx in random.sample(letter_positions, min(3, len(letter_positions))):
        cells[idx]["b"] = True
    words = [{"a": w, "r": r, "c": c, "d": d} for (w, _, r, c, d) in placed]
    return {"id": pid, "title": title, "cols": COLS, "rows": ROWS,
            "cells": cells, "words": words}

TITLES = ["Warm-Up", "First Serve", "Rally Time", "Smash Hit", "Net Play",
          "Top Spin", "Match Point", "Grand Slam", "Fast Break", "Full Court",
          "Overtime", "Championship"]

def main():
    outdir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "..", "SWISH", "Resources", "puzzles")
    os.makedirs(outdir, exist_ok=True)
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    for i in range(count):
        best = None
        best_key = (-1, -1)
        for _ in range(120):
            grid, placed = build_once(WORDS)
            key = score_layout(grid, placed)
            if key > best_key:
                best_key = key
                best = (grid, placed)
        grid, placed = best
        print(f"puzzle {i+1}: {len(placed)} words, key={best_key}")
        # ascii preview
        for r in range(ROWS):
            print("".join("#" if g == "#" else (g if g else ".") for g in grid[r]))
        print()
        pid = f"swish-{i+1:02d}"
        puzzle = finalize(grid, placed, pid, TITLES[i % len(TITLES)])
        with open(os.path.join(outdir, f"puzzle-{i+1:02d}.json"), "w") as f:
            json.dump(puzzle, f)

if __name__ == "__main__":
    main()
