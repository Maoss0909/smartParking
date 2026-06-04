#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "pathname"

ROOT = Pathname.new(__dir__).parent
SOURCE = ROOT.join("停车收费系统用户手册.md")
VERSION_FILE = ROOT.join("版本管理/用户手册/版本记录.md")
OUTPUT = ROOT.join("index.html")

abort "Missing source: #{SOURCE}" unless SOURCE.exist?

def escape_html(value)
  CGI.escapeHTML(value.to_s)
end

def escape_attr(value)
  escape_html(value).gsub('"', "&quot;")
end

def plain_text(markdown)
  markdown
    .gsub(/!\[[^\]]*\]\([^)]+\)/, "")
    .gsub(/\[([^\]]+)\]\([^)]+\)/, "\\1")
    .gsub(/[`*_~]/, "")
    .strip
end

def inline_html(markdown)
  parts = markdown.split(/(`[^`]*`)/)
  html = parts.map do |part|
    if part.start_with?("`") && part.end_with?("`")
      "<code>#{escape_html(part[1...-1])}</code>"
    else
      escaped = escape_html(part)
      escaped.gsub(/\*\*([^*]+)\*\*/, '<strong>\1</strong>')
    end
  end.join

  html.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
    label = Regexp.last_match(1)
    href = Regexp.last_match(2)
    %(<a href="#{escape_attr(href)}">#{label}</a>)
  end
end

def slug_for(title, used)
  number = title[/\A(\d+(?:\.\d+)*)/, 1]
  base =
    if number
      "sec-#{number.tr(".", "-")}"
    else
      cleaned = title.downcase.gsub(/[^\p{Alnum}\p{Han}]+/u, "-").gsub(/\A-|-+\z/, "")
      cleaned.empty? ? "sec-#{Digest::SHA1.hexdigest(title)[0, 10]}" : cleaned
    end

  used[base] += 1
  used[base] == 1 ? base : "#{base}-#{used[base]}"
end

def split_table_row(line)
  line.strip.sub(/\A\|/, "").sub(/\|\z/, "").split("|").map(&:strip)
end

def table_separator?(line)
  cells = split_table_row(line)
  return false if cells.empty?

  cells.all? { |cell| cell.match?(/\A:?-{3,}:?\z/) }
end

def image_line?(line)
  line.match?(/\A!\[[^\]]*\]\((?:<[^>]+>|[^)]+)\)\z/)
end

def image_parts(line)
  match = line.match(/\A!\[([^\]]*)\]\((?:<([^>]+)>|([^)]+))\)\z/)
  return nil unless match

  [match[1], match[2] || match[3]]
end

