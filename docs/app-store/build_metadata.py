#!/usr/bin/env python3
"""Builds appstore-metadata.json and measures every field against the App Store Connect limits."""
import json
import re
import unicodedata
from pathlib import Path

OUT = Path(__file__).with_name("appstore-metadata.json")


def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


NAME = "MindMap AI by xDev"

SUBTITLE = {
    "en-US": "Brainstorm & Organize Ideas",
    "vi": "Sơ đồ tư duy, sắp xếp ý tưởng",
}

# ---------------------------------------------------------------- descriptions

EN_MAC = """MindMap AI by xDev turns loose thoughts into a clear map you can edit. Type a topic, keep typing, and the map lays itself out.

MAP YOUR THINKING
• Automatic layout on an endless canvas, with zoom, collapse and expand
• Return adds a sibling, Tab adds a child; drag to reorder or move a branch
• Canvas and outline views of the same map
• Notes, web links and tags on any topic
• Search every map by title, topic or tag, with or without Vietnamese accents
• Favorites, Recent, and Recently Deleted for 30 days
• Undo and redo every change

AI ON YOUR MAC, WITH APPLE INTELLIGENCE
• Generate a map from a short description
• Suggest Subtopics, Brainstorm Ideas, Suggest Tags and Summarize Branch
• Rewrite a topic shorter, clearer, simpler or more formal, or in English or Vietnamese
• Ask About This Map: answers point to the topics they used
• AI results are labeled suggestions you can edit, accept or discard, and undo in one step

IMPORT, EXPORT AND SHARE
• Markdown and plain text import and export
• PNG and PDF export, plus complete MindMap AI Backup files
• Send text and links from other apps with the Share menu
• Shortcuts actions, and Spotlight finds your maps by title

MADE FOR THE MAC
• A full menu bar with keyboard shortcuts
• Each map in its own window
• AI Apps: let AI apps on your Mac read your maps over the Model Context Protocol (MCP). Off by default, read-only, limited to this Mac, with a key for each app

PRIVATE BY DESIGN
No account, no xDev server, no ads, and no data collected. Your maps are stored on your Mac, and AI runs on your Mac with Apple Intelligence. With AI Apps on, the apps you connect can read your maps and may send that text to their own AI provider.

AI features require a Mac with Apple silicon and Apple Intelligence turned on, in a supported language. On other Macs they are hidden and everything else works.

MINDMAP AI PRO
Mind mapping is free. Pro is a one-time purchase, not a subscription, and adds:
• High-resolution PNG and multi-page vector PDF export
• The xDev Blue and Graphite themes
• Voice input in English or Vietnamese, recognized on your device
• Advanced AI: generate a map from a long description, summarize a whole map, find missing topics
Pro works with Family Sharing, and one purchase also unlocks it on iPad and iPhone."""

EN_IOS = """MindMap AI by xDev turns loose thoughts into a clear map you can edit, on iPhone and iPad. Add a topic, then the next, and the map lays itself out.

MAP YOUR THINKING
• Automatic layout on an endless canvas, with zoom, collapse and expand
• Pinch to zoom, and tap + on a selected topic to add a child or a sibling
• Canvas and outline views of the same map
• Notes, web links and tags on any topic
• Search every map by title, topic or tag, with or without Vietnamese accents
• Favorites, Recent, and Recently Deleted for 30 days
• Undo and redo every change

AI ON YOUR DEVICE, WITH APPLE INTELLIGENCE
• Generate a map from a short description
• Suggest Subtopics, Brainstorm Ideas, Suggest Tags and Summarize Branch
• Rewrite a topic shorter, clearer, simpler or more formal, or in English or Vietnamese
• Ask About This Map: answers point to the topics they used
• AI results are labeled suggestions you can edit, accept or discard, and undo in one step

IMPORT, EXPORT AND SHARE
• Markdown and plain text import and export
• PNG and PDF export, plus complete MindMap AI Backup files
• Send text and links from other apps to a map with the share sheet
• Shortcuts actions, and Spotlight finds your maps by title

PRIVATE BY DESIGN
No account, no xDev server, no ads, and no data collected. Your maps are stored on your device, and AI runs on your device with Apple Intelligence.

AI features require an iPhone or iPad that supports Apple Intelligence, with Apple Intelligence turned on, in a supported language. On other devices they are hidden and everything else works.

MINDMAP AI PRO
Mind mapping is free. Pro is a one-time purchase, not a subscription, and adds:
• High-resolution PNG and multi-page vector PDF export
• The xDev Blue and Graphite themes
• Voice input in English or Vietnamese, recognized on your device
• Advanced AI: generate a map from a long description, summarize a whole map, find missing topics
Pro works with Family Sharing, and one purchase also unlocks it on the Mac."""

