/* Breakdown preview — the data layer behind the Breakdown screen's input card.
 *
 * Subtasks use the walker's contract from breakdown.jac (#3): subtask_id, title,
 * tier ("Deep Work" | "Shallow Work" | "Low Energy"), estimated_duration (minutes)
 * and order (1..n). Until the walker is served over HTTP, mockBreakdown stands in
 * for it with the same signature, so wiring the real call means replacing that one
 * function. Everything is validated before it reaches the DOM because the real
 * response will be model output.
 *
 * Plain script, no build step: the browser gets window.BreakdownPreview, Node's
 * test runner gets module.exports.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.BreakdownPreview = api;
  }
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const TIER_CLASSES = Object.freeze({
    "Deep Work": "deep",
    "Shallow Work": "shallow",
    "Low Energy": "low",
  });
  const EMPTY_DESCRIPTION = "Paste the assignment description first.";
  const MOCK_LATENCY_MS = 600;
  const MINUTES_PER_HOUR = 60;

  const SAMPLE_SUBTASKS = Object.freeze(
    [
      { title: "Review assignment requirements", tier: "Shallow Work", estimated_duration: 20 },
      { title: "Plan the implementation approach", tier: "Deep Work", estimated_duration: 30 },
      { title: "Complete the main assignment work", tier: "Deep Work", estimated_duration: 90 },
      { title: "Test and review the work", tier: "Shallow Work", estimated_duration: 30 },
      { title: "Finalize and submit", tier: "Low Energy", estimated_duration: 15 },
    ].map((step, index) =>
      Object.freeze({ subtask_id: `subtask-${index + 1}`, ...step, order: index + 1 })
    )
  );

  function validateDescription(text) {
    return String(text ?? "").trim() ? null : EMPTY_DESCRIPTION;
  }

  function contractError(subtask, position) {
    const where = `Subtask ${position}`;
    if (typeof subtask?.subtask_id !== "string" || !subtask.subtask_id) {
      return `${where} is missing a subtask_id.`;
    }
    if (typeof subtask.title !== "string" || !subtask.title.trim()) {
      return `${where} has an empty title.`;
    }
    if (!Object.hasOwn(TIER_CLASSES, subtask.tier)) {
      return `${where} has an unknown tier: ${subtask.tier}.`;
    }
    if (!Number.isInteger(subtask.estimated_duration) || subtask.estimated_duration <= 0) {
      return `${where} needs a positive whole-minute estimated_duration.`;
    }
    if (subtask.order !== position) {
      return `${where} has order ${subtask.order}; orders must run 1..n.`;
    }
    return null;
  }

  /* Throws on the first contract violation; returns the list unchanged otherwise. */
  function assertSubtasks(subtasks) {
    if (!Array.isArray(subtasks) || subtasks.length === 0) {
      throw new Error("The breakdown came back with no subtasks.");
    }
    const problem = subtasks.map((s, i) => contractError(s, i + 1)).find(Boolean);
    if (problem) {
      throw new Error(problem);
    }
    if (new Set(subtasks.map((s) => s.subtask_id)).size !== subtasks.length) {
      throw new Error("Subtask IDs must be unique.");
    }
    return subtasks;
  }

  function tierClass(tier) {
    if (!Object.hasOwn(TIER_CLASSES, tier)) {
      throw new Error(`Unknown tier: ${tier}`);
    }
    return TIER_CLASSES[tier];
  }

  function formatMinutes(total) {
    const hours = Math.floor(total / MINUTES_PER_HOUR);
    const minutes = total % MINUTES_PER_HOUR;
    if (!hours) return `${minutes}m`;
    return minutes ? `${hours}h ${minutes}m` : `${hours}h`;
  }

  function summarize(subtasks) {
    const total = subtasks.reduce((sum, s) => sum + s.estimated_duration, 0);
    const noun = subtasks.length === 1 ? "subtask" : "subtasks";
    return `${subtasks.length} ${noun}, ${formatMinutes(total)} total`;
  }

  /* Stand-in for the walker. Resolves to a fresh copy so callers can't edit the sample. */
  function mockBreakdown(description, { delayMs = MOCK_LATENCY_MS } = {}) {
    const problem = validateDescription(description);
    if (problem) {
      return Promise.reject(new Error(problem));
    }
    const copy = SAMPLE_SUBTASKS.map((s) => ({ ...s }));
    return new Promise((resolve) => setTimeout(() => resolve(copy), delayMs));
  }

  return Object.freeze({
    SAMPLE_SUBTASKS,
    assertSubtasks,
    formatMinutes,
    mockBreakdown,
    summarize,
    tierClass,
    validateDescription,
  });
});
