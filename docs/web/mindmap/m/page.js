// Draws the map of the link in this page's fragment as an outline.
// Text goes in with textContent only; links open only for http, https and mailto.
import { decodeFragment, MapLinkError } from "./maplink.js";

const strings = {
  en: {
    subtitle: "A map shared from MindMap AI",
    privacy: "This map is inside the link. Your browser drew it here; nothing was sent to xDev.",
    store: "Get MindMap AI on the App Store",
    ai: "AI",
    empty: "Open a MindMap AI map link to see the map here.",
    notAMapLink: "This link can’t be opened. It may be incomplete.",
    damaged: "This link can’t be opened. It may be incomplete.",
    tooLarge: "This map is too big to show here.",
    newerVersion: "This link needs a newer version of MindMap AI.",
    unsupported: "Open this link on a device with MindMap AI.",
  },
  vi: {
    subtitle: "Sơ đồ được chia sẻ từ MindMap AI",
    privacy: "Sơ đồ nằm trong đường link. Trình duyệt vẽ nó ngay tại đây; không có gì được gửi tới xDev.",
    store: "Tải MindMap AI trên App Store",
    ai: "AI",
    empty: "Mở một link sơ đồ của MindMap AI để xem sơ đồ tại đây.",
    notAMapLink: "Không mở được link này. Có thể link bị thiếu.",
    damaged: "Không mở được link này. Có thể link bị thiếu.",
    tooLarge: "Sơ đồ này quá lớn để hiện tại đây.",
    newerVersion: "Link này cần phiên bản MindMap AI mới hơn.",
    unsupported: "Hãy mở link này trên thiết bị có MindMap AI.",
  },
  ja: {
    subtitle: "MindMap AI で共有されたマップ",
    privacy: "このマップはリンクの中に入っています。ブラウザがここで表示しており、xDev には何も送信されていません。",
    store: "App Store で MindMap AI を入手",
    ai: "AI",
    empty: "MindMap AI のマップリンクを開くと、ここにマップが表示されます。",
    notAMapLink: "このリンクを開けません。リンクが途中で切れている可能性があります。",
    damaged: "このリンクを開けません。リンクが途中で切れている可能性があります。",
    tooLarge: "このマップは大きすぎるため、ここでは表示できません。",
    newerVersion: "このリンクを開くには、新しいバージョンの MindMap AI が必要です。",
    unsupported: "MindMap AI がインストールされたデバイスでこのリンクを開いてください。",
  },
};

const language = (navigator.languages ?? [navigator.language]).map((tag) => tag.slice(0, 2)).find((code) => code in strings) ?? "en";
const t = strings[language];
document.documentElement.lang = language;

const element = (tag, className, text) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

function showMessage(text) {
  const outline = document.getElementById("outline");
  outline.replaceChildren(element("p", "message", text));
}

function topicItem(topic) {
  const item = element("li");
  const title = topic.link ? element("a", "title", topic.title) : element("span", "title", topic.title);
  if (topic.link) {
    title.href = topic.link;
    title.rel = "noopener noreferrer nofollow";
  }
  item.append(title);
  if (topic.ai) item.append(element("span", "ai", t.ai));
  if (topic.note) item.append(element("p", "note", topic.note));
  return item;
}

// Built with a stack, like the reader, so a deep map costs no recursion.
// Children go on the stack last-first, so each list fills in reading order.
function outlineList(root) {
  const top = element("ul");
  const stack = [{ topic: root, list: top }];
  while (stack.length > 0) {
    const { topic, list } = stack.pop();
    const item = topicItem(topic);
    list.append(item);
    if (topic.children.length > 0) {
      const children = element("ul");
      item.append(children);
      for (let index = topic.children.length - 1; index >= 0; index--) {
        stack.push({ topic: topic.children[index], list: children });
      }
    }
  }
  return top;
}

async function render() {
  document.getElementById("subtitle").textContent = t.subtitle;
  document.getElementById("privacy").textContent = t.privacy;
  document.getElementById("store").textContent = t.store;
  const fragment = location.hash.slice(1);
  if (!fragment) {
    showMessage(t.empty);
    return;
  }
  try {
    const map = await decodeFragment(fragment);
    document.title = `${map.title} · MindMap AI`;
    document.getElementById("title").textContent = map.title;
    const list = outlineList(map.root);
    document.getElementById("outline").replaceChildren(list);
  } catch (error) {
    showMessage(t[error instanceof MapLinkError ? error.kind : "damaged"] ?? t.damaged);
  }
}

window.addEventListener("hashchange", render);
render();
