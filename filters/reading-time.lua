-- Inject an estimated reading time under each chapter's H1.
-- Counts prose words (excluding code, raw HTML, image captions) and
-- divides by 200 wpm. Suppresses output on very short chapters.

local WPM = 200
-- Chapters below this threshold are typically activity-only pages
-- (prompts + embedded widgets); a "1 min read" estimate would
-- understate engagement, so we simply omit the indicator.
local MIN_WORDS = 50

local function count_words(s)
  if not s or s == "" then return 0 end
  local n = 0
  for _ in s:gmatch("%S+") do n = n + 1 end
  return n
end

local function stringify_inlines(inlines)
  local parts = {}
  for _, el in ipairs(inlines) do
    if el.t == "Str" then
      parts[#parts + 1] = el.text
    elseif el.t == "Space" or el.t == "SoftBreak" or el.t == "LineBreak" then
      parts[#parts + 1] = " "
    elseif el.t == "Image" or el.t == "RawInline" or el.t == "Code" then
      -- skip image captions, inline raw HTML, and inline code
    elseif el.content then
      parts[#parts + 1] = stringify_inlines(el.content)
    end
  end
  return table.concat(parts, "")
end

local function has_class(block, class)
  if not block.attr or not block.attr.classes then return false end
  for _, c in ipairs(block.attr.classes) do
    if c == class then return true end
  end
  return false
end

-- Activity markers we look for anywhere in the doc (code blocks
-- included, since widgets live inside ojs chunks).
local function detect_activity(blocks)
  for _, b in ipairs(blocks) do
    if b.t == "CodeBlock" then
      if b.text and (b.text:find("viewof", 1, true)
                     or b.text:find("Inputs.textarea", 1, true)
                     or b.text:find("createDownloadButton", 1, true)) then
        return true
      end
    elseif b.t == "Div" then
      if has_class(b, "thought") then return true end
      if detect_activity(b.content) then return true end
    elseif b.t == "BlockQuote" then
      if detect_activity(b.content) then return true end
    elseif b.t == "BulletList" or b.t == "OrderedList" then
      for _, item in ipairs(b.content) do
        if detect_activity(item) then return true end
      end
    end
  end
  return false
end

local function count_blocks(blocks)
  local total = 0
  for _, b in ipairs(blocks) do
    if b.t == "CodeBlock" or b.t == "RawBlock" or b.t == "HorizontalRule" then
      -- skip
    elseif b.t == "Div" and has_class(b, "hidden") then
      -- skip Quarto's injected navigation/meta blocks
    elseif b.t == "Para" or b.t == "Plain" then
      total = total + count_words(stringify_inlines(b.content))
    elseif b.t == "LineBlock" then
      for _, line in ipairs(b.content) do
        total = total + count_words(stringify_inlines(line))
      end
    elseif b.t == "Header" and b.level > 1 then
      total = total + count_words(stringify_inlines(b.content))
    elseif b.t == "BlockQuote" then
      total = total + count_blocks(b.content)
    elseif b.t == "BulletList" or b.t == "OrderedList" then
      for _, item in ipairs(b.content) do
        total = total + count_blocks(item)
      end
    elseif b.t == "DefinitionList" then
      for _, item in ipairs(b.content) do
        total = total + count_words(stringify_inlines(item[1]))
        for _, def in ipairs(item[2]) do
          total = total + count_blocks(def)
        end
      end
    elseif b.t == "Div" then
      total = total + count_blocks(b.content)
    elseif b.t == "Table" then
      -- Stringify the whole table and subtract caption words so
      -- captions are excluded, consistent with image captions.
      local caption_words = 0
      if b.caption and b.caption.long then
        caption_words = count_words(pandoc.utils.stringify(b.caption.long))
      end
      if b.caption and b.caption.short then
        caption_words = caption_words
          + count_words(pandoc.utils.stringify(b.caption.short))
      end
      total = total + math.max(0,
        count_words(pandoc.utils.stringify(b)) - caption_words)
    end
  end
  return total
end

local function html_escape(s)
  return (s:gsub("[&<>\"']", {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;",
  }))
end

local function read_session_minutes(meta)
  local v = meta and meta.session_minutes
  if v == nil then return nil end
  local s = pandoc.utils.stringify(v)
  local n = tonumber(s)
  if n and n > 0 then return math.floor(n) end
  return nil
end

local function indicator_block(minutes, has_activity, session_minutes)
  -- The two numbers measure different things — our reading metric is
  -- a literal text-throughput floor at 200 wpm, while session_minutes
  -- is the author's editorial allocation including reflection and
  -- activities. Render them side-by-side as independent measures, not
  -- as a bracket or an additive pair.
  --
  -- Collapse to the single-number form when the two values are within
  -- 1 min of each other: ceil rounding on our side and Neave's 5-min
  -- clock granularity together create that much noise inherently, so
  -- separating "11 vs 10" implies a precision neither number has.
  local body, label
  if session_minutes and math.abs(session_minutes - minutes) > 1 then
    body = string.format(
      "~ %d min reading &middot; ~ %d min recommended",
      minutes, session_minutes
    )
    label = "Estimated reading time and the author's recommended time including reflection and activities"
  elseif session_minutes then
    -- Within rounding noise — show the reading metric only.
    -- Omit the "+ activities" suffix even when has_activity is true:
    -- session_minutes already encodes activity time, so appending
    -- the suffix would double-count.
    body = string.format("~ %d min reading", minutes)
    label = "Estimated reading time"
  else
    local suffix = has_activity and " + activities" or ""
    body = string.format("~ %d min reading%s", minutes, suffix)
    label = has_activity
      and "Estimated reading time; this chapter also contains activities that add time"
      or "Estimated reading time"
  end
  -- `body` is composed entirely of integer-formatted values plus the
  -- static `&middot;` HTML entity, so it is intentionally not run
  -- through html_escape. Only `label` carries free-form text.
  local html = string.format(
    '<p class="reading-time" aria-label="%s">%s</p>',
    html_escape(label), body
  )
  return pandoc.RawBlock("html", html)
end

function Pandoc(doc)
  local words = count_blocks(doc.blocks)
  if words < MIN_WORDS then return doc end

  local minutes = math.max(1, math.ceil(words / WPM))
  local has_activity = detect_activity(doc.blocks)
  local session_minutes = read_session_minutes(doc.meta)
  local out = pandoc.List()
  local inserted = false

  for _, b in ipairs(doc.blocks) do
    out:insert(b)
    if not inserted and b.t == "Header" and b.level == 1 then
      out:insert(indicator_block(minutes, has_activity, session_minutes))
      inserted = true
    end
  end

  -- If no H1 is present in the body (Quarto renders title from YAML),
  -- inject at the very top so it still appears under the page title.
  if not inserted then
    out:insert(1, indicator_block(minutes, has_activity, session_minutes))
  end

  doc.blocks = out
  return doc
end
