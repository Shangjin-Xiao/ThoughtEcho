#!/usr/bin/env python3
"""
ThoughtEcho Thoughter AI 第二模拟用户（林晚·古建与风物学者）100条拟真真实生活场景基准评测引擎
涵盖：田野调查与古建考察、营造典籍与民艺摘录、风物食记与工匠随笔、田野测绘清单与图纸记录。
验证长期记忆系统在全新文风、专业领域、长句白描与多样化记录习惯下的普适性、归属识别准确率与抗污染隔离性。
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
# 100 条高保真拟真笔记数据集生成（林晚·古建与风物学者）
# -----------------------------------------------------------------------------
def generate_100_lin_wan_notes():
    now = datetime.now()
    def days_ago(d, hour=10):
        t = now - timedelta(days=d)
        return t.replace(hour=hour, minute=15, second=0).strftime("%Y-%m-%d %H:%M:%S")

    notes = []

    # =========================================================================
    # 类别 1: 田野调查与古建考察 (25 条) - Ground Truth: original
    # =========================================================================
    travel_data = [
        ("山西佛光寺", "大佛光寺东大殿依山而筑，唐代木构宏阔雄浑。檐下七铺作双抄双下昂斗栱如云朵般从柱头飞展而出，梁枋交接处浑然天成。站在殿前仰望，七间面阔的大殿在暮色中沉静如山。殿内唐代彩塑体态丰满，衣纹飞动。梁思成当年在梁下发现林徽因题写的唐代墨书，那一刻该是多么震撼。余立于阶下久之，不忍离去。——录于佛光寺东大殿测绘，林晚", "山西·五台山佛光寺", "clear", "17°C", 2, "林晚", "田野笔记"),
        ("山西应县木塔", "立于释迦塔下，仰视通高六十七米全木构古塔，叹为观止。五层六檐八角，实际夹有暗层共九层，运用了五十四种斗栱，堪称中国木构斗栱博物馆。辽代工匠以榫卯咬合抵御了近千年地震与风蚀。攀至二层平座，凭栏远眺桑干河平原，秋风卷地，风铃叮咚，令人神思万里。——林晚", "山西·应县木塔", "clear", "15°C", 4, "林晚", None),
        ("太原晋祠圣母殿", "晋祠圣母殿北宋大木作，前廊减柱造法使得前廊深广达两间，视界极为空旷。廊柱上八条木雕盘龙昂首怒目，鳞爪飞扬，近千年仍保存完好。殿前难老泉水汩汩流淌，宋代侍女像眉目如生，各自若有所思，生活气息极为浓厚。——记于太原晋祠，林晚", "山西·太原晋祠", "cloudy", "18°C", 7, "林晚", "田野手记"),
        ("蓟县独乐寺", "独乐寺观音阁为辽代阁道式木构，通高二十三米。上下两层檐出挑深远，明间辟门，内部中空筑须弥座，供奉十六米高十一面观音立像。阁内梁架穿插精巧，减柱与斜撑配合极妙，柱头铺作双抄重栱。漫步阁下，沉浸在辽代营造的雄健气魄中。——林晚", "天津·蓟县独乐寺", "clear", "16°C", 9, "林晚", None),
        ("大同华严寺", "华严寺大雄宝殿始建于辽，金代重建。单檐庑殿顶面阔九间，进深五间，正脊两侧三米高的金代琉璃鸱吻在阳光下泛着古铜色光泽。殿内采用减柱移柱造，将内柱大幅度向两侧挪移，腾出极为辽阔的礼佛空间，空间体量之雄奇令人屏息。", "山西·大同华严寺", "clear", "14°C", 11, None, None),
        ("芮城永乐宫", "永乐宫三清殿元代巨制，殿顶九脊顶，梁架彻上露明造。最摄人心魄的是环绕三面的朝元图壁画，二百八十六位神祇衣带飘举，神情各异。青绿与朱砂历经七百年依然沉着厚重，纯熟的游丝铁线勾勒出中国工笔重彩画的绝顶之作。——录于永乐宫，林晚", "山西·芮城永乐宫", "cloudy", "19°C", 13, "林晚", "采风录"),
        ("徽州呈坎古村", "呈坎依八卦风水而建，二水穿村，三街九十九巷纵横宛如迷宫。罗东舒祠之宝纶阁堪称江南第一祠堂，五开间明代彩画梁架斑驳雅致，白果木雀替雕工精绝，镂刻着花鸟鱼虫与吉祥云纹。天井四水归堂，青苔沿石阶蔓延，满是时光的温润印记。——林晚田野笔记", "黄山·呈坎古村", "rainy", "16°C", 16, "林晚", "林晚田野笔记"),
        ("黟县宏村", "水系规划之精妙莫过于宏村。引牛形泉水入村，经九曲水圳流经家家户户门前，汇入半月沼与南湖。清晨南湖薄雾笼罩，画桥倒映在如镜的水面上，粉墙黛瓦与层叠的马头墙在晨光中宛如泼墨长卷。村民在石埠头淘米浣衣，人声与流水声交织。", "黄山·黟县宏村", "cloudy", "17°C", 18, None, None),
        ("歙县许国石坊", "许国石坊立于歙县古城心，为罕见的八脚牌坊，四面重檐歇山顶。明代万历年间红砂岩雕凿，坊额题写大学士，四面梁枋上镂雕双狮滚绣球、百鸟朝凤与文臣武将。石质风化呈现沧桑的暗红色，沉雄壮丽，是徽州石雕工艺的巅峰之作。——林晚", "黄山·歙县古城", "clear", "19°C", 20, "林晚", None),
        ("泉州开元寺双塔", "开元寺镇国塔与仁寿塔并峙于刺桐城中，为中国现存最高宋代仿木石塔。花岗岩仿木构斗栱层层叠挑，塔身外壁八面各雕二尊罗汉与菩萨浮雕，刀法洗练有力，衣纹随海风起伏。石构建筑竟能还原木构梁柱的弹性韵律，令人击节赞赏。——摄于泉州开元寺，林晚", "泉州·开元寺", "clear", "23°C", 23, "林晚", "田野手记"),
        ("南靖田螺坑土楼", "四菜一汤的生土夯筑奇观。步云楼居中为方楼，和昌楼、振昌楼、瑞云楼与文昌楼环抱四周。厚逾两米的生土墙内掺竹片、松木与糯米红糖浆，外墙厚重防御敌寇，内院三层木构走廊开敞明亮，聚族而居的宗族伦理深嵌于环形建筑肌理中。", "漳州·田螺坑土楼", "cloudy", "22°C", 25, None, None),
        ("华安二宜楼", "被誉为圆楼之王的二宜楼，双环同心，直径达七十三米。外环四层设十六个独立单元，以防火封火墙隔开，单元内设独立楼梯与天井，既各自私密又整体严密。楼内保留了数百平方米清代彩绘与西洋钟表壁纸，是闽南沿海文明交流的罕见活化石。——林晚", "漳州·华安二宜楼", "clear", "24°C", 27, "林晚", None),
        ("泰顺泗溪木拱廊桥", "溪东桥与北涧桥静卧于泗溪之上，被称为世上最美廊桥。采用编木拱梁结构，不着一钉，由数十根圆木交错搭接成纵横骨架，形成大跨度八字撑拱梁。桥上建有重檐廊屋，可避风雨，中设神龛供奉玄帝。走在廊桥木板上，桥下碧溪激石，恍若梦境。——林晚田野手记", "温州·泰顺泗溪", "rainy", "18°C", 30, "林晚", "田野手记"),
        ("松阳杨家堂古村", "阶梯式分布在山坡上的杨家堂，被称为江南布达拉宫。泥土夯筑的金黄外墙在夕阳下泛着温暖的光辉，两株五百年的大樟树守护在村口。古道依山势蜿蜒，马头墙错落有致，保留着原生态的宗祠、老油坊与农家晒场，宁静得只闻鸡鸣犬吠。", "丽水·松阳杨家堂", "clear", "21°C", 32, None, None),
        ("武义延福寺", "深山中的元代木构大殿，隐于武义桃溪镇。大殿三开间单檐歇山顶，梁架用材硕大，保留了典型的草架与明栿结合形制，斗栱出跳朴茂古拙。柱根呈明显的梭柱收分，江南雨水丰沛，殿内保存如此完好的早期木构实属罕见。——林晚", "金华·武义延福寺", "cloudy", "19°C", 35, "林晚", None),
        ("肇兴侗寨鼓楼群", "五座高耸的鼓楼代表着仁义礼智信五大宗族房族。穿斗式木构重檐密阁，从数层到十几层不等，全凭杉木穿枋咬合，飞檐翘角形如杉树。鼓楼下设火塘，长者围坐烤火聊天，年轻人弹唱侗族大歌。建筑、火塘与歌声，构成了侗寨不灭的文化心脏。——作于肇兴侗寨，林晚", "黔东南·肇兴侗寨", "clear", "17°C", 38, "林晚", "行记"),
        ("从江增冲鼓楼", "建于清康熙十一年，是黔东南现存最古老的侗寨鼓楼。十三重飞檐攒尖顶，通高二十五米，四根巨大的杉木直穿顶层作为主受力柱。底层四方设有木质靠椅，雕花栏杆上刻有鱼龙花鸟。古楼在山水掩映中静默伫立，工匠智慧令人肃然起敬。——林晚", "黔东南·从江增冲", "cloudy", "16°C", 40, "林晚", None),
        ("凤凰古城沱江吊脚楼", "沱江两岸的木结构吊脚楼，后半部坐落在江岸石基上，前半部则由细长的杉木柱凌空撑立在水波之上。挑梁伸出江面，推开木窗即见游船泛波。木板随脚步微微作响，岁月将木料浸润成温厚的深褐色，与水色烟云融为一体。", "湘西·凤凰古城", "rainy", "15°C", 42, None, None),
        ("邛崃平乐古镇林盘", "川西民居的穿斗木架构展现出极高的灵活性。竹编夹泥墙，屋面覆以青小瓦，挑檐深远以避多雨气候。古镇外的林盘将院落、竹林、水渠与农田有机融合，推门见绿，小桥流水，是人与自然共生共栖的典范生态聚落。——林晚田野笔记", "成都·邛崃平乐", "cloudy", "20°C", 45, "林晚", "田野笔记"),
        ("大理喜洲严家大院", "白族传统民居三坊一照壁、四合五天井的典范之作。照壁雕花彩绘，正中镶嵌天然大理石山水画。木雕门窗层层叠叠，镂空雕刻花鸟走兽，玲珑剔透。角楼与跑马转角楼相连，白墙青瓦与蓝天白云相映，展现出西南边陲独特的典雅与富庶。——林晚", "大理·喜洲古镇", "clear", "21°C", 48, "林晚", None),
        ("建水朝阳楼", "建水东门城楼，比北京天安门还早建二十八年。三层飞檐重阁，全木构架立于高大砖砌城台之上。檐角反翘凌空，斗栱雄健层叠，站在城楼眺望建水老城全景，红瓦铺陈，古井遍布。晚霞穿透隔扇门窗，投下斑驳的光影。——调查于建水古城，林晚", "红河·建水朝阳楼", "clear", "22°C", 50, "林晚", "采风录"),
        ("苏州东山雕花楼", "香山帮匠人耗时三年精工细作之春在楼。全楼无处不雕刻，门楼砖雕精细如丝绸刺绣，室内落地长窗雕镂三国水浒演义故事。梁枋上的白果木圆雕玲珑剔透，榫卯交接严丝合缝，展现出江南文人园林与富商宅邸结合的精湛木作极境。——林晚", "苏州·吴中区东山", "cloudy", "18°C", 53, "林晚", None),
        ("莫高窟第196窟木构窟檐", "晚唐景福二年建造的崖壁窟檐，是极罕见的唐代地面木构实物遗存。单檐歇山顶紧贴鸣沙山崖壁，斗栱五铺作双抄偷心造，用材粗犷硕大。历经干旱大漠千余年风沙洗礼，红松木构件依然刚劲挺拔，仿佛盛唐的余晖犹在戈壁上燃烧。——林晚手记", "酒泉·敦煌莫高窟", "clear", "13°C", 56, "林晚", "手记"),
        ("宁波保国寺大殿", "大殿采用宋代厅堂式大木构架，大殿内无一根大梁通达前后，全靠短柱、枋木与拼合梁穿插支撑。柱头为瓜棱柱，斗栱硕大。传说大殿有鸟不栖、虫不蛀、蛛不结网之奇，实因黄杨木与良好通风营造之微气候所致。宋代营造智慧令人叹服。", "宁波·江北区保国寺", "cloudy", "20°C", 59, None, None),
        ("西安大雁塔", "慈恩寺大雁塔为唐高宗永徽年间玄奘法师督建。七层四角锥体砖仿木结构，底层各面辟券门，外檐仿木构出檐挑出，叠涩菱角牙子砖层次分明。千年来历经数十次大地震而不倒，巍峨耸立于古都中轴线之侧，是佛教建筑本土化的伟大见证。——林晚", "西安·大慈恩寺", "clear", "16°C", 62, "林晚", None),
    ]

    for i, (loc, content, poi, weather, temp, d, author, work) in enumerate(travel_data, 1):
        notes.append({
            "id": f"travel-{i:02d}",
            "content": content,
            "date": days_ago(d),
            "source_author": author or "",
            "source_work": work or "",
            "tags": ["田野调查", "古建筑", "营造学"],
            "weather": weather,
            "day_period": "afternoon" if i % 2 == 0 else "morning",
            "location": poi,
            "temperature": temp,
            "favorite": i in [1, 2, 7, 10, 13, 23],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 2: 营造典籍与民艺文化经典摘录 (25 条) - Ground Truth: excerpt
    # =========================================================================
    excerpts_data = [
        ("建筑是凝固的音乐，也是一个民族历史文化最忠实的记录者。一个东方老国的城市，在建筑上如果完全失掉自己的艺术特征，在文化上的表现便是一种退化。", "梁思成", "中国建筑史", ["建筑学", "文化史", "历史"]),
        ("斗栱在中国建筑中的地位，犹如希腊建筑中的柱式。它不仅是主要的受力承重构件，更是断定一座古代建筑时代特征的最明确标尺。", "梁思成", "图像中国建筑史", ["建筑理论", "斗栱", "营造"]),
        ("无论哪一个巍峨的古城楼，或一角倾颓的殿基，都在默默地讲述着过去的年月。它有它的生命，有它的历史，有它曾经经历的风霜与荣耀。", "林徽因", "平郊建筑杂录", ["建筑随笔", "散文", "审美"]),
        ("当我们在深山废寺中发现那座雄浑的唐代木构时，暮色正笼罩着村落。那一刻的欣喜与敬畏，超越了所有路途的颠簸与艰辛。", "林徽因", "晋汾古建筑纪行", ["考察纪行", "唐代木构"]),
        ("凡构屋之制，皆以材为祖。材有八等，度屋之大小，因而用之。广厚虽不同，而各有一定之分数。", "李诫", "营造法式", ["古籍", "宋代", "营造技术"]),
        ("从基层上看去，中国社会是乡土性的。我们说乡下人土气，这个土字用得极好。土字里包含着人与土地不可分割的血肉关联。", "费孝通", "乡土中国", ["社会学", "乡土文化", "人类学"]),
        ("传统手工业不仅是农民日常生计的重要补充，更是维系乡村社区伦理、邻里互助与文化记忆的重要纤维。", "费孝通", "江村经济", ["社会学", "民间手工艺"]),
        ("由四川过湖南去，靠东有一条官路。这官路将近湘西边境，到了一座小山城，名叫茶峒。小溪流下去，绕山岨流，约三里便汇入茶峒大河。", "沈从文", "边城", ["文学", "湘西", "风土"]),
        ("橘柚成熟时，满山满谷一片金黄。辰水清澈见底，游鱼可数。水手们在船头摇橹唱滩歌，声音在两岸青岩峭壁间荡漾开去。", "沈从文", "长河", ["文学", "河流", "风土"]),
        ("栀子花粗粗大大的，又香得呛人，这就有点野性。她说：‘去你妈的，我就是要这样香，香得痛痛快快，你们他妈管得着吗！’", "汪曾祺", "人间草木", ["散文", "植物", "生活情趣"]),
        ("庵赵庄的庵叫菩提庵，里面住着三个和尚。他们不住禅房，住平房；不吃素，吃腊肉；也不做早晚课，各自耕种自留地，日子过得安闲自在。", "汪曾祺", "受戒", ["小说", "乡风民俗", "自由"]),
        ("美并不存在于孤芳自赏的高贵陈设中，而是沉淀在无名手艺人日复一日为了百姓日用而创造的朴拙器物里。", "柳宗悦", "民艺论", ["民间工艺", "日用之美", "美学"]),
        ("器物之美，是使用之美，是器物与日常生活深情相依所自然产生的温存。手作的痕迹是人心的体温。", "柳宗悦", "工艺之道", ["手工艺", "匠人精神"]),
        ("无论多么偏远的山村，每一个土坡、每一口老井，都附着着祖先的生活记忆与山神精怪的古老物语。", "柳田国男", "远野物语", ["民俗学", "民间故事", "日本文学"]),
        ("真正的建筑不应是抽象的几何纪念碑，而应是有时间厚度的活体，容纳草木的滋生、雨水的浸润与残破瓦片的重生。", "王澍", "造房子", ["当代建筑", "园林", "手作建筑"]),
        ("建筑的记忆之灯告诉我们：每一座伟大的建筑不仅属于当代，更属于未来的世代。它是前人生命与灵魂的真实容器。", "约翰·罗斯金", "建筑的七盏明灯", ["建筑哲学", "遗产保护"]),
        ("中国美学追求由有限走向无限，由实入虚，虚实相生。无论是园林、建筑还是水墨山水，皆在空白处寄托深情。", "宗白华", "美学散步", ["美学", "中国艺术", "哲学"]),
        ("虽由人作，宛自天开。巧于因借，精在体宜。三分匠人，七分主人，境由心造也。", "计成", "园冶", ["造园", "传统美学", "古籍"]),
        ("传统榫卯之绝妙，在于互避互让，暗中咬合。各构件相互牵制又相互包容，不假一颗铁钉而经数百年不摇不散。", "王世襄", "明式家具研究", ["传统家具", "榫卯", "工匠工艺"]),
        ("木欣欣以向荣，泉涓涓而始流。善万物之得时，感吾生之行休。策扶老以流憩，时矫首而遐观。", "陶渊明", "归去来兮辞", ["古典文学", "田园诗", "归隐"]),
        ("事不目见耳闻，而臆断其有无，可乎？郦元之所见闻，殆与余同，而言之不详；士大夫终不肯以小舟夜泊绝壁之下，故莫能知。", "苏轼", "石钟山记", ["古文", "实地考察", "求真"]),
        ("我们于日用必需的东西以外，必须还有一点无用的游戏与享乐，生活才觉得有意思。我们看夕阳，看秋河，看花，听雨，闻香。", "周作人", "雨天的书", ["生活美学", "闲适散文"]),
        ("文化的进化与人类精神的成熟，在本质上等同于从日常实用器物中剔除纯粹虚伪繁琐的装饰。", "阿道夫·路斯", "装饰与罪恶", ["现代主义", "设计理论"]),
        ("建筑是光线下形状的大胆、正确与绝妙的游戏。建筑师的任务是赋予事物以秩序，让空间产生动人的诗意。", "勒·柯布西耶", "走向新建筑", ["建筑理论", "空间美学"]),
        ("天下兴亡，匹夫有责。治学莫如实事求是，身临其境而验之于物，考之于史，方免穿凿附会之弊。", "顾炎武", "日知录", ["明清学术", "求实精神"]),
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
            "location": "书斋",
            "temperature": "20°C",
            "favorite": i in [1, 3, 5, 6, 12, 15, 19],
            "type_ground_truth": "excerpt"
        })

    # =========================================================================
    # 类别 3: 风物食记与工匠日常随笔 (25 条) - Ground Truth: original
    # =========================================================================
    ramblings_data = [
        ("冬至前后，呈坎老乡家院子里挂满了腊肉与腌板鸭。天井下的一缸臭鳜鱼正发酵到最佳时节，闻着微臭，下锅煎透加姜蒜笋片红烧，肉质蒜瓣般紧实弹嫩，入口奇香。饮食习惯往往与徽州潮湿阴凉的盆地气候深深相嵌。——林晚食记", "林晚", "林晚食记", ["风物", "徽州美食", "发酵"]),
        ("在泾县小岭村的造纸作坊看师傅捞纸。竹帘在漂浮着檀皮与沙田稻草浆的清泉池中轻轻一荡，双臂发力平稳起落，一张湿纸便均匀附着在帘上。看似轻巧的一舀一荡，全凭指尖数十年积淀的肌肉记忆与对水流阻力的精准感知。——林晚手记", "林晚", "手记", ["传统手艺", "宣纸", "工匠精神"]),
        ("踏入桐木关的青楼木屋，浓烈的马尾松烟香气扑鼻而来。茶青摊在二楼焙架上，底层松柴明火慢煨，烟气穿透楼板松木缝隙熏蒸茶叶。冲泡开来，汤色金红明亮，既有桂圆干的甘甜，又带深沉的松烟木质香，暖透肺腑。——林晚", "林晚", None, ["茶事", "正山小种", "武夷山"]),
        ("守了一夜的松木柴窑终于降温开窑。戴着石棉手套取出刚出膛的青白瓷盏，胎体薄如脱水蝉翼，釉面泛着如玉的青翠光晕。由于窑内还原气氛与落灰偶然交融，几只盏底形成了奇妙的铁斑窑变。这种火与泥土的偶然馈赠，正是柴烧不可替代的魅力。", None, None, ["景德镇", "柴烧", "瓷器"]),
        ("冬水清冽，正是绍兴传统手工黄酒下缸之时。蒸熟的糯米拌入麦曲与酒药，置于陶坛中浸润在鉴湖源头活水里。师傅每日以木耙翻缸搅拌，听陶坛内轻微的咕嘟发酵声，那是微生物在时光中的低语。——林晚随笔", "林晚", "随笔", ["黄酒", "绍兴", "传统发酵"]),
        ("苗岭侗寨的红酸汤是用野生小番茄与红辣椒在陶坛中自然发酵而成，酸冽开胃。刚从稻田里捞出的冷水禾花鱼肉质细嫩带花清香，整条投入滚沸的红酸汤中，撒上一把木姜子油与青花椒，酸辣鲜爽，山野的元气瞬间在舌尖炸裂。——林晚食记", "林晚", "林晚食记", ["黔东南", "苗族酸汤", "风味"]),
        ("清晨六点的石狮老街，面线糊摊前已腾起大片白雾。细如发丝的面线在猪大骨与海蚌熬制的浓汤中煮至软烂如糊，点一勺醋肉、卤大肠与海蛎，最后撒上胡椒粉与芫荽，配上一根刚出锅炸得金黄酥脆的油条。一口热汤下肚，整座海丝古城的烟火气便醒了。", None, None, ["泉州", "闽南小吃", "早餐"]),
        ("在矾山矾矿遗址遇见年过七旬的老石工。一把铁錾子、一柄八角锤，沿着花岗岩石料的天然纹理轻敲重凿。石屑纷飞间，石块应声平整裂开。老人说石头也是有骨肉纹理的，顺着它的性子敲它就听话，逆着来怎么打都会崩裂。万物皆有其理。——林晚", "林晚", None, ["石工", "老手艺", "感悟"]),
        ("清晨逛篆新市集，满眼都是滇南丰茂的风物。摊位上堆叠着新鲜采自高山的见手青、鸡枞、干巴菌，还有建水浸在清水木盆里的雪白草芽。买了一小包干巴菌和两把鲜草芽，回客栈借厨房切片清炒，草芽清甜脆嫩如初春雪笋，干巴菌醇香扑鼻。", None, None, ["云南", "菜市场", "菌子"]),
        ("潮州工夫茶席极为讲究。橄榄炭在风炉里烧得通红，砂铫水初沸如鱼目，立即冲入朱泥小壶。高冲低泡，关公巡城，韩信点兵。第一道鸭屎香单丛入口，花香幽雅，山韵浓郁，舌底鸣泉。茶汤三巡过后，整个人心神澄澈，如沐春风。——林晚手记", "林晚", "田野手记", ["工夫茶", "单丛", "潮州风物"]),
        ("初夏时节的东山，太湖里的抱卵青虾最为肥美。手工将虾仁、虾脑、虾籽分别剥出，热锅快炒，晶莹剔透的虾仁裹着鲜红的虾脑与金黄的虾籽，鲜甜弹牙。再配一碗滑润如丝的莼菜银鱼羹，江南水乡的清丽温润全在这一席船菜之间。", None, None, ["苏州", "太湖船菜", "节令美食"]),
        ("扬州早茶的皮包水精髓全在一盘烫干丝。豆腐干切得细如发丝，沸水反复浇烫三次去掉豆腥，沥干后整齐码入瓷盘，浇上虾籽酱油与麻油，点缀嫩生姜丝与开洋。入口软嫩爽滑，酱香醇厚，配一壶魁龙珠热茶，慢条斯理地消磨清晨光阴。", None, None, ["扬州早茶", "淮扬菜", "慢生活"]),
        ("走进平遥东泉老醋坊，老陈醋的酸香与熏醅焦香扑鼻而来。高粱大曲发酵后入熏炉翻醅数日，颜色由浅黄逐渐转为紫黑。夏伏晒、冬捞冰，数年陈酿沉淀出挂杯如红酒般的纯酿老醋。尝一滴含在口中，酸中带绵甜，回味生津。——林晚", "林晚", None, ["山西", "平遥老醋", "物产"]),
        ("蜀南竹海翠竹万竿，晨雾未散。跟着村民扛着锄头在竹根间寻觅刚刚拱土的冬笋。挖出一根肥硕鲜嫩的笋，洗净切厚片，与院子里柴火熏烤了一冬的陈年老腊肉同煨。笋片饱吸了腊肉的油脂与烟熏香气，咸鲜脆嫩，满山竹影仿佛都融在碗中。", None, None, ["宜宾", "冬笋", "乡村物产"]),
        ("在龙泉青瓷作坊看师傅拉坯。陶轮飞速旋转，师傅双手蘸水轻抚泥团，拇指下压、四指提拉，泥土便如生灵般在指尖升起延展，转瞬化作优雅轻盈的梅子青梅瓶弧度。器皿的形制与线条，原是工匠指掌与大地泥土之间最亲密的对话。——林晚", "林晚", None, ["龙泉青瓷", "拉坯", "传统手艺"]),
        ("在徽州古宅修缮工地上，老木匠老张坐在长凳上给推刨调刃。用小木槌极轻地敲击刨铁两侧，将刨刃微调出仅一根头发丝厚度的缝隙。推刨在百年老榉木上平稳推进，木花如薄纱般卷曲涌出，木质香气弥漫四周。对尺寸微芒的极致执守，令人动容。——林晚田野笔记", "林晚", "林晚田野笔记", ["大木作", "木工", "修缮"]),
        ("蟳埔渔村的古老民居，墙体是用大贝壳（生蚝壳）与海泥混合砌筑而成。硕大的蚵壳整齐下倾排列，既耐海风海盐侵蚀，又可阻挡雨水内渗，冬暖夏凉。村中阿婆发髻上插满鲜花围成簪花围，推着海鲜三轮车走在蚵壳小巷里，斑斓如画。", None, None, ["泉州", "蟳埔女", "蚵壳厝"]),
        ("雨后独自行走在徽杭古道盘山石阶上。数百年来无数徽商独轮车与布鞋踏过的青石板，棱角已被磨得浑圆光亮，泛着墨绿色的润泽。路旁山泉潺潺，野菊花正盛开。古建筑与古道皆是生活留在地表上的刻度，承载着先民沉重的希望与离愁。——林晚", "林晚", None, ["徽杭古道", "山川漫步", "历史"]),
        ("走了一整天，双腿酸软。在老客栈的木桌前拧开台灯，铺开白天的测绘手稿。铅笔线条略显杂乱，用针管笔重新勾勒斗栱正立面与挑檐剖面。墨水渗入棉浆纸纤维，散发出特有的墨香。窗外竹影摇曳，夜色清寒，内心的安宁无与伦比。——林晚", "林晚", "日记", ["测绘手记", "夜晚", "平静"]),
        ("冬日清晨六点半的巷口豆腐摊。大铁锅里煮着滚烫的豆浆，浓郁的豆香在冷空气中化作阵阵白汽。摊主大叔麻利地将点卤凝固的豆腐脑舀入木框，盖上白布压上青石板。买了一块刚压好的温热老豆腐，切厚块两面煎黄撒葱花，朴素却至味。", None, None, ["清晨市井", "豆腐", "烟火气"]),
        ("走进墨厂车间，空气中弥漫着清凉的冰片与松烟墨香。赤膊的师傅手持十几斤重的铁锤，对着垫铁上的墨泥有节奏地反复捶打上千次。墨越捶越细，胶越溶越匀。只有经过千万次重击，墨锭才能做到落纸如漆、经久不褪。手艺人的坚守令人肃然起敬。——林晚", "林晚", None, ["徽墨", "传统工艺", "守艺人"]),
        ("窗外寒风凛冽，屋里红泥小火炉炭火正红。铁壶里的十年老寿眉咕嘟咕嘟翻滚，茶汤泛着温润的枣红色，陈香扑鼻。炉边烤着两颗青皮砂糖橘与几枚板栗，橘皮烤得微焦，酸甜汁水化作甘饴。冬夜围炉，与好友温言细语，不知东方之既白。", None, None, ["围炉煮茶", "冬日", "生活随感"]),
        ("村头的小石拱桥已历经三百余年。半圆形的石拱由粗砺的花岗岩长条石挤压砌筑，拱券两侧爬满了青绿的薜荔藤蔓。桥下浅滩游鱼穿梭水草之间，偶尔有村童骑水牛涉水而过。古桥与流水、树木、飞鸟早已融为不可分割的自然生境。——林晚随感", "林晚", "随感", ["石拱桥", "乡村生境", "自然"]),
        ("晚上在书房核对研究生交上来的山西玉皇庙大殿测绘剖面图。发现学生在铺作层梁栿交接处少画了暗销与驼峰垫木。在图纸上用红笔一一标注修正：大木作各构件之咬合既严密又互有伸缩余量，一处画错，整体受力逻辑便不复存在。田野测绘容不得半点想当然。——林晚", "林晚", "工作手记", ["学术治学", "木构教学", "严谨"]),
        ("腊八清晨，将紫皮大蒜一一剥去外衣，放入清洗风干的玻璃罐中，倒入陈年老米醋与少许冰糖，密封置于北阳台阴凉处。十余日后蒜瓣将逐渐转为通体碧绿如翠玉，辣味收敛，酸香爽脆。四季流转，风物随时令而变，这是生活给耐心的奖赏。", None, None, ["节气民俗", "腊八蒜", "时间的美学"]),
    ]

    for i, (content, author, work, tags) in enumerate(ramblings_data, 1):
        notes.append({
            "id": f"rambling-{i:02d}",
            "content": content,
            "date": days_ago(i + 3, hour=21 if i % 2 == 0 else 7),
            "source_author": author or "",
            "source_work": work or "",
            "tags": tags,
            "weather": "clear" if i % 3 == 0 else "cloudy",
            "day_period": "night" if i % 2 == 0 else "morning",
            "location": "田野工作站" if i % 2 == 0 else "书斋",
            "temperature": "18°C",
            "favorite": i in [1, 2, 6, 8, 10, 16, 21],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 4: 田野测绘结构化清单与考察备忘 (15 条) - Ground Truth: original
    # =========================================================================
    checklist_data = [
        ("应县木塔三层平座测绘仪器清点 Checklist：\n- [x] 激光测距仪两台（已校准水平精度）\n- [x] 拓印蜡纸、特制拓包与红星宣纸\n- [x] 50米高精度皮尺两卷\n- [ ] 强光防爆手电筒备用锂电池\n- [ ] 安全绳、防滑手套与安全帽两副\n注意木构暗层缝隙狭小，禁止携带任何易燃火源。——林晚备忘", "林晚", "备忘", ["清单", "测绘准备", "应县木塔"]),
        ("徽州古村落宗祠形制与风水勘测要点清单：\n- [x] 测绘前门五凤楼式歇山屋顶起翘角度\n- [x] 记录天井排水暗沟四水归堂水流走向\n- [x] 拓印享堂享牌与石柱础雕刻图案\n- [ ] 查阅宗谱确认始祖迁徙与建祠确切年代\n- [ ] 访谈族长记录祭祖仪式口述史", "林晚", "田野备忘", ["宗祠", "徽州", "调研清单"]),
        ("中国传统大木作宋式与清式斗栱构件对照表：\n- [x] 栌栱（宋） vs 坐斗（清）：注意斗耳、斗腰、斗底比例差异\n- [x] 华栱（宋） vs 昂翘（清）：宋式单抄双抄与清式平出之演化\n- [x] 慢栱与令栱：清式统称为正心瓜栱与外拽厢栱\n- [ ] 昂嘴下垂角度与批竹昂演化时间线比对\n- [ ] 编制宋清两代营造模数八等材与斗口换算表", "林晚", "学术笔记", ["营造法式", "大木作", "斗栱"]),
        ("闽南红砖厝燕尾脊与砖雕勘验项目清单：\n- [x] 测定正脊双向飞檐反翘曲率半径\n- [x] 勘验红砖墙交合处出砖入石砌筑工艺\n- [ ] 记录山墙悬鱼与照壁泥塑彩绘剥落程度\n- [ ] 登记大门门头青草石雕花板损毁状况", None, "勘验清单", ["闽南建筑", "红砖厝", "保护"]),
        ("浙南木拱廊桥受力构件安全性评估巡检表：\n- [x] 检查主拱三节苗与五节苗搭接点位移变形\n- [x] 勘验桥台金刚墙花岗岩基座水流冲刷淘空\n- [ ] 监测廊屋柱脚受潮霉烂与白蚁蛀蚀情况\n- [ ] 检查桥面铺板松动与防滑条破损", "林晚", "安全巡检", ["廊桥", "木构安全", "泰顺"]),
        ("黔东南侗族鼓楼穿斗结构防腐与防火巡查清单：\n- [x] 检查底层火塘排烟通道及周边阻燃石板\n- [x] 检查四根主承重杉木柱脚防潮石墩接触面\n- [ ] 巡视高层飞檐重檐挂瓦有无脱落移位\n- [ ] 落实村寨消防蓄水池与高压水泵试运转", None, "鼓楼巡查", ["侗族鼓楼", "非遗保护"]),
        ("徽州传统墨锭与歙砚制作工序记录 Checklist：\n- [x] 收集炼烟松烟与桐油烟采集温度数据\n- [x] 观摩金箔包裹与捶墨师傅铁锤打击频次\n- [ ] 记录歙县龙尾山砚石开采石品纹理分类\n- [ ] 整理国家级非遗传承人访谈录音整理稿", "林晚", "非遗调研", ["徽墨", "歙砚", "调研"]),
        ("2026年下半年晋南早期木构考察路线行前规划：\n- [x] Day1 太原出发：晋祠圣母殿与献殿\n- [x] Day2 临汾：广胜寺上寺琉璃飞虹塔\n- [x] Day3 运城：解州关帝庙春秋楼与芮城永乐宫\n- [ ] Day4 平陆：黄河古栈道摩崖石刻与地坑院\n- [ ] Day5 万荣：秋风楼与飞云楼全木纯榫卯楼阁", "林晚", "考察规划", ["晋南木构", "行程路线"]),
        ("田野考察急救药箱与野外防护装备清单：\n- [x] 蛇药片、碘伏棉棒与防水创可贴\n- [x] 防蚊虫叮咬喷雾与清凉油\n- [ ] 口服补液盐散与诺氟沙星肠道胶囊\n- [ ] 户外高帮防滑徒步鞋与专业护膝\n- [ ] 卫星定位救援呼叫器北斗车载端", None, "野外装备", ["田野安全", "防护清单"]),
        ("传统手工造纸（泾县皮纸）十三道工序记录表：\n- [x] 选料：青檀树皮浸泡、剥皮与日晒蒸煮\n- [x] 踏料与舂碓：石臼反复碾压纤维至松散\n- [ ] 捞纸：双人抬帘起落控制厚薄均匀度\n- [ ] 榨水：木榨重石压榨去除游离水分\n- [ ] 焙纸：铁板烘热刷帚抚平定型烘干", "林晚", "非遗记录", ["手工纸", "泾县皮纸"]),
        ("古建筑三维激光扫描点云数据备份规范 Checklist：\n- [x] 现场核对多测站点云拼接重合误差（<3mm）\n- [x] 每日考察结束后同步导入移动工作站三盘备份\n- [ ] 导出原始点云LAS格式与高精贴图纹理包\n- [ ] 建立应县木塔平座暗层三维网格模型", "林晚", "数据规范", ["三维测绘", "点云", "数字化"]),
        ("乡土人类学村落口述史访谈提纲与受访人登记：\n- [x] 呈坎罗氏宗族世系源流与清代徽商往事\n- [x] 泰顺廊桥绳桥头建造主墨师傅传规记忆\n- [ ] 龙泉金村南宋古窑址瓷片堆积层口传掌故\n- [ ] 整理十位七十岁以上乡村老工匠录像归档", "林晚", "口述史", ["人类学", "乡村记忆"]),
        ("传统木作榫卯二十四式测绘图谱整理待办：\n- [x] 绘制抱肩榫、粽角榫与夹头榫透视分解图\n- [x] 绘制挂榫、托角榫与走马销受力原理图\n- [ ] 绘制大木作馒头榫、巴掌榫与燕尾榫详图\n- [ ] 校对梁思成《营造算例》对应尺寸比例注释", "林晚", "图谱整理", ["榫卯", "大木作", "制图"]),
        ("云南白族民居彩画与照壁形制记录表：\n- [x] 拍摄喜洲四合五天井照壁苍山大理石天然画\n- [x] 记录檐下泥塑彩绘渔樵耕读人物造型细节\n- [ ] 勘测大理白族传统土木建筑抗震减震斗栱形制\n- [ ] 收集白族民居彩画矿物颜料调配古法配方", None, "民居调研", ["白族建筑", "彩画", "照壁"]),
        ("博士后田野调查工作站阶段性研究总结待办：\n- [x] 撰写完成《宋辽大木作铺作层受力演变》初稿\n- [x] 提交《徽州传统村落水系防洪适应机制》报告\n- [ ] 整理发表《闽浙木拱廊桥构造力学与匠作传承》\n- [ ] 组织筹备全国古建筑测绘青年学者研讨会", "林晚", "工作总结", ["学术规划", "研究总结"]),
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
            "location": "田野工作站",
            "temperature": "19°C",
            "favorite": i in [1, 2, 8, 13],
            "type_ground_truth": "original"
        })

    # =========================================================================
    # 类别 5: 古建测绘图纸与现场影像记录 (10 条) - Ground Truth: original
    # =========================================================================
    media_notes_data = [
        ("应县木塔二层平座暗层斗栱节点测绘图纸与特写：\n[图片:应县木塔平座斗栱暗层测绘.jpg]\n暗层内部由内外两圈柱网与斜撑交织，构成了极其坚固的箱型结构刚度环。辽代匠师对力学传导的理解令人惊叹。——林晚", "yingxian_pagoda_bracket.jpg", "林晚", "木塔手记", ["木塔", "斗栱", "图纸"]),
        ("太原晋祠圣母殿前廊宋代木雕盘龙立面测绘：\n[图片:晋祠前廊木雕盘龙详图.png]\n一条宋代木雕龙怒目张口，四爪遒劲抓抱檐柱。木质表面保留有早期青绿朱砂矿物颜料痕迹。——林晚", "jinci_dragon_pillar.png", "林晚", None, ["晋祠", "木雕", "宋代"]),
        ("徽州呈坎罗东舒祠宝纶阁白果木雀替特写：\n[图片:宝纶阁镂空木雕雀替.jpg]\n明代白果木雕刻，九层镂空，刀法圆润精湛。历经数百年未受虫蛀，在天井斜阳下投射出纤丽的花影。", "baolunge_spandrel.jpg", None, None, ["呈坎", "木雕", "徽派建筑"]),
        ("蓟县独乐寺观音阁侧样测绘剖面手稿：\n[图片:独乐寺观音阁剖面测绘手稿.png]\n手绘侧样剖面，清晰标注上下层檐出挑距离与柱头铺作角度。辽构粗壮硕大的用材与沉稳的大屋顶尺度呼之欲出。——林晚", "dulesi_section_drawing.png", "林晚", "测绘图谱", ["独乐寺", "辽代木构", "手稿"]),
        ("浙江泰顺北涧桥编木拱梁纵剖结构测绘照：\n[图片:北涧桥叠梁编木拱结构.jpg]\n纵向排列的圆木与横向锁固梁相互别压咬合，形成优雅完美的抛物线红桥拱券。——林晚", "taishun_bridge_arch.jpg", "林晚", "廊桥手记", ["泰顺廊桥", "木拱桥", "桥梁"]),
        ("泉州开元寺仁寿塔须弥座浮雕天王像特写：\n[图片:开元寺西塔须弥座浮雕天王.jpg]\n宋代花岗岩深浮雕，天王金刚身披铠甲，怒目威严。海风千年吹拂侵蚀，线条反倒增添了一种浑厚斑驳的质感。", "kaiyuansi_stone_carving.jpg", None, None, ["泉州", "开元寺", "石雕"]),
        ("景德镇三宝村柴烧镇窑窑顶双曲拱砖石结构：\n[图片:景德镇传统蛋形柴窑拱券.jpg]\n传统蛋形柴窑拱顶全凭耐火砖与黄泥浆契合，受热膨胀时自相挤紧，蕴含着民间工匠极高的耐热拱券经验。——林晚", "jingdezhen_kiln_arch.jpg", "林晚", None, ["柴窑", "窑炉构造", "景德镇"]),
        ("五台山佛光寺东大殿梁架七铺作现场实测照片：\n[图片:佛光寺东大殿七铺作斗栱实录.jpg]\n仰视佛光寺东大殿柱头铺作，双抄双下昂挑出达四米之远。唐构之雄伟，非亲临其境无法想象其震撼。——林晚", "foguangsi_bracket_set.jpg", "林晚", "佛光寺手记", ["佛光寺", "唐代建筑", "大木作"]),
        ("徽州明代老宅天井排水水街石渠构造测绘：\n[图片:徽州老民居暗渠排水系统.png]\n天井四水归堂，青石地漏下接地下陶管与青石阴沟，雨水经多重沉淀流入村中水圳，百年未见内涝。——林晚", "huizhou_drainage_system.png", "林晚", None, ["徽州老宅", "水系构造", "古水利"]),
        ("黔东南增冲鼓楼十三重密檐穿斗手绘透视草图：\n[图片:增冲鼓楼手绘等角透视图.jpg]\n用等角投影透视画法拆解十三重檐与四根通天主柱的穿接关系，杉木榫卯咬合的精密结构跃然纸上。——林晚", "zengchong_axonometric.jpg", "林晚", "鼓楼手绘", ["侗寨鼓楼", "透视图", "手绘"]),
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
            "location": "田野现场",
            "temperature": "18°C",
            "favorite": i in [1, 4, 8],
            "has_media": True,
            "type_ground_truth": "original"
        })

    return notes

# -----------------------------------------------------------------------------
# 归属算法实现（匹配 ThoughtEcho QuoteModel 最新实现）
# -----------------------------------------------------------------------------
def legacy_classify_attribution(note, nickname=""):
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
# 林晚实机场景基准测试
# -----------------------------------------------------------------------------
def run_benchmark():
    print("=" * 80)
    print("🚀 开始执行 ThoughtEcho 第二模拟用户（林晚·古建与风物学者）100篇基准评测")
    print("=" * 80)

    notes = generate_100_lin_wan_notes()
    print(f"📊 已生成林晚高保真拟真笔记总数: {len(notes)} 篇")
    type_counts = {}
    for n in notes:
        cat = n["id"].split("-")[0]
        type_counts[cat] = type_counts.get(cat, 0) + 1
    print(f"   - 田野调查与古建考察 (travel): {type_counts.get('travel', 0)} 篇")
    print(f"   - 营造典籍与民艺摘录 (excerpt): {type_counts.get('excerpt', 0)} 篇")
    print(f"   - 风物食记与工匠随笔 (rambling): {type_counts.get('rambling', 0)} 篇")
    print(f"   - 测绘清单与结构待办 (todo): {type_counts.get('todo', 0)} 篇")
    print(f"   - 测绘手稿与实测图像 (media): {type_counts.get('media', 0)} 篇")

    # 1. 归属算法准确率评测
    print("\n" + "-" * 80)
    print("🔬 [评测维度 1]: 未设昵称时自签名笔名（林晚）归属识别准确率对比")
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
    print(f"   误判为摘录的原创笔记数: {legacy_false_excerpts} 篇 (将林晚署名的田野笔记/食记错当外部作者)")
    print(f"✅ 修复后 (Optimized) 归属准确率: {optimized_correct}/{len(notes)} ({opt_acc:.1f}%)")
    print(f"   误判为摘录的原创笔记数: {optimized_false_excerpts} 篇")

    # 2. Dreaming 采样纯度评估
    print("\n" + "-" * 80)
    print("🔬 [评测维度 2]: Dreaming 采样池隔离纯度度量 (Voice vs Taste)")
    print("-" * 80)

    opt_originals = [n for n in notes if optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases) == "original"]
    opt_excerpts = [n for n in notes if optimized_classify_attribution(n, nickname="", inferred_aliases=inferred_aliases) == "excerpt"]

    lin_wan_in_taste = [n for n in opt_excerpts if "林晚" in (n.get("source_author") or "") or "林晚" in (n.get("source_work") or "")]
    print(f"📌 原创池总数: {len(opt_originals)} 篇 (全量保留为文风 Voice 归纳基准)")
    print(f"📌 摘录池总数: {len(opt_excerpts)} 篇 (全量保留为品味 Taste 归纳基准)")
    print(f"🛡️ 摘录品味池受「林晚」污染篇数: {len(lin_wan_in_taste)} 篇 (纯净度: {100.0 - len(lin_wan_in_taste)/len(opt_excerpts)*100:.1f}%)")

    # 3. 实机 LLM 评测
    if not API_KEY:
        print("\n⚠️ 未检测到有效 GEMINI_API_KEY，跳过实机 LLM 评测。")
        return

    print("\n" + "-" * 80)
    print("🔬 [评测维度 3]: 实机 Gemini 模型评测（林晚画像注入后的文风、品味与记忆自洽性）")
    print("-" * 80)

    client = ResilientGeminiClient(API_KEY, BASE_URL, PREFERRED_MODELS)

    lin_wan_profile = (
        "<user_profile>\n"
        "以下是你在过往对话中记下的用户偏好，仅描述该怎么回应这个用户：\n"
        "- [称呼·用户填写] 称呼用户为「林晚」\n"
        "- [文风·3天前] 偏好观察性田野散文与详实白描，注重建筑构件、材料肌理、空间构造与风物细节，语言温润典雅，多感官描写与地方民俗记录，段落长句舒缓，避免浮躁口号与排比套话\n"
        "- [品味·3天前] 偏好古建营造与民艺人类学（梁思成、林徽因、李诫《营造法式》、费孝通、沈从文、汪曾祺、柳宗悦），关注乡土中国、手工艺温度与时间造物\n"
        "- [偏好·5天前] 喜欢田野古建考察测绘、传统木作榫卯、品武夷岩茶（大红袍/肉桂）、手绘剖面草图与逛传统农贸市集\n"
        "- [近况·1天前] 最近在做山西应县木塔与徽州古村落宗祠测绘整理，撰写大木作构件榫卯演变论文，常喝岩茶与整理田野口述史\n"
        "</user_profile>"
    )

    test_cases = [
        {
            "id": "lin_wan_sc1_article",
            "title": "场景 1: 生成古建考察散文（佛光寺或应县木塔）",
            "prompt": "我刚完成佛光寺东大殿和应县木塔的现场测绘，想写一篇关于中国早期木构斗栱与梁架生命力的随笔，帮我起个头并写出前两段。",
            "expect": ["斗栱", "梁架", "木构", "佛光寺", "木塔"]
        },
        {
            "id": "lin_wan_sc2_polish",
            "title": "场景 2: 文本润色（保留材料肌理与田野白描）",
            "prompt": "帮我润色这段田野手记，不要破坏我的观察细节：'今天在徽州呈坎看老木匠修祠堂，白果木雀替雕得很细，老张用推刨刮木头，薄薄的木花卷起来像丝绸，木香很好闻。老张说木头是有灵性的。'",
            "expect": ["呈坎", "白果木", "雀替", "木花", "木香"]
        },
        {
            "id": "lin_wan_sc3_reading",
            "title": "场景 3: 书籍与思想推荐（契合营造学与乡土民艺）",
            "prompt": "最近田野跑得有些疲惫，想读点能让人沉静下来、探讨传统器物、乡村社会或建筑手艺的书，有什么好推荐吗？",
            "expect": ["营造", "民艺", "沈从文", "梁思成", "费孝通", "手艺", "乡土", "木作"]
        },
        {
            "id": "lin_wan_sc4_recent",
            "title": "场景 4: 近况感知与跨会话连续性",
            "prompt": "今天忙完有点放空，你还记得我最近都在琢磨些什么吗？",
            "expect": ["木塔", "徽州", "测绘", "榫卯", "岩茶", "宗祠"]
        }
    ]

    case_results = []

    for tc in test_cases:
        print(f"\n📝 正在执行: {tc['title']}")
        system_prompt = (
            "你是心迹（ThoughtEcho）笔记应用的 Thoughter AI 伴侣。"
            "温和、真诚、有洞察力。严禁机械宣读记忆，自然融入对话。"
        )
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": lin_wan_profile},
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
    opt_purity = (100.0 - len(lin_wan_in_taste) / len(opt_excerpts) * 100) if opt_excerpts else 0.0

    print("=" * 80)
    print("🎯 林晚基准测试综合度量汇总")
    print("=" * 80)
    print(f"1. 归属辨析准确率: 从 {leg_acc:.1f}% 提升至 {opt_acc:.1f}% (+{opt_acc-leg_acc:.1f}%)")
    print(f"2. Dreaming 采样纯度: 原创 Voice 池 {len(opt_originals)} 篇，摘录 Taste 池林晚污染 {len(lin_wan_in_taste)} 篇 (纯净度: {opt_purity:.1f}%)")
    print(f"3. 场景评测通过率: {successful_cases}/{total_cases} ({case_success_rate:.1f}%)")
    print("=" * 80)

if __name__ == "__main__":
    run_benchmark()
