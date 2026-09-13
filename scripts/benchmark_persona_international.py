#!/usr/bin/env python3
"""
ThoughtEcho Thoughter AI 第四模拟用户（Alex Morgan·国际英语用户 / 跨国独立工程师与作家）高拟真基准评测引擎
涵盖：
1. 经典英文文学与哲学摘录 (Classic English Literature & Philosophy Excerpts)
2. 摇滚/民谣歌词与经典电影台词摘录 (Western Music Lyrics & Cinema Quotes)
3. 跨国工程开发与日常随笔 (Daily Life & Engineering Reflections) - 署名多词英文 "Alex Morgan"
4. 全球旅行与地理风物行记 (Global Travel Notes & Field Journals)
5. 技术重构与徒步出行清单 (Checklists & Engineering Todos)

核心验证：
- 长期记忆系统在纯英文多词笔名（含空格："Alex Morgan"）下的抽取保留与归属辨析能力。
- 验证 cleanAlias 不破坏词间空格，统计推断准确识别用户别名并将带多词署名的原创随笔准确收归 Voice 原创池。
- 验证 Taste 与 Voice 采样隔离纯度及英文对话下的文风、品味与连续性感知。
"""

import os
import sys
import json
import time
import re
import urllib.request
import urllib.error
from datetime import datetime, timedelta

