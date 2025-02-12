module Fastlane
  module Actions
    module SharedValues
      LATEST_VERSION = :LATEST_VERSION
    end

    class AppleAppStoreLatestVersionAction < Action
      def self.run(params)
        # Extract parameters
        api_key = params[:api_key]
        app_identifier = params[:app_identifier]
        live = params[:live]

        Actions.lane_context[SharedValues::LATEST_VERSION] = "0.0.0"

        begin
          versions = Set.new

          # Fetch latest version for each platform
          %w[appletvos ios osx].each do |platform|
            other_action.app_store_build_number(
              api_key: api_key,
              app_identifier: ENV["APP_IDENTIFIER"],
              live: false,
              platform: platform
            )
            version = lane_context[SharedValues::LATEST_VERSION]
            versions.add(Gem::Version.new(version))
          end

          # Select the highest version found
          latest_version = versions.max
          unless latest_version
            UI.important("No versions found in for #{app_identifier}")
            return
          end

          Actions.lane_context[SharedValues::LATEST_VERSION] = latest_version.to_s
        rescue Google::Apis::ClientError => e
          UI.important("Error fetching track info: #{e.message}")
        end
      end

      def self.description
        "Fetches the latest version number from Apple App Store for a specified environment"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :api_key,
            description: "Apple App Store Connect api key",
            type: Hash,
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_identifier,
            description: "The bundle identifier of the app",
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
          ["LATEST_VERSION", "The latest version found set by this action"]
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
