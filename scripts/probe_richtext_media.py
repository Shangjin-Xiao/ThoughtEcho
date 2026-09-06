#!/usr/bin/env python3
"""
ThoughtEcho Thoughter AI 富文本与媒体笔记专项评测引擎
涵盖：
  1. 富文本局部精准修改 (replace / insertBefore / insertAfter)
  2. 结构化块级格式插入 (insert_blocks: 标题、复选框待办、引用块)
  3. 富文本整篇重写 (replaceDocument 与 Delta 规范化)
  4. 带图片/媒体的富文本笔记修改（零媒体丢失防御校验）
  5. 双模态一致性与 Revision 版本冲突自愈
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

print(f"🔧 富文本/媒体评测配置: Model={MODEL} | Endpoint={BASE_URL} | Key={API_KEY[:6]}***")

# -----------------------------------------------------------------------------
# 种子富文本笔记（含结构化排版与内嵌图片）
# -----------------------------------------------------------------------------
def get_richtext_seed_notes():
    now = datetime.now()
    def days_ago(d):
        return (now - timedelta(days=d)).strftime("%Y-%m-%d %H:%M:%S")

    return [
        # 1. 结构化富文本笔记 (带标题、正文、待办清单)
        {
            "id": "note-rich-plan",
            "content": "心迹 2.0 发布规划\n\n核心要点：\n- 支持富文本与多端同步\n- 强化 Thoughter AI 长期记忆\n- 完善本地优先离线能力\n\n上线前务必做好全量回归测试。",
            "delta_content": json.dumps([
                {"insert": "心迹 2.0 发布规划"},
                {"attributes": {"header": 1}, "insert": "\n"},
                {"insert": "\n核心要点：\n"},
                {"insert": "支持富文本与多端同步"},
                {"attributes": {"list": "checked"}, "insert": "\n"},
                {"insert": "强化 Thoughter AI 长期记忆"},
                {"attributes": {"list": "unchecked"}, "insert": "\n"},
                {"insert": "完善本地优先离线能力"},
                {"attributes": {"list": "unchecked"}, "insert": "\n"},
                {"insert": "\n上线前务必做好全量回归测试。\n"}
            ]),
            "edit_source": "fullscreen",
            "revision": "rev-101",
            "date": days_ago(2),
            "tags": ["技术思考", "工作与效率"]
        },

        # 2. 夹带图片的富文本笔记 (Media Embed)
        {
            "id": "note-rich-media",
            "content": "在天目里美术馆看到的那幅画。\n\n[media]\n\n拍的不好看，反正就是很蓝，很安静，说不上来哪里好。",
            "delta_content": json.dumps([
                {"insert": "在天目里美术馆看到的那幅画。\n\n"},
                {"insert": {"image": "file:///data/user/0/com.thoughtecho/media/art_blue.jpg"}},
                {"insert": "\n\n拍的不好看，反正就是很蓝，很安静，说不上来哪里好。\n"}
            ]),
            "edit_source": "fullscreen",
            "revision": "rev-202",
            "date": days_ago(4),
            "tags": ["日常随笔", "生活杂感"]
        },

        # 3. 诗歌排版笔记 (带引用块与斜体)
        {
            "id": "note-rich-poem",
            "content": "雨夜杂感\n\n檐雨如丝落小阶，茶烟一缕带诗怀。\n\n深夜写代码，最怕不是 Bug，而是思路被打破的瞬间。",
            "delta_content": json.dumps([
                {"insert": "雨夜杂感"},
                {"attributes": {"header": 2}, "insert": "\n"},
                {"insert": "檐雨如丝落小阶，茶烟一缕带诗怀。"},
                {"attributes": {"blockquote": True}, "insert": "\n"},
                {"insert": "\n深夜写代码，最怕不是 Bug，而是思路被打破的瞬间。\n"}
            ]),
            "edit_source": "fullscreen",
            "revision": "rev-303",
            "date": days_ago(5),
            "tags": ["日常随笔"]
        }
    ]

# -----------------------------------------------------------------------------
# 生产级 Propose Note Edit Tools Schema
# -----------------------------------------------------------------------------
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "explore_notes",
            "description": "按关键词检索笔记。",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string"}
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_note_detail",
            "description": "获取笔记详情，返回正文预览、delta结构与最新 base_revision。",
            "parameters": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"}
                },
                "required": ["id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "propose_note_edit",
            "description": "对已有笔记提出修改提案。包含 operations（支持 replace, insertBefore, insertAfter, append, replaceDocument）。含媒体的笔记严禁使用丢失媒体的整篇重写，必须使用局部文本 replace。",
            "parameters": {
                "type": "object",
                "properties": {
                    "proposal_title": {"type": "string", "description": "提案卡片标题"},
                    "reason": {"type": "string", "description": "修改理由"},
                    "note_id": {"type": "string", "description": "笔记 ID"},
                    "base_revision": {"type": "string", "description": "原样填写 get_note_detail 返回的 revision"},
                    "result_kind": {"type": "string", "enum": ["preserve", "rich"], "description": "结果形态"},
                    "operations": {
                        "type": "array",
                        "description": "修改操作列表",
                        "items": {
                            "type": "object",
                            "properties": {
                                "type": {"type": "string", "enum": ["replace", "insertBefore", "insertAfter", "append", "replaceDocument"]},
                                "old_text": {"type": "string", "description": "被替换的原文锚点"},
                                "anchor_text": {"type": "string", "description": "插入位置的锚点"},
                                "insert_text": {"type": "string", "description": "写入的纯文本"},
                                "insert_blocks": {
                                    "type": "array",
                                    "description": "结构化格式块",
                                    "items": {
                                        "type": "object",
                                        "properties": {
                                            "block_type": {"type": "string", "enum": ["heading", "checklist", "blockquote", "codeblock", "bullet"]},
                                            "text": {"type": "string"}
                                        }
                                    }
                                }
                            },
                            "required": ["type"]
                        }
                    }
                },
                "required": ["proposal_title", "note_id", "base_revision", "result_kind", "operations"]
            }
        }
    }
]

class RichTextAgentSession:
    def __init__(self, bound_note=None):
        self.notes = get_richtext_seed_notes()
        self.bound_note = bound_note
        self.proposals = []
        self.messages = []
        self.system_prompt = self._build_prompt()
        self.messages.append({"role": "system", "content": self.system_prompt})

    def _build_prompt(self):
        bound_str = ""
        if self.bound_note:
            bound_str = f"""
