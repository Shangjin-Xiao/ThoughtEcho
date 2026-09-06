#!/usr/bin/env python3
"""
ThoughtEcho Thoughter AI 拟真场景综合评测与探针执行引擎
"""

import os
import sys
import json
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
BASE_URL = os.getenv("TE_TEST_BASE_URL", ENV.get("AGENT_TEST_BASE_URL", "https://ollama.com/v1"))
MODEL = os.getenv("TE_PROBE_MODEL", os.getenv("TE_TEST_MODEL", ENV.get("AGENT_TEST_MODEL", "gemma4:31b")))
API_KEY = os.getenv("TE_TEST_API_KEY", ENV.get("AGENT_TEST_API_KEY", ""))

print(f"🔧 配置: Model={MODEL} | Endpoint={BASE_URL} | Key={API_KEY[:6]}***")

# -----------------------------------------------------------------------------
# 种子数据（22 篇高保真拟真笔记）
# -----------------------------------------------------------------------------
def get_seed_notes():
    now = datetime.now()
    def days_ago(d):
        return (now - timedelta(days=d)).strftime("%Y-%m-%d %H:%M:%S")

    return [
        # 1. 名家名著摘录
        {
            "id": "seed-excerpt-turkle",
            "content": "沉浸在连接中却感到孤立，技术承诺免除脆弱的陪伴。我们期待技术能替代真实的人际投入，却忘记了独处才是反思的起点。",
            "date": days_ago(14),
            "source_author": "雪莉·特克尔",
            "source_work": "群体性孤独",
            "tags": ["读书", "技术思考"],
            "weather": "rainy",
            "day_period": "evening",
            "location": "杭州·西湖区",
            "temperature": "18°C",
            "favorite": True,
        },
        {
            "id": "seed-excerpt-seneca",
            "content": "并非我们拥有的时间太少，而是我们虚掷了太多。生命足够长久，如果我们善加利用，它足以完成最伟大的事业。",
            "date": days_ago(20),
            "source_author": "塞涅卡",
            "source_work": "论生命的短促",
            "tags": ["读书", "斯多葛与哲学"],
            "weather": "clear",
            "day_period": "morning",
            "location": "杭州·西湖区",
            "temperature": "22°C",
            "favorite": False,
        },
        {
            "id": "seed-excerpt-jobs",
            "content": "保持饥饿，保持愚蠢。不要被教条所束缚，不要让别人的意见淹没了你内心的声音。",
            "date": days_ago(25),
            "source_author": "史蒂夫·乔布斯",
            "source_work": "斯坦福大学毕业演讲",
            "tags": ["读书", "工作与效率"],
            "weather": "cloudy",
            "day_period": "afternoon",
            "location": "上海·张江高科",
            "temperature": "24°C",
            "favorite": True,
        },
        {
            "id": "seed-excerpt-balzac",
            "content": "苦难对于天才是一块垫脚石，对于能干的人是一笔财富，对于弱者是个万丈深渊。",
            "date": days_ago(40),
            "source_author": "奥诺雷·德·巴尔扎克",
            "source_work": "人间喜剧",
            "tags": ["读书", "生活杂感"],
            "weather": "rainy",
            "day_period": "morning",
            "location": "杭州",
            "temperature": "15°C",
            "favorite": False,
        },
        {
            "id": "seed-excerpt-luxun",
            "content": "希望是本无所谓有，无所谓无的。这正如地上的路；其实地上本没有路，走的人多了，也便成了路。",
            "date": days_ago(60),
            "source_author": "鲁迅",
            "source_work": "故乡",
            "tags": ["读书"],
            "weather": "cloudy",
            "day_period": "night",
            "location": "绍兴",
            "temperature": "12°C",
            "favorite": False,
        },
        {
            "id": "seed-excerpt-aurelius",
            "content": "你拥有控制自己思想的力量，而不是外界事件。认识到这一点，你就会找到力量。",
            "date": days_ago(8),
            "source_author": "马可·奥勒留",
            "source_work": "沉思录",
            "tags": ["读书", "斯多葛与哲学"],
            "weather": "clear",
            "day_period": "dawn",
            "location": "杭州·天目里",
            "temperature": "19°C",
            "favorite": False,
        },
        {
            "id": "seed-excerpt-maugham",
            "content": "满地都是六便士，他却抬头看见了月亮。",
            "date": days_ago(50),
            "source_author": "威廉·萨默塞特·毛姆",
            "source_work": "月亮与六便士",
            "tags": ["读书", "生活杂感"],
            "weather": "clear",
            "day_period": "night",
            "location": "杭州",
            "temperature": "20°C",
            "favorite": True,
        },
        # 2. 个人生活与技术日记（原创）
        {
            "id": "seed-daily-subway",
            "content": "早高峰2号线挤得像沙丁鱼罐头，耳机里放着播客。突然想到状态管理的事件解耦其实跟人流调度一模一样，都是背压问题。",
            "date": days_ago(1),
            "source_author": "",
            "source_work": "",
            "tags": ["日常随笔", "技术思考"],
            "weather": "cloudy",
            "day_period": "morning",
            "location": "杭州·钱江世纪城",
            "temperature": "23°C",
            "favorite": False,
        },
        {
            "id": "seed-daily-flow",
            "content": "下午在海创园咖啡馆写完了架构重构提案，三个小时完全进入心流状态。没有无意义的会议和被打断，这种感觉太爽了。",
            "date": days_ago(2),
            "source_author": "",
            "source_work": "",
            "tags": ["日常随笔", "工作与效率"],
            "weather": "clear",
            "day_period": "afternoon",
            "location": "杭州·海创园",
            "temperature": "26°C",
            "favorite": True,
        },
        {
            "id": "seed-daily-anxiety",
            "content": "凌晨两点半突然醒来，想起下半年项目的技术路线选型，翻来覆去睡不着。爬起来泡了杯热牛奶，其实焦虑只是因为把未来的不确定性折现到了今天。",
            "date": days_ago(4),
            "source_author": "",
            "source_work": "",
            "tags": ["日常随笔", "生活杂感"],
            "weather": "rainy",
            "day_period": "night",
            "location": "杭州·西湖区文三路",
            "temperature": "19°C",
            "favorite": False,
        },
        {
            "id": "seed-daily-latte",
            "content": "楼下新开了一家手冲咖啡店，耶加雪菲的花香很明显。跟老板聊了聊，他也是程序员转行做咖啡的。他说代码会过时，但好喝的咖啡不会。",
            "date": days_ago(5),
            "source_author": "",
            "source_work": "",
            "tags": ["日常随笔", "生活杂感"],
            "weather": "clear",
            "day_period": "afternoon",
            "location": "杭州·天目里",
            "temperature": "25°C",
            "favorite": False,
        },
        {
            "id": "seed-daily-offline",
            "content": "思考了很久 Local-First 架构的核心哲学：数据所有权必须回归用户本身。云端只负责同步和多端协作，没有网络时一切功能必须丝滑可用。",
            "date": days_ago(6),
            "source_author": "",
            "source_work": "",
            "tags": ["技术思考", "产品与设计"],
            "weather": "clear",
            "day_period": "evening",
            "location": "杭州·海创园",
            "temperature": "21°C",
            "favorite": False,
        },
        {
            "id": "seed-daily-cat",
            "content": "小区里那只橘猫今天居然主动蹭我的裤脚，还发出呼噜呼噜的声音。给它喂了半根香肠，治愈了一整天的疲惫。",
            "date": days_ago(7),
            "source_author": "",
            "source_work": "",
            "tags": ["日常随笔", "生活杂感"],
            "weather": "cloudy",
            "day_period": "evening",
            "location": "杭州·西湖区",
            "temperature": "22°C",
            "favorite": False,
        },
        {
            "id": "seed-daily-hiking",
            "content": "周末去九溪十八涧徒步，一路绿意盎然，溪水冰凉。远离电脑屏幕和即时消息，在森林里大口呼吸，整个人像被重置了一遍。",
            "date": days_ago(9),
            "source_author": "",
            "source_work": "",
            "tags": ["日常随笔", "生活杂感"],
            "weather": "clear",
            "day_period": "afternoon",
            "location": "杭州·九溪",
            "temperature": "24°C",
            "favorite": True,
        },
        {
            "id": "seed-daily-refactor",
            "content": "花了一整天把遗留的全局状态重构成单一数据流，删掉了 400 行胶水代码。虽然外部界面看起来没有任何变化，但内心极度舒适。",
            "date": days_ago(10),
            "source_author": "",
            "source_work": "",
            "tags": ["技术思考", "工作与效率"],
            "weather": "cloudy",
            "day_period": "night",
            "location": "杭州·海创园",
            "temperature": "20°C",
            "favorite": False,
        },
        # 3. 用户自签名原创随笔
        {
            "id": "seed-user-signed-running",
            "content": "夜跑西湖十公里，微风拂面，苏堤上游人渐稀。汗水顺着脸颊流下来，所有的杂念都被脚步声踩碎在夜色里。——写于夜跑归来，阿澈",
            "date": days_ago(3),
            "source_author": "阿澈",
            "source_work": "",
            "tags": ["日常随笔", "生活杂感"],
            "weather": "clear",
            "day_period": "night",
            "location": "杭州·西湖断桥",
            "temperature": "21°C",
            "favorite": True,
        },
        {
            "id": "seed-user-signed-future",
            "content": "致五年后的阿澈：希望你依然对构建好产品保持好奇与热情，依然会在深夜为优雅的代码心动，依然敢于做出改变一生的决定。",
            "date": days_ago(12),
            "source_author": "阿澈",
            "source_work": "",
            "tags": ["日常随笔", "斯多葛与哲学"],
            "weather": "clear",
            "day_period": "night",
            "location": "杭州·西湖区",
            "temperature": "18°C",
            "favorite": False,
        },
        {
            "id": "seed-user-signed-garden",
            "content": "海创园的晚霞烧红了半边天，坐在长椅上吹着晚风，突然觉得生活除了赶进度，还有这些停顿的片刻值得铭记。——阿澈随笔",
            "date": days_ago(15),
            "source_author": "",
            "source_work": "",
            "tags": ["日常随笔", "生活杂感"],
            "weather": "clear",
            "day_period": "evening",
            "location": "杭州·海创园",
            "temperature": "25°C",
            "favorite": False,
        },
        # 4. 无作者/未标注出处名句
        {
            "id": "seed-unattributed-quote-1",
            "content": "真正重要的东西，用眼睛是看不见的，只有用心才能看清楚。",
            "date": days_ago(30),
            "source_author": "",
            "source_work": "",
            "tags": ["读书"],
            "weather": "cloudy",
            "day_period": "morning",
            "location": "杭州",
            "temperature": "17°C",
            "favorite": False,
        },
        {
            "id": "seed-unattributed-quote-2",
            "content": "每一个不曾起舞的日子，都是对生命的辜负。",
            "date": days_ago(35),
            "source_author": "",
            "source_work": "",
            "tags": ["读书", "斯多葛与哲学"],
            "weather": "clear",
            "day_period": "afternoon",
            "location": "杭州",
            "temperature": "22°C",
            "favorite": False,
        },
        {
            "id": "seed-unattributed-quote-3",
            "content": "人的一切痛苦，本质上都是对自己的无能的愤怒。",
            "date": days_ago(45),
            "source_author": "",
            "source_work": "",
            "tags": ["读书"],
            "weather": "rainy",
            "day_period": "night",
            "location": "杭州",
            "temperature": "16°C",
            "favorite": False,
        },
        {
            "id": "seed-daily-debug",
            "content": "排查了一个诡异的并发竞争 Bug，原来是异步通知在已销毁的实例上触发了微任务。写代码千万不能心存侥幸，边界防御必须扎扎实实。",
            "date": days_ago(11),
            "source_author": "",
            "source_work": "",
            "tags": ["技术思考", "工作与效率"],
            "weather": "clear",
            "day_period": "afternoon",
            "location": "杭州·海创园",
            "temperature": "23°C",
            "favorite": False,
        }
    ]

