require 'pastel'
require 'json'
require 'digest/md5'
require 'pry'
require 'active_support'

class CucumberAnalyzer
  FEATURE_PATH = "#{Rails.root}/features"
  FEATURE_GLOB = '**/*.feature'
  FILE_NAME_REGEX = %r{#{Rails.root}/\K.*}
  FEATURE_FILES = Dir["#{FEATURE_PATH}/#{FEATURE_GLOB}"]

  REPORT_PATH = "#{Rails.root}/cucumber_struct.json"

  # NOTE: matches the description, ignoring trailing whitespace
  # e.g. Senario:<tab>wow<space>
  # would match only `wow`
  DESCRIPTION_REGEX = /\s*(?:(?<description>.*)(?<!\s))/

  # NOTE: matches 1-n steps till we hit:
  # - double linebreak (\n\n)
  # - EOF
  # - next Scenario: / Background: / Feature:
  STEPS_REGEX = /(?<steps>[\S\s]*?(?=[\r\n]{2}|\Z|[\s]*?(?:Scenario|Background|Feature)))/

  # NOTE: Destructures a single step definition <type> <description>
  # e.g.  type:<Given>, description:<I am a signed in user>
  STEP_REGEX = /(?<type>Given|When|Then|And|But|\*)#{DESCRIPTION_REGEX}/

  FEATURE_REGEX = /Feature:#{DESCRIPTION_REGEX}/

  # NOTE: matches a single scenario and its steps
  SCENARIO_REGEX = /(?<type>Scenario):#{DESCRIPTION_REGEX}#{STEPS_REGEX}/

  # NOTE: matches a single background and its steps
  BACKGROUND_REGEX = /(?<type>Background):#{STEPS_REGEX}/

  # NOTE: lambada to quickly map over array of hashes
  # and extract the fingerprint value
  EXTRACT_FINGER_PRINT = ->(h) { h[:fingerprint] }

  attr_reader :features

  def self.generate_combined_fingerprint(hash)
    Digest::MD5.hexdigest(
      hash.map(&CucumberAnalyzer::EXTRACT_FINGER_PRINT).join(":"),
    )
  end

  def self.process_steps(raw_steps)
    steps = raw_steps.to_enum(:scan, STEP_REGEX).map { Regexp.last_match }

    steps.map do |step|
      {
        fingerprint: Digest::MD5.hexdigest(step[0]),
        raw_content: step[0],
        type: step[:type],
        description: step[:description],
      }
    end
  end

  # NOTE: scenario is a <MatchData ..> object containing
  # the following named capture groups:
  # - description
  # - steps
  def self.process_scenario(scenario)
    steps = process_steps(scenario[:steps])

    {
      fingerprint: generate_combined_fingerprint(steps),
      description: scenario[:description],
      raw_content: scenario[0],
      raw_steps: scenario[:steps],
      steps: steps,
    }
  end

  # NOTE: background is a <MatchData ..> object containing
  # the following named capture groups:
  # - steps
  def self.process_background(background)
    # NOTE: some feature files dont have a Background:
    return nil if background.nil?

    steps = process_steps(background[:steps])

    {
      fingerprint: generate_combined_fingerprint(steps),
      raw_content: background[0],
      raw_steps: background[:steps],
      steps: steps,
    }
  end

  def self.process_feature(path: nil, result: nil)
    file, _line = path.split(":")
    file_content = File.read(file)

    feature_definition = file_content.match(FEATURE_REGEX)
    fail "file '#{file}' does not contain Feature:" unless feature_definition

    feature_description = feature_definition[:description]

    # NOTE: instantiate feature hash
    feature_result = {}

    # NOTE: store description and file path
    feature_result[:description] = feature_description
    feature_result[:path] = file[FILE_NAME_REGEX]

    # NOTE: extract and process scenarios
    scenario_definitions = file_content
      .to_enum(:scan, SCENARIO_REGEX)
      .map { Regexp.last_match }

    feature_result[:scenarios] = scenario_definitions
      .map { |scenario| process_scenario(scenario) }

    # NOTE: extract and process background
    background_definition = file_content.match(BACKGROUND_REGEX)
    feature_result[:background] = process_background(background_definition)

    # NOTE: generate combined Feature: fingerprint
    # By fingerprinting the fingerprints of background steps + scenario steps
    # We ignore whitespace, and scenario names and only look at the effective content.
    feature_result[:fingerprint] = CucumberAnalyzer.generate_combined_fingerprint(
      [*feature_result[:scenarios], feature_result[:background]].compact,
    )

    result << feature_result unless result.nil?

    feature_result
  end

  def self.process_features(files: FEATURE_FILES)
    result = []
    files.each do |file|
      CucumberAnalyzer.process_feature(path: file, result: result)
    end

    result
  end

  def self.write_report(features:, destination: REPORT_PATH)
    features ||= @features || process_features

    file = File.new(destination, 'w')

    file.puts features.to_json
  ensure
    file.close
  end

  def initialize(file: nil)
    @features = nil

    if file.present? && File.exist?(file)
      @features = JSON.parse(File.read(file))
    end
  end
end
