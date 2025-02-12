require "net/http"
require "json"
require "uri"

module Fastlane
  module Actions
    module SharedValues
      LATEST_VERSION = :LATEST_VERSION
    end

    class WebLatestVersionAction < Action
      def self.run(params)
        # Extract parameters
        domain = params[:app_identifier].split(".").reverse.join(".")
        version_url = "https://#{domain}/version.json"
        versions = Set.new

        Actions.lane_context[SharedValues::LATEST_VERSION] = "0.0.0"
        UI.message("Fetching version from #{version_url}")

        begin
          # Parse the version.json URL
          uri = URI.parse(version_url)

          # Fetch the content using Net::HTTP
          response = Net::HTTP.get(uri)
          version_data = JSON.parse(response)

          # Extract the version string
          versions.add(Gem::Version.new(version_data["version"]))
        rescue Exception => e
          UI.important("Error fetching or parsing version.json: #{e.message}")
        end
        
        # Select the highest version found
        latest_version = versions.max
        unless latest_version
          UI.important("No version found in the version.json file at #{version_url}")
          latest_version = Gem::Version.new("0.0.0")
        end
        
        # Set the lane's shared value result
        Actions.lane_context[SharedValues::LATEST_VERSION] = latest_version.to_s
      end

      def self.description
        "Fetches the latest version from a web platform version.json file"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :api_key,
            description: "HTTP Authorization Bearer token",
            type: String,
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_identifier,
            description: "The package name of the app",
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :live,
            description: "Whether to fetch from the production track or a pre-production track",
            type: Boolean,
            default_value: true
          )
        ]
      end

      def self.output
        [
          ["LATEST_VERSION", "The latest version fetched from the version.json file"]
        ]
      end

      def self.return_value
        nil
      end

      def self.authors
        ["DigitalDementia"]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