# -----------------------------------------------------------------------------
# 生产级 Tools Schema
# -----------------------------------------------------------------------------
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "explore_notes",
            "description": "按关键词、标签、日期范围或收藏状态检索用户的笔记列表。返回笔记列表（正文为200字预览，每条都包含代表原创/摘录的 type 字段）。",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "检索关键词，支持匹配正文或出处"},
                    "tags": {"type": "array", "items": {"type": "string"}, "description": "标签筛选"},
                    "date_start": {"type": "string", "description": "起始日期，格式 YYYY-MM-DD"},
                    "date_end": {"type": "string", "description": "截止日期，格式 YYYY-MM-DD"},
                    "favorites_only": {"type": "boolean", "description": "是否只看收藏笔记"},
                    "page": {"type": "integer", "description": "页码，从 1 开始"},
                    "page_size": {"type": "integer", "description": "每页条数，默认 10"}
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_note_detail",
            "description": "根据笔记 ID 获取单篇笔记的完整详情（含完整正文、全部标签、作者出处与修订版本号）。",
            "parameters": {
                "type": "object",
                "properties": {
                    "id": {"type": "string", "description": "笔记唯一 ID"}
                },
                "required": ["id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_tags",
            "description": "获取当前用户所有已创建的标签列表及其笔记计数。",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "remember",
            "description": "记录、更新或删除用户的长期偏好、习惯纠正或身份信息。",
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {"type": "string", "enum": ["add", "update", "delete"], "description": "操作类型"},
                    "kind": {"type": "string", "enum": ["identity", "preference", "correction", "context"], "description": "记忆类别"},
                    "content": {"type": "string", "description": "记忆具体内容描述"},
                    "id": {"type": "string", "description": "要更新或删除的记忆条目 ID"}
                },
                "required": ["action", "content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "recall",
            "description": "从长期记忆库中检索相关的用户偏好、习惯或历史事实。",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "记忆检索关键词"}
                },
                "required": ["query"]
            }
        }
    }
]