VI_MAC = """MindMap AI by xDev biến những suy nghĩ rời rạc thành một sơ đồ rõ ràng, sửa được. Gõ một chủ đề, gõ tiếp, sơ đồ tự sắp xếp.

SƠ ĐỒ CHO MỌI Ý TƯỞNG
• Bố cục tự động trên khung vẽ rộng, phóng to, thu nhỏ, thu gọn và mở rộng nhánh
• Return thêm chủ đề cùng cấp, Tab thêm chủ đề con; kéo để sắp lại hoặc chuyển cả nhánh
• Xem cùng một sơ đồ dạng khung vẽ hoặc dàn ý
• Ghi chú, liên kết web và thẻ cho từng chủ đề
• Tìm mọi sơ đồ theo tên, chủ đề hoặc thẻ, gõ có dấu hay không dấu đều được
• Yêu thích, Gần đây, và Đã xoá gần đây giữ sơ đồ 30 ngày
• Hoàn tác và làm lại mọi thay đổi

AI NGAY TRÊN MÁY MAC, BẰNG APPLE INTELLIGENCE
• Tạo sơ đồ từ một mô tả ngắn
• Đề xuất chủ đề con, động não ý tưởng, gợi ý thẻ, tóm tắt nhánh
• Viết lại chủ đề ngắn hơn, rõ hơn, đơn giản hơn, trang trọng hơn, hoặc sang tiếng Việt, tiếng Anh
• Hỏi về sơ đồ này: câu trả lời chỉ ra những chủ đề đã dùng
• Kết quả AI là đề xuất có nhãn AI: sửa, chấp nhận hoặc bỏ đi, và hoàn tác trong một bước

NHẬP, XUẤT VÀ CHIA SẺ
• Nhập và xuất Markdown, văn bản thuần
• Xuất PNG, PDF và Bản sao lưu MindMap AI đầy đủ
• Gửi văn bản và liên kết từ ứng dụng khác qua menu Chia sẻ
• Tác vụ cho ứng dụng Phím tắt, và Spotlight tìm sơ đồ theo tên

DÀNH RIÊNG CHO MAC
• Thanh menu đầy đủ, kèm phím tắt bàn phím
• Mỗi sơ đồ một cửa sổ riêng
• Ứng dụng AI: cho các ứng dụng AI trên máy Mac đọc sơ đồ qua Model Context Protocol (MCP). Mặc định tắt, chỉ đọc, chỉ trong máy Mac này, mỗi ứng dụng một mã riêng

RIÊNG TƯ NGAY TỪ THIẾT KẾ
Không tài khoản, không máy chủ xDev, không quảng cáo, không thu thập dữ liệu. Sơ đồ được lưu trên máy Mac, AI chạy ngay trên máy bằng Apple Intelligence. Khi bật Ứng dụng AI, các ứng dụng bạn kết nối có thể đọc sơ đồ và gửi nội dung đó tới nhà cung cấp AI của họ.

Tính năng AI cần máy Mac dùng chip Apple, đã bật Apple Intelligence với ngôn ngữ được hỗ trợ. Trên máy Mac khác, AI được ẩn, mọi thứ khác vẫn dùng bình thường.

MINDMAP AI PRO
Vẽ sơ đồ tư duy là miễn phí. Pro mua một lần, không phải gói thuê bao, và thêm:
• Xuất PNG độ phân giải cao và PDF vector nhiều trang
• Bộ màu xDev Blue và Graphite
• Nhập bằng giọng nói tiếng Việt hoặc tiếng Anh, nhận dạng ngay trên thiết bị
• AI nâng cao: tạo sơ đồ từ mô tả dài, tóm tắt cả sơ đồ, tìm chủ đề còn thiếu
Pro dùng được với Chia sẻ trong gia đình, và một lần mua cũng mở khoá Pro trên iPad và iPhone."""

