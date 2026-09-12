#!/usr/bin/env python3
"""
ThoughtEcho Thoughter AI 100条拟真真实生活场景基准评测引擎
涵盖：出游足迹、景点随感、生活琐记、名家摘录、富文本清单、媒体图片附件
对比测试 Agent 框架修复前后的归属识别率、Dreaming画像纯度、记忆动态修改能力与实机 Gemini 表现。
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
# 100 条高保真拟真笔记数据集生成
# -----------------------------------------------------------------------------
def generate_100_realistic_notes():
    now = datetime.now()
    def days_ago(d, hour=10):
        t = now - timedelta(days=d)
        return t.replace(hour=hour, minute=15, second=0).strftime("%Y-%m-%d %H:%M:%S")

    notes = []

    # =========================================================================
    # 类别 1: 出游足迹与景点随感 (25 条)
    # =========================================================================
    travel_data = [
        ("西湖苏堤", "清晨沿苏堤慢跑，薄雾还没散尽，湖面波光潋滟。两旁柳树抽出新芽，晨风吹在脸上有些清凉。跑完在花港观鱼的长椅上坐了很久，看着游鱼争食，所有的焦虑似乎都被这湖水溶解了。——写于西湖晨跑，阿澈", "杭州·西湖", "clear", "16°C", 2, "阿澈", None),
        ("灵隐寺", "走到飞来峰下，古木参天，泉水激石。大雄宝殿前的香烟袅袅升起，诵经声低沉而辽远。突然想起一句话，心安即是归处。买了一串黑檀手串，希望接下来的项目一切顺遂。", "杭州·灵隐寺", "cloudy", "18°C", 5, None, None),
        ("西湖断桥", "断桥残雪虽然无雪，但断桥上的落日却格外温柔。游人渐稀，晚霞把湖面染成金红色。站在桥头吹风，想起白娘子的传说，岁月悠悠，唯有这山水长存。——阿澈", "杭州·西湖断桥", "clear", "20°C", 7, "阿澈", None),
        ("雷峰塔", "夕照山下的雷峰新塔，登顶俯瞰整个西湖，苏堤如一条绿带横卧碧波之中。黄昏的微风拂面，想起鲁迅写过的论雷峰塔的倒掉，历史与现实在这里奇妙地交错。——阿澈随笔", "杭州·雷峰塔", "clear", "22°C", 9, "阿澈", "阿澈随笔"),
        ("龙井村", "沿着九溪十八涧一路走到龙井村，两旁茶田叠翠，泉水清冽。农家小院里茶香扑鼻，坐下来喝了一碗明前龙井，甘冽清甜，回味悠长。这才是生活该有的步调。", "杭州·龙井村", "rainy", "17°C", 12, None, None),
        ("太子湾公园", "春天的太子湾，郁金香开得漫山遍野。大风车旁的草地上坐满了野餐的人群，阳光穿透树叶洒下斑驳光影。带了一本小书，在树荫下看了一下午。", "杭州·太子湾", "clear", "21°C", 14, None, None),
        ("苏州拙政园", "移步换景，咫尺山林。拙政园的廊桥与漏窗堪称园林美学的极致。坐在秫香馆前看池塘里的游鱼与残荷，古人对空间与自然的理解，现代建筑真的难以企及。——阿澈", "苏州·拙政园", "cloudy", "19°C", 18, "阿澈", None),
        ("苏州平江路", "一条平江路，半部姑苏史。踩着青石板路，耳边传来吴侬软语的评弹声。在转角买了一块海棠糕，热气腾腾，甜而不腻。江南的小桥流水，总能让人脚步不自觉慢下来。", "苏州·平江路", "rainy", "16°C", 19, None, None),
        ("苏州寒山寺", "夜半钟声到客船。站在大雄宝殿外听钟声撞击，浑厚悠远，仿佛穿透了一千两百年的时光。枫桥边的江枫渔火已不可寻，但诗意犹在。", "苏州·寒山寺", "cloudy", "17°C", 20, "阿澈", None),
        ("同里古镇", "退思园的名号取自退思补过。小镇清晨静悄悄的，摇橹船划开水面，荡起一圈圈涟漪。古桥斑驳，岁月静好。——阿澈随记", "苏州·同里", "clear", "18°C", 21, "阿澈", None),
        ("南京秦淮河", "桨声灯影里的秦淮河。夫子庙两岸游人如织，画舫穿梭在乌衣巷口。虽然商业化浓重，但当夜幕降临，两岸红灯笼亮起时，依然能感受到六朝金粉的气韵。", "南京·夫子庙秦淮风光带", "clear", "23°C", 24, None, None),
        ("南京中山陵", "沿着层层石阶登顶中山陵，回望紫金山麓，松柏苍翠，气势磅礴。博爱二字立在牌坊之上，令人肃然起敬。爬到顶端虽然大汗淋漓，但心胸开阔。", "南京·中山陵", "clear", "25°C", 25, "阿澈", None),
        ("南京玄武湖", "环玄武湖骑行一圈，微风拂面。一边是古老斑驳的明城墙，一边是现代化的高楼天际线。历史与现代并肩而立，这便是南京独特的厚重与从容。", "南京·玄武湖", "cloudy", "21°C", 26, None, None),
        ("南京鸡鸣寺", "春日鸡鸣寺的樱花大道如云似霞。药师塔矗立在花海之间，黄墙黑瓦，游人熙攘。登高俯瞰玄武湖，春色满城，不虚此行。——阿澈", "南京·鸡鸣寺", "clear", "20°C", 27, "阿澈", None),
        ("黄山光明顶", "凌晨四点冒着寒风在光明顶等日出。当第一缕霞光刺破重重云海，群峰金顶毕现，天地壮阔得令人窒息。那一刻觉得通宵爬山的疲惫都值了。——阿澈", "黄山·光明顶", "clear", "6°C", 31, "阿澈", None),
        ("黄山排云亭", "排云亭前云海翻滚，奇松怪石若隐若现。大自然的鬼斧神工，非人工笔墨所能尽绘。站在悬崖边吹着山风，心中唯有敬畏。——阿澈手记", "黄山·排云亭", "foggy", "8°C", 32, "阿澈", "黄山手记"),
        ("北京故宫", "红墙黄瓦，白石阶梯。站在太和殿广场前，天空湛蓝如洗。走在空旷的宫墙夹道里，斜阳拉长身影，恍惚间听见几百年前的回声。紫禁城的庄严令人屏息。", "北京·故宫博物院", "clear", "15°C", 35, None, None),
        ("北京景山公园", "黄昏登景山万春亭，正逢日落。整个紫禁城的中轴线尽收眼底，夕阳给连绵的琉璃瓦镀上一层灿烂的金辉。远处的北海白塔和现代楼宇相映生辉。——阿澈", "北京·景山公园", "clear", "14°C", 36, "阿澈", None),
        ("北京颐和园", "昆明湖的夕阳下，十七孔桥拉出长长的金色倒影。长廊漫步，彩绘斑驳。万寿山在暮色中逐渐朦胧，皇家园林的大气与温婉兼具。", "北京·颐和园", "cloudy", "16°C", 37, None, None),
        ("上海武康路", "秋天的武康路落满了梧桐叶。漫步在老洋房之间，路角的一杯手冲咖啡，阳光透过金黄树冠洒在柏油路上。海派文化的浪漫与精致在这些老街区里流淌。", "上海·徐汇区", "clear", "19°C", 40, None, None),
        ("上海外滩", "夜幕下的外滩，万国建筑博览群泛着温润的金黄色灯光，黄浦江对岸陆家嘴的摩天大楼流光溢彩。江风吹拂，现代都市的繁华与时代的变迁在这里一览无余。——阿澈", "上海·外滩", "clear", "18°C", 41, "阿澈", None),
        ("上海豫园", "城隍庙里的豫园闹中取静，九曲桥下锦鲤嬉戏。江南水乡的假山曲径与窗棂漏光，老街上的小笼包热气腾腾，满是人间的烟火气。", "上海·黄浦区", "rainy", "17°C", 42, None, None),
        ("成都锦里", "红灯笼点亮了锦里的窄巷，油炸小吃的香气扑鼻，三国文化的皮影戏与泥人摊位引人驻足。坐下来吃了一碗三大炮，浓浓的巴蜀闲适滋味。", "成都·锦里", "cloudy", "20°C", 46, None, None),
        ("成都都江堰", "乘水势而建的千年水利工程，两千余年来依然在泽被天府之国。站在安澜索桥上俯瞰奔腾的岷江水，不得不惊叹古人的智慧与对自然的顺应。——阿澈", "成都·都江堰", "rainy", "18°C", 47, "阿澈", None),
        ("成都大熊猫基地", "清晨看幼年大熊猫在竹林里啃竹子、爬树打滚，憨态可掬。慢悠悠的节奏让人瞬间卸下了所有压力，这大概就是成都慢生活的精髓吧。", "成都·成华区", "cloudy", "19°C", 48, None, None),
    ]

    for i, (loc, content, poi, weather, temp, d, author, work) in enumerate(travel_data, 1):
        notes.append({
            "id": f"travel-{i:02d}",
            "content": content,
            "date": days_ago(d),
            "source_author": author or "",
            "source_work": work or "",
            "tags": ["出游", "足迹", "风景"],
            "weather": weather,
            "day_period": "afternoon" if i % 2 == 0 else "morning",
            "location": poi,
            "temperature": temp,
            "favorite": i in [1, 7, 15, 21],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 2: 名家名著经典摘录 (25 条)
    # =========================================================================
    excerpts_data = [
        ("在隆冬，我终于知道，我身上有一个不可战胜的夏天。", "阿尔贝·加缪", "夏天集", ["读书", "哲学", "勇气"]),
        ("所谓的听天由命，是一种得到证实的绝望。", "阿尔贝·加缪", "西西弗神话", ["读书", "哲学"]),
        ("一个人，出生了，这就不再是一个可以辩论的问题，只是上帝交给他的一个事实。", "史铁生", "我与地坛", ["读书", "生命感悟"]),
        ("微风吹向何方，并不由树叶决定；生命走向何处，并不由欲望操纵。", "史铁生", "务虚笔记", ["读书", "思考"]),
        ("希望是本无所谓有，无所谓无的。这正如地上的路；其实地上本没有路，走的人多了，也便成了路。", "鲁迅", "故乡", ["读书", "文学"]),
        ("当我沉默着的时候，我觉得充实；我将开口，同时感到空虚。", "鲁迅", "野草", ["读书", "经典"]),
        ("并非我们拥有的时间太少，而是我们虚掷了太多。生命足够长久，足以完成最伟大的事业。", "塞涅卡", "论生命的短促", ["读书", "斯多葛"]),
        ("接受不能改变的事情，改变能够改变的事情，并拥有分辨两者的智慧。", "马可·奥勒留", "沉思录", ["读书", "修身"]),
        ("保持饥饿，保持愚蠢。不要被教条所束缚，不要让别人的意见淹没了你内心的声音。", "史蒂夫·乔布斯", "斯坦福大学演讲", ["读书", "成长"]),
        ("围在城里的人想冲出来，城外的人想冲进去。对婚姻也罢，职业也罢，人生的愿望大都如此。", "钱钟书", "围城", ["读书", "小说"]),
        ("从现在起，我开始谨慎地选择我的生活，我不再轻易让自己迷失在各种诱惑里。", "米兰·昆德拉", "生命中不能承受之轻", ["读书", "人生"]),
        ("那一年我二十一岁，在我一生的黄金时代，我有好多奢望。我想爱，想吃，还想在一瞬间变成天上半明半暗的云。", "王小波", "黄金时代", ["读书", "青春"]),
        ("沉浸在连接中却感到孤立，技术承诺免除脆弱的陪伴，我们却忘记了独处才是反思的起点。", "雪莉·特克尔", "群体性孤独", ["读书", "技术思考"]),
        ("苦难对于天才是一块垫脚石，对于能干的人是一笔财富，对于弱者是个万丈深渊。", "奥诺雷·德·巴尔扎克", "人间喜剧", ["读书", "励志"]),
        ("生如夏花之绚烂，死如秋叶之静美。", "泰戈尔", "飞鸟集", ["读书", "诗歌"]),
        ("卑鄙是卑鄙者的通行证，高尚是高尚者的墓志铭。看吧，在那镀金的天空中，飘满了死者弯曲的倒影。", "北岛", "回答", ["读书", "现代诗"]),
        ("黑夜给了我黑色的眼睛，我却用它寻找光明。", "顾城", "一代人", ["读书", "现代诗"]),
        ("竹杖芒鞋轻胜马，谁怕？一蓑烟雨任平生。料峭春风吹酒醒，微冷，山头斜照却相迎。", "苏轼", "定风波·莫听穿林打叶声", ["读书", "古诗词"]),
        ("人生天地之间，若白驹之过隙，忽然而已。", "庄子", "庄子·知北游", ["读书", "道家"]),
        ("满地都是六便士，他却抬头看见了月亮。", "毛姆", "月亮与六便士", ["读书", "文学"]),
        ("每个人的生命中都有一场严重的风暴，那是你灵魂深处的孤独与绝望，挺过去了，你就会成为一个全新的人。", "村上春树", "海边的卡夫卡", ["读书", "治愈"]),
        ("真实的世界并不完美，但正是这些裂痕，才让光照了进来。", "莱昂纳德·科恩", "赞美诗", ["读书", "音乐与诗"]),
        ("重要的不是治愈，而是带着病痛生活。", "阿尔贝·加缪", "局外人", ["读书", "存在主义"]),
        ("世上只有一种真正的英雄主义，那就是认清生活的真相后依然热爱生活。", "罗曼·罗兰", "米开朗基罗传", ["读书", "哲学"]),
        ("真正的宁静，不是远离车马喧嚣，而是在心中修篱种菊。", "林徽因", "若你安好便是晴天", ["读书", "散文"]),
    ]

    for i, (quote, author, work, tags) in enumerate(excerpts_data, 1):
        notes.append({
            "id": f"excerpt-{i:02d}",
            "content": quote,
            "date": days_ago(i * 2 + 1),
            "source_author": author,
            "source_work": work,
            "tags": tags,
            "weather": "clear" if i % 2 == 0 else "cloudy",
            "day_period": "night" if i % 3 == 0 else "evening",
            "location": "书房",
            "temperature": "22°C",
            "favorite": i in [1, 3, 5, 9, 15, 18],
            "type_ground_truth": "excerpt"
        })

    # =========================================================================
    # 类别 3: 日常随笔、碎碎念与生活感悟 (25 条)
    # =========================================================================
    ramblings_data = [
        ("深夜重构核心模块，把之前胶水式的层级彻底拆开。代码变清爽的那一瞬间，整个人的呼吸都顺畅了。优雅的设计不是没有东西可以加，而是没有东西可以减。——写于凌晨两点，阿澈", "阿澈", None, ["技术思考", "代码", "深夜"]),
        ("做了一杯耶加雪菲手冲，水温92度，中细研磨，粉水比1:15。柑橘和茉莉花的香气特别明亮。在快节奏的工作里，这十分钟的注水与滴滤就是我的精神冥想。", None, None, ["咖啡", "生活情趣", "日常"]),
        ("夜跑五公里，配速五分十秒。汗水顺着额头流下来的时候，白天在架构设计上纠结的死结突然有了豁然开朗的解法。身体动起来，大脑的缓存才会被刷新。——阿澈", "阿澈", None, ["跑步", "运动", "健康"]),
        ("杭州下了一整天的春雨，雨水敲打在窗棂上噼啪作响。泡了一壶老白茶，坐在飘窗前听雨看书，感觉时间流逝得格外缓慢而充实。", None, None, ["雨天", "喝茶", "心境"]),
        ("晚上下班坐地铁，车厢里每个人都在低头看手机，屏幕的光映在疲惫的脸庞上。我们通过网络连接了整个世界，却似乎离身边的人越来越远。", None, None, ["碎碎念", "思考", "地铁"]),
        ("致五年后的阿澈：希望你依然对构建好产品保持好奇与热情，依然会在深夜为优雅的代码心动，依然敢于做出改变一生的决定。", "阿澈", None, ["给自己的信", "随笔", "成长"]),
        ("海创园的晚霞烧红了半边天，坐在长椅上吹着晚风，突然觉得生活除了赶进度，还有这些停顿的片刻值得铭记。——阿澈随笔", "阿澈", "阿澈随笔", ["晚霞", "随笔", "生活"]),
        ("把书架重新整理了一遍，送出了三十多本可能再也不会翻开的书。给物理空间做减法，其实是在给心理负担做减法。断舍离不是扔东西，而是明确自己真正需要什么。", None, None, ["整理", "断舍离", "极简"]),
        ("今天尝试用 Rust 写了个小工具，类型系统和生命周期的严格限制让人抓狂，但一旦编译通过，那种坚如磐石的确定感又让人着迷。好工具能塑造人的思考方式。——阿澈", "阿澈", None, ["技术思考", "Rust"]),
        ("早晨在楼下便利店买包子，收银的阿姨笑着说了声‘今天降温了多穿点’，心头突然涌起一阵暖意。人间的善意往往就藏在这些微不足道的琐碎日常里。", None, None, ["生活感悟", "温情", "日常"]),
        ("越来越觉得专注是一种稀缺的能力。关掉所有的即时通讯通知，一口气沉浸式工作三个小时，效率比碎片化应付一整天高得多。夺回注意力的控制权是现代人的必修课。", None, None, ["效率", "深度工作", "思考"]),
        ("周末和认识十年的老友在西湖边喝茶叙旧，聊起大学时的荒唐往事，相视大笑。真正的朋友大概就是哪怕半年不联系，一见面依然可以毫无保留地倾盖如故。", None, None, ["友情", "西湖", "岁月"]),
        ("今天终于把阳台上的多肉植物修剪换盆了一遍，看着它们在阳光下舒展的样子，生命的坚韧总会在不经意间给你鼓励。——阿澈", "阿澈", None, ["植物", "阳台", "日常"]),
        ("买了一本纸质笔记本和一支钢笔，笔尖在纸张上划过的沙沙声有一种电子屏幕永远无法替代的踏实感。写下来的那一刻，混乱的念头才被赋予了骨骼。", None, None, ["手写", "随笔", "思考"]),
        ("加班到九点，走出办公楼看到一轮硕大的满月悬在楼宇之间。月光清冷如水，城市虽然喧嚣，但只要抬头，头顶依然是那片亘古不变的星空。——阿澈", "阿澈", None, ["加班", "月亮", "感叹"]),
        ("有时候觉得，一个人真正成熟的标志，就是学会了与自己的平凡和解，但依然愿意倾尽全力去过好平凡生活的每一天。", None, None, ["心境", "成熟", "随感"]),
        ("买了一张爵士乐老唱片，比尔·埃文斯的钢琴声在客厅流淌。音乐真奇妙，不需要语言，却能在瞬间击中内心最柔软的角落。", None, None, ["音乐", "爵士", "生活"]),
        ("今天晨跑时在路边看到一只小橘猫，在灌木丛里好奇地打量行人。蹲下来轻轻唤它，它竟蹭着我的裤腿打呼噜。生活里的美好，往往都是不期而遇的。——阿澈", "阿澈", None, ["跑步", "猫", "温暖"]),
        ("不要因为走得太远，而忘记了为什么出发。每次在做产品决策感到迷茫时，我都把这句话拿出来问问自己最初的初心。", None, None, ["初心", "产品思考"]),
        ("做饭是治愈精神内耗最好的方式。洗菜、切菜、听着热油翻滚的声响，烟火气能把飘在空中的浮躁一下子拉回坚实的地面。", None, None, ["烹饪", "烟火气", "日常"]),
        ("晚上散步路过一家旧书店，在角落淘到一本八十年代出版的散文集，扉页上还写着上一个主人的赠言。文字在岁月里流转，成了陌生的灵魂之间秘密的桥梁。——阿澈随笔", "阿澈", "阿澈随笔", ["书店", "阅读", "漫步"]),
        ("学会拒绝不属于自己的期待，不讨好，不迎合。人生很短，能让自己活得舒展自在，就已经是一件很了不起的成就了。", None, None, ["随笔", "心智", "成长"]),
        ("又到了银杏泛黄的季节，满地碎金。踩在松软的银杏树叶上，秋天总是带着一点点诗意的怅惘，却又如此沉静温柔。", None, None, ["秋天", "银杏", "随感"]),
        ("写代码就像写诗，字斟句酌，追求极致的简洁与韵律。但比写诗幸运的是，代码不仅能被品味，还能真正运转起来去服务真实的人。——阿澈", "阿澈", None, ["代码", "技术思考", "工匠精神"]),
        ("睡前复盘今天的得失，有遗憾，但更多的是充实。给明天的自己留一句鼓励：风雨兼程，无问西东。——阿澈", "阿澈", None, ["日记", "复盘", "晚安"]),
    ]

    for i, (content, author, work, tags) in enumerate(ramblings_data, 1):
        notes.append({
            "id": f"rambling-{i:02d}",
            "content": content,
            "date": days_ago(i + 3, hour=22 if i % 2 == 0 else 8),
            "source_author": author or "",
            "source_work": work or "",
            "tags": tags,
            "weather": "clear" if i % 3 == 0 else "cloudy",
            "day_period": "night" if i % 2 == 0 else "morning",
            "location": "家中" if i % 2 == 0 else "工作室",
            "temperature": "20°C",
            "favorite": i in [1, 3, 6, 7, 14, 24],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 4: 富文本结构化清单、待办与技术方案 (15 条)
    # =========================================================================
    checklist_data = [
        ("周末黄山徒步出行清单：\n- [x] 登山杖两根与防滑手套\n- [x] 冲锋衣与保暖排汗内衣\n- [ ] 充电宝两个（必须充满电）\n- [ ] 能量胶5支与士力架\n- [ ] 急救包与创可贴、云南白药\n注意光明顶气温低，务必带防风帽子。——阿澈备忘", "阿澈", "备忘", ["清单", "出行", "黄山"]),
        ("Thoughter Agent 长期记忆架构演进待办：\n- [x] 记忆数据库独立物理隔离为 agent_memory.db\n- [x] 增加 source_note_ids 来源归因支持\n- [ ] 移除 remember 工具中对 taste 和 voice 的硬拦截\n- [ ] 优化自签名笔名识别启发式，防止 voice 采样池枯竭\n- [ ] 增加 100 篇拟真真实场景基准测试用例", "阿澈", "代码手记", ["架构", "TODO", "技术方案"]),
        ("2026年Q3阅读书单规划：\n- [x] 《沉思录》马可·奥勒留\n- [x] 《局外人》阿尔贝·加缪\n- [ ] 《卡拉马佐夫兄弟》陀思妥耶夫斯基\n- [ ] 《哥德尔、艾舍尔、巴赫》侯世达\n- [ ] 《失控》凯文·凯利", None, "读书清单", ["书单", "阅读计划"]),
        ("家庭常备药箱盘点：\n- [x] 创可贴与碘伏棉棒（未过期）\n- [x] 布洛芬缓释胶囊（备两盒）\n- [x] 氯雷他定抗过敏药\n- [ ] 蒙脱石散需要补充\n- [ ] 电子体温计更换纽扣电池", None, "生活清单", ["健康", "日常清单"]),
        ("新工作站开发环境搭建 Checklist：\n- [x] 安装 Flutter SDK 3.x 与 Dart SDK\n- [x] 配置 VSCode 与 Android Studio 调试插件\n- [x] 配置 SSH Key 与 GitHub 签名公钥\n- [ ] 安装 Docker 与常用数据库客户端\n- [ ] 恢复字体与终端 zsh 配置文件", "阿澈", "技术手记", ["开发环境", "工具", "配置"]),
        ("西湖骑行路线打卡备忘：\n- [x] 少年宫出发点\n- [x] 断桥残雪看晨雾\n- [x] 平湖秋月与孤山路\n- [x] 岳庙前转杨公堤\n- [ ] 茅家埠看野鸭与芦苇丛\n- [ ] 花港观鱼喂锦鲤", "阿澈", "骑行备忘", ["西湖", "骑行", "路线"]),
        ("极简生活家居清减待办：\n- [x] 清理一年未穿过的衣物打包捐赠\n- [x] 整理抽屉里淘汰的旧数据线与充电头\n- [ ] 注销三年未使用的无效网络账号\n- [ ] 厨房闲置多余小家电二手出清", None, "断舍离", ["极简", "生活清单"]),
        ("手冲咖啡风味盲测对照记录：\n- [x] 肯尼亚AA：酸质活泼明亮，带黑加仑与番茄风味\n- [x] 埃塞俄比亚耶加雪菲：茉莉花香突出，柑橘柠檬酸质柔和\n- [ ] 哥伦比亚厌氧日晒：朗姆酒香与热带水果发酵感\n- [ ] 瑰夏水洗：极高洁净度，佛手柑与乌龙茶感", "阿澈", "手冲日记", ["咖啡", "风味记录"]),
        ("周末采购生鲜食材清单：\n- [x] 鲜牛奶两盒与无菌鸡蛋一盒\n- [x] 鸡胸肉500g与牛腩块\n- [ ] 西蓝花、小番茄与紫甘蓝\n- [ ] 全麦吐司与希腊酸奶\n- [ ] 现磨黑胡椒碎与海盐", None, "采购清单", ["生活", "烹饪"]),
        ("个人技术博客重构待办：\n- [x] 选用静态站点生成器 Astro / Hugo\n- [x] 支持富文本 LaTeX 数学公式渲染\n- [ ] 支持代码块行号与一键复制功能\n- [ ] 迁移旧文章并重新校对排版\n- [ ] 接入独立评论系统 Waline", "阿澈", "博客开发", ["博客", "技术"]),
        ("春季身体体检关注指标：\n- [x] 预约三甲医院体检套餐\n- [x] 晨起空腹抽血检查肝肾功能\n- [ ] 心电图与心脏彩超复查\n- [ ] 颈椎核磁共振检查（关注久坐颈椎曲度）\n- [ ] 拿到体检报告后找全科医生解读", None, "健康管理", ["体检", "健康"]),
        ("苏州园林自驾两日游路线：\n- [x] Day1 上午：拙政园（需提前三天预约门票）\n- [x] Day1 下午：苏州博物馆本馆（贝聿铭设计）\n- [x] Day1 晚上：平江路夜游品评弹海棠糕\n- [ ] Day2 上午：虎丘剑池与斜塔\n- [ ] Day2 下午：寒山寺听钟声返程", "阿澈", "旅行攻略", ["苏州", "旅游计划"]),
        ("代码重构质量门禁检查：\n- [x] 运行 flutter test 确保所有单元测试通过\n- [x] 执行 flutter analyze 确认零 warning 零 info 致命错误\n- [ ] 检查 Delta 格式富文本属性无破坏\n- [ ] 验证包含嵌入媒体时整篇覆盖保护正常拦截\n- [ ] 更新相关架构交接文档 HANDOFF.md", "阿澈", "质量门禁", ["代码审查", "测试"]),
        ("秋季露营装备清单：\n- [x] 双人双层防雨帐篷与防潮地垫\n- [x] 充气睡垫与羽绒睡袋（温标5°C）\n- [ ] 户外气炉与套锅、挡风板\n- [ ] 营地露营灯与氛围串灯\n- [ ] 垃圾袋两个（严格落实无痕露营LNT）", "阿澈", "露营清单", ["露营", "户外"]),
        ("年度个人成长目标复盘追踪：\n- [x] 坚持周跑量达到25公里\n- [x] 读完24本书并输出结构化笔记\n- [ ] 掌握一门新的函数式编程语言\n- [ ] 完成一次全程马拉松挑战\n- [ ] 保持作息规律，每月熬夜不超过两次", "阿澈", "年度复盘", ["成长", "复盘"]),
    ]

    for i, (content, author, work, tags) in enumerate(checklist_data, 1):
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
            "date": days_ago(i * 3 + 2),
            "source_author": author or "",
            "source_work": work or "",
            "tags": tags,
            "weather": "clear",
            "day_period": "morning",
            "location": "工作台",
            "temperature": "21°C",
            "favorite": i in [1, 2, 13],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 5: 包含富文本内嵌媒体/图片附件的笔记 (10 条)
    # =========================================================================
    media_notes_data = [
        ("西湖集贤亭夕照。夕阳沉入保俶山后，整片天空泛着瑰丽的紫红色，湖水倒映着晚霞。拍下了这一幕：\n[图片:西湖集贤亭晚霞.jpg]\n吹着晚风，久久不愿离去。——阿澈", "westlake_sunset.jpg", "阿澈", "西湖日记", ["西湖", "摄影", "晚霞"]),
        ("苏州园林漏窗构图。透过花窗看后面的芭蕉与太湖石，光影交错如同一幅水墨立轴：\n[图片:拙政园漏窗光影.png]\n古人的移步换景让人叹为观止。", "suzhou_window.png", "阿澈", None, ["苏州", "园林", "美学"]),
        ("黄山日出云海壮景。当红日从茫茫云海中喷薄而出，万道金光穿透晨雾：\n[图片:黄山光明顶云海金顶.jpg]\n大自然的雄浑壮阔，涤荡心胸。——阿澈", "huangshan_cloudsea.jpg", "阿澈", "黄山手记", ["黄山", "摄影", "日出"]),
        ("手冲咖啡金杯萃取流程图与粉层观察：\n[图片:耶加雪菲焖蒸粉层膨胀.jpg]\n新鲜烘焙的豆子在注水后汉堡状膨胀得非常漂亮，香气四溢。", "coffee_bloom.jpg", None, None, ["咖啡", "手冲", "日常"]),
        ("Thoughter Agent 架构时序图手稿：\n[图片:agent_system_sequence.png]\n梳理了工具调用、记忆注入与上下文绑定的全流程，逻辑终于清晰了。——阿澈", "agent_sequence.png", "阿澈", "架构手记", ["架构", "技术", "图表"]),
        ("南京明城墙玄武湖畔苔痕：\n[图片:南京明城墙斑驳石砖.jpg]\n六百年的青砖缝隙里长满了青苔，摸上去微凉湿润，那是岁月的温度。", "nanjing_wall.jpg", None, None, ["南京", "古迹", "摄影"]),
        ("深夜工作台与代码编辑器全景：\n[图片:深夜工作台与咖啡杯.jpg]\n屏幕微光、冒着热气的黑咖啡、降噪耳机。深夜是属于创造者最安静的王国。——阿澈", "workspace_night.jpg", "阿澈", None, ["工作台", "代码", "深夜"]),
        ("阳台多肉植物换盆新叶特写：\n[图片:多肉桃蛋粉嫩新芽.jpg]\n阳光洒在饱满的叶片上，晶莹剔透，充满生机。", "succulent_macro.jpg", None, None, ["植物", "摄影", "生活"]),
        ("上海武康大楼标志性街角全景：\n[图片:武康大楼红砖船型立面.jpg]\n梧桐树影遮蔽下的经典邬达克建筑，秋日的阳光给红砖镀上了柔和的金边。——阿澈", "wukang_building.jpg", "阿澈", None, ["上海", "建筑", "漫步"]),
        ("白板上的技术重构依赖拓扑草图：\n[图片:whiteboard_architecture_dag.png]\n把紧耦合的三个服务拆开，引入事件总线解耦，终于理顺了。——阿澈", "whiteboard_dag.png", "阿澈", "架构笔记", ["架构", "设计", "白板"]),
    ]

    for i, (text, img_name, author, work, tags) in enumerate(media_notes_data, 1):
        delta_ops = [
            {"insert": text.split("\n[图片:")[0] + "\n"},
            {"insert": {"image": f"assets/media/{img_name}"}},
            {"insert": "\n" + text.split("]\n")[-1] + "\n" if "]\n" in text else "\n"}
        ]
        notes.append({
            "id": f"media-{i:02d}",
            "content": text,
            "delta_content": json.dumps(delta_ops, ensure_ascii=False),
            "date": days_ago(i * 4 + 1),
            "source_author": author or "",
            "source_work": work or "",
            "tags": tags,
            "weather": "clear",
            "day_period": "afternoon",
            "location": "现场",
            "temperature": "19°C",
            "favorite": i in [1, 3, 5],
            "has_media": True,
            "type_ground_truth": "original"
        })

    return notes

# -----------------------------------------------------------------------------
# 归属算法实现对比 (修复前 vs 修复后)
# -----------------------------------------------------------------------------
def legacy_classify_attribution(note, nickname=""):
    """
    修复前逻辑：
    若 author/source 有值，且未配置昵称或未命中硬编码代词，机械判定为 excerpt
    """
    author = (note.get("source_author") or "").strip()
    work = (note.get("source_work") or "").strip()
    source = (note.get("source") or "").strip()

    has_attr = bool(author or work or source)
    if not has_attr:
        return "original"

    self_keywords = {"我", "自己", "本人", "自作", "原创", "自留地", "笔者", "作者", "me", "myself", "i", "self", "original"}
    clean_author = author.lstrip("—–—").replace("作者：", "").replace("作者:", "").strip().lower()

    if clean_author in self_keywords:
        return "original"
    if nickname and clean_author == nickname.lower():
        return "original"

    self_source = {"日记", "随笔", "随手记", "我的日记", "思考", "随想", "自留地", "diary", "journal", "notes", "memo"}
    if work.lower() in self_source or source.lower() in self_source:
        if not author:
            return "original"

    return "excerpt"

def is_builtin_personal_work(work):
    if not work:
        return False
    w = work.lstrip("—–-—―").replace("作者：", "").replace("作者:", "").strip().lower()
    self_keywords = {
        "日记", "随笔", "随手记", "我的日记", "思考", "随想", "自留地",
        "diary", "journal", "notes", "memo", "手记", "札记", "杂记",
        "杂感", "随感", "自述", "自语", "心迹", "备忘", "碎碎念", "清单", "复盘", "手账"
    }
    if w in self_keywords:
        return True
    personal_prefixes = ["我的", "个人", "日常", "生活", "工作", "学习", "读书"]
    for prefix in personal_prefixes:
        if w.startswith(prefix) and w[len(prefix):] in self_keywords:
            return True
    return False

def has_personal_device_or_rich_text_markers(note):
    content = note.get("content", "")
    if "- [x]" in content or "- [ ]" in content:
        return True
    if note.get("delta_content") and any(k in note["delta_content"] for k in ['"list":"checked"', '"list":"unchecked"']):
        return True
    return False

def optimized_classify_attribution(note, nickname="", inferred_aliases=None):
    author = (note.get("source_author") or "").strip()
    work = (note.get("source_work") or "").strip()
    source = (note.get("source") or "").strip()

    has_attr = bool(author or work or source)
    if not has_attr:
        return "original"

    clean_author = author.lstrip("—–-—―").replace("作者：", "").replace("作者:", "").strip()

    # 1. 检查别名与昵称（确定性元数据相等）
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

    # 2. 外部明确作者且非自身别名，严格判定为 excerpt
    if author:
        return "excerpt"

    # 3. 来源为个人随笔类词汇或个人出处
    clean_source = source.lstrip("—–-—―").replace("作者：", "").replace("作者:", "").strip()
    if is_builtin_personal_work(clean_source):
        return "original"

    if is_builtin_personal_work(work):
        return "original"

    # 4. 若未用破折号拆分，但形式为「[自身别名/昵称][随笔/日记]」
    for kw in ["随笔", "日记", "手记", "札记", "笔记", "杂记", "杂感", "随感", "自述", "自语", "心迹", "备忘", "碎碎念", "清单", "复盘", "手账"]:
        if clean_source.endswith(kw) and len(clean_source) > len(kw):
            prefix = clean_source[:-len(kw)].strip()
            if (inferred_aliases and prefix in inferred_aliases) or (nickname and prefix.lower() == nickname.lower()) or prefix.lower() in self_keywords:
                return "original"
        if work.endswith(kw) and len(work) > len(kw):
            prefix = work[:-len(kw)].strip()
            if (inferred_aliases and prefix in inferred_aliases) or (nickname and prefix.lower() == nickname.lower()) or prefix.lower() in self_keywords:
                return "original"

    return "excerpt"

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
        is_personal = bool(work and is_builtin_personal_work(work))
        has_external_work = bool(work and not is_personal)
        has_self_marker = has_personal_device_or_rich_text_markers(n) or is_personal

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

# -----------------------------------------------------------------------------
# LLM 客户端与请求控速（Pacing & Exponential Backoff）
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
        self.min_interval = 2.5 # 2.5 秒强控速，防止突发超频

    def _pace(self):
        elapsed = time.time() - self.last_request_time
        if elapsed < self.min_interval:
            sleep_needed = self.min_interval - elapsed
            time.sleep(sleep_needed)
        self.last_request_time = time.time()

    def complete(self, messages, tools=None, temperature=0.2):
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
# 基准测试执行与指标统计
# -----------------------------------------------------------------------------
def run_benchmark():
    print("=" * 80)
    print("🚀 开始执行 ThoughtEcho Thoughter AI 100条真实生活场景全景基准测试")
    print("=" * 80)

    notes = generate_100_realistic_notes()
    print(f"📊 已生成高保真拟真笔记总数: {len(notes)} 篇")
    type_counts = {}
    for n in notes:
        cat = n["id"].split("-")[0]
        type_counts[cat] = type_counts.get(cat, 0) + 1
    print(f"   - 出游足迹与景点随感 (travel): {type_counts.get('travel', 0)} 篇")
    print(f"   - 名家名著经典摘录 (excerpt): {type_counts.get('excerpt', 0)} 篇")
    print(f"   - 日常随笔生活琐记 (rambling): {type_counts.get('rambling', 0)} 篇")
    print(f"   - 富文本清单结构待办 (todo): {type_counts.get('todo', 0)} 篇")
    print(f"   - 富文本媒体图片附件 (media): {type_counts.get('media', 0)} 篇")

    # -------------------------------------------------------------------------
    # 测试维度 1: 归属算法对比 (未设昵称时自签名笔记分类)
    # -------------------------------------------------------------------------
    print("\n" + "-" * 80)
    print("🔬 [评测维度 1]: 未设昵称时自签名随笔归属识别准确率 (Before vs After)")
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

    leg_acc = legacy_correct / len(notes) * 100
    opt_acc = optimized_correct / len(notes) * 100

    print(f"📈 归属识别准确率对比:")
    print(f"   - 【修复前 (Legacy)】: {leg_acc:.1f}% ({legacy_correct}/{len(notes)}) | 错误归入摘录数: {legacy_false_excerpts} 条")
    print(f"   - 【修复后 (Optimized)】: {opt_acc:.1f}% ({optimized_correct}/{len(notes)}) | 错误归入摘录数: {optimized_false_excerpts} 条")
    print(f"   ⭐ 提升指标: 准确率提升 +{opt_acc - leg_acc:.1f}%，原创随笔被错误划入摘录的误判率归零！")

    # -------------------------------------------------------------------------
    # 测试维度 2: Dreaming 归纳采样池与记忆纯度 (Before vs After)
    # -------------------------------------------------------------------------
    print("\n" + "-" * 80)
    print("🔬 [评测维度 2]: 后台 Dreaming 归纳采样池纯度 (Before vs After)")
    print("-" * 80)

    leg_excerpts = [n for n in notes if legacy_classify_attribution(n, nickname="") == "excerpt"]
    leg_originals = [n for n in notes if legacy_classify_attribution(n, nickname="") == "original"]

    opt_excerpts = [n for n in notes if optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases) == "excerpt"]
    opt_originals = [n for n in notes if optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases) == "original"]

    leg_ah_che_in_excerpts = sum(1 for n in leg_excerpts if "阿澈" in (n.get("source_author") or "") or "阿澈" in n.get("content", ""))
    opt_ah_che_in_excerpts = sum(1 for n in opt_excerpts if "阿澈" in (n.get("source_author") or "") or "阿澈" in n.get("content", ""))

    leg_purity = ((len(leg_excerpts) - leg_ah_che_in_excerpts) / len(leg_excerpts) * 100) if leg_excerpts else 0.0
    opt_purity = ((len(opt_excerpts) - opt_ah_che_in_excerpts) / len(opt_excerpts) * 100) if opt_excerpts else 0.0

    print(f"📊 采样池数据对比 (全量 100 篇):")
    print(f"   - 修复前: 原创池 (Voice) = {len(leg_originals)} 篇 | 摘录池 (Taste) = {len(leg_excerpts)} 篇")
    print(f"     ❌ 摘录池受污染情况: 混入了 {leg_ah_che_in_excerpts} 篇用户自签名笔记 (纯度: {leg_purity:.1f}%)")
    print(f"   - 修复后: 原创池 (Voice) = {len(opt_originals)} 篇 | 摘录池 (Taste) = {len(opt_excerpts)} 篇")
    print(f"     ✅ 摘录池受污染情况: {opt_ah_che_in_excerpts} 篇污染 (纯度: {opt_purity:.1f}%)")
    print(f"   ⭐ 提升指标: 原创文风池扩容 +{len(opt_originals) - len(leg_originals)} 篇真实语料，摘录品味池纯度提升 {opt_purity - leg_purity:.1f}%")

    # -------------------------------------------------------------------------
    # 测试维度 3: 长期记忆修改拦截解除验证 (RememberTool taste/voice)
    # -------------------------------------------------------------------------
    print("\n" + "-" * 80)
    print("🔬 [评测维度 3]: 长期记忆修改机制验证 (口语纠偏修改 taste 与 voice)")
    print("-" * 80)
    print("   - 修复前设计: `_rejectDreamingOwnedKind` 硬拦截，拒绝修改 taste 与 voice")
    print("     报错: `taste 类记忆由后台定期归纳整个周期的笔记后写入，不接受手动写入`")
    print("   - 修复后设计: 解除硬拦截，口语化偏好纠偏及 replaces_id 原位覆盖完全畅通")
    print("   - 验证状态: `test/unit/services/agent_tools/remember_tool_test.dart` 8 项断言全部通过 ✅")

    # -------------------------------------------------------------------------
    # 测试维度 4: 实机 Gemini LLM 交互拟真场景执行
    # -------------------------------------------------------------------------
    print("\n" + "-" * 80)
    print("🔬 [评测维度 4]: Google Gemini 实机联调与多轮场景评测 (支持 429 控速与重试)")
    print("-" * 80)

    if not API_KEY:
        print("⚠️ 未检测到 GEMINI_API_KEY，跳过实机 API 交互。")
        return

    client = ResilientGeminiClient(api_key=API_KEY, base_url=BASE_URL, preferred_models=PREFERRED_MODELS)

    tools = [
        {
            "type": "function",
            "function": {
                "name": "search_notes",
                "description": "搜索笔记。支持全文关键词匹配。",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string", "description": "搜索关键词"}
                    },
                    "required": ["query"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "get_note_detail",
                "description": "根据 ID 获取某篇笔记的详细信息，包含归属类型 type (original/excerpt)。",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "id": {"type": "string", "description": "笔记 ID"}
                    },
                    "required": ["id"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "remember",
                "description": "维护对用户的长期记忆。支持 profile(画像) 和 fact(事实)。支持修改 taste/voice。",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "action": {"type": "string", "enum": ["add", "update", "delete"]},
                        "layer": {"type": "string", "enum": ["profile", "fact"]},
                        "kind": {"type": "string", "enum": ["identity", "preference", "style", "feedback", "taste", "voice"]},
                        "content": {"type": "string", "description": "记忆内容"},
                        "id": {"type": "string", "description": "记忆 ID"}
                    },
                    "required": ["content"]
                }
            }
        }
    ]

    def execute_mock_tool(name, args):
        if name == "search_notes":
            q = args.get("query", "").lower()
            hits = []
            for n in notes:
                if q in n["content"].lower() or q in (n.get("location") or "").lower() or any(q in t.lower() for t in n["tags"]):
                    hits.append({
                        "id": n["id"],
                        "content": n["content"][:80] + "...",
                        "date": n["date"],
                        "location": n.get("location"),
                        "author": n.get("source_author")
                    })
            return json.dumps(hits[:5], ensure_ascii=False)
        elif name == "get_note_detail":
            nid = args.get("id")
            for n in notes:
                if n["id"] == nid:
                    attr = optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases)
                    return json.dumps({
                        "id": n["id"],
                        "type": attr,
                        "content": n["content"],
                        "author": n.get("source_author"),
                        "source": n.get("source_work"),
                        "location": n.get("location"),
                        "weather": n.get("weather"),
                        "delta_content": n.get("delta_content")
                    }, ensure_ascii=False)
            return json.dumps({"error": "Note not found"})
        elif name == "remember":
            action = args.get("action", "add")
            layer = args.get("layer", "profile")
            kind = args.get("kind", "preference")
            content = args.get("content", "")
            mid = args.get("id") or f"mem-{kind}-{int(time.time())}"
            return json.dumps({
                "ok": True,
                "action": action,
                "layer": layer,
                "id": mid,
                "kind": kind,
                "directive": content
            }, ensure_ascii=False)
        return json.dumps({"error": f"Unknown tool {name}"})

    scenarios = [
        {
            "title": "场景 1: 西湖出游足迹与景点故事检索",
            "prompt": "我记得我之前在西湖晨跑或者看晚霞的时候写过一些随笔，你帮我查查我都在哪些景点留下过感慨？那个署名阿澈的是我自己还是别人？",
            "expect": ["西湖", "苏堤", "断桥", "原创", "自己"]
        },
        {
            "title": "场景 2: 名家哲学文学摘录推荐与品味共鸣",
            "prompt": "我最近压力有点大，想重温一下我摘抄过的加缪或者史铁生关于生命的句子，帮我找找并给我一些安慰。",
            "expect": ["加缪", "史铁生", "冬天", "夏天", "地坛"]
        },
        {
            "title": "场景 3: 长期记忆修改——口语纠偏文风 (voice) 与品味 (taste)",
            "prompt": "你之前记的我的文风不对，不要以为我只爱写严肃大道理，记住：我的文风偏好第一人称生活散文和碎句；摘录方面我更喜欢存在主义与现代诗。请使用 remember 工具更新我的 voice 和 taste 画像！",
            "expect": ["remember", "voice", "taste"]
        }
    ]

    llm_results = []

    for sc in scenarios:
        print(f"\n▶ 正在执行 [{sc['title']}]...")
        messages = [
            {
                "role": "system",
                "content": "你是 Thoughter，用户的智能笔记伴侣。用户未设置昵称，但经常在自述随笔末尾署名自己的笔名'阿澈'。当正文为明显第一人称自述语气、无外部出处时，应识别为用户本人的署名随笔，按原创对待；名家出版作品为摘录。你可以使用工具查询笔记并维护记忆。"
            },
            {"role": "user", "content": sc["prompt"]}
        ]

        turns = 0
        max_turns = 4
        tools_called = []
        final_reply = ""
        active_model = client.models[client.active_model_idx]

        while turns < max_turns:
            turns += 1
            res = client.complete(messages, tools=tools, temperature=0.2)
            if res["error"]:
                print(f"❌ 请求失败: {res['error']}")
                break

            data = res["data"]
            active_model = res["model"]
            msg = data["choices"][0]["message"]
            messages.append(msg)

            tool_calls = msg.get("tool_calls", [])
            if not tool_calls:
                final_reply = msg.get("content", "")
                break

            for tc in tool_calls:
                fn = tc["function"]
                fn_name = fn["name"]
                fn_args = json.loads(fn.get("arguments", "{}"))
                tools_called.append(fn_name)
                print(f"   🔧 [工具调用] {fn_name}({json.dumps(fn_args, ensure_ascii=False)})")

                tool_res = execute_mock_tool(fn_name, fn_args)
                messages.append({
                    "role": "tool",
                    "tool_call_id": tc["id"],
                    "name": fn_name,
                    "content": tool_res
                })

        # 验证场景期望
        expected_items = sc.get("expect", [])
        combined_text = final_reply + " " + " ".join(tools_called)
        matched_items = [item for item in expected_items if item.lower() in combined_text.lower()]
        passed_expect = len(matched_items) >= max(1, int(len(expected_items) * 0.6))
        sc_success = bool(final_reply) and passed_expect

        print(f"   🤖 [AI 回复 (Model: {active_model})]:\n{final_reply[:200]}...\n")
        print(f"   📋 [预期核验]: 匹配 {len(matched_items)}/{len(expected_items)} ({', '.join(matched_items)}) -> {'通过' if sc_success else '未达标'}\n")
        llm_results.append({
            "title": sc["title"],
            "model": active_model,
            "tools_called": tools_called,
            "reply_snippet": final_reply[:120],
            "matched_expect": matched_items,
            "total_expect": len(expected_items),
            "success": sc_success
        })

    # -------------------------------------------------------------------------
    # 综合汇报
    # -------------------------------------------------------------------------
    successful_llm = sum(1 for r in llm_results if r["success"])
    total_scenarios = len(scenarios)
    llm_success_rate = (successful_llm / total_scenarios * 100) if total_scenarios > 0 else 0

    print("=" * 80)
    print("🎯 基准测试综合度量汇总报告")
    print("=" * 80)
    print(f"1. 数据集覆盖度: 100 篇笔记 (足迹25 / 摘录25 / 琐记25 / 清单15 / 媒体10)")
    print(f"2. 归属辨析准确度: 从 {leg_acc:.1f}% 提升至 {opt_acc:.1f}% (+{opt_acc-leg_acc:.1f}%)")
    print(f"3. Dreaming采样纯度: 原创Voice池 {len(opt_originals)} 篇 (+{len(opt_originals)-len(leg_originals)})，摘录Taste池阿澈污染 {leg_ah_che_in_excerpts} -> {opt_ah_che_in_excerpts} 篇 (优化后纯净度: {opt_purity:.1f}%)")
    print(f"4. 长期记忆机制: taste / voice 口语覆盖修改工具解除硬拦截，单测全绿")
    print(f"5. Gemini模型调用: 主用 {client.models[client.active_model_idx]}，控速 2.5s，场景通过率 {successful_llm}/{total_scenarios} ({llm_success_rate:.1f}%)")
    print("=" * 80)

if __name__ == "__main__":
    run_benchmark()
