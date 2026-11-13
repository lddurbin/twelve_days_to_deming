import { describe, it, expect } from "vitest";
import {
  canonicalPageUrl,
  githubReportHref,
  emailReportHref,
} from "../assets/scripts/report-error.js";

const PAGE = "https://learndeming.org/content/day-03/05-funnel.html";
const TITLE = "Day 3: The Funnel";

describe("canonicalPageUrl", () => {
  it("always names the production host, whatever host served the page", () => {
    expect(canonicalPageUrl("/content/day-03/05-funnel.html", "")).toBe(PAGE);
  });

  it("keeps the section fragment so the report lands on the passage", () => {
    expect(canonicalPageUrl("/privacy.html", "#analytics")).toBe(
      "https://learndeming.org/privacy.html#analytics",
    );
  });
});

describe("githubReportHref", () => {
  const href = new URL(githubReportHref(PAGE, TITLE));

  it("opens the transcription-error issue form", () => {
    expect(href.origin + href.pathname).toBe(
      "https://github.com/lddurbin/twelve_days_to_deming/issues/new",
    );
    expect(href.searchParams.get("template")).toBe("transcription-error.yml");
  });

  // `page` must match the input's id in
  // .github/ISSUE_TEMPLATE/transcription-error.yml, or GitHub silently
  // leaves the field empty.
  it("pre-fills the page field with the page address", () => {
    expect(href.searchParams.get("page")).toBe(PAGE);
  });

  it("names the page in the issue title", () => {
    expect(href.searchParams.get("title")).toBe("Transcription error: " + TITLE);
  });

  it("falls back to the address when the page has no title", () => {
    const untitled = new URL(githubReportHref(PAGE, ""));
    expect(untitled.searchParams.get("title")).toBe("Transcription error: " + PAGE);
  });
});

describe("emailReportHref", () => {
  const href = emailReportHref(PAGE, TITLE);
  const params = new URLSearchParams(href.slice(href.indexOf("?") + 1));

  it("is a mailto link", () => {
    expect(href.startsWith("mailto:")).toBe(true);
  });

  it("asks for the same things as the issue form", () => {
    const body = params.get("body");
    expect(body).toContain("The passage");
    expect(body).toContain("What I think it should say");
    expect(body).toContain("Neave's page number");
  });

  it("identifies the page", () => {
    expect(params.get("body")).toContain(TITLE + "\n" + PAGE);
  });
});