VI_IOS = """MindMap AI by xDev biến những suy nghĩ rời rạc thành một sơ đồ rõ ràng, sửa được, ngay trên iPhone và iPad. Thêm một chủ đề, rồi chủ đề tiếp theo, sơ đồ tự sắp xếp.

SƠ ĐỒ CHO MỌI Ý TƯỞNG
• Bố cục tự động trên khung vẽ rộng, phóng to, thu nhỏ, thu gọn và mở rộng nhánh
• Chụm hai ngón để phóng to, thu nhỏ; chạm nút + trên chủ đề đang chọn để thêm chủ đề con hoặc cùng cấp
• Xem cùng một sơ đồ dạng khung vẽ hoặc dàn ý
• Ghi chú, liên kết web và thẻ cho từng chủ đề
• Tìm mọi sơ đồ theo tên, chủ đề hoặc thẻ, gõ có dấu hay không dấu đều được
• Yêu thích, Gần đây, và Đã xoá gần đây giữ sơ đồ 30 ngày
• Hoàn tác và làm lại mọi thay đổi

AI NGAY TRÊN THIẾT BỊ, BẰNG APPLE INTELLIGENCE
• Tạo sơ đồ từ một mô tả ngắn
• Đề xuất chủ đề con, động não ý tưởng, gợi ý thẻ, tóm tắt nhánh
• Viết lại chủ đề ngắn hơn, rõ hơn, đơn giản hơn, trang trọng hơn, hoặc sang tiếng Việt, tiếng Anh
• Hỏi về sơ đồ này: câu trả lời chỉ ra những chủ đề đã dùng
• Kết quả AI là đề xuất có nhãn AI: sửa, chấp nhận hoặc bỏ đi, và hoàn tác trong một bước

NHẬP, XUẤT VÀ CHIA SẺ
• Nhập và xuất Markdown, văn bản thuần
• Xuất PNG, PDF và Bản sao lưu MindMap AI đầy đủ
• Gửi văn bản và liên kết từ ứng dụng khác vào sơ đồ qua bảng chia sẻ
• Tác vụ cho ứng dụng Phím tắt, và Spotlight tìm sơ đồ theo tên

RIÊNG TƯ NGAY TỪ THIẾT KẾ
Không tài khoản, không máy chủ xDev, không quảng cáo, không thu thập dữ liệu. Sơ đồ được lưu trên thiết bị, AI chạy ngay trên thiết bị bằng Apple Intelligence.

Tính năng AI cần iPhone hoặc iPad hỗ trợ Apple Intelligence, đã bật Apple Intelligence với ngôn ngữ được hỗ trợ. Trên thiết bị khác, AI được ẩn, mọi thứ khác vẫn dùng bình thường.

MINDMAP AI PRO
Vẽ sơ đồ tư duy là miễn phí. Pro mua một lần, không phải gói thuê bao, và thêm:
• Xuất PNG độ phân giải cao và PDF vector nhiều trang
• Bộ màu xDev Blue và Graphite
• Nhập bằng giọng nói tiếng Việt hoặc tiếng Anh, nhận dạng ngay trên thiết bị
• AI nâng cao: tạo sơ đồ từ mô tả dài, tóm tắt cả sơ đồ, tìm chủ đề còn thiếu
Pro dùng được với Chia sẻ trong gia đình, và một lần mua cũng mở khoá Pro trên máy Mac."""

# ---------------------------------------------------------------- keywords and promo

KEYWORDS = {
    "MAC_OS": {
        "en-US": "mind,map,mapping,outline,notes,visual,thinking,concept,diagram,private,offline,markdown,mcp,study",
        "vi": "động não,ghi chú,học tập,kế hoạch,tóm tắt,mind,map,brainstorm,outline,notes,mcp",
    },
    "IOS": {
        "en-US": "mind,map,mapping,outline,notes,visual,thinking,concept,diagram,private,offline,markdown,study,plan",
        "vi": "động não,ghi chú,học tập,kế hoạch,tóm tắt,mind,map,brainstorm,outline,notes,offline",
    },
}

PROMO = {
    "MAC_OS": {
        "en-US": "Type a topic and the map lays itself out. Brainstorm, rewrite and ask about your map with Apple Intelligence, right on your Mac. No account, no ads.",
        "vi": "Gõ một chủ đề, sơ đồ tự sắp xếp. Động não, viết lại và hỏi về sơ đồ bằng Apple Intelligence ngay trên máy Mac. Không cần tài khoản, không quảng cáo.",
    },
    "IOS": {
        "en-US": "Capture ideas on iPhone and iPad and watch them become a map. Brainstorm and ask about your map with Apple Intelligence, on your device. No account, no ads.",
        "vi": "Ghi lại ý tưởng trên iPhone, iPad và xem chúng thành sơ đồ. Động não và hỏi về sơ đồ bằng Apple Intelligence ngay trên thiết bị. Không cần tài khoản, không quảng cáo.",
    },
}

DESCRIPTION = {
    "MAC_OS": {"en-US": EN_MAC, "vi": VI_MAC},
    "IOS": {"en-US": EN_IOS, "vi": VI_IOS},
}

# ---------------------------------------------------------------- review notes

