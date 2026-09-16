#!/usr/bin/env python3
"""
ThoughtEcho Thoughter AI 第三模拟用户（小舟·在读大学生）拟真生活学习场景基准评测引擎
涵盖：
1. 校园瞬间与日常碎碎念（早八高数、食堂生煎、期末周抢座、宿舍晚霞、操场夜跑、实验折腾）
2. 喜欢的课外书精选摘录（王小波、毛姆、刘慈欣、史铁生、村上春树、加缪、卡尔维诺等）
3. 古诗词与古典文学摘录（苏轼、李清照、辛弃疾、杜甫、王维、陶渊明、李白等）
4. 听歌歌词与日漫台词摘录（周杰伦、五月天、朴树、新海诚、宫崎骏、RADWIMPS等）
5. 假期旅游与应景诗文感悟（泰山日出、西湖烟雨、青海湖远行、徽州古村，融情于景）
6. 学习备考与出行清单（期末复习、四六级、穷游背包清单）

验证长期记忆系统在学生群体语言、碎片化日常记录、多源摘录（诗词/歌词/动漫/书摘）与旅游诗文场景下的归属识别、采样纯度与文风画像自适应。
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
# 高保真拟真笔记数据集生成（小舟·在读大学生）
# -----------------------------------------------------------------------------
def generate_student_notes():
    now = datetime.now()
    def days_ago(d, hour=12):
        t = now - timedelta(days=d)
        return t.replace(hour=hour, minute=20, second=0).strftime("%Y-%m-%d %H:%M:%S")

    notes = []

    # =========================================================================
    # 类别 1: 校园瞬间与日常碎碎念 (20 条) - Ground Truth: original
    # =========================================================================
    campus_data = [
        ("早八高数课，老教授在黑板上板书傅里叶级数，窗外香樟树枝头落了两只灰喜鹊。阳光斜照进阶梯教室，微尘在光柱里慢慢打转。趴在课桌上，眼皮打架，强撑着把例题抄完。大学的早晨总是混杂着清醒与困倦。——小舟", "小舟", "随手记", "早上", "clear", "16°C", 1),
        ("大学城二食堂二楼的生煎包真是绝了，底焦脆，里面一包滚烫鲜甜的汤汁，配上一碗热腾腾的无糖豆浆，只要五块钱。阿姨每次都多给舀半勺葱花，吃完整个人都有了去图书馆占座的力气。", None, None, "清晨", "clear", "15°C", 2),
        ("期末周的图书馆一位难求。早上七点在晨雾里排队，开门瞬间大家像沙丁鱼一样涌向三楼自习区。找了个靠窗的角落插上电脑，桌上摆满了机械原理、草稿纸和保温杯，准备闭关一整天。——小舟日常", "小舟", "日常", "上午", "cloudy", "14°C", 4),
        ("宿舍阳台的傍晚，天边烧起了一整片橘紫色的晚霞。风吹动晾衣绳上的白衬衫，洗衣液的柠檬香在空气里散开。隔壁宿舍有人在弹吉他唱《安河桥》，有些跑调，但那一刻觉得青春真好。——小舟", "小舟", None, "傍晚", "clear", "20°C", 6),
        ("大学物理实验测光电效应，微安表指针晃晃悠悠总也调不到零点。换了三个遮光罩，重新接线四次，终于测出了普朗克常数。虽然误差有8%，但在数据表上签下名字那一刻，莫名很有成就感。", None, None, "下午", "cloudy", "18°C", 8),
        ("下课骑共享单车穿过校园林荫道，初秋的凉风把衬衫后背吹得鼓鼓的。金黄的银杏叶一片一片落在车筐里。耳机里正放着周杰伦的《反方向的钟》，感觉自己像骑进了一场慢动作电影。——小舟随笔", "小舟", "随笔", "傍晚", "clear", "19°C", 10),
        ("晚上自习到闭馆，收拾书包走在空荡荡的校园林荫路上。路灯把影子拉得很长很长。走到操场跑了五圈，深秋夜风吹干了额头的汗，耳机里鼓点一下下撞击心脏，所有绩点和保研的焦虑都被风吹散了。——小舟", "小舟", "日记", "深夜", "clear", "12°C", 12),
        ("室友通宵打游戏开黑，键盘敲得劈啪作响。戴上入耳式降噪耳机，播放白噪音里的雨声，世界终于安静了。在台灯微光下翻完《卡拉马佐夫兄弟》的最后一章，心里久久不能平息。", None, None, "深夜", "cloudy", "13°C", 14),
        ("星期五下午没课，宿舍四个人一起坐地铁去市区吃老灶火锅。红油翻滚，毛肚鸭肠在九宫格里涮得脆嫩，喝着冰镇北冰洋汽水，聊着各自暗恋的女生和未来的打算，笑得前仰后合。", None, None, "下午", "clear", "22°C", 16),
        ("洗完一盆衣服端到楼顶天台晾晒。风很大，整片城市的楼宇尽收眼底。天很蓝，有飞机划过留下一道白色的航迹云。靠在栏杆上发呆了半小时，什么也没想，但觉得很被治愈。——小舟", "小舟", None, "下午", "clear", "21°C", 18),
        ("上思政大课，阶梯教室坐了三个班两百号人。前排同学在认真记笔记，中排在看平板网课，后排在补觉。悄悄拿出王小波的小说藏在课本底下偷看，看到有趣的地方死死憋住笑，憋得腹肌疼。", None, None, "上午", "clear", "17°C", 20),
        ("双十一网购了一大箱红烧牛肉面和螺蛳粉囤在宿舍柜子里，期末通宵画图复习的战略物资终于齐备。拆快递纸箱的快乐是大学生活中少数不花大钱的高光时刻。——小舟", "小舟", "生活杂感", "晚上", "clear", "16°C", 22),
        ("雨天没有带伞，和同班同学挤在一把格纹伞底下从教学楼狂奔到食堂。裤脚全湿透了，鞋子里噗嗤噗嗤响，但大家看着彼此狼狈的落汤鸡模样，忍不住在雨地里哈哈大笑。", None, None, "中午", "rainy", "15°C", 25),
        ("第一次当学生会干事负责晚会剧场音响调音。后台黑漆漆的，手里握着对讲机听指令，掌心全是汗。当幕布拉开、聚光灯亮起、全场欢呼响起的那一秒，心跳快得要跳出嗓子眼。——小舟手记", "小舟", "手记", "晚上", "clear", "18°C", 28),
        ("周末在宿舍补觉到十一点，阳光透过遮光帘缝隙照在床单上。翻个身继续赖床，听着楼下水房传来的水龙头滴水声和宿管阿姨的广播通知。这种懒洋洋的无所事事，是忙碌大学里最珍贵的缝隙。", None, None, "中午", "clear", "20°C", 31),
        ("在二手书跳蚤市场花了十五块钱淘到一本1988年版黄封皮的《博尔赫斯短篇小说集》。扉页上原主人用钢笔写着：赠予1992年的阿华。字迹已经泛黄，不知道当年的阿华如今身在何方。——小舟", "小舟", None, "下午", "cloudy", "17°C", 34),
        ("体测八百米和一千米。跑完最后一圈冲过终点线，整个人直接瘫倒在绿茵场人造草皮上，喉咙里泛着铁锈味，胸口剧烈起伏。仰望着灰白色的天幕，看着同伴伸过来的手，活着真好。", None, None, "下午", "cloudy", "16°C", 37),
        ("大学英语四级考场。做完听力脑子里全是'Welcome to CET-4'的机械播音腔。最后写作文手腕发酸，交卷铃响的那一刻，走出考场阳光刺眼，感觉肩膀上卸下了一块大石头。——小舟", "小舟", "备忘", "中午", "clear", "19°C", 40),
        ("深夜一点半改完PPT，保存发到导师邮箱。关上笔记本，阳台上夜风吹进来，整栋宿舍楼都熄了灯，黑黢黢的像一座沉默的岛屿。远处高架桥上偶有一辆夜班车呼啸而过。——小舟碎碎念", "小舟", "碎碎念", "深夜", "clear", "11°C", 43),
        ("春天的玉兰花在图书馆门前全开了，白色的花瓣像一盏盏小酒杯。拿着两本借来的书走下台阶，微风掠过，花瓣轻轻落在肩头。忍不住掏出手机抓拍了一张，春光短暂，值得记住。", None, None, "下午", "clear", "22°C", 46),
    ]

    for i, (content, author, work, day_period, weather, temp, d) in enumerate(campus_data, 1):
        notes.append({
            "id": f"campus-{i:02d}",
            "content": content,
            "date": days_ago(d, hour=8 if day_period=="清晨" else (22 if day_period=="深夜" else 14)),
            "source_author": author or "",
            "source_work": work or "",
            "tags": ["校园生活", "大学日常", "碎碎念"],
            "weather": weather,
            "day_period": "morning" if day_period in ["早上", "清晨", "上午"] else ("night" if day_period in ["晚上", "深夜"] else "afternoon"),
            "location": "大学城校区",
            "temperature": temp,
            "favorite": i in [1, 4, 7, 10, 16],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 2: 课外书精选摘录 (15 条) - Ground Truth: excerpt
    # =========================================================================
    book_excerpts = [
        ("那一天我二十一岁，在我一生的黄金时代。我有好多奢望。我想爱，想吃，还想在一瞬间变成天上半明半暗的云。后来我才知道，生活就是个缓慢受锤的过程。", "王小波", "黄金时代", ["小说", "经典摘录", "青春"]),
        ("满地都是六便士，他却抬头看见了月亮。一个人如果想做他喜欢的事，并且有勇气承担一切后果，那他就是最幸福的人。", "毛姆", "月亮与六便士", ["文学", "理想", "人生"]),
        ("给岁月以文明，而不是给文明以岁月。无论结果将面对黑暗还是光明，我们都要尽最大努力去探索去热爱。", "刘慈欣", "三体II·黑暗森林", ["科幻", "宇宙", "哲思"]),
        ("一个人，出生了，这就不再是一个可以辩论的问题，而只是上帝交给他的一个事实；上帝在交给我们这件事实的时候，已经顺便保证了它的结果，所以死是一件不必急于求成的事。", "史铁生", "我与地坛", ["散文", "生命", "坚韧"]),
        ("死并非生的对立面，而作为生的一部分永存。哪怕在这个充满缺憾的世界里，依然有值得我们深爱的人与物。", "村上春树", "挪威的森林", ["日本文学", "孤独", "成长"]),
        ("在隆冬，我终于知道，我身上有一个不可战胜的夏天。哪怕面对荒谬与无常，也要勇敢地活着并抗争下去。", "加缪", "夏天集", ["存在主义", "哲学", "勇气"]),
        ("城市犹如梦境：凡可以想象的东西都可以梦见，但是，即使最不可思议的梦境也是一幅画谜，其中潜隐着欲望，或者恐惧。", "卡尔维诺", "看不见的城市", ["小说", "城市", "想象力"]),
        ("我心里一直都在暗暗设想：天堂应该是图书馆的模样。万卷书册层叠至天际，所有的知识与奥秘皆静候探寻。", "博尔赫斯", "诗艺", ["文学", "图书馆", "阅读"]),
        ("世界上只有一种真正的英雄主义，那就是认清生活的真相后依然热爱生活。去直面惨淡，并在泥泞中盛开。", "罗曼·罗兰", "米开朗琪罗传", ["传记", "英雄主义", "励志"]),
        ("真正有价值的东西，不是那些可以拿来向别人炫耀的财富与名声，而是那些能够让你在深夜里感到内心充盈与安宁的事物。", "周国平", "守望的距离", ["散文", "哲思", "内省"]),
        ("你要搞清楚自己人生的剧本——不是你父母的续集，不是你子女的前传，更不是你朋友的外篇。你是你自己的唯一主角。", "尼采", "查拉图斯特拉如是说", ["哲学", "独立", "自我"]),
        ("当一个人沉醉在一个幻想之中，他就会把这幻想成模糊的情味，当作真实的酒。你喝酒为的是求醉；我喝酒为的是要从别的醉中醒来。", "纪伯伦", "沙与沫", ["诗歌", "哲理", "灵性"]),
        ("少年就是少年，他们看春风不喜，看夏蝉不烦，看秋风不悲，看冬雪不叹，看满身富贵懒察觉，看不公不允敢拔刀。", "陀思妥耶夫斯基", "少年", ["外国文学", "青春", "锐气"]),
        ("无论走到哪里，都应该记住，过去都是假的，回忆是一条没有尽头的路，以往的一切春天都无法复原，唯有当下真实可握。", "加西亚·马尔克斯", "百年孤独", ["魔幻现实主义", "经典", "时光"]),
        ("每个人都是一座孤岛，但书本是横跨岛屿之间的桥梁。只要你翻开书页，千百年前的灵魂便在与你低语。", "赫尔曼·黑塞", "悉达多", ["小说", "灵魂", "寻道"]),
    ]

    for i, (content, author, work, tags) in enumerate(book_excerpts, 1):
        notes.append({
            "id": f"book-{i:02d}",
            "content": content,
            "date": days_ago(i * 3 + 1, hour=21),
            "source_author": author,
            "source_work": work,
            "tags": tags,
            "weather": "clear" if i % 2 == 0 else "cloudy",
            "day_period": "night",
            "location": "校图书馆",
            "temperature": "18°C",
            "favorite": i in [1, 2, 4, 6, 8],
            "type_ground_truth": "excerpt"
        })

    # =========================================================================
    # 类别 3: 古诗词与传统文学摘录 (15 条) - Ground Truth: excerpt
    # =========================================================================
    poem_excerpts = [
        ("莫听穿林打叶声，何妨吟啸且徐行。竹杖芒鞋轻胜马，谁怕？一蓑烟雨任平生。料峭春风吹酒醒，微冷，山头斜照却相迎。回首向来萧瑟处，归去，也无风雨也无晴。", "苏轼", "定风波·莫听穿林打叶声", ["宋词", "苏轼", "旷达", "古诗词"]),
        ("常记溪亭日暮，沉醉不知归路。兴尽晚回舟，误入藕花深处。争渡，争渡，惊起一滩鸥鹭。", "李清照", "如梦令·常记溪亭日暮", ["宋词", "李清照", "青春", "唯美"]),
        ("东风夜放花千树。更吹落、星如雨。宝马雕车香满路。凤箫声动，玉壶光转，一夜鱼龙舞。蛾儿雪柳黄金缕。笑语盈盈暗香去。众里寻他千百度。蓦然回首，那人却在，灯火阑珊处。", "辛弃疾", "青玉案·元夕", ["宋词", "辛弃疾", "经典"]),
        ("岱宗夫如何？齐鲁青未了。造化钟神秀，阴阳割昏晓。荡胸生曾云，决眦入归鸟。会当凌绝顶，一览众山小。", "杜甫", "望岳", ["唐诗", "杜甫", "泰山", "豪迈"]),
        ("中岁颇好道，晚家南山陲。兴来每独往，胜事空自知。行到水穷处，坐看云起时。偶然值林叟，谈笑无还期。", "王维", "终南别业", ["唐诗", "王维", "山水", "禅意"]),
        ("结庐在人境，而无车马喧。问君何能尔？心远地自偏。采菊东篱下，悠然见南山。山气日夕佳，飞鸟相与还。此中有真意，欲辨已忘言。", "陶渊明", "饮酒·其五", ["魏晋", "陶渊明", "田园", "闲适"]),
        ("君不见黄河之水天上来，奔流到海不复回。君不见高堂明镜悲白发，朝如青丝暮成雪。人生得意须尽欢，莫使金樽空对月。天生我材必有用，千金散尽还复来。", "李白", "将进酒", ["唐诗", "李白", "浪漫", "豪迈"]),
        ("人生天地之间，若白驹之过隙，忽然而已。注然勃然，莫不出焉；油然寥然，莫不入焉。", "庄子", "庄子·知北游", ["先秦诸子", "哲学", "虚静"]),
        ("水光潋滟晴方好，山色空濛雨亦奇。欲把西湖比西子，淡妆浓抹总相宜。", "苏轼", "饮湖上初晴后雨", ["宋词", "西湖", "写景"]),
        ("曾经沧海难为水，除却巫山不是云。取次花丛懒回顾，半缘修道半缘君。", "元稹", "离思五首·其四", ["唐诗", "深情", "怀古"]),
        ("落霞与孤鹜齐飞，秋水共长天一色。渔舟唱晚，响穷彭蠡之滨；雁阵惊寒，声断衡阳之浦。", "王勃", "滕王阁序", ["骈赋", "盛唐", "绝景"]),
        ("行香子·过七里濑：一叶舟轻，双桨鸿惊。水天清、影湛波平。鱼翻藻鉴，鹭点烟汀。过沙溪急，霜溪冷，月溪明。", "苏轼", "行香子", ["宋词", "山水", "行舟"]),
        ("白日依山尽，黄河入海流。欲穷千里目，更上一层楼。", "王之涣", "登鹳雀楼", ["唐诗", "登高", "哲理"]),
        ("飞来山上千寻塔，闻说鸡鸣见日升。不畏浮云遮望眼，自缘身在最高层。", "王安石", "登飞来峰", ["宋诗", "格局", "登高"]),
        ("江南无所有，聊赠一枝春。折花逢驿使，寄与陇头人。", "陆凯", "赠范晔诗", ["古诗", "江南", "友情"]),
    ]

    for i, (content, author, work, tags) in enumerate(poem_excerpts, 1):
        notes.append({
            "id": f"poem-{i:02d}",
            "content": content,
            "date": days_ago(i * 3 + 2, hour=19),
            "source_author": author,
            "source_work": work,
            "tags": tags,
            "weather": "clear",
            "day_period": "evening",
            "location": "校图书馆阅览室",
            "temperature": "19°C",
            "favorite": i in [1, 2, 4, 7, 9],
            "type_ground_truth": "excerpt"
        })

    # =========================================================================
    # 类别 4: 听歌歌词与日漫台词摘录 (15 条) - Ground Truth: excerpt
    # =========================================================================
    music_anime_excerpts = [
        ("故事的小黄花，从出生那年就飘着。童年的荡秋千，随记忆一直晃到现在。从前从前有个人爱你很久，但偏偏风渐渐把距离吹得好远。好不容易又能再多爱一天，但故事的最后你好像还是说了拜拜。", "周杰伦", "晴天", ["歌词", "周杰伦", "青春怀旧"]),
        ("雨下整夜，我的爱溢出就像雨水。院子落叶，跟我的思念厚厚一叠。几句是非，也无法将我的热情冷却。你出现在我诗的每一页。", "周杰伦", "七里香", ["流行音乐", "周杰伦", "夏日"]),
        ("怎么去拥有，一只光彩夺目的蝴蝶。怎么去拥有一道彩虹，怎么去拥抱一夏天的风。天上的星星笑地上的人，总是不能懂，不能觉得足够。如果我爱上你的笑容，要怎么收藏要怎么拥有。", "五月天", "知足", ["歌词", "五月天", "纯真"]),
        ("我曾经跨过山和大海，也穿过人山人海。我曾经拥有着一切，转眼都飘散如烟。我曾经失落失望失掉所有方向，直到看见平凡才是唯一的答案。", "朴树", "平凡之路", ["民谣", "朴树", "成长", "人生"]),
        ("樱花落下的速度是每秒五厘米，那我该用怎样的速度，才能与你相遇？雨滴落下的速度是每秒十米，我该用怎样的速度，才能将你挽留？", "新海诚", "秒速5厘米", ["日漫台词", "新海诚", "唯美", "遗憾"]),
        ("只要记住你的名字，不管你在世界的哪个地方，我一定会去见你。重要的人，不能忘记的人，不想忘记的人。你的名字是？", "新海诚", "你的名字。", ["动漫电影", "新海诚", "感动"]),
        ("隐约雷鸣，阴霾天空，但盼风雨来，能留你在此。隐约雷鸣，阴霾天空，即使天无雨，我亦留此地。", "新海诚", "言叶之庭", ["动画", "万叶集", "雨天"]),
        ("人生就是一列开往坟墓的列车，路途上会有很多站，很难有人可以自始至终陪着走完。当陪你的人要下车时，即使不舍也该心存感激，然后挥手道别。", "宫崎骏", "千与千寻", ["吉卜力", "宫崎骏", "成长哲理"]),
        ("世界这么大，人生这么长，总会有这么一个人，让你想要温柔地对待。哪怕被大雨淋湿，也要大步往前走。", "宫崎骏", "哈尔的移动城堡", ["吉卜力", "治愈", "爱情"]),
        ("哪怕没有翅膀，我们也要仰望天空。纵使身处泥沼，心中的光芒也绝不熄灭。", "宫崎骏", "风之谷", ["动画", "勇气", "希望"]),
        ("我们总是渴望被理解，却又害怕被看穿。在人群中喧闹，却在深夜里与孤独握手言和。", "RADWIMPS", "前前前世", ["日音", "摇滚", "共鸣"]),
        ("哪怕生活充满风浪，也要如野草般顽强生长。时代车轮滚滚向前，愿我们都能握紧属于自己的微小火种。", "中岛美雪", "骑在银龙的背上", ["经典日音", "力量", "坚韧"]),
        ("我吹过你吹过的晚风，那我们算不算相拥？我走过你走过的路，这算不算相逢？", "宿羽阳", "暗恋是一个人的事情", ["民谣", "暗恋", "心动"]),
        ("所谓成熟，大概就是把哭声调成静音的过程。世界喧嚣，守住内心的安宁便胜过万千繁华。", "毛不易", "消愁", ["流行", "成长", "感悟"]),
        ("有些路很远，走下去会很累。可是，不走，会后悔。趁年轻，去追风，去见山，去爱。", "海子", "海子的诗", ["现代诗", "青春", "梦想"]),
    ]

    for i, (content, author, work, tags) in enumerate(music_anime_excerpts, 1):
        notes.append({
            "id": f"art-{i:02d}",
            "content": content,
            "date": days_ago(i * 2 + 1, hour=23),
            "source_author": author,
            "source_work": work,
            "tags": tags,
            "weather": "cloudy" if i % 2 == 0 else "rainy",
            "day_period": "night",
            "location": "宿舍床头",
            "temperature": "17°C",
            "favorite": i in [1, 3, 5, 8, 12],
            "type_ground_truth": "excerpt"
        })

    # =========================================================================
    # 类别 5: 假期旅游与应景诗文感悟 (15 条) - Ground Truth: original
    # =========================================================================
    travel_data = [
        ("夜爬泰山。凌晨五点半挤在日观峰呼啸的寒风里，裹着军大衣冻得瑟瑟发抖。忽然天边破开一道金紫色的裂隙，红日一跃而出，整片茫茫云海瞬间镀上一层熔金。那一刻脑海里唯有杜甫的‘会当凌绝顶，一览众山小’。所有通宵攀爬十八盘的酸痛，在此刻彻底化作浩然之气。——小舟行记", "泰山日观峰", "clear", "4°C", 3, "小舟", "小舟行记"),
        ("烟雨蒙蒙的天气里一个人游西湖。从断桥走到孤山，雨丝轻柔如烟，湖面水汽蒸腾，远处的保俶塔在空濛水色里若隐若现。忽然懂了苏轼‘水光潋滟晴方好，山色空濛雨亦奇’不是客套，江南的雨真有一种洗涤尘虑的温润。坐在湖边茶馆喝一碗龙井，心静如水。——小舟", "杭州西湖", "rainy", "17°C", 7, "小舟", None),
        ("青海湖环湖骑行。天蓝得没有一丝杂质，公路一侧是无边无际湛蓝如宝石的湖水，另一侧是金灿灿铺到天边的油菜花田。高原的烈风吹得耳边呼呼作响，阳光把手臂晒得通红。停下车坐在湖边碎石滩上，大口灌着矿泉水，感觉自己像一只挣脱了囚笼的野鹰。——小舟", "青海湖二郎剑", "clear", "14°C", 11, "小舟", "行记"),
        ("站在黄山光明顶凭栏远眺。狂风席卷着白云从山谷翻涌而上，奇松怪石在云雾开合间时隐时现。想起‘登高壮观天地间，大江茫茫去不还’。人在万丈绝壁与天地大美面前，渺小得如同一粒尘埃，但能亲眼见证这造化神工，何其有幸。", "黄山光明顶", "cloudy", "9°C", 15, None, None),
        ("徽州宏村的清晨。天刚蒙蒙亮，月沼如镜，徽派马头墙倒映在泛着清幽晨光的水面上。村民提着竹篮在水圳边洗菜，偶有两只白鸭划开水波。穿行在湿漉漉的高墙深巷里，青苔沿着石板缝隙蔓延，仿佛走进了戴望舒的雨巷。——小舟", "黟县宏村", "rainy", "16°C", 19, "小舟", None),
        ("在大理洱海生态廊道骑行。阳光透过柳树洒下斑驳光影，苍山十九峰上的积雪在蓝天映衬下晶莹剔透。坐在沿海长椅上发呆，海鸥掠过水面争食面包屑。风很温柔，吹得人想睡个长长的午觉。大理的慢节奏让人忘记了所有的deadline。——小舟行记", "大理洱海", "clear", "20°C", 23, "小舟", "小舟行记"),
        ("坐绿皮慢速火车穿行在秦岭深处的隧道群。车厢里旅客大多在打瞌睡，小贩推着推车卖瓜子泡面。靠窗看着窗外重峦叠嶂的翠绿山岭与依山而建的梯田，溪流在谷底奔腾。慢车走走停停，让人重温了从前那种‘日色变得慢，车马邮件都慢’的从容。", "秦岭山间火车", "cloudy", "15°C", 27, None, None),
        ("南京鸡鸣寺看樱花。樱花大道上游人如织，粉白色的花瓣像雪一样在风里飘扬。买了一串香甜的梅花糕，站在寺院高台俯瞰玄武湖与明城墙。古今交错在此处毫无违和感，繁华与沧桑在一抹花影里自然流淌。——小舟", "南京鸡鸣寺", "clear", "19°C", 30, "小舟", None),
        ("敦煌鸣沙山月牙泉。赤脚踩在被夕阳晒得温热的细沙上，一步一滑攀上沙丘脊线。回望黄沙环抱中的那一弯碧蓝月牙泉，驼队在沙梁上缓缓前行，驼铃声清脆悠远。王维的‘大漠孤烟直，长河落日圆’穿越千年直击心扉。——小舟", "敦煌鸣沙山", "clear", "24°C", 33, "小舟", "随笔"),
        ("成都锦里与人民公园。坐在鹤鸣茶社的老竹椅上，泡一碗盖碗绿茶，听着耳边清脆的采耳铁片叮当声，看旁边老爷爷下象棋争论得面红耳赤。所谓人间烟火气，最抚凡人心，大概就是这种安逸闲适的模样。", "成都人民公园", "cloudy", "21°C", 36, None, None),
        ("苏州拙政园初冬。残荷在水池里傲立，‘留得残荷听雨声’的意境瞬间拉满。白墙漏窗，移步换景，一拳代山，一勺代水。中国文人把整个宇宙的哲思与山水缩微在一座园林里，这种审美的精致令人折服。——小舟", "苏州拙政园", "rainy", "12°C", 39, "小舟", None),
        ("武汉长江大桥凭栏。夜幕降临，浩浩荡荡的长江水滚滚东去，江风把头发吹得凌乱。两岸龟山蛇山灯火辉煌，黄鹤楼在夜色里金碧辉煌。汽笛长鸣，货轮划破夜水，真正感受到了‘极目楚天舒’的雄浑气魄。——小舟手记", "武汉长江大桥", "clear", "18°C", 42, "小舟", "手记"),
        ("西安大雁塔北广场与大唐不夜城。穿汉服的小姐姐裙裾飘飘，灯火阑珊，梦回长安。吃了一大碗油泼扯面配肉夹馍，面条筋道香辣，蒜香浓郁。古老与现代在这里碰撞出最炽热的生命力。", "西安大雁塔", "clear", "16°C", 45, None, None),
        ("厦门环岛路与曾厝垵。脱下帆布鞋踩在细腻松软的沙滩上，咸涩的海风迎面吹来，白色的海浪一层一层拍打脚踝。捡了几只小贝壳装在口袋里，面朝大海，春暖花开的感觉真实地拥抱了全身。——小舟", "厦门环岛路", "clear", "23°C", 48, "小舟", None),
        ("洛阳龙门石窟。暮色中卢舍那大佛依山开凿，面容安详温和，嘴角含着看透一切的淡淡微笑。站在伊河对岸凝望千年佛龛与摩崖造像，历史的风烟散尽，唯有这份慈悲与定力在巨石中永存。——小舟", "洛阳龙门石窟", "cloudy", "17°C", 51, "小舟", "行记"),
    ]

    for i, (content, poi, weather, temp, d, author, work) in enumerate(travel_data, 1):
        notes.append({
            "id": f"travel-{i:02d}",
            "content": content,
            "date": days_ago(d, hour=17),
            "source_author": author or "",
            "source_work": work or "",
            "tags": ["旅行足迹", "诗意行囊", "感悟"],
            "weather": weather,
            "day_period": "afternoon",
            "location": poi,
            "temperature": temp,
            "favorite": i in [1, 2, 3, 5, 9, 11],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 6: 学习备考与穷游清单 (5 条) - Ground Truth: original
    # =========================================================================
    todo_data = [
        ("大二下学期期末通关复习 Checklist：\n- [x] 高等数学：刷完近三年真题与期末重点习题集\n- [x] 大学物理：整理电磁学与光学公式手抄卡片\n- [ ] 数据结构与算法：手写红黑树与快速排序伪代码\n- [ ] 近现代史纲要：背诵论述题核心考点框架\n期末不挂科，暑假才能安心出去浪！——小舟", "小舟", "复习备忘"),
        ("大学英语六级冲刺两周计划表：\n- [x] 每天背诵四十分钟核心词汇（星火核心词库）\n- [x] 精听真题听力两套并跟读长对话\n- [ ] 总结写作模板与常用论据高分句式\n- [ ] 计时模拟考一套完整试卷控制答题节奏", "小舟", "打卡清单"),
        ("暑假西北穷游大环线背包行李清单：\n- [x] 身份证、学生证（景区半价神仙卡）\n- [x] 防晒霜SPF50+、墨镜与宽檐防晒帽\n- [x] 便携洗漱包、快干毛巾与隔脏睡袋内胆\n- [ ] 充电宝两万毫安（符合民航标准）\n- [ ] 肠胃药、晕车贴与防水创可贴\n- [ ] 胶卷相机与两卷柯达金200", "小舟", "行李清单"),
        ("本周课外阅读与观影待办：\n- [x] 读完毛姆《月亮与六便士》前十二章\n- [x] 重温新海诚《言叶之庭》\n- [ ] 整理苏轼词集里写雨天的五首佳作\n- [ ] 整理近期旅行随笔并挑选九张图配文", None, "待办清单"),
        ("开学宿舍生活用品采购清单：\n- [x] 床头挂篮、宿舍强光护眼台灯\n- [x] 降噪耳塞（拯救室友呼噜声神器）\n- [x] 不锈钢泡面大汤碗配筷勺套装\n- [ ] 宿舍门后粘钩与除湿袋十包", "小舟", "采购清单"),
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
            "date": days_ago(i * 5 + 3, hour=10),
            "source_author": author or "",
            "source_work": work or "",
            "tags": ["待办清单", "学生日常", "规划"],
            "weather": "clear",
            "day_period": "morning",
            "location": "学生公寓",
            "temperature": "20°C",
            "favorite": i in [1, 3],
            "type_ground_truth": "original"
        })

    return notes

# -----------------------------------------------------------------------------
# 归属算法实现（匹配 ThoughtEcho 核心判定规则）
# -----------------------------------------------------------------------------
def legacy_classify_attribution(note, nickname=""):
    author = (note.get("source_author") or "").strip()
    work = (note.get("source_work") or "").strip()
    source = (note.get("source") or "").strip()

    has_attr = bool(author or work or source)
    if not has_attr:
        return "original"

    self_keywords = {"我", "自己", "本人", "自作", "原创", "自留地", "笔者", "作者", "me", "myself", "i", "self", "original"}
    clean_author = author.lstrip("—–-—―").replace("作者：", "").replace("作者:", "").strip().lower()

    if clean_author in self_keywords:
        return "original"
    if nickname and clean_author == nickname.lower():
        return "original"

    self_source = {"日记", "随笔", "随手记", "我的日记", "思考", "随想", "自留地", "diary", "journal", "notes", "memo"}
    if work.lower() in self_source or source.lower() in self_source:
        if not author:
            return "original"

    return "excerpt"

def is_builtin_personal_work(work, author=""):
    if not work:
        return False
    w = work.lstrip("—–-—―").replace("作者：", "").replace("作者:", "").strip().lower()
    if not w:
        return False
    if author and author.lower() in w:
        return True
    self_suffixes = [
        "日记", "随笔", "手记", "札记", "笔记", "杂记", "杂感", "随感", "自述", "自语",
        "心迹", "备忘", "碎碎念", "清单", "复盘", "手账", "行记", "游记", "食记", "采风录",
        "日常", "手稿", "手绘", "备忘录", "打卡", "diary", "journal", "notes", "memo"
    ]
    if any(w.endswith(s) for s in self_suffixes):
        return True
    personal_prefixes = ["我的", "个人", "日常", "生活", "工作", "学习", "读书", "打卡", "复习"]
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

def infer_aliases_from_notes(notes, nickname=""):
    author_stats = {}
    self_keywords = {
        "我", "自己", "本人", "自作", "自撰", "原创", "自留地",
        "笔者", "作者", "余", "吾", "愚", "me", "myself", "i", "self", "author", "original"
    }
    for n in notes:
        author = (n.get("source_author") or "").strip()
        if not author:
            continue
        clean = author.lstrip("—–-—―").replace("作者：", "").replace("作者:", "").strip()
        if not clean or clean.lower() in self_keywords or (nickname and clean.lower() == nickname.lower()):
            continue

        work = (n.get("source_work") or "").strip()
        is_personal = bool(work and is_builtin_personal_work(work, clean))
        has_external_work = bool(work and not is_personal)
        content = n.get("content", "")
        has_signature = (
            f"——{clean}" in content or
            f"—{clean}" in content or
            f"--{clean}" in content or
            f"-{clean}" in content or
            f"@{clean}" in content
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

def optimized_classify_attribution(note, nickname="", inferred_aliases=None):
    author = (note.get("source_author") or "").strip()
    work = (note.get("source_work") or "").strip()
    source = (note.get("source") or "").strip()

    has_attr = bool(author or work or source)
    if not has_attr:
        return "original"

    clean_author = author.lstrip("—–-—―").replace("作者：", "").replace("作者:", "").strip()

    self_keywords = {
        "我", "自己", "本人", "自作", "自撰", "原创", "自述", "自留地",
        "笔者", "作者", "余", "吾", "愚", "me", "myself", "i", "self", "author", "original"
    }
    if clean_author.lower() in self_keywords:
        return "original"
    if nickname and clean_author.lower() == nickname.lower():
        return "original"
    if inferred_aliases and clean_author in inferred_aliases:
        return "original"

    if author:
        return "excerpt"

    clean_source = source.lstrip("—–-—―").replace("作者：", "").replace("作者:", "").strip()
    clean_work = work.lstrip("—–-—―").replace("作者：", "").replace("作者:", "").strip()
    if is_builtin_personal_work(clean_source) or is_builtin_personal_work(clean_work):
        return "original"

    for kw in ["随笔", "日记", "手记", "札记", "笔记", "杂记", "杂感", "随感", "自述", "自语", "心迹", "备忘", "碎碎念", "清单", "复盘", "手账", "行记"]:
        if clean_source.endswith(kw) and len(clean_source) > len(kw):
            prefix = clean_source[:-len(kw)].strip()
            if (inferred_aliases and prefix in inferred_aliases) or (nickname and prefix.lower() == nickname.lower()) or prefix.lower() in self_keywords:
                return "original"
        if clean_work.endswith(kw) and len(clean_work) > len(kw):
            prefix = clean_work[:-len(kw)].strip()
            if (inferred_aliases and prefix in inferred_aliases) or (nickname and prefix.lower() == nickname.lower()) or prefix.lower() in self_keywords:
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
                    print(f"⚠️ [{model_name}] 网络请求异常 (attempt {attempt+1}/{max_retries}): {e}")
                    time.sleep(backoff)
                    backoff *= 1.5

            print(f"🔄 模型 {model_name} 额度受限或不可用，自动降级至备选模型...")

        return {"data": None, "model": None, "latency": 0, "error": "所有备选模型均不可用或超额"}

# -----------------------------------------------------------------------------
# 学生用户实机场景基准评测
# -----------------------------------------------------------------------------
def run_benchmark():
    print("=" * 80)
    print("🚀 开始执行 ThoughtEcho 第三模拟用户（小舟·在读大学生）高拟真基准评测")
    print("=" * 80)

    notes = generate_student_notes()
    print(f"📊 已生成小舟高保真拟真笔记总数: {len(notes)} 篇")
    type_counts = {}
    for n in notes:
        cat = n["id"].split("-")[0]
        type_counts[cat] = type_counts.get(cat, 0) + 1
    print(f"   - 校园瞬间与碎碎念 (campus): {type_counts.get('campus', 0)} 篇")
    print(f"   - 课外名著精选摘录 (book): {type_counts.get('book', 0)} 篇")
    print(f"   - 古诗词与古典名篇 (poem): {type_counts.get('poem', 0)} 篇")
    print(f"   - 听歌歌词与日漫台词 (art): {type_counts.get('art', 0)} 篇")
    print(f"   - 假期旅游与应景诗文 (travel): {type_counts.get('travel', 0)} 篇")
    print(f"   - 备考与生活清单待办 (todo): {type_counts.get('todo', 0)} 篇")

    # 1. 归属算法准确率评测
    print("\n" + "-" * 80)
    print("🔬 [评测维度 1]: 未设昵称时自签名笔名（小舟）归属识别准确率对比")
    print("-" * 80)

    inferred_aliases = infer_aliases_from_notes(notes, nickname="")
    print(f"💡 自动推断的用户自签名笔名别名集合: {inferred_aliases}")

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

    print(f"❌ 修复前 (Legacy) 归属准确率: {legacy_correct}/{len(notes)} ({leg_acc:.1f}%)")
    print(f"   误判为摘录的原创笔记数: {legacy_false_excerpts} 篇 (将「小舟」署名的随笔/行记/碎碎念误判为外部作者)")
    print(f"✅ 修复后 (Optimized) 归属准确率: {optimized_correct}/{len(notes)} ({opt_acc:.1f}%)")
    print(f"   误判为摘录的原创笔记数: {optimized_false_excerpts} 篇")

    # 2. Dreaming 采样纯度评估
    print("\n" + "-" * 80)
    print("🔬 [评测维度 2]: Dreaming 采样池隔离纯度度量 (Voice vs Taste)")
    print("-" * 80)

    opt_originals = [n for n in notes if optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases) == "original"]
    opt_excerpts = [n for n in notes if optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases) == "excerpt"]

    student_in_taste = [n for n in opt_excerpts if n.get("type_ground_truth") == "original"]
    opt_purity = (100.0 - len(student_in_taste) / len(opt_excerpts) * 100) if opt_excerpts else 0.0

    print(f"📌 原创池总数: {len(opt_originals)} 篇 (全量保留为文风 Voice 归纳基准)")
    print(f"📌 摘录池总数: {len(opt_excerpts)} 篇 (全量保留为品味 Taste 归纳基准)")
    print(f"🛡️ 摘录品味池受「小舟」原创污染篇数: {len(student_in_taste)} 篇 (纯净度: {opt_purity:.1f}%)")

    # 3. 实机 LLM 评测
    if not API_KEY:
        print("\n⚠️ 未检测到有效 GEMINI_API_KEY，跳过实机 LLM 评测。")
        return

    print("\n" + "-" * 80)
    print("🔬 [评测维度 3]: 实机 Gemini 模型评测（学生画像注入后的共鸣、品味与记忆自洽性）")
    print("-" * 80)

    client = ResilientGeminiClient(API_KEY, BASE_URL, PREFERRED_MODELS)

    student_profile = (
        "<user_profile>\n"
        "以下是你在过往对话中记下的用户偏好，仅描述该怎么回应这个用户：\n"
        "- [称呼·用户填写] 称呼用户为「小舟」\n"
        "- [身份·观察推断] 大二在读工科/文理交叉学生，日常穿梭于阶梯教室、图书馆、操场与学生公寓\n"
        "- [文风·3天前] 偏好真实细腻的青春校园白描与真挚碎碎念，善于抓取生活微小细节（如阳光微尘、生煎包的脆底、雨天单车、耳机风声），语言轻快真诚，偶尔流露对未来的迷茫与热爱，避免说教爹味\n"
        "- [品味·3天前] 偏好经典文学（王小波、毛姆、史铁生、刘慈欣）、豁达宋词唐诗（苏轼《定风波》、杜甫《望岳》、李清照）、华语流行音乐（周杰伦、五月天、朴树）与新海诚/宫崎骏的唯美治愈动漫台词\n"
        "- [偏好·5天前] 喜欢穷游背包旅行（去过泰山日出、西湖烟雨、青海湖骑行、宏村），出行时常结合古诗词借景抒情，喜欢操场夜跑、吃二食堂生煎包与淘旧书\n"
        "- [近况·1天前] 最近处于期末周高数与大学物理复习备考中，经常清晨去图书馆抢座，在阳台看橘色晚霞，复习之余计划暑假穷游\n"
        "</user_profile>"
    )

    test_cases = [
        {
            "id": "student_sc1_late_night_anxiety",
            "title": "场景 1: 深夜自习室树洞（期末焦虑倾诉与共情）",
            "prompt": "刚从图书馆自习出来，高数真题错了一大半，感觉怎么复习都抓不住重点，有点心烦意乱又很迷茫，不知道这么卷到底为了什么。",
            "expect": ["高数", "小舟", "图书馆", "慢慢来", "休息"]
        },
        {
            "id": "student_sc2_travel_reflection",
            "title": "场景 2: 旅游应景随笔（泰山日出或西湖烟雨）",
            "prompt": "我想整理一下之前去泰山看日出和西湖看烟雨的几张照片发朋友圈，帮我写一段两百字左右的配文随笔，自然带一点古诗词的意境，别太矫情。",
            "expect": ["泰山", "西湖", "云海", "烟雨", "诗"]
        },
        {
            "id": "student_sc3_recommendation",
            "title": "场景 3: 课外阅读与音乐推荐（契合王小波/新海诚/周杰伦审美）",
            "prompt": "复习累了想在睡前听一首歌或者读一篇短篇，有没有那种像王小波那样有趣、或者像新海诚那样细腻温柔的作品推荐？",
            "expect": ["王小波", "温柔", "细腻", "作品", "浪漫"]
        },
        {
            "id": "student_sc4_recent_continuity",
            "title": "场景 4: 近况感知与学生身份连续性",
            "prompt": "今天总算考完一科，脑子嗡嗡的，你还记得我最近都在忙些什么、又念叨过想去哪儿吗？",
            "expect": ["高数", "图书馆", "暑假", "旅行", "生煎", "晚霞"]
        }
    ]

    case_results = []

    for tc in test_cases:
        print(f"\n📝 正在执行: {tc['title']}")
        system_prompt = (
            "你是心迹（ThoughtEcho）笔记应用的 Thoughter AI 伴侣。"
            "平等、温和、青春、懂学生的苦乐，严禁长辈式空洞说教，自然融入对话。"
        )
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": student_profile},
            {"role": "user", "content": tc["prompt"]}
        ]

        res = client.complete(messages, temperature=0.3)
        if res["error"]:
            print(f"❌ 请求失败: {res['error']}")
            case_results.append({"id": tc["id"], "success": False, "matched": 0, "total": len(tc["expect"])})
            continue

        reply = res["data"]["choices"][0]["message"]["content"]
        active_model = res["model"]
        expected_items = tc["expect"]
        matched_items = [item for item in expected_items if item.lower() in reply.lower()]
        passed_expect = len(matched_items) >= max(1, int(len(expected_items) * 0.4))
        case_success = bool(reply) and passed_expect

        print(f"🤖 [模型: {active_model} | 耗时: {res['latency']:.2f}s]:\n{reply[:260]}...\n")
        print(f"📋 [预期核验]: 匹配 {len(matched_items)}/{len(expected_items)} ({', '.join(matched_items)}) -> {'通过' if case_success else '未达标'}\n")
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
    print("🎯 小舟（在读大学生）基准测试综合度量汇总")
    print("=" * 80)
    print(f"1. 归属辨析准确率: 从 {leg_acc:.1f}% 提升至 {opt_acc:.1f}% (+{opt_acc-leg_acc:.1f}%)")
    print(f"2. Dreaming 采样纯度: 原创 Voice 池 {len(opt_originals)} 篇，摘录 Taste 池小舟污染 {len(student_in_taste)} 篇 (纯净度: {opt_purity:.1f}%)")
    print(f"3. 场景评测通过率: {successful_cases}/{total_cases} ({case_success_rate:.1f}%)")
    print("=" * 80)

if __name__ == "__main__":
    run_benchmark()
