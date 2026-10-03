// Reads a MindMap AI map link (ADR 0012, docs/app-clip.md): the fragment
// "<version>.<base64url of raw DEFLATE of JSON>". The same checks as
// MapLinkCodec in the app, so a link the app refuses is refused here too.
// Nothing is sent anywhere: the fragment never leaves the browser.

export const CURRENT_VERSION = 1;
export const MAXIMUM_PAYLOAD_SIZE = 1048576;
export const MAXIMUM_TOPICS = 2000;
export const MAXIMUM_DEPTH = 100;

export class MapLinkError extends Error {
  /** @param {"notAMapLink" | "damaged" | "newerVersion" | "tooLarge" | "unsupported"} kind */
  constructor(kind) {
    super(kind);
    this.kind = kind;
  }
}

/** The map as { title, root: { title, note, link, ai, children } }. */
export async function decodeFragment(fragment) {
  const match = /^([0-9]+)\.([A-Za-z0-9_-]+)$/.exec(fragment.replace(/^#/, ""));
  if (!match) throw new MapLinkError("notAMapLink");
  // Compared as text so a version too long for a number is still "newer".
  const version = match[1].replace(/^0+(?=.)/, "");
  if (version.length > 1 || Number(version) > CURRENT_VERSION) throw new MapLinkError("newerVersion");
  if (Number(version) !== CURRENT_VERSION) throw new MapLinkError("notAMapLink");
  if (typeof DecompressionStream === "undefined") throw new MapLinkError("unsupported");

  const compressed = base64URLDecode(match[2]);
  const json = await inflate(compressed);
  if (nestingDepth(json) > 2 * MAXIMUM_DEPTH + 4) throw new MapLinkError("tooLarge");
  let payload;
  try {
    payload = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(json));
  } catch {
    throw new MapLinkError("damaged");
  }
  return toMap(payload);
}

function base64URLDecode(text) {
  if (text.length % 4 === 1) throw new MapLinkError("damaged");
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  let binary;
  try {
    binary = atob(base64);
  } catch {
    throw new MapLinkError("damaged");
  }
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

// Stops reading past the limit, so a small link cannot inflate into gigabytes.
async function inflate(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  const reader = stream.getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAXIMUM_PAYLOAD_SIZE) {
        reader.cancel().catch(() => {});
        throw new MapLinkError("tooLarge");
      }
      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof MapLinkError) throw error;
    throw new MapLinkError("damaged");
  }
  if (size === 0) throw new MapLinkError("damaged");
  const output = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }
  return output;
}

function nestingDepth(bytes) {
  let depth = 0, deepest = 0, inString = false, escaped = false;
  for (const byte of bytes) {
    if (inString) {
      if (escaped) escaped = false;
      else if (byte === 0x5c) escaped = true;
      else if (byte === 0x22) inString = false;
      continue;
    }
    if (byte === 0x22) inString = true;
    else if (byte === 0x7b || byte === 0x5b) deepest = Math.max(deepest, ++depth);
    else if (byte === 0x7d || byte === 0x5d) depth--;
  }
  return deepest;
}

const isText = (value) => value === undefined || value === null || typeof value === "string";

// Walked with a stack, like the app, so depth costs no recursion.
function toMap(payload) {
  if (!payload || typeof payload !== "object" || !payload.r || typeof payload.r !== "object" || !isText(payload.t)) {
    throw new MapLinkError("damaged");
  }
  let count = 0;
  const root = {};
  const stack = [{ source: payload.r, target: root, depth: 0 }];
  while (stack.length > 0) {
    const { source, target, depth } = stack.pop();
    if (++count > MAXIMUM_TOPICS || depth > MAXIMUM_DEPTH) throw new MapLinkError("tooLarge");
    if (!source || typeof source !== "object" || !isText(source.t) || !isText(source.n) || !isText(source.l)) {
      throw new MapLinkError("damaged");
    }
    if (source.c !== undefined && !Array.isArray(source.c)) throw new MapLinkError("damaged");
    if (source.a !== undefined && typeof source.a !== "number") throw new MapLinkError("damaged");
    target.title = source.t ?? "";
    target.note = source.n && source.n.trim() ? source.n : null;
    target.link = safeLink(source.l);
    target.ai = source.a === 1;
    target.children = (source.c ?? []).map(() => ({}));
    for (let index = (source.c ?? []).length - 1; index >= 0; index--) {
      stack.push({ source: source.c[index], target: target.children[index], depth: depth + 1 });
    }
  }
  const title = payload.t && payload.t.trim() ? payload.t : root.title;
  return { title, root };
}

/** Only the schemes the app opens; anything else is shown as no link. */
export function safeLink(text) {
  if (typeof text !== "string" || text.length > 2048) return null;
  try {
    const url = new URL(text);
    if (url.protocol === "http:" || url.protocol === "https:") return url.host ? url.href : null;
    if (url.protocol === "mailto:") return url.pathname ? url.href : null;
  } catch {
    return null;
  }
  return null;
}
