#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'pry'

params = {}
OptionParser.new do |opts|
  opts.banner = "Usage: find_step.rb [options]"
  opts.on("-v", "--[no-]verbose", "Run verbosely")
  opts.on("-p String", "--path String", "specify cucumber scenario's path")
  opts.on("-i String", "--id String", "specify cucumber id to search")
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!(into: params)

SCENARIO_PATH = params.fetch(:path, './features').freeze

features = Dir["#{SCENARIO_PATH}/**/*.feature"]

feature, scenario = params[:id].split(";")

FEATURE_PATTERN = feature.split("-").join(" ")
feature_matches = features.find_all do |file|
  File.readlines(file).grep(/#{FEATURE_PATTERN}/i).size > 0
end

if params[:verbose]
  puts "NOTE: following feature files match the extracted feature ID(#{feature})"
  feature_matches.each do |m|
    puts "- #{m}"
  end
  puts " "
end

SCENARIO_PATTERN = scenario.split("-").join(" ")
scenario_matches = []
feature_matches.each do |file|
  lines = File.readlines(file)
  matches = lines.grep(/#{SCENARIO_PATTERN}/i)

  next unless matches.size.positive?
  fail "ambiguous scenario match in #{file} for #{SCENARIO_PATTERN}" if matches.size > 1

  scenario_matches << "#{file}:#{lines.index(matches.first)}"
end

if params[:verbose]
  puts "NOTE: following scenario's match the composite ID(#{params[:id]})"
  scenario_matches.each do |m|
    puts "- #{m}"
  end
  puts " "
end

case scenario_matches.count
when 0
  fail 'no scenarios match provided identifier'
when 1
  puts "#{scenario_matches.first}"
else
  fail "Ambiguous matches for provided ID, number of scenario's matching ID: #{scenario_matches.count}"
end
