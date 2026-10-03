// node --test docs/web/mindmap/m/decode.test.mjs
// The same golden link as MapLinkCodecTests in the app, so both readers agree.
import assert from "node:assert/strict";
import { test } from "node:test";
import { deflateRawSync } from "node:zlib";
import { decodeFragment, MapLinkError, safeLink } from "./maplink.js";

const golden = "1.q1YqUbJSCinKLFAoyVc4MuHwAgWfh7sWlijpKBUpWVXDZYH8ZCWraIiAR35Jag5QJA_I9ktNLFIoyUhVyEnMTo3JCyzNTAVpzgFKZZSUFBRb6eunViTmFuSk6iXn5-on2ifZGqol2xop1epADHPLz08BakhUsjJEtiMg4-Hu-Qo2SXZJhzfZ6CfZKdXG1sbqKFUApTLT8_KLUlOUamsB";

const fragment = (json) => "1." + deflateRawSync(Buffer.from(json)).toString("base64url");

async function rejects(promise, kind) {
  await assert.rejects(promise, (error) => error instanceof MapLinkError && error.kind === kind);
}

test("reads the golden link", async () => {
  const map = await decodeFragment("#" + golden);
  assert.equal(map.title, "Trip to Đà Lạt");
  assert.equal(map.root.title, "Trip");
  assert.deepEqual(map.root.children.map((c) => c.title), ["Hotel", "Food"]);
  assert.equal(map.root.children[0].note, "Near the lake\nQuiet");
  assert.equal(map.root.children[0].link, "https://example.com/a?b=1&c=2");
  assert.equal(map.root.children[1].ai, true);
  assert.equal(map.root.children[1].children[0].title, "Phở <b>bò</b>");
});

test("refuses links that are not map links", async () => {
  for (const text of ["", "abc", "1.", "1.ab+cd", "1.ab.cd", "0.q1Yq"]) await rejects(decodeFragment(text), "notAMapLink");
});

test("says when a link is newer", async () => {
  await rejects(decodeFragment("2.q1Yq"), "newerVersion");
  await rejects(decodeFragment("99999999999999999999999.q1Yq"), "newerVersion");
});

test("refuses damaged links", async () => {
  await rejects(decodeFragment(golden.slice(0, -20)), "damaged");
  await rejects(decodeFragment(fragment('{"t":"No root"}')), "damaged");
  await rejects(decodeFragment(fragment("not json")), "damaged");
});

test("refuses bombs and huge maps", async () => {
  await rejects(decodeFragment(fragment('{"r":{"t":"' + " ".repeat(2_000_000) + '"}}')), "tooLarge");
  const many = '{"r":{"t":"A","c":[' + Array(2000).fill('{"t":"x"}').join(",") + "]}}";
  await rejects(decodeFragment(fragment(many)), "tooLarge");
  const deep = '{"r":' + '{"t":"x","c":['.repeat(5000) + '{"t":"x"}' + "]}".repeat(5000) + "}";
  await rejects(decodeFragment(fragment(deep)), "tooLarge");
});

test("keeps only http, https and mailto links", () => {
  assert.equal(safeLink("javascript:alert(1)"), null);
  assert.equal(safeLink("file:///etc/passwd"), null);
  assert.equal(safeLink("https://ok.example"), "https://ok.example/");
  assert.equal(safeLink("mailto:a@example.com"), "mailto:a@example.com");
});
