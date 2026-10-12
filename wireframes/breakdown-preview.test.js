// Run with: node --test wireframes/breakdown-preview.test.js
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  SAMPLE_SUBTASKS,
  assertSubtasks,
  formatMinutes,
  summarize,
  tierClass,
  validateDescription,
  mockBreakdown,
} = require("./breakdown-preview.js");

const subtask = (overrides = {}) => ({
  subtask_id: "subtask-1",
  title: "Outline the report",
  tier: "Shallow Work",
  estimated_duration: 20,
  order: 1,
  ...overrides,
});

test("validateDescription rejects empty and whitespace-only input", () => {
  assert.equal(validateDescription(""), "Paste the assignment description first.");
  assert.equal(validateDescription("  \n\t "), "Paste the assignment description first.");
});

test("validateDescription accepts any non-blank text", () => {
  assert.equal(validateDescription("Submit the quiz"), null);
});

test("sample subtasks satisfy the walker contract", () => {
  assert.deepEqual(assertSubtasks(SAMPLE_SUBTASKS), SAMPLE_SUBTASKS);
  assert.ok(Object.isFrozen(SAMPLE_SUBTASKS));
});

test("assertSubtasks rejects an empty breakdown", () => {
  assert.throws(() => assertSubtasks([]), /no subtasks/);
  assert.throws(() => assertSubtasks(null), /no subtasks/);
});

test("assertSubtasks names the field that breaks the contract", () => {
  const cases = [
    [{ title: "   " }, /title/],
    [{ tier: "Medium Work" }, /tier/],
    [{ estimated_duration: 0 }, /estimated_duration/],
    [{ estimated_duration: 12.5 }, /estimated_duration/],
    [{ subtask_id: "" }, /subtask_id/],
  ];
  for (const [overrides, pattern] of cases) {
    assert.throws(() => assertSubtasks([subtask(overrides)]), pattern);
  }
});

test("assertSubtasks requires unique IDs and orders 1..n", () => {
  const duplicateIds = [subtask(), subtask({ order: 2 })];
  const gappedOrder = [subtask(), subtask({ subtask_id: "subtask-2", order: 3 })];

  assert.throws(() => assertSubtasks(duplicateIds), /unique/);
  assert.throws(() => assertSubtasks(gappedOrder), /order/);
});

test("tierClass maps contract tiers to the wireframe's tier classes", () => {
  assert.equal(tierClass("Deep Work"), "deep");
  assert.equal(tierClass("Shallow Work"), "shallow");
  assert.equal(tierClass("Low Energy"), "low");
  assert.throws(() => tierClass("deep"), /tier/);
});

test("formatMinutes reads naturally at every scale", () => {
  assert.equal(formatMinutes(45), "45m");
  assert.equal(formatMinutes(60), "1h");
  assert.equal(formatMinutes(185), "3h 5m");
});

test("summarize counts subtasks and totals their minutes", () => {
  const two = [subtask(), subtask({ subtask_id: "subtask-2", order: 2, estimated_duration: 70 })];

  assert.equal(summarize(two), "2 subtasks, 1h 30m total");
  assert.equal(summarize([subtask()]), "1 subtask, 20m total");
});

test("mockBreakdown resolves to a fresh copy of the sample", async () => {
  const first = await mockBreakdown("Write the lab report", { delayMs: 0 });
  first[0].title = "changed";

  const second = await mockBreakdown("Write the lab report", { delayMs: 0 });

  assert.deepEqual(second, SAMPLE_SUBTASKS);
  assert.notEqual(second, SAMPLE_SUBTASKS);
});

test("mockBreakdown rejects blank input like the walker does", async () => {
  await assert.rejects(mockBreakdown("   ", { delayMs: 0 }), /Paste the assignment description/);
});