## 当前编辑器绑定笔记上下文
用户正在编辑器中查看这篇富文本笔记：
<note id="{self.bound_note['id']}" revision="{self.bound_note['revision']}">
{self.bound_note['content']}
</note>
"""
        return f"""你叫 Thoughter，是笔记应用 ThoughtEcho（心迹）里的 AI 助手。

## 笔记修改规则
1. 修改笔记前必须通过 `get_note_detail` 获取最新正文与 `base_revision`。
2. 优先使用局部替换（type=replace / insertAfter 等），锚点 old_text 必须完全匹配原文且唯一。
3. **媒体安全防御准则**：富文本笔记中包含 [media]（图片、音频、视频）时，**严禁做跨越或丢失媒体的整篇替换**，必须使用局部文本 replace 仅修改文字部分，以确保图片媒体绝对不丢失。
4. 普通替换传 insert_text；需要富文本格式（标题、清单、引用）时传 insert_blocks。
{bound_str}"""

    def execute_tool(self, name, args):
        print(f"  ⚙️ [工具调用] {name}({json.dumps(args, ensure_ascii=False)})")
        if name == "explore_notes":
            q = args.get("query", "").lower()
            res = [n for n in self.notes if not q or q in n["content"].lower()]
            return json.dumps({"notes": [{"id": n["id"], "content_preview": n["content"][:100]} for n in res]}, ensure_ascii=False)

        elif name == "get_note_detail":
            nid = args.get("id")
            for n in self.notes:
                if n["id"] == nid:
                    return json.dumps({
                        "id": n["id"],
                        "content": n["content"],
                        "document_revision": n["revision"],
                        "has_media": "[media]" in n["content"] or "image" in n.get("delta_content", ""),
                        "tags": n["tags"]
                    }, ensure_ascii=False)
            return json.dumps({"error": "Note not found"}, ensure_ascii=False)

        elif name == "propose_note_edit":
            self.proposals.append(args)
            nid = args.get("note_id")
            ops = args.get("operations", [])
            
            # 校验媒体不变量 (hasSameEmbeds)
            target = next((n for n in self.notes if n["id"] == nid), None)
            if target and "[media]" in target["content"]:
                # 如果是整篇 replaceDocument 且没有嵌入媒体，则工具拒绝
                for op in ops:
                    if op.get("type") == "replaceDocument" and "[media]" not in op.get("insert_text", ""):
                        return json.dumps({"error": "为避免丢失笔记中的媒体，请保留图片、音频和视频，并改用不跨越媒体的局部文本修改。"}, ensure_ascii=False)

            return json.dumps({"status": "success", "proposal_title": args.get("proposal_title")}, ensure_ascii=False)

        return json.dumps({"error": "Unknown tool"})

    def ask(self, user_text):
        self.messages.append({"role": "user", "content": user_text})
        print(f"\n👤 [用户] {user_text}")

        for _ in range(5):
            payload = {
                "model": MODEL,
                "messages": self.messages,
                "tools": TOOLS,
                "stream": False,
                "temperature": 0.2
            }
            req = urllib.request.Request(
                f"{BASE_URL.rstrip('/')}/chat/completions",
                headers={"Content-Type": "application/json", "Authorization": f"Bearer {API_KEY}"},
                data=json.dumps(payload).encode("utf-8")
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read().decode("utf-8"))

            msg = data["choices"][0]["message"]
            self.messages.append(msg)
            tcs = msg.get("tool_calls", [])
            if not tcs:
                content = msg.get("content", "")
                print(f"\n🤖 [AI 回复]\n{content}\n")
                return {"reply": content, "proposals": self.proposals}

            for tc in tcs:
                fn = tc["function"]
                name = fn["name"]
                args = json.loads(fn.get("arguments", "{}"))
                res_str = self.execute_tool(name, args)
                self.messages.append({
                    "role": "tool",
                    "tool_call_id": tc["id"],
                    "name": name,
                    "content": res_str
                })

        return {"reply": self.messages[-1].get("content", ""), "proposals": self.proposals}

# -----------------------------------------------------------------------------
# 评测场景执行
# -----------------------------------------------------------------------------
def run_richtext_media_tests():
    report = []
    report.append(f"# Thoughter AI 富文本与媒体笔记深度评测 ({MODEL})")
    report.append(f"执行时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

    # =========================================================================
    # 场景 1: 带图片媒体的富文本笔记修改（零丢失测试）
    # =========================================================================
    print("="*70)
    print("▶ 场景 1: 带图片媒体的富文本笔记局部修改（零丢失测试）")
    print("="*70)

    notes = get_richtext_seed_notes()
    media_note = next(n for n in notes if n["id"] == "note-rich-media")
    s1 = RichTextAgentSession(bound_note=media_note)

    r1 = s1.ask("把图片后面那段口语化的描述改得更有艺术感和书面感一点，图片和第一句千万不要动。")
    
    c1_has_proposal = len(s1.proposals) > 0
    if c1_has_proposal:
        p1 = s1.proposals[0]
        ops = p1.get("operations", [])
        # 必须是局部 replace 操作，而不是整篇冲掉
        c1_is_local_replace = any(op.get("type") == "replace" for op in ops)
        c1_matches_old_text = any("拍的不好看" in op.get("old_text", "") for op in ops)
        c1_no_media_wipe = not any(op.get("type") == "replaceDocument" for op in ops)
        c1_rev_correct = p1.get("base_revision") == "rev-202"
    else:
        c1_is_local_replace = c1_matches_old_text = c1_no_media_wipe = c1_rev_correct = False

    print(f"💡 成功生成修改提案: {'✅' if c1_has_proposal else '❌'}")
    print(f"💡 采用局部文本 replace（非粗暴整篇重写）: {'✅' if c1_is_local_replace else '❌'}")
    print(f"💡 锚点 old_text 精确匹配图片后文本: {'✅' if c1_matches_old_text else '❌'}")
    print(f"💡 零媒体丢失防御（未破坏图片 embed）: {'✅' if c1_no_media_wipe else '❌'}")
    print(f"💡 正确携带 base_revision (rev-202): {'✅' if c1_rev_correct else '❌'}")
    if c1_has_proposal:
        print(f"   提案详情: {json.dumps(s1.proposals[0], ensure_ascii=False)}")

    report.append("## 场景 1: 带图片媒体的富文本笔记局部修改")
    report.append(f"- **局部 replace 策略**: {'✅' if c1_is_local_replace else '❌'}")
    report.append(f"- **图片 Embed 完整保留**: {'✅' if c1_no_media_wipe else '❌'}")
    report.append(f"- **锚点精确度**: {'✅' if c1_matches_old_text else '❌'}")
    report.append(f"- **提案内容**: `{json.dumps(s1.proposals[0] if s1.proposals else {}, ensure_ascii=False)}`\n")

    # =========================================================================
    # 场景 2: 结构化待办清单与标题插入 (insert_blocks / Checklist)
    # =========================================================================
    print("\n" + "="*70)
    print("▶ 场景 2: 结构化富文本待办清单修改")
    print("="*70)

    plan_note = next(n for n in notes if n["id"] == "note-rich-plan")
    s2 = RichTextAgentSession(bound_note=plan_note)

    r2 = s2.ask("在核心要点清单的最后，再追加一条未勾选的待办事项：‘准备 App Store 截图与发布文案’。")

    c2_has_proposal = len(s2.proposals) > 0
    if c2_has_proposal:
        p2 = s2.proposals[0]
        ops = p2.get("operations", [])
        c2_valid_op = any(op.get("type") in ["insertAfter", "append", "replace", "insertBefore"] for op in ops)
        c2_text_match = any("App Store" in op.get("insert_text", "") or any("App Store" in b.get("text", "") for b in op.get("insert_blocks", [])) for op in ops)
    else:
        c2_valid_op = c2_text_match = False

    print(f"💡 成功生成修改提案: {'✅' if c2_has_proposal else '❌'}")
    print(f"💡 使用正确的局部插入/追加操作: {'✅' if c2_valid_op else '❌'}")
    print(f"💡 待办文本精确包含目标内容: {'✅' if c2_text_match else '❌'}")
    if c2_has_proposal:
        print(f"   提案详情: {json.dumps(s2.proposals[0], ensure_ascii=False)}")

    report.append("## 场景 2: 结构化富文本待办清单追加")
    report.append(f"- **结构化操作调用**: {'✅' if c2_valid_op else '❌'}")
    report.append(f"- **待办项文本吻合**: {'✅' if c2_text_match else '❌'}")
    report.append(f"- **提案内容**: `{json.dumps(s2.proposals[0] if s2.proposals else {}, ensure_ascii=False)}`\n")

    # =========================================================================
    # 场景 3: 诗歌排版与引用块微调
    # =========================================================================
    print("\n" + "="*70)
    print("▶ 场景 3: 诗歌排版与引用块微调")
    print("="*70)

    poem_note = next(n for n in notes if n["id"] == "note-rich-poem")
    s3 = RichTextAgentSession(bound_note=poem_note)

    r3 = s3.ask("把第二句诗里的‘带诗怀’改成‘引诗裁’，其他排版格式保持不变。")

    c3_has_proposal = len(s3.proposals) > 0
    if c3_has_proposal:
        p3 = s3.proposals[0]
        ops = p3.get("operations", [])
        c3_anchor_poem = any("带诗怀" in op.get("old_text", "") for op in ops)
        c3_insert_poem = any("引诗裁" in op.get("insert_text", "") for op in ops)
    else:
        c3_anchor_poem = c3_insert_poem = False

    print(f"💡 成功生成修改提案: {'✅' if c3_has_proposal else '❌'}")
    print(f"💡 精准定位诗句锚点 (带诗怀): {'✅' if c3_anchor_poem else '❌'}")
    print(f"💡 精准替换为目标诗句 (引诗裁): {'✅' if c3_insert_poem else '❌'}")
    if c3_has_proposal:
        print(f"   提案详情: {json.dumps(s3.proposals[0], ensure_ascii=False)}")

    report.append("## 场景 3: 诗歌排版与局部词句微调")
    report.append(f"- **锚点匹配度**: {'✅' if c3_anchor_poem else '❌'}")
    report.append(f"- **格式保持与文本替换**: {'✅' if c3_insert_poem else '❌'}")
    report.append(f"- **提案内容**: `{json.dumps(s3.proposals[0] if s3.proposals else {}, ensure_ascii=False)}`\n")

    out_file = f"/home/azureuser/ThoughtEcho/build/agent-probe/00-富文本与媒体评测-{MODEL.replace(':', '_')}.md"
    with open(out_file, "w", encoding="utf-8") as f:
        f.write("\n".join(report))
    print(f"\n📄 富文本与媒体专项评测报告已生成: {out_file}")

if __name__ == "__main__":
    run_richtext_media_tests()