def load_env():
    env_file = os.path.expanduser("~/.thoughtecho-dev/agent-test.env")
    env = {}
    if os.path.exists(env_file):
        with open(env_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip()
    return env

ENV = load_env()
BASE_URL = os.getenv("TE_TEST_BASE_URL", "https://generativelanguage.googleapis.com/v1beta/openai")
if not BASE_URL.startswith("https://"):
    raise ValueError(f"Insecure TE_TEST_BASE_URL rejected: {BASE_URL}. HTTPS is required.")
API_KEY = os.getenv("GEMINI_API_KEY", os.getenv("GEMINI_TEST_API_KEY", ENV.get("GEMINI_API_KEY", "")))

PREFERRED_MODELS = [
    os.getenv("TE_PROBE_MODEL", "gemini-3.8-flash"),
    "gemini-3.5-flash-lite",
    "gemini-3.6-flash",
]

# -----------------------------------------------------------------------------
# 高保真拟真笔记数据集生成（Alex Morgan·国际英语用户）
# -----------------------------------------------------------------------------
def generate_international_notes():
    now = datetime.now()
    def days_ago(d, hour=11):
        t = now - timedelta(days=d)
        return t.replace(hour=hour, minute=15, second=0).strftime("%Y-%m-%d %H:%M:%S")

    notes = []

    # =========================================================================
    # 类别 1: 日常生活与工程随笔 (Daily Life & Tech Ramblings, 20 条) - Ground Truth: original
    # =========================================================================
    daily_data = [
        ("The ritual of morning espresso: 18 grams of Ethiopian Yirgacheffe, ground fine, extracted at 9 bars in exactly 27 seconds. Watching the caramel-colored crema swirl in the porcelain cup is the only meditation I need before wrestling with compiler errors. — Alex Morgan", "Alex Morgan", "daily notes", "clear", "16°C", 1),
        ("Debugging asynchronous Rust code at 2 AM in a quiet corner of the cafe. The borrow checker is uncompromising, almost cruel, but when the lifetimes finally align and the code compiles cleanly, the sense of architectural serenity is unmatched. — Alex Morgan's journal", "Alex Morgan", "journal", "cloudy", "14°C", 3),
        ("Walking through the dense fog in the Presidio. Eucalyptus trees loom like silent giants against the grey sky, dripping moisture onto the pine needles below. The Golden Gate Bridge is just a red rust tower piercing through rolling clouds. It's good to step away from screens and breathe damp air.", None, None, "foggy", "13°C", 5),
        ("Spent three hours browsing dusty second-hand record stores in Shibuya. Found a pristine 1977 pressing of Steely Dan's Aja. There's a tangible warmth in analog vinyl grooves that lossless digital streaming somehow smooths over. You have to handle it with care, flip the disc, and truly listen. — Alex Morgan", "Alex Morgan", "notes", "rainy", "17°C", 7),
        ("Refactoring a monolithic state container into decentralized event-driven actors. It feels less like writing code and more like pruning a bonsai tree: removing tangled branches so that light and air can pass through the core structure.", None, None, "clear", "19°C", 9),
        ("Rainy Sunday afternoon in London. Sitting by the bow window with a steaming pot of Earl Grey tea, watching red double-decker buses glide over glistening black asphalt. A rare quiet afternoon without Slack notifications or production alerts. — Alex Morgan", "Alex Morgan", "memo", "rainy", "11°C", 11),
        ("Late night commute on the BART train across the San Francisco Bay. The city skyline looks like an illuminated circuit board reflected on pitch-black water. Headphones playing Brian Eno's ambient synth, everyone staring into their handheld rectangles, each carrying a private universe. — Alex Morgan", "Alex Morgan", "journal", "clear", "12°C", 13),
        ("There is an understated beauty in plain text and markdown. No hidden proprietary schemas, no cloud vendor lock-in, just human-readable UTF-8 bytes that will still be intelligible fifty years from now. Simplicity is the ultimate hedge against bit rot.", None, None, "cloudy", "18°C", 15),
        ("Visited the local farmers market on Saturday morning. Bought fresh sourdough, dark wildflower honey, and heirloom tomatoes smelling of sun and soil. Cooked a simple pasta al pomodoro for dinner. Good software, like good cooking, comes down to high-grade ingredients and restraint. — Alex Morgan", "Alex Morgan", "daily notes", "clear", "21°C", 17),
        ("Wrestling with distributed consensus and network partitions. CAP theorem isn't just an abstract theoretical lemma; it's the physics of our digital reality. You cannot cheat latency, and you cannot fake consistency without paying in availability.", None, None, "clear", "15°C", 19),
        ("Sitting on the wooden bench at Crissy Field, watching container ships slowly glide beneath the bridge toward the open Pacific. The wind carries the sharp sting of salt and seaweed. Sometimes the mind needs horizons wider than a 27-inch 4K monitor. — Alex Morgan", "Alex Morgan", None, "windy", "14°C", 21),
        ("Swapped out the mechanical keyboard switches today for tactile lubed Holy Pandas. The thock sound on the brass plate feels immensely satisfying, like typewriter keys hammering on heavy parchment. Tactile feedback transforms writing from a chore into a physical pleasure.", None, None, "clear", "20°C", 23),
        ("Woke up early and caught the first light over Twin Peaks. The entire bay basin was submerged under a thick blanket of marine fog, leaving only the tallest skyscraper spires floating above like islands in an ethereal white ocean. Breathtaking. — Alex Morgan", "Alex Morgan", "notes", "clear", "10°C", 25),
        ("Writing documentation is often the purest test of design. If an API is difficult to explain in two concise sentences, the flaw is never in the documentation—it is buried deep in the abstraction boundary itself. — Alex Morgan's dev notes", "Alex Morgan", "dev notes", "cloudy", "17°C", 27),
        ("Cleaned out the home workbench. Oiled the Japanese woodworking chisels, organized hex keys, swept cedar shavings off the floor. Craftsmanship is unified whether you are cutting mortise-and-tenon joints in oak or designing clean interface seams in Dart.", None, None, "clear", "18°C", 29),
        ("Late afternoon thunderstorm in Austin. Sheet lightning dancing across indigo clouds while thunder rattles the windowpanes. Stepped out onto the porch to inhale that intoxicating ozone and petrichor smell. Nature reminding us who's truly in charge. — Alex Morgan", "Alex Morgan", "journal", "stormy", "22°C", 31),
        ("Reflecting on software longevity. Most modern frameworks age like fresh milk, obsolete within three seasons. The Unix philosophy, C stdlib, and SQLite age like wine. Choose dependencies that have survived at least two hype cycles.", None, None, "clear", "16°C", 33),
        ("Cycling across the Golden Gate toward Marin Headlands. That relentless three-mile uphill grind burns the thighs, but cresting Hawk Hill with the Pacific on one side and the bay on the other is pure euphoria. — Alex Morgan", "Alex Morgan", "notes", "windy", "15°C", 35),
        ("Spent Friday evening sketching user flows on dotted Rhodia notebooks with an archival fountain pen. Nib scratching softly on cotton paper. Digital canvases give you infinite undo; analog ink forces commitment and clarity of thought before the pen ever touches paper. — Alex Morgan", "Alex Morgan", "memo", "clear", "19°C", 37),
        ("Midnight thoughts: we spend so much energy optimizing latency by ten milliseconds, yet waste whole hours on trivial distractions. The real performance bottleneck of our lives is rarely computational; it is intentionality.", None, None, "clear", "13°C", 39),
    ]

    for i, (content, author, work, weather, temp, d) in enumerate(daily_data, 1):
        notes.append({
            "id": f"daily-{i:02d}",
            "content": content,
            "date": days_ago(d),
            "source_author": author or "",
            "source_work": work or "",
            "tags": ["Life", "Engineering", "Reflections"],
            "weather": weather,
            "day_period": "night" if i % 2 == 0 else "morning",
            "location": "San Francisco",
            "temperature": temp,
            "favorite": i in [1, 2, 6, 7, 14],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 2: 经典文学与哲学摘录 (Classic Excerpts, 15 条) - Ground Truth: excerpt
    # =========================================================================
    classic_data = [
        ("War is peace. Freedom is slavery. Ignorance is strength. In the end the Party would announce that two and two made five, and you would have to believe it.", "George Orwell", "1984", ["Literature", "Dystopia", "Classics"]),
        ("Man is not made for defeat. A man can be destroyed but not defeated. Everything about him was old except his eyes and they were the same color as the sea and were cheerful and undefeated.", "Ernest Hemingway", "The Old Man and the Sea", ["Literature", "Courage", "Sea"]),
        ("If you are lucky enough to have lived in Paris as a young man, then wherever you go for the rest of your life, it stays with you, for Paris is a moveable feast.", "Ernest Hemingway", "A Moveable Feast", ["Memoir", "Paris", "Youth"]),
        ("A woman must have money and a room of her own if she is to write fiction. Life is not a series of gig lamps symmetrically arranged; life is a luminous halo, a semi-transparent envelope surrounding us.", "Virginia Woolf", "A Room of One's Own", ["Essay", "Feminism", "Writing"]),
        ("To the Lighthouse: What is the meaning of life? That was all—a simple question that tended to close in on one with years. The great revelation had never come. The great revelation perhaps never did come.", "Virginia Woolf", "To the Lighthouse", ["Modernism", "Philosophy"]),
        ("The books that the world calls immoral are books that show the world its own shame. To live is the rarest thing in the world. Most people exist, that is all.", "Oscar Wilde", "The Picture of Dorian Gray", ["Classics", "Aesthetics"]),
        ("So we beat on, boats against the current, borne back ceaselessly into the past. He looked at her the way all women want to be looked at by a man.", "F. Scott Fitzgerald", "The Great Gatsby", ["Literature", "Nostalgia"]),
        ("You have power over your mind - not outside events. Realize this, and you will find strength. The soul becomes dyed with the color of its thoughts.", "Marcus Aurelius", "Meditations", ["Stoicism", "Philosophy", "Wisdom"]),
        ("The happiness of your life depends upon the quality of your thoughts: therefore, guard accordingly, and take care that you entertain no notions unsuitable to virtue and reasonable nature.", "Marcus Aurelius", "Meditations", ["Stoicism", "Mindfulness"]),
        ("In the midst of winter, I found there was, within me, an invincible summer. And that makes me happy. For it says that no matter how hard the world pushes against me, there is something stronger inside.", "Albert Camus", "Return to Tipasa", ["Existentialism", "Resilience"]),
        ("There is only one really serious philosophical problem, and that is suicide. Deciding whether or not life is worth living is to answer the fundamental question in philosophy.", "Albert Camus", "The Myth of Sisyphus", ["Philosophy", "Absurdism"]),
        ("Whoso would be a man must be a nonconformist. He who would gather immortal palms must not be hindered by the name of goodness, but must explore if it be goodness. Nothing is at last sacred but the integrity of your own mind.", "Ralph Waldo Emerson", "Self-Reliance", ["Transcendentalism", "Autonomy"]),
        ("I went to the woods because I wished to live deliberately, to front only the essential facts of life, and see if I could not learn what it had to teach, and not, when I came to die, discover that I had not lived.", "Henry David Thoreau", "Walden", ["Nature", "Simplicity"]),
        ("Two roads diverged in a wood, and I—I took the one less traveled by, and that has made all the difference.", "Robert Frost", "The Road Not Taken", ["Poetry", "Choices"]),
        ("It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness, it was the epoch of belief, it was the epoch of incredulity.", "Charles Dickens", "A Tale of Two Cities", ["Classics", "History"]),
    ]

    for i, (quote, author, work, tags) in enumerate(classic_data, 1):
        notes.append({
            "id": f"classic-{i:02d}",
            "content": quote,
            "date": days_ago(i * 3 + 1),
            "source_author": author,
            "source_work": work,
            "tags": tags,
            "weather": "clear",
            "day_period": "night",
            "location": "Library Study",
            "temperature": "19°C",
            "favorite": i in [1, 2, 8, 10, 13],
            "type_ground_truth": "excerpt"
        })

    # =========================================================================
    # 类别 3: 摇滚民谣与电影台词摘录 (Music & Cinema, 15 条) - Ground Truth: excerpt
    # =========================================================================
    media_data = [
        ("How many roads must a man walk down, before you call him a man? The answer, my friend, is blowin' in the wind, the answer is blowin' in the wind.", "Bob Dylan", "Blowin' in the Wind", ["Folk", "Bob Dylan", "Music"]),
        ("How does it feel, how does it feel? To be on your own, with no direction home, like a complete unknown, like a rolling stone?", "Bob Dylan", "Like a Rolling Stone", ["Rock", "Dylan", "Classics"]),
        ("How I wish, how I wish you were here. We're just two lost souls swimming in a fish bowl, year after year, running over the same old ground. What have we found? The same old fears.", "Pink Floyd", "Wish You Were Here", ["Rock", "Pink Floyd", "Poignant"]),
        ("Ticking away the moments that make up a dull day. Fritter and waste the hours in an offhand way. Kicking around on a piece of ground in your hometown, waiting for someone or something to show you the way.", "Pink Floyd", "Time", ["Progressive Rock", "Time", "Existential"]),
        ("Ground Control to Major Tom. Take your protein pills and put your helmet on. Ground Control to Major Tom, commencing countdown, engines on.", "David Bowie", "Space Oddity", ["Bowie", "Space", "Art Rock"]),
        ("There are places I'll remember, all my life, though some have changed. Some forever, not for better, some have gone and some remain. All these places had their moments.", "The Beatles", "In My Life", ["The Beatles", "Nostalgia"]),
        ("Karma police, arrest this man, he talks in maths, he buzzes like a fridge, he's like a detuned radio. For a minute there, I lost myself.", "Radiohead", "Karma Police", ["Alternative", "Radiohead", "Modern"]),
        ("I've seen things you people wouldn't believe. Attack ships on fire off the shoulder of Orion. I watched C-beams glitter in the dark near the Tannhäuser Gate. All those moments will be lost in time, like tears in rain. Time to die.", "Ridley Scott", "Blade Runner", ["Cinema", "Sci-Fi", "Soliloquy"]),
        ("Do not go gentle into that good night. Rage, rage against the dying of the light. Love is the one thing we're capable of perceiving that transcends dimensions of time and space.", "Christopher Nolan", "Interstellar", ["Cinema", "Sci-Fi", "Love"]),
        ("O Captain! My Captain! our fearful trip is done. Carpe diem. Seize the day, boys. Make your lives extraordinary.", "Peter Weir", "Dead Poets Society", ["Cinema", "Inspiration", "Literature"]),
        ("I guess it comes down to a simple choice, really. Get busy living, or get busy dying. Hope is a good thing, maybe the best of things, and no good thing ever dies.", "Frank Darabont", "The Shawshank Redemption", ["Cinema", "Hope", "Classics"]),
        ("May the Force be with you. Fear is the path to the dark side. Fear leads to anger, anger leads to hate, hate leads to suffering.", "George Lucas", "Star Wars", ["Cinema", "Wisdom"]),
        ("Hello darkness, my old friend. I've come to talk with you again. Because a vision softly creeping, left its seeds while I was sleeping.", "Simon & Garfunkel", "The Sound of Silence", ["Folk", "Melancholy"]),
        ("Some people feel the rain. Others just get wet.", "Bob Marley", "Quotes", ["Reggae", "Life"]),
        ("The only people for me are the mad ones, the ones who are mad to live, mad to talk, mad to be saved, desirous of everything at the same time.", "Jack Kerouac", "On the Road", ["Beat Generation", "Literature"]),
    ]

    for i, (quote, author, work, tags) in enumerate(media_data, 1):
        notes.append({
            "id": f"media-{i:02d}",
            "content": quote,
            "date": days_ago(i * 2 + 2),
            "source_author": author,
            "source_work": work,
            "tags": tags,
            "weather": "cloudy",
            "day_period": "evening",
            "location": "Listening Room",
            "temperature": "18°C",
            "favorite": i in [1, 3, 8, 9, 11],
            "type_ground_truth": "excerpt"
        })

    # =========================================================================
    # 类别 4: 全球旅行与田野风物 (Global Travel & Field Journals, 15 条) - Ground Truth: original
    # =========================================================================
    travel_data = [
        ("Hiking the trail from Grindelwald to Kleine Scheidegg. The towering north face of the Eiger loomed over us like a colossal wall of black limestone and hanging seracs. Cowbells chimed rhythmically across alpine meadows dotted with yellow wildflowers. The sheer scale makes you acutely aware of human fragility. — Alex Morgan", "Grindelwald, Swiss Alps", "clear", "8°C", 4, "Alex Morgan", "travel journal"),
        ("6:00 AM at Fushimi Inari in Kyoto before the tour buses arrive. Walking beneath thousands of vermilion torii gates winding up the sacred mountain. Mist drifting through cedar groves, damp stone lanterns coated in emerald moss, the distant chime of a shrine bell. Absolute stillness. — Alex Morgan", "Kyoto Fushimi Inari", "cloudy", "15°C", 8, "Alex Morgan", "travel notes"),
        ("Standing before Botticelli's The Birth of Venus in the Uffizi Gallery. No digital photograph can prepare you for the luminosity of the egg tempera on linen, the delicate gold leaf woven through Venus's flowing tresses, or the serene melancholy in her gaze. Art that outlives empires. — Alex Morgan", "Florence Uffizi Gallery", "clear", "22°C", 12, "Alex Morgan", None),
        ("Cobblestones of Edinburgh Old Town under a gentle Scottish drizzle. The blackened stone tenements of the Royal Mile stand stacked like Gothic bookends against the slate sky. Stepped into an underground pub, warmed my hands by the peat fire, and sipped a dram of smoky Islay single malt. — Alex Morgan", "Edinburgh Royal Mile", "rainy", "9°C", 16, "Alex Morgan", "travel journal"),
        ("Road trip along California Highway 1 through Big Sur. The highway hugs sheer granite cliffs dropping a thousand feet straight into the crashing Pacific surf. Bixby Bridge arched gracefully over the canyon, fog rolling over the redwood ridges. Open windows, cold salt wind, pure freedom. — Alex Morgan", "Big Sur, California", "windy", "16°C", 20, "Alex Morgan", None),
        ("Lost in the labyrinthine alleys of the Marrakech Medina. The air is thick with aromas of roasted cumin, cedar shavings, tanning leather, and freshly brewed mint tea poured from high spouts into gold-rimmed glasses. Sensory overload in the best possible way. — Alex Morgan", "Marrakech Medina", "clear", "26°C", 24, "Alex Morgan", "field notes"),
        ("Riding the overnight sleeper train from Vienna to Venice. Waking up as the train crossed the causeway over the Venetian lagoon at dawn. Water gleaming like liquid pewter under pink morning light, pale marble palazzos rising straight out of the Adriatic. Magic made real. — Alex Morgan", "Venice Santa Lucia", "clear", "14°C", 28, "Alex Morgan", None),
        ("Watching the aurora borealis dancing over Tromsø in northern Norway. Curtains of electric green and violet rippling across a sky strewn with Arctic stars. The cold was biting at minus fifteen degrees, but nobody moved. We stood on the snow in reverent silence. — Alex Morgan", "Tromsø, Norway", "clear", "-15°C", 32, "Alex Morgan", "travel notes"),
        ("Exploring the ancient cliff dwellings at Mesa Verde. Ancestral Puebloans built entire stone villages sheltered beneath sandstone canyon overhangs eight hundred years ago. Looking at the hand-and-toe trails pecked into the rock face, you feel the profound tenacity of human survival. — Alex Morgan", "Mesa Verde National Park", "clear", "20°C", 36, "Alex Morgan", "travel journal"),
        ("Sunset at the temple of Poseidon at Cape Sounion. The ruined white marble Doric columns stand on a headland jutting dramatically into the Aegean Sea. Lord Byron carved his name into the stone here in 1810. As the sun dipped beneath the waves, the sea turned the color of dark wine. — Alex Morgan", "Cape Sounion, Greece", "clear", "23°C", 40, "Alex Morgan", None),
        ("Morning coffee at a sidewalk cafe in Saint-Germain-des-Prés, Paris. Crisp buttery croissants, café crème, and watching stylish Parisians walk briskly past with baguettes tucked under their coats. Hemingway was right; Paris is a rhythm you absorb into your blood.", "Paris Saint-Germain", "cloudy", "17°C", 44, None, None),
        ("Hiking through the towering bamboo forest of Arashiyama. When the wind picks up, the giant green culms knock together with a hollow, resonant clatter that sounds like natural percussion. Looking up, the canopy filters sunlight into a shimmering jade glow. — Alex Morgan", "Kyoto Arashiyama", "clear", "19°C", 48, "Alex Morgan", "travel notes"),
        ("Paddling a sea kayak through Milford Sound in New Zealand. Waterfalls plunging hundreds of meters directly from sheer rainforest cliffs into ink-dark glacial water. Bottlenose dolphins broke the surface alongside my bow, their smooth grey backs gleaming in the spray. Unspoiled paradise. — Alex Morgan", "Milford Sound, NZ", "rainy", "12°C", 52, "Alex Morgan", "field notes"),
        ("Strolling through Lisbon's Alfama neighborhood. Pastels of faded yellow and terracotta tile roofs tumbling down toward the blue Tagus river. Fado guitar echoing from an open tavern doorway, the melancholic melody capturing that untranslatable Portuguese saudade. — Alex Morgan", "Lisbon Alfama", "clear", "21°C", 56, "Alex Morgan", None),
        ("Climbing the red sandstone dunes of Sossusvlei in Namibia at sunrise. The wind sculpted razor-sharp ridges dividing blazing orange sand in the sun from deep purple shadows on the lee side. Dead camelthorn tree skeletons preserved for nine centuries in the white clay pan. Timeless. — Alex Morgan", "Sossusvlei, Namibia", "clear", "28°C", 60, "Alex Morgan", "travel journal"),
    ]

    for i, (content, poi, weather, temp, d, author, work) in enumerate(travel_data, 1):
        notes.append({
            "id": f"travel-{i:02d}",
            "content": content,
            "date": days_ago(d),
            "source_author": author or "",
            "source_work": work or "",
            "tags": ["Travel", "World", "Journals"],
            "weather": weather,
            "day_period": "afternoon",
            "location": poi,
            "temperature": temp,
            "favorite": i in [1, 2, 5, 8, 13],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 5: 工程待办与背包出行清单 (Checklists, 5 条) - Ground Truth: original
    # =========================================================================
    todo_data = [
        ("Microservices to Modular Monolith Migration Checklist:\n- [x] Consolidate user identity and auth services into core domain\n- [x] Eliminate distributed gRPC overhead in hot query paths\n- [ ] Replace asynchronous event bus with in-process SQLite transactions\n- [ ] Measure p99 latency reduction under simulated 10k RPS load\nSimpler systems fail in simpler, debuggable ways. — Alex Morgan", "Alex Morgan", "engineering checklist"),
        ("Pacific Northwest Backpacking Gear Checklist (Mount Rainier):\n- [x] Three-season ultralight tent & seam-sealed rainfly\n- [x] Down sleeping bag (rated to 20°F) & insulated sleeping pad\n- [x] Katadyn gravity water filter & bear-proof food canister\n- [ ] Trekking poles with carbide tips & spare blister tape\n- [ ] Garmin inReach Mini 2 satellite communicator with active SOS", "Alex Morgan", "gear checklist"),
        ("Q3 Deep Reading & Essay Writing Goals:\n- [x] Re-read George Orwell's 'Politics and the English Language'\n- [x] Finish draft of essay on distributed systems and software craft\n- [ ] Read Virginia Woolf's diaries regarding creative flow\n- [ ] Publish retrospective on multi-tenant database partitioning", "Alex Morgan", "reading goals"),
        ("Home Audio Listening Room Acoustic Optimization:\n- [x] Install bass traps in all four corners of the listening room\n- [x] Calibrate turntable cartridge tracking force and anti-skate\n- [ ] Measure room frequency response using calibrated measurement mic\n- [ ] Position wooden acoustic diffusers behind listening couch", None, "audio checklist"),
        ("Pre-Flight International Travel Essentials:\n- [x] Passport valid for > 6 months & international travel insurance\n- [x] Universal plug adapter with dual USB-C 65W GaN charging\n- [x] Noise-cancelling headphones & Kindle loaded with offline books\n- [ ] Offline maps of destination city downloaded on phone", "Alex Morgan", "travel checklist"),
    ]

    for i, (content, author, work) in enumerate(todo_data, 1):
        delta_ops = []
        for line in content.split("\n"):
            if line.startswith("- [x]"):
                delta_ops.append({"insert": line[5:].strip() + "\n", "attributes": {"list": "checked"}})
            elif line.startswith("- [ ]"):
                delta_ops.append({"insert": line[5:].strip() + "\n", "attributes": {"list": "unchecked"}})
            else:
                delta_ops.append({"insert": line + "\n"})

        notes.append({
            "id": f"todo-{i:02d}",
            "content": content,
            "delta_content": json.dumps(delta_ops, ensure_ascii=False),
            "date": days_ago(i * 4 + 2),
            "source_author": author or "",
            "source_work": work or "",
            "tags": ["Checklist", "Engineering", "TravelPrep"],
            "weather": "clear",
            "day_period": "morning",
            "location": "Home Office",
            "temperature": "19°C",
            "favorite": i in [1, 2],
            "type_ground_truth": "original"
        })

    return notes

# -----------------------------------------------------------------------------
# 归属与别名提取算法（支持英文带空格多词作者如 "Alex Morgan"）
# -----------------------------------------------------------------------------
def is_builtin_personal_work(work, author=""):
    if not work:
        return False
    w = work.lstrip("—–-—―").replace("author:", "").replace("by:", "").replace("作者：", "").replace("作者:", "").strip().lower()
    if not w:
        return False
    if author and author.lower() in w:
        return True
    self_suffixes = [
        "diary", "journal", "notes", "memo", "checklist", "dev notes", "daily notes",
        "travel journal", "travel notes", "field notes", "goals", "reflections",
        "日记", "随笔", "手记", "札记", "笔记", "杂记", "杂感", "随感", "自述", "自语",
        "心迹", "备忘", "碎碎念", "清单", "复盘", "手账", "行记", "游记", "食记"
    ]
    if any(w.endswith(s) for s in self_suffixes):
        return True
    personal_prefixes = ["my ", "personal ", "daily ", "work ", "study ", "reading ", "travel ", "我的", "个人", "日常"]
    for prefix in personal_prefixes:
        if w.startswith(prefix) and any(w[len(prefix):].endswith(s) for s in self_suffixes):
            return True
    return False

def has_personal_device_or_rich_text_markers(note):
    content = note.get("content", "")
    if "- [x]" in content or "- [ ]" in content:
        return True
    if note.get("delta_content") and any(k in note["delta_content"] for k in ['"list":"checked"', '"list":"unchecked"']):
        return True
    return False

def clean_author_name(author):
    """规范化剥离作者前缀与前后引号破折号，严格保留人名中间的空格（如 'Alex Morgan'）"""
    if not author:
        return ""
    trimmed = author.strip()
    trimmed = re.sub(r'^[-—–—―]+\s*', '', trimmed).strip()
    lower = trimmed.lower()
    if lower.startswith("author:") or lower.startswith("author："):
        trimmed = trimmed[7:].strip()
    elif lower.startswith("by:") or lower.startswith("by "):
        trimmed = trimmed[3:].strip()
    elif lower.startswith("作者：") or lower.startswith("作者:"):
        trimmed = trimmed[3:].strip()
    trimmed = re.sub(r'^[-—–—―]+\s*', '', trimmed).strip()
    # 仅剥离两端标点与引号，绝不破坏内部空格
    trimmed = re.sub(r'''^[「“"'《【\[\s]+|[」”"'》】\]\s]+$''', '', trimmed)
    return trimmed

def infer_aliases_from_notes(notes, nickname=""):
    author_stats = {}
    self_keywords = {
        "me", "myself", "i", "self", "author", "original",
        "我", "自己", "本人", "自作", "自撰", "原创", "自留地", "笔者", "作者"
    }
    for n in notes:
        author = (n.get("source_author") or "").strip()
        if not author:
            continue
        clean = clean_author_name(author)
        if not clean or clean.lower() in self_keywords or (nickname and clean.lower() == nickname.lower()):
            continue

        work = (n.get("source_work") or "").strip()
        is_personal = bool(work and is_builtin_personal_work(work, clean))
        has_external_work = bool(work and not is_personal)
        content = n.get("content", "")
        has_signature = (
            f"— {clean}" in content or
            f"—{clean}" in content or
            f"-- {clean}" in content or
            f"--{clean}" in content or
            f"- {clean}" in content or
            f"-{clean}" in content or
            f"@{clean}" in content or
            f"by {clean}" in content.lower()
        )
        has_self_marker = has_personal_device_or_rich_text_markers(n) or is_personal or has_signature

        stats = author_stats.setdefault(clean, {"count": 0, "self_markers": 0, "external_works": 0})
        stats["count"] += 1
        if has_self_marker:
            stats["self_markers"] += 1
        if has_external_work:
            stats["external_works"] += 1

    inferred = set()
    for author, stats in author_stats.items():
        if stats["self_markers"] >= 2 and stats["external_works"] == 0:
            inferred.add(author)
        elif stats["count"] >= 3 and stats["self_markers"] >= 1 and stats["external_works"] == 0:
            inferred.add(author)
    return inferred

def legacy_classify_attribution(note, nickname=""):
    author = (note.get("source_author") or "").strip()
    work = (note.get("source_work") or "").strip()
    source = (note.get("source") or "").strip()

    has_attr = bool(author or work or source)
    if not has_attr:
        return "original"

    self_keywords = {"me", "myself", "i", "self", "author", "original", "我", "自己", "本人", "自作", "原创"}
    clean_author = clean_author_name(author).lower()

    if clean_author in self_keywords:
        return "original"
    if nickname and clean_author == nickname.lower():
        return "original"

    self_source = {"diary", "journal", "notes", "memo", "日记", "随笔", "随手记", "思考", "随想"}
    if work.lower() in self_source or source.lower() in self_source:
        if not author:
            return "original"

    return "excerpt"

def optimized_classify_attribution(note, nickname="", inferred_aliases=None):
    author = (note.get("source_author") or "").strip()
    work = (note.get("source_work") or "").strip()
    source = (note.get("source") or "").strip()

    has_attr = bool(author or work or source)
    if not has_attr:
        return "original"

    clean_author = clean_author_name(author)

    self_keywords = {
        "me", "myself", "i", "self", "author", "original",
        "我", "自己", "本人", "自作", "自撰", "原创", "自述", "自留地"
    }
    if clean_author.lower() in self_keywords:
        return "original"
    if nickname and clean_author.lower() == nickname.lower():
        return "original"
    if inferred_aliases and clean_author in inferred_aliases:
        return "original"

    if author:
        return "excerpt"

    clean_source = clean_author_name(source)
    clean_work = clean_author_name(work)
    if is_builtin_personal_work(clean_source) or is_builtin_personal_work(clean_work):
        return "original"

    for kw in ["diary", "journal", "notes", "memo", "checklist", "随笔", "日记", "手记", "笔记", "备忘", "清单"]:
        if clean_source.lower().endswith(kw) and len(clean_source) > len(kw):
            prefix = clean_source[:-len(kw)].strip()
            if (inferred_aliases and prefix in inferred_aliases) or (nickname and prefix.lower() == nickname.lower()):
                return "original"
        if clean_work.lower().endswith(kw) and len(clean_work) > len(kw):
            prefix = clean_work[:-len(kw)].strip()
            if (inferred_aliases and prefix in inferred_aliases) or (nickname and prefix.lower() == nickname.lower()):
                return "original"

    return "excerpt"

# -----------------------------------------------------------------------------
# LLM 客户端与请求控速
# -----------------------------------------------------------------------------
class ResilientGeminiClient:
    def __init__(self, api_key, base_url, preferred_models):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        if not self.base_url.startswith("https://"):
            raise ValueError(f"Insecure benchmark base_url rejected: {self.base_url}. HTTPS is required.")
        self.models = preferred_models
        self.active_model_idx = 0
        self.last_request_time = 0
        self.min_interval = 2.5

    def _pace(self):
        elapsed = time.time() - self.last_request_time
        if elapsed < self.min_interval:
            sleep_needed = self.min_interval - elapsed
            time.sleep(sleep_needed)
        self.last_request_time = time.time()

    def complete(self, messages, tools=None, temperature=0.3):
        max_retries = 3
        backoff = 3.0

        for model_idx in range(self.active_model_idx, len(self.models)):
            model_name = self.models[model_idx]
            for attempt in range(max_retries):
                self._pace()
                url = f"{self.base_url}/chat/completions"
                payload = {
                    "model": model_name,
                    "messages": messages,
                    "temperature": temperature,
                }
                if tools:
                    payload["tools"] = tools

                req = urllib.request.Request(
                    url,
                    headers={
                        "Content-Type": "application/json",
                        "Authorization": f"Bearer {self.api_key}",
                    },
                    data=json.dumps(payload).encode("utf-8"),
                )

                try:
                    start_t = time.time()
                    with urllib.request.urlopen(req, timeout=45) as resp:
                        data = json.loads(resp.read().decode("utf-8"))
                        self.last_request_time = time.time()
                        self.active_model_idx = model_idx
                        return {"data": data, "model": model_name, "latency": time.time() - start_t, "error": None}
                except urllib.error.HTTPError as e:
                    body = ""
                    try:
                        body = e.read().decode("utf-8")
                    except Exception:
                        pass
                    print(f"⚠️ [{model_name}] HTTP {e.code} (attempt {attempt+1}/{max_retries}): {e.reason} {body[:120]}")
                    if e.code in (429, 503, 500):
                        time.sleep(backoff)
                        backoff *= 2.0
                        continue
                    else:
                        break
                except Exception as e:
                    print(f"⚠️ [{model_name}] Network error (attempt {attempt+1}/{max_retries}): {e}")
                    time.sleep(backoff)
                    backoff *= 1.5

            print(f"🔄 Model {model_name} rate-limited or unavailable, falling back...")

        return {"data": None, "model": None, "latency": 0, "error": "All models exhausted"}

# -----------------------------------------------------------------------------
# 国际英语用户实机场景基准评测
# -----------------------------------------------------------------------------
def run_benchmark():
    print("=" * 80)
    print("🚀 Starting ThoughtEcho Persona 4 (Alex Morgan - International User) Benchmark")
    print("=" * 80)

    notes = generate_international_notes()
    print(f"📊 Generated {len(notes)} realistic international notes for Alex Morgan:")
    type_counts = {}
    for n in notes:
        cat = n["id"].split("-")[0]
        type_counts[cat] = type_counts.get(cat, 0) + 1
    print(f"   - Daily Life & Engineering Reflections (daily): {type_counts.get('daily', 0)}")
    print(f"   - Classic Literature & Philosophy Excerpts (classic): {type_counts.get('classic', 0)}")
    print(f"   - Music Lyrics & Cinema Soliloquies (media): {type_counts.get('media', 0)}")
    print(f"   - Global Travel & Field Journals (travel): {type_counts.get('travel', 0)}")
    print(f"   - Engineering & Travel Checklists (todo): {type_counts.get('todo', 0)}")

    # 1. 归属算法准确率评测
    print("\n" + "-" * 80)
    print("🔬 [Benchmark Dimension 1]: Attribution accuracy with multi-word signature 'Alex Morgan'")
    print("-" * 80)

    inferred_aliases = infer_aliases_from_notes(notes, nickname="")
    print(f"💡 Automatically inferred author aliases from notes: {inferred_aliases}")
    assert "Alex Morgan" in inferred_aliases, "Failed to infer multi-word alias 'Alex Morgan'!"

    legacy_correct = 0
    optimized_correct = 0
    legacy_false_excerpts = 0
    optimized_false_excerpts = 0

    for n in notes:
        gt = n["type_ground_truth"]
        leg = legacy_classify_attribution(n, nickname="")
        opt = optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases)

        if leg == gt:
            legacy_correct += 1
        elif leg == "excerpt" and gt == "original":
            legacy_false_excerpts += 1

        if opt == gt:
            optimized_correct += 1
        elif opt == "excerpt" and gt == "original":
            optimized_false_excerpts += 1

    leg_acc = (legacy_correct / len(notes)) * 100
    opt_acc = (optimized_correct / len(notes)) * 100

    print(f"❌ Legacy Attribution Accuracy: {legacy_correct}/{len(notes)} ({leg_acc:.1f}%)")
    print(f"   False Excerpts (Originals misclassified as excerpts): {legacy_false_excerpts}")
    print(f"✅ Optimized Attribution Accuracy: {optimized_correct}/{len(notes)} ({opt_acc:.1f}%)")
    print(f"   False Excerpts: {optimized_false_excerpts}")

    # 2. Dreaming 采样纯度评估
    print("\n" + "-" * 80)
    print("🔬 [Benchmark Dimension 2]: Dreaming Sample Isolation Purity (Voice vs Taste)")
    print("-" * 80)

    opt_originals = [n for n in notes if optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases) == "original"]
    opt_excerpts = [n for n in notes if optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases) == "excerpt"]

    alex_in_taste = [n for n in opt_excerpts if n.get("type_ground_truth") == "original"]
    opt_purity = (100.0 - len(alex_in_taste) / len(opt_excerpts) * 100) if opt_excerpts else 0.0

    print(f"📌 Originals Pool (Voice baseline): {len(opt_originals)}")
    print(f"📌 Excerpts Pool (Taste baseline): {len(opt_excerpts)}")
    print(f"🛡️ Taste Pool Bleeding from Alex Morgan: {len(alex_in_taste)} (Purity: {opt_purity:.1f}%)")

    # 3. 实机 LLM 评测
    if not API_KEY:
        print("\n⚠️ No valid GEMINI_API_KEY found, skipping live LLM evaluation.")
        return

    print("\n" + "-" * 80)
    print("🔬 [Benchmark Dimension 3]: Live Gemini Model Evaluation (English Voice & Taste Fidelity)")
    print("-" * 80)

    client = ResilientGeminiClient(API_KEY, BASE_URL, PREFERRED_MODELS)

    alex_profile = (
        "<user_profile>\n"
        "Here are preferences learned in previous conversations, describing how to respond to this user:\n"
        "- [identity·inferred] Address the user as 'Alex Morgan' or 'Alex'\n"
        "- [voice·3 days ago] Prefers reflective, lucid first-person prose with a focus on tactile craftsmanship, computational elegance, and sensory clarity (e.g. morning espresso extraction, analog vinyl warmth, foggy hills, clean abstraction seams). Natural, grounded English with thoughtful cadence; avoids empty jargon, excessive exclamation marks, and patronizing AI cheerfulness.\n"
        "- [taste·3 days ago] Appreciates classic literature and philosophy (George Orwell, Ernest Hemingway, Virginia Woolf, Marcus Aurelius, Albert Camus, Thoreau), vintage rock/folk music (Pink Floyd, Bob Dylan, David Bowie, Radiohead), and contemplative sci-fi cinema (Blade Runner, Interstellar).\n"
        "- [preferences·5 days ago] Enjoys alpine hiking (Swiss Alps, Pacific Northwest), mechanical keyboards, pour-over coffee, fountain pens, and wandering through historic cities and natural coastlines.\n"
        "- [recent·1 day ago] Working on refactoring microservices back into a modular monolith, recently traveled through Kyoto and Big Sur, preparing for a high-altitude trek on Mount Rainier.\n"
        "</user_profile>"
    )

    test_cases = [
        {
            "id": "alex_sc1_craftsmanship_essay",
            "title": "Scenario 1: Essay on Software Craftsmanship and Analog Rituals",
            "prompt": "I'm sitting at my desk watching the morning fog roll over the hills with an espresso in hand. Help me write the opening two paragraphs of an essay about why tactile rituals—like brewing coffee or using fountain pens—keep us grounded in an increasingly virtual world.",
            "expect": ["espresso", "tactile", "fog", "grounded", "virtual"]
        },
        {
            "id": "alex_sc2_travel_synthesis",
            "title": "Scenario 2: Travel Essay Synthesizing Big Sur and Kyoto",
            "prompt": "Looking through my recent travel photos from the vermilion gates of Fushimi Inari and the sheer cliffs of Big Sur. Write a short piece connecting how stillness can be found both in ancient cedar forests and wild ocean winds.",
            "expect": ["Fushimi", "Big Sur", "stillness", "wind", "Kyoto"]
        },
        {
            "id": "alex_sc3_reading_recommendation",
            "title": "Scenario 3: Book and Music Recommendations Matching Orwell/Camus/Pink Floyd",
            "prompt": "I need something contemplative for a quiet rainy evening. What would you recommend reading and listening to that echoes the quiet resilience of Camus or the spacious melancholy of Pink Floyd?",
            "expect": ["Camus", "Pink Floyd", "resilience", "melancholy", "quiet"]
        },
        {
            "id": "alex_sc4_recent_context",
            "title": "Scenario 4: Recent Context & Project Continuity Recall",
            "prompt": "Long day at the terminal. Do you remember what architectural mess I've been untangling this week and where I'm gearing up to hike next?",
            "expect": ["monolith", "microservices", "Rainier", "hike", "modular"]
        }
    ]

    case_results = []

    for tc in test_cases:
        print(f"\n📝 Executing: {tc['title']}")
        system_prompt = (
            "You are the Thoughter AI companion inside ThoughtEcho notes app."
            "Thoughtful, perceptive, grounded, intellectually honest. Converse naturally in elegant English."
        )
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": alex_profile},
            {"role": "user", "content": tc["prompt"]}
        ]

        res = client.complete(messages, temperature=0.3)
        if res["error"]:
            print(f"❌ Request failed: {res['error']}")
            case_results.append({"id": tc["id"], "success": False, "matched": 0, "total": len(tc["expect"])})
            continue

        reply = res["data"]["choices"][0]["message"]["content"]
        active_model = res["model"]
        expected_items = tc["expect"]
        matched_items = [item for item in expected_items if item.lower() in reply.lower()]
        passed_expect = len(matched_items) >= max(1, int(len(expected_items) * 0.4))
        case_success = bool(reply) and passed_expect

        print(f"🤖 [Model: {active_model} | Latency: {res['latency']:.2f}s]:\n{reply[:260]}...\n")
        print(f"📋 [Verification]: Matched {len(matched_items)}/{len(expected_items)} ({', '.join(matched_items)}) -> {'PASSED' if case_success else 'FAILED'}\n")
        case_results.append({
            "id": tc["id"],
            "success": case_success,
            "matched": len(matched_items),
            "total": len(expected_items)
        })

    successful_cases = sum(1 for c in case_results if c["success"])
    total_cases = len(test_cases)
    case_success_rate = (successful_cases / total_cases * 100) if total_cases > 0 else 0.0

    print("=" * 80)
    print("🎯 Alex Morgan (International User) Benchmark Summary")
    print("=" * 80)
    print(f"1. Attribution Accuracy: From {leg_acc:.1f}% to {opt_acc:.1f}% (+{opt_acc-leg_acc:.1f}%)")
    print(f"2. Inferred Pen Name: {inferred_aliases} (Preserved internal spaces)")
    print(f"3. Dreaming Sampling Purity: Voice {len(opt_originals)}, Taste {len(opt_excerpts)}, Bleed: {len(alex_in_taste)} (Purity: {opt_purity:.1f}%)")
    print(f"4. Scenario Pass Rate: {successful_cases}/{total_cases} ({case_success_rate:.1f}%)")
    print("=" * 80)

if __name__ == "__main__":
    run_benchmark()