def render_image(line, image_state)
  alt, src = image_parts(line)
  src = src.sub(/\A\.\//, "")
  caption = alt.empty? ? File.basename(src, ".*") : alt
  image_state[:count] += 1
  image_state[:missing] << src unless ROOT.join(src).exist?

  <<~HTML
    <figure class="screenshot-card" data-screenshot="#{image_state[:count]}">
      <button class="screenshot-open" type="button" aria-label="查看截图：#{escape_attr(caption)}">
        <img src="#{escape_attr(src)}" alt="#{escape_attr(caption)}" loading="lazy" decoding="async" data-full="#{escape_attr(src)}">
      </button>
      <figcaption>#{escape_html(caption)}</figcaption>
    </figure>
  HTML
end

def render_table(lines, index)
  header = split_table_row(lines[index])
  rows = []
  cursor = index + 2

  while cursor < lines.length && lines[cursor].include?("|") && !lines[cursor].strip.empty?
    rows << split_table_row(lines[cursor])
    cursor += 1
  end

  html = +"<div class=\"table-wrap\"><table><thead><tr>"
  html << header.map { |cell| "<th>#{inline_html(cell)}</th>" }.join
  html << "</tr></thead><tbody>"
  rows.each do |row|
    html << "<tr>"
    html << row.map { |cell| "<td>#{inline_html(cell)}</td>" }.join
    html << "</tr>"
  end
  html << "</tbody></table></div>"

  [html, cursor]
end

def render_list(lines, index, ordered)
  marker = ordered ? /\A\s*\d+\.\s+(.+)\z/ : /\A\s*[-*+]\s+(.+)\z/
  tag = ordered ? "ol" : "ul"
  items = []
  cursor = index

  while cursor < lines.length
    match = lines[cursor].match(marker)
    break unless match

    items << match[1]
    cursor += 1
  end

  html = +"<#{tag}>"
  items.each { |item| html << "<li>#{inline_html(item)}</li>" }
  html << "</#{tag}>"

  [html, cursor]
end

def render_blockquote(lines, index)
  parts = []
  cursor = index

  while cursor < lines.length && lines[cursor].start_with?(">")
    parts << lines[cursor].sub(/\A>\s?/, "")
    cursor += 1
  end

  content = parts.reject(&:empty?).map { |part| inline_html(part) }.join("<br>")
  [%(<blockquote>#{content}</blockquote>), cursor]
end

def render_markdown(markdown)
  lines = markdown.lines(chomp: true)
  used_slugs = Hash.new(0)
  toc = []
  html = []
  image_state = { count: 0, missing: [] }
  doc_title = "智慧停车收费系统用户手册"
  chapter_open = false
  i = 0

  while i < lines.length
    line = lines[i]
    stripped = line.strip

    if stripped.empty?
      i += 1
      next
    end

    if (heading = stripped.match(/\A(#{'#'}{1,4})\s+(.+)\z/))
      level = heading[1].length
      title = plain_text(heading[2])

      if level == 1
        doc_title = title
        i += 1
        next
      end

      id = slug_for(title, used_slugs)

      if level == 2
        html << "</section>" if chapter_open
        html << %(<section class="chapter" id="#{escape_attr(id)}-chapter">)
        chapter_open = true
      elsif !chapter_open
        html << %(<section class="chapter" id="manual-preface">)
        chapter_open = true
      end

      toc << { level: level, title: title, id: id } if level <= 3
      html << %(<h#{level} id="#{escape_attr(id)}"><a class="heading-anchor" href="##{escape_attr(id)}">#{inline_html(heading[2])}</a></h#{level}>)
      i += 1
      next
    end

    if stripped.start_with?(">")
      blockquote_html, i = render_blockquote(lines, i)
      html << blockquote_html
      next
    end

    if image_line?(stripped)
      html << render_image(stripped, image_state)
      i += 1
      next
    end

    if i + 1 < lines.length && stripped.include?("|") && table_separator?(lines[i + 1])
      table_html, i = render_table(lines, i)
      html << table_html
      next
    end

    if stripped.match?(/\A\d+\.\s+/)
      list_html, i = render_list(lines, i, true)
      html << list_html
      next
    end

    if stripped.match?(/\A[-*+]\s+/)
      list_html, i = render_list(lines, i, false)
      html << list_html
      next
    end

    paragraph = [stripped]
    i += 1
    while i < lines.length
      candidate = lines[i].strip
      break if candidate.empty?
      break if candidate.match?(/\A#{'#'}{1,4}\s+/)
      break if candidate.start_with?(">")
      break if image_line?(candidate)
      break if candidate.match?(/\A\d+\.\s+/)
      break if candidate.match?(/\A[-*+]\s+/)
      break if i + 1 < lines.length && candidate.include?("|") && table_separator?(lines[i + 1])

      paragraph << candidate
      i += 1
    end
    html << "<p>#{inline_html(paragraph.join(" "))}</p>"
  end

  html << "</section>" if chapter_open

  {
    title: doc_title,
    html: html.join("\n"),
    toc: toc,
    screenshot_count: image_state[:count],
    missing_images: image_state[:missing]
  }
end

def toc_html(toc)
  toc.map do |item|
    %(<a class="toc-link toc-level-#{item[:level]}" href="##{escape_attr(item[:id])}">#{escape_html(item[:title])}</a>)
  end.join("\n")
end

def version_info
  fallback = { name: "V1.0", date: Time.now.strftime("%Y-%m-%d") }
  return fallback unless VERSION_FILE.exist?

  content = VERSION_FILE.read(encoding: "UTF-8")
  name = content[/^## (V[0-9.]+)/, 1] || fallback[:name]
  section = content[/^## #{Regexp.escape(name)}\n(.*?)(?=^## |\z)/m, 1] || content
  date = section[/版本日期：([0-9-]+)/, 1] || fallback[:date]
  { name: name, date: date }
end

CSS = <<~CSS
  :root {
    --bg: #f6f7f1;
    --paper: #ffffff;
    --paper-soft: #fbfcf7;
    --ink: #14201f;
    --muted: #697674;
    --line: #d9dfd2;
    --line-strong: #b9c3b8;
    --teal: #007f73;
    --teal-dark: #005f57;
    --gold: #b58a2b;
    --blue: #315f80;
    --danger: #a33a2d;
    --shadow: 0 18px 45px rgba(34, 47, 42, 0.10);
    --radius: 8px;
    --topbar-height: 76px;
  }

  * {
    box-sizing: border-box;
    letter-spacing: 0;
  }

  html {
    scroll-behavior: smooth;
  }

  body {
    margin: 0;
    color: var(--ink);
    background:
      linear-gradient(90deg, rgba(20, 32, 31, 0.035) 1px, transparent 1px),
      linear-gradient(180deg, rgba(20, 32, 31, 0.035) 1px, transparent 1px),
      var(--bg);
    background-size: 34px 34px;
    font-family: "Avenir Next", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    font-size: 16px;
    line-height: 1.75;
  }

  body.is-lightbox-open {
    overflow: hidden;
  }

  a {
    color: inherit;
  }

  button,
  input {
    font: inherit;
  }

  .progress {
    position: fixed;
    top: 0;
    left: 0;
    z-index: 40;
    width: 100%;
    height: 3px;
    background: transparent;
  }

  .progress-bar {
    width: 0;
    height: 100%;
    background: var(--teal);
    transition: width 120ms ease;
  }

  .topbar {
    position: sticky;
    top: 0;
    z-index: 30;
    min-height: var(--topbar-height);
    padding: 14px 28px;
    display: grid;
    grid-template-columns: minmax(230px, 360px) minmax(280px, 1fr) auto;
    gap: 16px;
    align-items: center;
    border-bottom: 1px solid rgba(185, 195, 184, 0.72);
    background: rgba(246, 247, 241, 0.92);
    backdrop-filter: blur(16px);
  }

  .brand {
    text-decoration: none;
  }

  .brand-title {
    display: block;
    font-size: 18px;
    font-weight: 750;
    line-height: 1.25;
  }

  .brand-version {
    display: block;
    color: var(--muted);
    font-size: 12px;
    line-height: 1.3;
    margin-top: 4px;
  }

  .search-box {
    position: relative;
  }

  .search-box input {
    width: 100%;
    min-height: 46px;
    padding: 0 16px 0 42px;
    border: 1px solid var(--line-strong);
    border-radius: var(--radius);
    color: var(--ink);
    background: rgba(255, 255, 255, 0.86);
    outline: none;
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.85);
  }

  .search-box input:focus {
    border-color: var(--teal);
    box-shadow: 0 0 0 3px rgba(0, 127, 115, 0.14);
  }

  .search-box::before {
    content: "";
    position: absolute;
    left: 16px;
    top: 50%;
    width: 13px;
    height: 13px;
    border: 2px solid var(--teal-dark);
    border-radius: 50%;
    transform: translateY(-56%);
  }

  .search-box::after {
    content: "";
    position: absolute;
    left: 28px;
    top: 29px;
    width: 9px;
    height: 2px;
    background: var(--teal-dark);
    transform: rotate(45deg);
    transform-origin: left center;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .action-button,
  .chip {
    min-height: 36px;
    border: 1px solid var(--line-strong);
    border-radius: var(--radius);
    color: var(--ink);
    background: rgba(255, 255, 255, 0.82);
    cursor: pointer;
    transition: border-color 160ms ease, background 160ms ease, color 160ms ease, transform 160ms ease;
  }

  .action-button {
    padding: 0 12px;
    white-space: nowrap;
  }

  .action-button:hover,
  .chip:hover {
    border-color: var(--teal);
    color: var(--teal-dark);
    background: #ffffff;
  }

  .layout {
    width: min(1760px, 100%);
    margin: 0 auto;
    padding: 24px 28px 60px;
    display: grid;
    grid-template-columns: 288px minmax(0, 1fr);
    gap: 24px;
  }

  .sidebar {
    position: sticky;
    top: calc(var(--topbar-height) + 24px);
    align-self: start;
    max-height: calc(100vh - var(--topbar-height) - 48px);
    overflow: auto;
    padding: 18px;
    border: 1px solid var(--line);
    border-radius: var(--radius);
    background: rgba(255, 255, 255, 0.72);
    box-shadow: 0 12px 30px rgba(34, 47, 42, 0.06);
  }

  .side-label {
    margin: 0 0 12px;
    color: var(--muted);
    font-size: 12px;
  }

  .toc {
    display: grid;
    gap: 2px;
  }

  .toc-link {
    display: block;
    padding: 8px 10px;
    border-radius: 6px;
    color: var(--muted);
    text-decoration: none;
    line-height: 1.35;
    border-left: 3px solid transparent;
  }

  .toc-level-2 {
    margin-top: 4px;
    color: var(--ink);
    font-weight: 700;
  }

  .toc-level-3 {
    padding-left: 22px;
    font-size: 13px;
  }

  .toc-link:hover,
  .toc-link.active {
    color: var(--teal-dark);
    background: rgba(0, 127, 115, 0.08);
    border-left-color: var(--teal);
  }

  .content {
    min-width: 0;
  }

  .overview {
    padding: 28px;
    border: 1px solid var(--line);
    border-radius: var(--radius);
    background: rgba(255, 255, 255, 0.84);
    box-shadow: var(--shadow);
  }

  .eyebrow {
    margin: 0 0 8px;
    color: var(--teal-dark);
    font-size: 13px;
    font-weight: 750;
  }

  .overview h1 {
    margin: 0;
    font-size: clamp(30px, 4.2vw, 54px);
    line-height: 1.08;
    font-weight: 780;
  }

  .intro {
    max-width: 980px;
    margin: 16px 0 0;
    color: var(--muted);
    font-size: 16px;
  }

  .stat-grid {
    margin-top: 22px;
    display: grid;
    grid-template-columns: repeat(4, minmax(120px, 1fr));
    border: 1px solid var(--line);
    border-radius: var(--radius);
    overflow: hidden;
    background: var(--paper-soft);
  }

  .stat {
    min-height: 78px;
    padding: 14px 16px;
    border-right: 1px solid var(--line);
  }

  .stat:last-child {
    border-right: none;
  }

  .stat strong {
    display: block;
    font-size: 23px;
    line-height: 1.1;
  }

  .stat span {
    display: block;
    margin-top: 6px;
    color: var(--muted);
    font-size: 12px;
  }

  .chip-row {
    margin-top: 18px;
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  .chip {
    padding: 6px 11px;
    color: var(--teal-dark);
    background: rgba(0, 127, 115, 0.06);
  }

  .search-results {
    margin-top: 18px;
    display: none;
    border: 1px solid var(--line);
    border-radius: var(--radius);
    background: #fff;
    overflow: hidden;
  }

  .search-results.visible {
    display: block;
  }

  .result-link {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 12px;
    padding: 12px 14px;
    text-decoration: none;
    border-bottom: 1px solid var(--line);
  }

  .result-link:last-child {
    border-bottom: none;
  }

  .result-link:hover {
    color: var(--teal-dark);
    background: rgba(0, 127, 115, 0.06);
  }

  .result-meta {
    color: var(--muted);
    font-size: 12px;
  }

  .empty-state {
    margin-top: 18px;
    padding: 14px;
    border: 1px solid rgba(163, 58, 45, 0.24);
    border-radius: var(--radius);
    color: var(--danger);
    background: rgba(163, 58, 45, 0.055);
  }

  .manual-content {
    margin-top: 24px;
    display: grid;
    gap: 18px;
  }

  .chapter {
    padding: 28px;
    border: 1px solid var(--line);
    border-radius: var(--radius);
    background: rgba(255, 255, 255, 0.88);
    box-shadow: 0 12px 34px rgba(34, 47, 42, 0.07);
  }

  .chapter[hidden] {
    display: none;
  }

  .manual-content h2,
  .manual-content h3,
  .manual-content h4 {
    scroll-margin-top: calc(var(--topbar-height) + 24px);
  }

  .manual-content h2 {
    margin: 0 0 18px;
    padding-bottom: 12px;
    border-bottom: 1px solid var(--line);
    font-size: 28px;
    line-height: 1.25;
  }

  .manual-content h3 {
    margin: 30px 0 12px;
    font-size: 21px;
    line-height: 1.35;
  }

  .manual-content h4 {
    margin: 24px 0 10px;
    color: var(--blue);
    font-size: 17px;
    line-height: 1.4;
  }

  .heading-anchor {
    text-decoration: none;
  }

  .manual-content p {
    margin: 10px 0;
    color: #24302f;
  }

  .manual-content blockquote {
    margin: 0 0 16px;
    padding: 14px 16px;
    border-left: 4px solid var(--teal);
    border-radius: 0 var(--radius) var(--radius) 0;
    color: #344341;
    background: rgba(0, 127, 115, 0.065);
  }

  .manual-content ol,
  .manual-content ul {
    margin: 10px 0 16px;
    padding-left: 24px;
  }

  .manual-content li {
    margin: 6px 0;
  }

  .manual-content code {
    padding: 2px 6px;
    border: 1px solid var(--line);
    border-radius: 5px;
    color: var(--teal-dark);
    background: var(--paper-soft);
    font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
    font-size: 0.92em;
  }

  .table-wrap {
    margin: 14px 0 20px;
    overflow: auto;
    border: 1px solid var(--line);
    border-radius: var(--radius);
  }

  table {
    width: 100%;
    border-collapse: collapse;
    background: #fff;
    font-size: 14px;
  }

  th,
  td {
    padding: 12px 14px;
    border-bottom: 1px solid var(--line);
    text-align: left;
    vertical-align: top;
  }

  th {
    color: var(--teal-dark);
    background: rgba(0, 127, 115, 0.07);
    font-weight: 760;
    white-space: nowrap;
  }

  tr:last-child td {
    border-bottom: none;
  }

  .screenshot-card {
    margin: 18px 0 26px;
    border: 1px solid var(--line);
    border-radius: var(--radius);
    overflow: hidden;
    background: #ffffff;
    box-shadow: 0 10px 28px rgba(34, 47, 42, 0.08);
  }

  .screenshot-open {
    display: block;
    width: 100%;
    padding: 0;
    border: none;
    border-radius: 0;
    background: #eef1e8;
    cursor: zoom-in;
  }

  .screenshot-open img {
    display: block;
    width: 100%;
    height: auto;
    max-height: 760px;
    object-fit: contain;
  }

  .screenshot-card figcaption {
    padding: 10px 14px;
    color: var(--muted);
    border-top: 1px solid var(--line);
    background: var(--paper-soft);
    font-size: 13px;
  }

  body.screenshots-collapsed .screenshot-card {
    display: none;
  }

  .lightbox {
    position: fixed;
    inset: 0;
    z-index: 80;
    padding: 22px;
    display: grid;
    grid-template-rows: auto minmax(0, 1fr);
    gap: 14px;
    background: rgba(10, 20, 19, 0.84);
  }

  .lightbox[hidden] {
    display: none;
  }

  .lightbox-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    color: #fff;
  }

  .lightbox-caption {
    margin: 0;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .lightbox-close {
    width: 42px;
    height: 42px;
    border: 1px solid rgba(255, 255, 255, 0.44);
    border-radius: var(--radius);
    color: #fff;
    background: rgba(255, 255, 255, 0.12);
    cursor: pointer;
    font-size: 26px;
    line-height: 1;
  }

  .lightbox-body {
    min-height: 0;
    display: grid;
    place-items: center;
  }

  .lightbox img {
    max-width: 100%;
    max-height: 100%;
    border-radius: var(--radius);
    background: #fff;
    box-shadow: 0 20px 70px rgba(0, 0, 0, 0.36);
  }

  .back-top {
    position: fixed;
    right: 22px;
    bottom: 22px;
    z-index: 35;
    width: 44px;
    height: 44px;
    border: 1px solid var(--line-strong);
    border-radius: var(--radius);
    color: var(--teal-dark);
    background: rgba(255, 255, 255, 0.92);
    box-shadow: 0 12px 26px rgba(34, 47, 42, 0.16);
    cursor: pointer;
  }

  @media (max-width: 1180px) {
    .topbar {
      grid-template-columns: 1fr;
      align-items: stretch;
    }

    .actions {
      justify-content: flex-start;
    }

    :root {
      --topbar-height: 174px;
    }
  }

  @media (max-width: 920px) {
    body {
      background-size: 28px 28px;
    }

    .layout {
      grid-template-columns: 1fr;
      padding: 16px;
      gap: 16px;
    }

    .sidebar {
      position: sticky;
      top: calc(var(--topbar-height) + 8px);
      z-index: 20;
      max-height: 240px;
    }

    .toc {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .toc-level-3 {
      padding-left: 10px;
    }

    .overview,
    .chapter {
      padding: 20px;
    }

    .stat-grid {
      grid-template-columns: repeat(2, minmax(120px, 1fr));
    }

    .stat:nth-child(2n) {
      border-right: none;
    }

    .stat:nth-child(-n + 2) {
      border-bottom: 1px solid var(--line);
    }
  }

  @media (max-width: 620px) {
    :root {
      --topbar-height: 182px;
    }

    .topbar {
      padding: 12px 14px;
    }

    .sidebar {
      max-height: 220px;
    }

    .toc {
      grid-template-columns: 1fr;
    }

    .stat-grid {
      grid-template-columns: 1fr;
    }

    .stat {
      border-right: none;
      border-bottom: 1px solid var(--line);
    }

    .stat:last-child {
      border-bottom: none;
    }

    .actions {
      display: grid;
      grid-template-columns: 1fr 1fr;
    }

    .action-button {
      width: 100%;
    }

    .result-link {
      grid-template-columns: 1fr;
    }
  }

  @media print {
    .topbar,
    .sidebar,
    .back-top,
    .progress,
    .search-results,
    .empty-state {
      display: none !important;
    }

    body {
      background: #fff;
    }

    .layout {
      display: block;
      padding: 0;
      width: 100%;
    }

    .overview,
    .chapter,
    .screenshot-card {
      box-shadow: none;
      break-inside: avoid;
    }
  }
CSS

JS = <<~JS
  (function () {
    var search = document.getElementById("manualSearch");
    var results = document.getElementById("searchResults");
    var empty = document.getElementById("emptyState");
    var chapters = Array.prototype.slice.call(document.querySelectorAll(".chapter"));
    var headings = Array.prototype.slice.call(document.querySelectorAll(".manual-content h2, .manual-content h3, .manual-content h4"));
    var tocLinks = Array.prototype.slice.call(document.querySelectorAll(".toc-link"));
    var toggleScreenshots = document.getElementById("toggleScreenshots");
    var printManual = document.getElementById("printManual");
    var backTop = document.getElementById("backTop");
    var progressBar = document.getElementById("progressBar");
    var lightbox = document.getElementById("imageLightbox");
    var lightboxImage = document.getElementById("lightboxImage");
    var lightboxCaption = document.getElementById("lightboxCaption");
    var closeLightbox = document.getElementById("closeLightbox");

    function normalize(value) {
      return value.toLowerCase().replace(/\\s+/g, " ").trim();
    }

    function escapeHtml(value) {
      return value.replace(/[&<>"']/g, function (char) {
        return {
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;"
        }[char];
      });
    }

    function headingLevel(heading) {
      return heading.tagName.replace("H", "");
    }

    function renderResults(query) {
      var matched = headings.filter(function (heading) {
        var chapter = heading.closest(".chapter");
        var haystack = normalize(heading.textContent + " " + (chapter ? chapter.textContent : ""));
        return haystack.indexOf(query) !== -1;
      }).slice(0, 24);

      if (!query) {
        results.classList.remove("visible");
        results.innerHTML = "";
        return;
      }

      if (!matched.length) {
        results.classList.remove("visible");
        results.innerHTML = "";
        return;
      }

      results.innerHTML = matched.map(function (heading) {
        var chapter = heading.closest(".chapter");
        var chapterTitle = chapter ? chapter.querySelector("h2") : null;
        var label = escapeHtml(heading.textContent.trim());
        var meta = chapterTitle ? escapeHtml(chapterTitle.textContent.trim()) : "正文";
        return '<a class="result-link" href="#' + heading.id + '"><span>' + label + '</span><span class="result-meta">H' + headingLevel(heading) + " / " + meta + "</span></a>";
      }).join("");
      results.classList.add("visible");
    }

    function runSearch() {
      var query = normalize(search.value);
      var visibleCount = 0;

      chapters.forEach(function (chapter) {
        if (!query) {
          chapter.hidden = false;
          visibleCount += 1;
          return;
        }

        var isMatch = normalize(chapter.textContent).indexOf(query) !== -1;
        chapter.hidden = !isMatch;
        if (isMatch) visibleCount += 1;
      });

      renderResults(query);
      empty.hidden = !query || visibleCount > 0;
    }

    search.addEventListener("input", runSearch);

    document.querySelectorAll("[data-query]").forEach(function (chip) {
      chip.addEventListener("click", function () {
        search.value = chip.getAttribute("data-query");
        runSearch();
        search.focus();
      });
    });

    toggleScreenshots.addEventListener("click", function () {
      document.body.classList.toggle("screenshots-collapsed");
      toggleScreenshots.textContent = document.body.classList.contains("screenshots-collapsed") ? "显示截图" : "隐藏截图";
    });

    printManual.addEventListener("click", function () {
      window.print();
    });

    backTop.addEventListener("click", function () {
      window.scrollTo({ top: 0, behavior: "smooth" });
    });

    document.querySelectorAll(".screenshot-open img").forEach(function (img) {
      img.addEventListener("click", function () {
        lightboxImage.src = img.getAttribute("data-full") || img.src;
        lightboxImage.alt = img.alt;
        lightboxCaption.textContent = img.alt;
        lightbox.hidden = false;
        document.body.classList.add("is-lightbox-open");
      });
    });

    function hideLightbox() {
      lightbox.hidden = true;
      lightboxImage.removeAttribute("src");
      document.body.classList.remove("is-lightbox-open");
    }

    closeLightbox.addEventListener("click", hideLightbox);
    lightbox.addEventListener("click", function (event) {
      if (event.target === lightbox || event.target.classList.contains("lightbox-body")) {
        hideLightbox();
      }
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && !lightbox.hidden) {
        hideLightbox();
      }
    });

    if ("IntersectionObserver" in window) {
      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          tocLinks.forEach(function (link) {
            link.classList.toggle("active", link.getAttribute("href") === "#" + entry.target.id);
          });
        });
      }, { rootMargin: "-18% 0px -72% 0px", threshold: 0.01 });

      headings.forEach(function (heading) {
        observer.observe(heading);
      });
    }

    function updateProgress() {
      var max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
      var ratio = Math.min(1, Math.max(0, window.scrollY / max));
      progressBar.style.width = (ratio * 100).toFixed(2) + "%";
    }

    window.addEventListener("scroll", updateProgress, { passive: true });
    window.addEventListener("resize", updateProgress);
    updateProgress();
  }());
JS

manual = render_markdown(SOURCE.read(encoding: "UTF-8"))
version = version_info
chapter_count = manual[:toc].count { |item| item[:level] == 2 }
topic_count = manual[:toc].count { |item| item[:level] == 3 }

abort "Missing images:\n#{manual[:missing_images].join("\n")}" unless manual[:missing_images].empty?

html = <<~HTML
  <!doctype html>
  <html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{escape_html(manual[:title])}</title>
    <style>
  #{CSS}
    </style>
  </head>
  <body>
    <div class="progress" aria-hidden="true"><div class="progress-bar" id="progressBar"></div></div>

    <header class="topbar" id="top">
      <a class="brand" href="#top">
        <span class="brand-title">#{escape_html(manual[:title])}</span>
        <span class="brand-version">#{escape_html(version[:name])} / #{escape_html(version[:date])}</span>
      </a>
      <label class="search-box">
        <input id="manualSearch" type="search" autocomplete="off" placeholder="搜索功能、问题、页面名称或截图">
      </label>
      <div class="actions">
        <button class="action-button" id="toggleScreenshots" type="button">隐藏截图</button>
        <button class="action-button" id="printManual" type="button">打印</button>
      </div>
    </header>

    <div class="layout">
      <aside class="sidebar" aria-label="手册目录">
        <p class="side-label">目录</p>
        <nav class="toc">
  #{toc_html(manual[:toc])}
        </nav>
      </aside>

      <main class="content">
        <section class="overview" aria-labelledby="manual-title">
          <p class="eyebrow">第一版用户手册</p>
          <h1 id="manual-title">#{escape_html(manual[:title])}</h1>
          <p class="intro">基于已整理的 Markdown 手册和 #{manual[:screenshot_count]} 张系统截图生成，用于客户演示、内部查询和后续 HTML 版本迭代。页面内容遵循“不推断未确认规则”的边界。</p>
          <div class="stat-grid" aria-label="手册概览">
            <div class="stat"><strong>#{chapter_count}</strong><span>一级模块</span></div>
            <div class="stat"><strong>#{topic_count}</strong><span>功能章节</span></div>
            <div class="stat"><strong>#{manual[:screenshot_count]}</strong><span>系统截图</span></div>
            <div class="stat"><strong>#{escape_html(version[:name])}</strong><span>当前版本</span></div>
          </div>
          <div class="chip-row" aria-label="常用查询">
            <button class="chip" type="button" data-query="退款">退款</button>
            <button class="chip" type="button" data-query="欠费">欠费</button>
            <button class="chip" type="button" data-query="支付流水">支付流水</button>
            <button class="chip" type="button" data-query="设备">设备</button>
            <button class="chip" type="button" data-query="收费规则">收费规则</button>
            <button class="chip" type="button" data-query="白名单">白名单</button>
            <button class="chip" type="button" data-query="系统配置">系统配置</button>
            <button class="chip" type="button" data-query="微信服务号">微信服务号</button>
          </div>
          <div class="search-results" id="searchResults" aria-live="polite"></div>
          <div class="empty-state" id="emptyState" hidden>没有找到匹配内容。</div>
        </section>

        <article class="manual-content" id="manualContent">
  #{manual[:html]}
        </article>
      </main>
    </div>

    <button class="back-top" id="backTop" type="button" aria-label="返回顶部">↑</button>

    <div class="lightbox" id="imageLightbox" hidden>
      <div class="lightbox-top">
        <p class="lightbox-caption" id="lightboxCaption"></p>
        <button class="lightbox-close" id="closeLightbox" type="button" aria-label="关闭">×</button>
      </div>
      <div class="lightbox-body">
        <img id="lightboxImage" alt="">
      </div>
    </div>

    <script>
  #{JS}
    </script>
  </body>
  </html>
HTML

OUTPUT.write(html, mode: "w", encoding: "UTF-8")
puts "Generated #{OUTPUT}"
puts "Chapters: #{chapter_count}, topics: #{topic_count}, screenshots: #{manual[:screenshot_count]}"
