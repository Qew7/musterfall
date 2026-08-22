#!/usr/bin/env ruby
# frozen_string_literal: true

# Classify movement anomalies in Musterfall battle dumps.
#
# Expects JSON from read-battle-info dumps:
#   { battle_id, left, right, seed, terrain, phases: [{round, phase_type, turn_player, actions}] }
#
# `terrain` is the deployment map. Spell add/remove is applied from
# action/phase `terrainDelta` (camelCase) or `terrain_delta` while walking.
#
# Facing 0 = +X. Terrain features are axis-aligned.
# Stdlib only — no Bundler.

require "json"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
$stdout.set_encoding(Encoding::UTF_8)

def wrap180(delta)
  ((delta + 180.0) % 360.0) - 180.0
end

def dist(a, b)
  Math.hypot(b.fetch("x") - a.fetch("x"), b.fetch("y") - a.fetch("y"))
end

def leftover(man)
  budget = (man["mvBudget"] || 0).to_f
  spent = %w[mvSpentWheel mvSpentTurn mvSpentAdvance mvSpentMarch].sum { |key| (man[key] || 0).to_f }
  budget - spent
end

def terrain_aabb(feat)
  [
    feat.fetch("x") - feat.fetch("width") / 2.0,
    feat.fetch("y") - feat.fetch("depth") / 2.0,
    feat.fetch("x") + feat.fetch("width") / 2.0,
    feat.fetch("y") + feat.fetch("depth") / 2.0
  ]
end

def aabb_overlap?(a, b, pad: 0.0)
  !(a[2] + pad < b[0] || b[2] + pad < a[0] || a[3] + pad < b[1] || b[3] + pad < a[1])
end

def unit_aabb(pose, width, depth)
  hw = width / 2.0
  hd = depth / 2.0
  rad = (pose["facing"] || 0).to_f * Math::PI / 180.0
  cos = Math.cos(rad)
  sin = Math.sin(rad)
  xs = []
  ys = []
  [[-hd, -hw], [-hd, hw], [hd, -hw], [hd, hw]].each do |fd, rt|
    xs << pose.fetch("x") + fd * cos - rt * sin
    ys << pose.fetch("y") + fd * sin + rt * cos
  end
  [xs.min, ys.min, xs.max, ys.max]
end

def size_of(action)
  after = action["actorStateAfter"] || {}
  [(after["baseWidth"] || 0).to_f, (after["baseDepth"] || 0).to_f]
end

def overlapping_impassable(pose, width, depth, terrain)
  box = unit_aabb(pose, width, depth)
  Array(terrain).filter_map do |feat|
    next unless feat["impassable"]

    "#{feat['id']}:#{feat['type']}" if aabb_overlap?(box, terrain_aabb(feat))
  end
end

def terrain_delta_of(entry)
  Array(entry && (entry["terrainDelta"] || entry["terrain_delta"]))
end

def apply_terrain_delta!(terrain, delta)
  Array(delta).each do |change|
    feature = change["feature"] || {}
    id = feature["id"]
    operation = change["operation"].to_s
    if operation == "add" && id && terrain.none? { |entry| entry["id"] == id }
      terrain << feature
    elsif operation == "remove" && id
      terrain.reject! { |entry| entry["id"] == id }
    end
  end
  terrain
end