REVIEW_NOTES = """No account, login or demo account is needed: the app has no server. It collects no data (no analytics, no ads, no tracking); maps are stored on the device.

AI: every AI feature uses Apple's Foundation Models framework (Apple Intelligence) on the device. Nothing is sent to xDev or to any cloud AI service. AI needs a device that supports Apple Intelligence (on the Mac: Apple silicon), with Apple Intelligence turned on and set to a supported language (the app supports English and Vietnamese). On a device that can never run it (for example an Intel Mac), the AI menu, the AI toolbar buttons and the AI tools on the paywall are hidden. When Apple Intelligence is off or still downloading, AI items stay visible but disabled, with one line that says why.

Core mind mapping works without AI and can be reviewed on any device: create a map (New Mind Map: Cmd-N on the Mac, the + button in the library toolbar on iPad and iPhone), add topics with Return (sibling) and Tab (child) or the + buttons on a selected topic, switch between Canvas and Outline, add notes, links and tags, use Find, Undo and Redo, then Import and Export (Markdown, plain text, PNG, PDF, MindMap AI Backup) from the File menu on the Mac, or Import... in the library toolbar and Export... in the editor toolbar on iPad and iPhone.

To try AI on an eligible device: open a map, select a topic, then AI > Suggest Subtopics (Ctrl-Cmd-E on the Mac; the sparkles AI button in the editor toolbar on iPad and iPhone). Suggestions are labelled AI and change nothing until Accept; Accept is one undo step. Ask About This Map (AI menu, Ctrl-Cmd-A, or its editor toolbar button) answers questions about the open map and only reads it.

In-app purchase: one non-consumable, MindMap AI Pro (asia.xdev.mindmapai.pro), StoreKit 2, Family Sharing on. To reach the paywall: on the Mac, MindMap AI > Settings... (Cmd-,) > Pro > See What's in Pro...; on iPad and iPhone, the Settings (gear) button in the library sidebar > Pro > See What's in Pro.... Choosing a Pro option also opens it, for example Settings > General > Theme for New Maps > xDev Blue (any theme other than Standard), or Settings > Export > PNG Resolution > High (2x). Restore Purchases is in Settings > Pro and on the paywall. Pro covers high-resolution PNG and multi-page PDF export, extra themes, voice input and three advanced AI actions; everything else is free.

Voice input (Pro): Add Topics by Voice (Topic menu on the Mac, microphone button in the editor toolbar) asks for microphone and speech recognition access the first time; recognition runs on the device and audio is not stored or sent.

AI Apps (Mac only): lets AI apps the user already has (for example Claude Code or ChatGPT desktop) read their maps over the Model Context Protocol. It is off by default: Settings (Cmd-,) > AI Apps > "Allow AI Apps to Read Maps". While on, the app listens on http://127.0.0.1:51947/mcp only (loopback; the port can be changed there) and only while the app runs, which is why it has the network.server entitlement. Every request needs a token the user creates with Add App... (one per app, kept in the Keychain); the app never writes another app's files. Access is read-only (list, read and search maps). To test without an AI app: turn the switch on, choose Add App... > Other, copy the token, then run in Terminal:
curl -s http://127.0.0.1:51947/mcp -H "Authorization: Bearer TOKEN" -H "Content-Type: application/json" -H "MCP-Protocol-Version: 2025-11-25" -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_maps","arguments":{}}}'
Revoke in the same pane stops the token at once. Nothing is sent to xDev.

Contact: duy@xdev.asia"""

# ---------------------------------------------------------------- in-app purchase

IAP = {
    "en-US": {"name": "MindMap AI Pro", "description": "Advanced export, themes, voice and AI tools"},
    "vi": {"name": "MindMap AI Pro", "description": "Xuất nâng cao, bộ màu, giọng nói, công cụ AI"},
}

# ---------------------------------------------------------------- checks

LIMITS = {"name": 30, "subtitle": 30, "promotionalText": 170, "description": 4000,
          "keywordsBytes": 100, "reviewNotesBytes": 4000, "iapName": 30, "iapDescription": 45}

problems: list[str] = []


def measure(s: str) -> dict:
    return {"chars": len(s), "bytes": len(s.encode("utf-8"))}


def check(label: str, s: str, limit: int, unit: str = "chars") -> dict:
    m = measure(s)
    m["limit"] = f"{limit} {unit}"
    m["ok"] = m[unit] <= limit
    if not m["ok"]:
        problems.append(f"{label}: {m[unit]} {unit} > {limit}")
    if s != nfc(s):
        problems.append(f"{label}: not NFC")
    return m


def words(s: str) -> set[str]:
    return {w for w in re.split(r"[^\w-]+", nfc(s).casefold()) if w}


