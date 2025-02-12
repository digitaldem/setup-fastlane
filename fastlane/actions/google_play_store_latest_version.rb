require 'google/apis/androidpublisher_v3'
require 'set'
require 'stringio'

module Fastlane
  module Actions
    module SharedValues
      LATEST_VERSION = :LATEST_VERSION
    end

    class GooglePlayStoreLatestVersionAction < Action
      def self.run(params)
        # Extract parameters
        api_key = params[:api_key]
        app_identifier = params[:app_identifier]
        live = params[:live]

        Actions.lane_context[SharedValues::LATEST_VERSION] = "0.0.0"

        begin
          # Initialize the Google Play API client
          service = Google::Apis::AndroidpublisherV3::AndroidPublisherService.new
          #service.client_options.log_http_requests = true
          service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
            json_key_io: StringIO.new(api_key.to_json()),
            scope: ["https://www.googleapis.com/auth/androidpublisher"]
          )

          UI.message("Fetching version list for #{app_identifier} on Google Play Store")

          # Create an edit for the app
          edit = service.insert_edit(app_identifier)

          # Track selection: live = true => production, live = false => internal
          track = live ? "production" : "internal"

          # Fetch track and extract the track's version codes as a 9 digit string
          track_info = service.get_edit_track(app_identifier, edit.id, track)
          codes = track_info.releases.flat_map(&:version_codes).map { |code| code.to_s.rjust(9, "0") }

          versions = Set.new
          codes.each do |code|
            # Convert the version code to semantic version string
            version = code.chars.each_slice(3).map { |slice| slice.join.to_i }.join(".")
            versions.add(Gem::Version.new(version))
          end

          # Select the highest version found
          latest_version = versions.max
          unless latest_version
            UI.important("No versions found in the #{track} track for #{app_identifier}")
            return
          end

          Actions.lane_context[SharedValues::LATEST_VERSION] = latest_version.to_s
        rescue Google::Apis::ClientError => e
          UI.important("Error fetching track info: #{e.message}")
        end
      end

      def self.description
        "Fetches the latest build number (version name) from Google Play Store for a specified track"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :api_key,
            description: "Google Play Store service account JSON key file",
            type: Hash,
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
          ['LATEST_VERSION', 'The latest version found set by this action']
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