def classify(action, terrain)
  return [] unless action["type"] == "movement"

  man = action["maneuver"] || {}
  from = action.fetch("from")
  to = action.fetch("to")
  dxy = dist(from, to)
  df = wrap180(to.fetch("facing").to_f - from.fetch("facing").to_f)
  left = leftover(man)
  trunc = man["truncatedByCollision"] ? true : false
  avoided = man["pathingAvoided"] || man["avoided"] ? true : false
  kind = man["kind"]
  blocker = man["blockerName"] || man["blockerId"]
  summary = action["summary"].to_s
  width, depth = size_of(action)
  hits = overlapping_impassable(to, width, depth, terrain)
  tags = []

  tags << "IDLE_ROW" if kind == "row_advance" && dxy < 0.05
  tags << "CRASH" unless hits.empty?

  terrain_blocker = %w[house lake forest difficult].include?(blocker.to_s) || summary.include?("местность")
  tags << "PHANTOM_TERRAIN" if trunc && terrain_blocker && hits.empty?
  tags << "REFUSED_BYPASS" if trunc && !avoided && left > 0.5

  desired = man["desired"] || {}
  heading = man["heading"]
  des_face = desired["facing"]
  if df.abs >= 80 && !heading.nil? && !des_face.nil? && wrap180(des_face.to_f - heading.to_f).abs >= 60
    tags << "TURN_AWAY"
  end
  tags << "TURN_AWAY" if summary.include?("разворачивается") && dxy < 4 && df.abs >= 80 && !tags.include?("TURN_AWAY")

  tags
end

def scan(path)
  data = JSON.parse(File.read(path, encoding: "UTF-8"))
  terrain = Array(data["terrain"]).map(&:dup)
  incidents = []

  Array(data["phases"]).each do |phase|
    apply_terrain_delta!(terrain, terrain_delta_of(phase))
    Array(phase["actions"]).each do |action|
      apply_terrain_delta!(terrain, terrain_delta_of(action))
      next unless action["type"] == "movement"

      tags = classify(action, terrain)
      next if tags.empty?

      man = action["maneuver"] || {}
      from = action.fetch("from")
      to = action.fetch("to")
      width, depth = size_of(action)
      incidents << {
        battle_id: data["battle_id"],
        round: phase["round"],
        actor: action["actorName"],
        actor_id: action["actorId"],
        tags: tags,
        kind: man["kind"],
        dxy: dist(from, to).round(2),
        df: wrap180(to.fetch("facing").to_f - from.fetch("facing").to_f).round(1),
        leftover: leftover(man).round(2),
        from: [from["x"].to_f.round(2), from["y"].to_f.round(2), from["facing"].to_f.round(1)],
        to: [to["x"].to_f.round(2), to["y"].to_f.round(2), to["facing"].to_f.round(1)],
        target: man["targetName"],
        blocker: man["blockerName"] || man["blockerId"],
        overlap: overlapping_impassable(to, width, depth, terrain),
        summary: action["summary"]
      }
    end
  end

  {
    battle_id: data["battle_id"],
    matchup: "#{data['left']} vs #{data['right']}",
    seed: data["seed"],
    incidents: incidents
  }
end

paths = ARGV
if paths.empty?
  warn "usage: ruby scan_movements.rb dump1.json dump2.json ..."
  exit 2
end

by_tag = Hash.new { |hash, key| hash[key] = [] }
paths.each do |path|
  report = scan(path)
  puts "\n=== battle #{report[:battle_id]} #{report[:matchup]} seed=#{report[:seed]} ==="
  puts "incidents=#{report[:incidents].size}"
  report[:incidents].each do |rec|
    rec[:tags].each { |tag| by_tag[tag] << rec }
    overlap = rec[:overlap].empty? ? "-" : rec[:overlap].inspect
    puts "  R#{rec[:round]} #{rec[:actor]} (#{rec[:actor_id]}) #{rec[:tags].inspect} " \
         "kind=#{rec[:kind]} dxy=#{rec[:dxy]} df=#{rec[:df]} left=#{rec[:leftover]} " \
         "blk=#{rec[:blocker]} tgt=#{rec[:target]} overlap=#{overlap}"
    puts "    #{rec[:from]} -> #{rec[:to]}  #{rec[:summary]}"
  end
end

puts "\n=== tally ==="
by_tag.sort_by { |_tag, recs| -recs.size }.each do |tag, recs|
  puts "  #{tag}: #{recs.size}"
end