BANNED_WORDS = {"app", "apps", "best", "#1", "free"}
COMPETITORS = {"xmind", "mindnode", "simplemind", "mindmeister", "scapple", "omnioutliner", "miro", "freeform", "ithoughts"}
UNBUILT = ["opml", "pencil", "icloud", "sync", "image", "floating", "callout", "boundar", "task", "priority", "filter", "symbol"]


def check_keywords(label: str, kw: str, locale: str) -> dict:
    m = check(label, kw, LIMITS["keywordsBytes"], "bytes")
    terms = kw.split(",")
    m["terms"] = len(terms)
    m["spaceAfterComma"] = ", " in kw
    if m["spaceAfterComma"]:
        problems.append(f"{label}: space after comma")
    if len(set(terms)) != len(terms):
        problems.append(f"{label}: duplicate term")
    taken = words(NAME) | words(SUBTITLE[locale])
    kw_words = set().union(*(words(t) for t in terms))
    overlap = sorted(kw_words & taken)
    m["overlapWithNameOrSubtitle"] = overlap
    if overlap:
        problems.append(f"{label}: repeats name/subtitle words {overlap}")
    bad = sorted(kw_words & (BANNED_WORDS | COMPETITORS))
    if bad:
        problems.append(f"{label}: banned words {bad}")
    return m


def scan_text(label: str, s: str) -> None:
    low = s.casefold()
    for c in COMPETITORS | {"android", "windows", "claude", "chatgpt", "cursor", "openai", "anthropic"}:
        if c in low:
            problems.append(f"{label}: mentions {c}")
    for u in UNBUILT:
        if u in low.replace("png image", "png"):
            problems.append(f"{label}: mentions unbuilt feature '{u}'")
    if re.search(r"[$€£₫]|\d+[.,]\d\d\b|usd|\bbest\b|#1", low):
        problems.append(f"{label}: price or superlative")
    if "subscription" not in low and "thuê bao" not in low and label.endswith("description"):
        pass


checks: dict = {"appInfo": {}, "version": {}, "reviewNotes": {}, "iapPro": {}}
for loc in ("en-US", "vi"):
    checks["appInfo"][loc] = {
        "name": check(f"{loc} name", NAME, LIMITS["name"]),
        "subtitle": check(f"{loc} subtitle", SUBTITLE[loc], LIMITS["subtitle"]),
    }
    scan_text(f"{loc} subtitle", SUBTITLE[loc])

for platform in ("MAC_OS", "IOS"):
    checks["version"][platform] = {}
    for loc in ("en-US", "vi"):
        d = DESCRIPTION[platform][loc]
        p = PROMO[platform][loc]
        checks["version"][platform][loc] = {
            "description": check(f"{platform} {loc} description", d, LIMITS["description"]),
            "keywords": check_keywords(f"{platform} {loc} keywords", KEYWORDS[platform][loc], loc),
            "promotionalText": check(f"{platform} {loc} promotionalText", p, LIMITS["promotionalText"]),
        }
        scan_text(f"{platform} {loc} description", d)
        scan_text(f"{platform} {loc} promotionalText", p)
        if platform == "IOS" and re.search(r"mcp|menu bar|thanh menu|window|cửa sổ", d.casefold()):
            problems.append(f"{platform} {loc}: Mac-only feature in the iOS description")

checks["reviewNotes"] = check("reviewNotes", REVIEW_NOTES, LIMITS["reviewNotesBytes"], "bytes")
for loc in ("en-US", "vi"):
    checks["iapPro"][loc] = {
        "name": check(f"{loc} iap name", IAP[loc]["name"], LIMITS["iapName"]),
        "description": check(f"{loc} iap description", IAP[loc]["description"], LIMITS["iapDescription"]),
    }

checks["measuredWith"] = "python3: len(s) for chars, len(s.encode('utf-8')) for bytes; all strings NFC"
checks["problems"] = problems

doc = {
    "appInfo": {loc: {"name": NAME, "subtitle": SUBTITLE[loc]} for loc in ("en-US", "vi")},
    "version": {
        platform: {
            loc: {
                "description": DESCRIPTION[platform][loc],
                "keywords": KEYWORDS[platform][loc],
                "promotionalText": PROMO[platform][loc],
            }
            for loc in ("en-US", "vi")
        }
        for platform in ("MAC_OS", "IOS")
    },
    "reviewNotes": REVIEW_NOTES,
    "iapPro": IAP,
    "checks": checks,
}

OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(checks, ensure_ascii=False, indent=1))
print("PROBLEMS:", problems or "none")
