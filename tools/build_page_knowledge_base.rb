#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

ROOT = Pathname.new(__dir__).parent
SOURCE = ROOT.join("版本管理/用户手册/实测记录/2026-06-04-页面采集.json")
OUTPUT = ROOT.join("知识库/页面知识库.md")

abort "Missing source: #{SOURCE}" unless SOURCE.exist?

MODULE_NAMES = {
  "park" => "停车中心",
  "orders" => "订单中心",
  "revenue" => "运营中心",
  "system" => "系统中心",
  "account" => "个人中心",
  "parkspace" => "封闭车场"
}.freeze

def clean_items(items)
  Array(items).map { |item| item.to_s.strip.gsub(/\s+/, " ") }.reject(&:empty?).uniq
end

def join_items(items)
  values = clean_items(items)
  values.empty? ? "本轮结构化采集未捕获" : values.join("、")
end

def module_name(route)
  MODULE_NAMES.fetch(route.to_s.split("/").first, "其他")
end

def route_url(route)
  "https://m.charge.movebroad.com/#/#{route}"
end

data = JSON.parse(SOURCE.read(encoding: "UTF-8"))
records = data.fetch("records")
groups = records.group_by { |record| module_name(record["route"]) }

lines = []
lines << "# 页面知识库"
lines << ""
lines << "本文件由 `#{SOURCE.relative_path_from(ROOT)}` 生成，记录测试环境实测到的后台页面事实。"
lines << ""
lines << "- 实测环境：`#{data["environment"]}`"
lines << "- 实测账号：`#{data["account"]}`"
lines << "- 实测时间：`#{data["collectedAt"]}`"
lines << "- 页面数量：#{data["routeCount"]}"
lines << "- 生成日期：2026-06-08"
lines << ""
lines << "说明：本文件只记录页面真实可见的标题、入口、按钮、筛选项和表格字段。页面没有展示的审批规则、计费影响、权限边界和后台任务结果，不在本文件中推断。"
lines << ""

groups.sort_by { |name, _| MODULE_NAMES.values.index(name) || 99 }.each do |name, module_records|
  lines << "## #{name}"
  lines << ""

  module_records.each do |record|
    title = record["title"].to_s.sub(/\s*-\s*一九停车\z/, "")
    lines << "### #{record["menu"]}"
    lines << ""
    lines << "| 项 | 内容 |"
    lines << "| --- | --- |"
    lines << "| 页面标题 | #{title.empty? ? record["title"] : title} |"
    lines << "| 路由 | `#{record["route"]}` |"
    lines << "| 入口 | `#{route_url(record["route"])}` |"
    lines << "| 表单/筛选标签 | #{join_items(record["formLabels"])} |"
    lines << "| 输入占位 | #{join_items(record["placeholders"])} |"
    lines << "| 下拉/页签可见值 | #{join_items(clean_items(record["tabs"]) + clean_items(record["selects"]))} |"
    lines << "| 操作按钮 | #{join_items(record["buttons"])} |"
    lines << "| 表格字段 | #{join_items(record["tableHeaders"])} |"
    lines << ""
  end
end

OUTPUT.write(lines.join("\n"), mode: "w", encoding: "UTF-8")
puts "Generated #{OUTPUT}"
puts "Records: #{records.length}"