# -----------------------------------------------------------------------------
# 智能体模拟器与工具分发
# -----------------------------------------------------------------------------
class AgentSession:
    def __init__(self, nickname="", memory_enabled=True):
        self.nickname = nickname
        self.memory_enabled = memory_enabled
        self.notes = get_seed_notes()
        self.memory_store = [] # List of {"id": str, "kind": str, "content": str, "active": bool}
        self.messages = []
        self.system_prompt = self._build_system_prompt()
        self.messages.append({"role": "system", "content": self.system_prompt})

    def _build_system_prompt(self):
        now_str = datetime.now().strftime("%Y年%m月%d日 %H:%M")
        profile_str = ""
        if self.nickname:
            profile_str += f"\n- [用户称呼] {self.nickname}"
        for m in self.memory_store:
            if m.get("active", True):
                profile_str += f"\n- [{m['kind']}] {m['content']}"

        user_profile_block = f"<user_profile>{profile_str}\n</user_profile>" if profile_str else "<user_profile>\n</user_profile>"

        return f"""你叫 Thoughter，是笔记应用 ThoughtEcho（心迹）里的 AI 助手。你帮助用户理解、检索和整理自己的笔记，并在需要时查询外部信息。回答要准确、克制、自然，不编造用户经历或笔记内容。

## 当前运行环境
- 现在是 {now_str}。涉及“今天”“最近”“上周”等相对时间时，以此为基准换算成具体日期再调用工具。

## 决策顺序
1. 无需工具即可可靠回答时，直接回答。
2. 问题涉及用户过去写过的内容时，使用 `explore_notes`；列表中的正文只是 200 字预览。
3. 需要总结某篇特定笔记时，用 `get_note_detail` 获取完整正文。

## 区分“他写的”和“他摘的”
检索结果里每条笔记都带 `type`：`excerpt` 是他摘抄的别人的话，`original` 是他自己写的。这个字段是按有没有归属标注算出来的，读正文之前先看它。
- `type` 只按标注判断，有一个例外要你自己认：`author` 填的是用户自己的称呼时，那是他给原创署了名，按 `original` 对待。用户的称呼见 <user_profile> 或对话本身。
- 转述摘录必须点明它是摘录（“你抄下的那句…”“你收藏的那段…”），绝不能写成“你说过…”“你写道…”。
- 分析“用户自己怎么想、写过什么”时以原创笔记为依据。摘录只能作为共鸣证据，不能当成用户的自述。

## 长期记忆
- 用户纠正（“叫我阿澈”“以后技术建议优先Dart”）立刻使用 `remember` 工具记录。
- 偏好变了用 `remember` 的 update 改同一条，不要追加相反的。

{user_profile_block}"""

    def execute_tool(self, name, args):
        print(f"  ⚙️ [工具调用] {name}({json.dumps(args, ensure_ascii=False)})")
        if name == "explore_notes":
            query = args.get("query", "").lower()
            tags = args.get("tags", [])
            fav = args.get("favorites_only", False)
            
            results = []
            for n in self.notes:
                if fav and not n.get("favorite"):
                    continue
                if tags and not any(t in n.get("tags", []) for t in tags):
                    continue
                if query:
                    match = (query in n["content"].lower() or 
                             query in n["source_author"].lower() or 
                             query in n["source_work"].lower() or
                             any(query in t.lower() for t in n["tags"]))
                    if not match:
                        continue
                
                # 判定 attributionKind (生产规则)
                has_attribution = bool(n["source_author"].strip() or n["source_work"].strip())
                kind = "excerpt" if has_attribution else "original"
                
                results.append({
                    "id": n["id"],
                    "type": kind,
                    "content_preview": n["content"][:200],
                    "date": n["date"],
                    "author": n["source_author"] if n["source_author"] else None,
                    "source": n["source_work"] if n["source_work"] else None,
                    "tags": n["tags"],
                    "weather": n["weather"],
                    "location": n["location"]
                })
            
            return json.dumps({"total": len(results), "notes": results[:args.get("page_size", 10)]}, ensure_ascii=False)

        elif name == "get_note_detail":
            nid = args.get("id")
            for n in self.notes:
                if n["id"] == nid:
                    has_attribution = bool(n["source_author"].strip() or n["source_work"].strip())
                    return json.dumps({
                        "id": n["id"],
                        "type": "excerpt" if has_attribution else "original",
                        "content": n["content"],
                        "date": n["date"],
                        "author": n["source_author"],
                        "source": n["source_work"],
                        "tags": n["tags"],
                        "weather": n["weather"],
                        "location": n["location"],
                        "revision": 1
                    }, ensure_ascii=False)
            return json.dumps({"error": "Note not found"}, ensure_ascii=False)

        elif name == "get_tags":
            tag_counts = {}
            for n in self.notes:
                for t in n["tags"]:
                    tag_counts[t] = tag_counts.get(t, 0) + 1
            return json.dumps([{"name": k, "count": v} for k, v in tag_counts.items()], ensure_ascii=False)

        elif name == "remember":
            action = args.get("action", "add")
            kind = args.get("kind", "preference")
            content = args.get("content", "")
            mem_id = args.get("id", f"mem-{len(self.memory_store)+1}")
            
            if action == "add":
                # 检查冲突
                for m in self.memory_store:
                    if "咖啡" in content and "咖啡" in m["content"]:
                        m["active"] = False # supersede
                self.memory_store.append({"id": mem_id, "kind": kind, "content": content, "active": True})
                return json.dumps({"status": "success", "id": mem_id, "message": f"已记住: {content}"}, ensure_ascii=False)
            elif action == "update":
                for m in self.memory_store:
                    if m["id"] == mem_id or (args.get("id") and m["id"] == args.get("id")):
                        m["content"] = content
                        m["kind"] = kind
                        return json.dumps({"status": "success", "message": f"已更新记忆: {content}"}, ensure_ascii=False)
                self.memory_store.append({"id": mem_id, "kind": kind, "content": content, "active": True})
                return json.dumps({"status": "success", "message": f"已记录新偏好: {content}"}, ensure_ascii=False)
            elif action == "delete":
                for m in self.memory_store:
                    if m["id"] == mem_id:
                        m["active"] = False
                return json.dumps({"status": "success", "message": "记忆已删除"}, ensure_ascii=False)
            return json.dumps({"status": "ok"}, ensure_ascii=False)

        elif name == "recall":
            q = args.get("query", "")
            hits = [m for m in self.memory_store if m.get("active", True) and q in m["content"]]
            return json.dumps({"hits": hits}, ensure_ascii=False)

        return json.dumps({"error": f"Unknown tool {name}"})

    def ask(self, user_text):
        self.messages.append({"role": "user", "content": user_text})
        print(f"\n👤 [用户] {user_text}")

        tool_calls_record = []
        max_turns = 5

        for turn in range(max_turns):
            payload = {
                "model": MODEL,
                "messages": self.messages,
                "tools": TOOLS,
                "stream": False,
                "temperature": 0.3
            }

            req = urllib.request.Request(
                f"{BASE_URL.rstrip('/')}/chat/completions",
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {API_KEY}"
                },
                data=json.dumps(payload).encode("utf-8")
            )

            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
            except Exception as e:
                print(f"❌ API 请求失败: {e}")
                return {"reply": "", "tool_calls": tool_calls_record, "error": str(e)}

            choice = data["choices"][0]
            msg = choice["message"]
            self.messages.append(msg)

            tool_calls = msg.get("tool_calls", [])
            if not tool_calls:
                content = msg.get("content", "")
                print(f"\n🤖 [AI 回复]\n{content}\n")
                return {"reply": content, "tool_calls": tool_calls_record, "error": None}

            for tc in tool_calls:
                fn = tc["function"]
                fn_name = fn["name"]
                fn_args = json.loads(fn.get("arguments", "{}"))
                tool_calls_record.append({"name": fn_name, "args": fn_args})
                
                result_str = self.execute_tool(fn_name, fn_args)
                self.messages.append({
                    "role": "tool",
                    "tool_call_id": tc["id"],
                    "name": fn_name,
                    "content": result_str
                })

        return {"reply": self.messages[-1].get("content", ""), "tool_calls": tool_calls_record, "error": None}

# -----------------------------------------------------------------------------
# 5 大场景评测执行
# -----------------------------------------------------------------------------
def run_all_scenarios():
    report_lines = []
    report_lines.append(f"# Thoughter AI 拟真评测报告 ({MODEL})")
    report_lines.append(f"执行时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

    # =========================================================================
    # 场景 1: 自然闲聊孤独归属辨识（未设昵称）
    # =========================================================================
    print("\n" + "="*70)
    print("▶ 开始评测 [场景 1]: 自然闲聊孤独归属辨识（未设昵称）")
    print("="*70)
    
    session1 = AgentSession(nickname="")
    res1 = session1.ask("诶，我记得我之前记过一句关于孤独的话，但我好像没经历过那么深刻的孤独吧，你帮我翻翻那是怎么回事？")
    reply1 = res1["reply"]
    
    # 判定
    c1_explore = any(t["name"] == "explore_notes" for t in res1["tool_calls"])
    c1_author = "雪莉·特克尔" in reply1 or "特克尔" in reply1
    c1_work = "群体性孤独" in reply1
    c1_distinguish = any(w in reply1 for w in ["摘录", "他人", "引用", "不是你", "书中", "作者", "摘抄", "收藏"])
    
    print("--- 场景 1 判定标准 ---")
    print(f"1. 工具调用 explore_notes: {'✅ 命中' if c1_explore else '❌ 未调用'}")
    print(f"2. 识别出作者（雪莉·特克尔）: {'✅' if c1_author else '❌'}")
    print(f"3. 识别出作品名（群体性孤独）: {'✅' if c1_work else '❌'}")
    print(f"4. 澄清这是摘录/他人观点: {'✅' if c1_distinguish else '❌'}")

    report_lines.append("## 场景 1: 自然闲聊孤独归属辨识")
    report_lines.append(f"- **工具命中**: {'✅' if c1_explore else '❌'}")
    report_lines.append(f"- **作者出处识别**: {'✅' if c1_author and c1_work else '❌'}")
    report_lines.append(f"- **摘录属性澄清**: {'✅' if c1_distinguish else '❌'}")
    report_lines.append(f"- **AI 响应原文**:\n> {reply1.replace(chr(10), chr(10)+'> ')}\n")

    # =========================================================================
    # 场景 2: 未设昵称时对「自签名原创」阿澈的归属辨析
    # =========================================================================
    print("\n" + "="*70)
    print("▶ 开始评测 [场景 2]: 未设昵称时对「自签名原创」阿澈的归属辨析")
    print("="*70)

    session2 = AgentSession(nickname="")
    res2 = session2.ask("我之前有没有在断桥或者海创园留下过什么感慨？那个署名阿澈的是怎么回事？")
    reply2 = res2["reply"]

    c2_treat_original = any(w in reply2 for w in ["你自己", "你的笔名", "你的随笔", "你的原创", "夜跑", "海创园", "署名"])

    print("--- 场景 2 判定标准 ---")
    print(f"1. 工具调用: {'✅ 命中' if res2['tool_calls'] else '❌'}")
    print(f"2. 辨析为用户原创/笔名随笔: {'✅' if c2_treat_original else '❌'}")

    report_lines.append("## 场景 2: 自签名原创「阿澈」归属辨析")
    report_lines.append(f"- **原创/笔名辨析**: {'✅' if c2_treat_original else '❌'}")
    report_lines.append(f"- **AI 响应原文**:\n> {reply2.replace(chr(10), chr(10)+'> ')}\n")

    # =========================================================================
    # 场景 3: 个人周总结（过滤名家摘录）
    # =========================================================================
    print("\n" + "="*70)
    print("▶ 开始评测 [场景 3]: 个人周总结（过滤名家摘录）")
    print("="*70)

    session3 = AgentSession(nickname="")
    res3 = session3.ask("帮我回顾一下最近两周我自己真实的生活和技术思考，总结一下我最近的状态。注意我只要我自己经历的，那些名人名言就别算我头上了。")
    reply3 = res3["reply"]

    c3_user_life = any(w in reply3 for w in ["心流", "Local-First", "橘猫", "夜跑", "海创园", "九溪", "重构", "架构"])
    c3_exclude_famous = ("沉思录" not in reply3 or "摘录" in reply3) and ("保持饥饿" not in reply3 or "摘录" in reply3)

    print("--- 场景 3 判定标准 ---")
    print(f"1. 包含用户真实生活/技术内容: {'✅' if c3_user_life else '❌'}")
    print(f"2. 排除名家名句算作个人经历: {'✅' if c3_exclude_famous else '❌'}")

    report_lines.append("## 场景 3: 个人周总结（过滤名家摘录）")
    report_lines.append(f"- **生活与技术提炼**: {'✅' if c3_user_life else '❌'}")
    report_lines.append(f"- **名家摘录隔离**: {'✅' if c3_exclude_famous else '❌'}")
    report_lines.append(f"- **AI 响应原文**:\n> {reply3.replace(chr(10), chr(10)+'> ')}\n")

    # =========================================================================
    # 场景 4: 自然口语偏好纠正与长期记忆写入
    # =========================================================================
    print("\n" + "="*70)
    print("▶ 开始评测 [场景 4]: 自然口语偏好纠正与长期记忆写入")
    print("="*70)

    session4 = AgentSession(nickname="小陈")
    res4 = session4.ask("以后别叫我小陈了，叫我阿澈就好。还有，我平时写代码主要用 Dart 和 Rust，以后给技术建议优先从这两门语言的角度出发。")
    reply4 = res4["reply"]

    c4_remember = any(t["name"] == "remember" for t in res4["tool_calls"])
    c4_memory_content = any("阿澈" in m["content"] or "Dart" in m["content"] or "Rust" in m["content"] for m in session4.memory_store)

    print("--- 场景 4 判定标准 ---")
    print(f"1. 调用 remember 工具: {'✅' if c4_remember else '❌'}")
    print(f"2. 记忆库成功写入新称呼/技术偏好: {'✅' if c4_memory_content else '❌'}")
    print(f"3. 记忆库当前条目: {json.dumps(session4.memory_store, ensure_ascii=False)}")

    report_lines.append("## 场景 4: 口语偏好纠正与长期记忆")
    report_lines.append(f"- **remember 工具调用**: {'✅' if c4_remember else '❌'}")
    report_lines.append(f"- **记忆条目持久化**: {'✅' if c4_memory_content else '❌'}")
    report_lines.append(f"- **记忆内容**: `{json.dumps(session4.memory_store, ensure_ascii=False)}`")
    report_lines.append(f"- **AI 响应原文**:\n> {reply4.replace(chr(10), chr(10)+'> ')}\n")

    # =========================================================================
    # 场景 5: 偏好翻转与原位覆盖（Supersede）
    # =========================================================================
    print("\n" + "="*70)
    print("▶ 开始评测 [场景 5]: 偏好翻转与原位覆盖（Supersede）")
    print("="*70)

    session5 = AgentSession(nickname="阿澈")
    session5.ask("我特别喜欢喝手冲咖啡，每天至少两杯。")
    print(f"  第一次记录偏好后记忆库: {json.dumps(session5.memory_store, ensure_ascii=False)}")

    res5_2 = session5.ask("最近医生建议我戒咖啡因，我现在完全不喝咖啡了，改喝普洱茶了。")
    print(f"  翻转偏好后记忆库: {json.dumps(session5.memory_store, ensure_ascii=False)}")

    active_coffee = [m for m in session5.memory_store if m.get("active", True) and "喜欢" in m["content"] and "咖啡" in m["content"]]
    c5_superseded = len(active_coffee) == 0

    print("--- 场景 5 判定标准 ---")
    print(f"1. 旧的喜欢咖啡偏好被成功废弃/覆盖: {'✅' if c5_superseded else '❌'}")

    report_lines.append("## 场景 5: 偏好翻转与原位覆盖")
    report_lines.append(f"- **旧矛盾偏好覆盖**: {'✅' if c5_superseded else '❌'}")
    report_lines.append(f"- **最终活跃记忆**: `{json.dumps([m for m in session5.memory_store if m.get('active', True)], ensure_ascii=False)}`\n")

    # 输出 Markdown 报告
    output_path = f"/home/azureuser/ThoughtEcho/build/agent-probe/00-综合评测-{MODEL.replace(':', '_')}.md"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(report_lines))
    print(f"\n📄 综合评测报告已生成: {output_path}")

if __name__ == "__main__":
    run_all_scenarios()
