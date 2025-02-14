require 'open3'

module Fastlane
  module Actions
    module SharedValues
      KEYTOOL_OUTPUT = :KEYTOOL_OUTPUT
    end

    class KeytoolAction < Action
      def self.run(params)
        validate_parameters!(params)

        # Build the base command with proper escaping
        keytool_command = build_command(params)

        # Execute the command securely
        begin
          UI.command(redact_sensitive_info(keytool_command.join(" ")))
          output, status = Open3.capture2e(*keytool_command)
          Actions.lane_context[SharedValues::KEYTOOL_OUTPUT] = output

          unless status.success?
            UI.user_error!("Keytool command failed:\nExit Status: #{status.exitstatus}\nOutput: #{redact_sensitive_info(output)}")
          end

          return status.exitstatus
        rescue StandardError => e
          UI.user_error!("Failed to execute keytool: #{e.message}")
        end
      end

      def self.build_command(params)
        cmd = ["keytool"]

        # Add the main command first
        cmd << "-#{params[:command]}"

        # Create keystore directory if needed
        if params[:keystore_path]
          FileUtils.mkdir_p(File.dirname(params[:keystore_path]))
          cmd += ["-keystore", params[:keystore_path]]
        end

        # Add parameters with proper escaping
        PARAMETER_MAPPING.each do |param, flag|
          next unless params[param]

          if params[param].is_a?(TrueClass)
            cmd << "-#{flag}"
          else
            cmd += ["-#{flag}", params[param].to_s]
          end
        end

        cmd
      end

      def self.validate_parameters!(params)
        # Verify required command parameter
        UI.user_error!("The parameter 'command' is required") unless params[:command]

        # Validate keystore path for commands that require it
        if COMMANDS_REQUIRING_KEYSTORE.include?(params[:command]) && !params[:keystore_path]
          UI.user_error!("The parameter 'keystore_path' is required for the '#{params[:command]}' command")
        end

        # Validate key alias for certain commands
        if COMMANDS_REQUIRING_ALIAS.include?(params[:command]) && !params[:key_alias]
          UI.user_error!("The parameter 'key_alias' is required for the '#{params[:command]}' command")
        end

        # Validate output file for export commands
        if COMMANDS_REQUIRING_FILE.include?(params[:command]) && !params[:file]
          UI.user_error!("The parameter 'file' is required for the '#{params[:command]}' command")
        end
      end

      def self.redact_sensitive_info(string)
        return "" if string.nil?

        redacted = string.dup
        SENSITIVE_PARAMS.each do |param|
          redacted.gsub!(/(-#{param}\s+)\S+/, '\1[REDACTED]')
        end
        redacted
      end

      # Constants for parameter validation and mapping
      PARAMETER_MAPPING = {
        keystore_password: 'storepass',
        key_alias: 'alias',
        key_algorithm: 'keyalg',
        key_size: 'keysize',
        validity: 'validity',
        dname: 'dname',
        trustcacerts: 'trustcacerts',
        verbose: 'v',
        genkeypair: 'genkeypair',
        list: 'list',
        delete: 'delete',
        certreq: 'certreq',
        importcert: 'importcert',
        importkeystore: 'importkeystore',
        exportcert: 'exportcert',
        noprompt: 'noprompt',
        storetype: 'storetype',
        providername: 'providername',
        providerclass: 'providerclass',
        providerarg: 'providerarg',
        rfc: 'rfc',
        file: 'file'
      }.freeze

      COMMANDS_REQUIRING_KEYSTORE = %w[
        genkeypair list delete importcert exportcert importkeystore
      ].freeze

      COMMANDS_REQUIRING_ALIAS = %w[
        genkeypair delete importcert exportcert certreq
      ].freeze

      COMMANDS_REQUIRING_FILE = %w[
        export exportcert certreq
      ].freeze

      SENSITIVE_PARAMS = %w[
        storepass keypass
      ].freeze

      def self.description
        "Interface with the keytool command to manage keystores and certificates for app signing"
      end

      def self.authors
        ["DigitalDementia"]
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :command,
            description: "Keytool subcommand to run (e.g., genkeypair, list)",
            optional: false,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Command cannot be empty") if value.to_s.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :keystore_path,
            description: "Path to the keystore file",
            optional: true,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Keystore path cannot be empty") if value.to_s.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :keystore_password,
            description: "Password for the keystore",
            optional: true,
            sensitive: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_alias,
            description: "Alias for the key",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_algorithm,
            description: "Key algorithm (e.g., RSA)",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_size,
            description: "Key size in bits",
            optional: true,
            type: Integer,
            verify_block: proc do |value|
              UI.user_error!("Key size must be a positive number") unless value.to_i.positive?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :validity,
            description: "Validity period in days",
            optional: true,
            type: Integer,
            verify_block: proc do |value|
              UI.user_error!("Validity must be a positive number") unless value.to_i.positive?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :dname,
            description: "Distinguished Name (e.g., CN=Your Name, OU=Org Unit, O=Your Org, L=Your City, ST=Your State, C=US)",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :trustcacerts,
            description: "Trust CA certificates",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :verbose,
            description: "Enable verbose output",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :genkeypair,
            description: "Generate a key pair",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :list,
            description: "List keystore entries",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :delete,
            description: "Delete a keystore entry",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :certreq,
            description: "Generate a certificate signing request",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :importcert,
            description: "Import a certificate",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :importkeystore,
            description: "Import one keystore into another",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :exportcert,
            description: "Export a certificate",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :noprompt,
            description: "Do not prompt for confirmations",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :storetype,
            description: "Keystore type (e.g., JKS, PKCS12)",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :providername,
            description: "Provider name for the keystore",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :providerclass,
            description: "Provider class for the keystore",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :providerarg,
            description: "Provider argument",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :rfc,
            description: "Output in RFC format (used with -exportcert or -list)",
            optional: true,
            type: Boolean,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :file,
            description: "Output file (used with -export, -exportcert, -certreq)",
            optional: true,
            type: String,
            verify_block: proc do |value|
              UI.user_error!("Output file path cannot be empty") if value.to_s.empty?
            end
          )
        ]
      end

      def self.return_value
        "Returns the exit status code from the keytool command"
      end

      def self.details
        "This action provides a Ruby interface to the Java keytool utility for managing " \
        "keystores, keys, and certificates. It supports all major keytool operations including " \
        "generating key pairs, managing certificates, and importing/exporting keys."
      end

      def self.example_code
        [
          'keytool(
            command: "genkeypair",
            keystore_path: "path/to/keystore.jks",
            keystore_password: "your_password",
            key_alias: "key_alias",
            key_algorithm: "RSA",
            key_size: 2048,
            validity: 10000,
            dname: "CN=Your Name, OU=Your Unit, O=Your Org, L=Your City, ST=Your State, C=US"
          )',
          'keytool(
            command: "exportcert",
            keystore_path: "path/to/keystore.jks",
            keystore_password: "your_password",
            key_alias: "certificate_to_export",
            rfc: true,  # Export certificate in RFC format
            file: "path/to/output/cert.pem"  # Output file path
          )',
          'keytool(
            command: "list",
            keystore_path: "path/to/keystore.jks",
            keystore_password: "your_password",
            verbose: true
          )',
          'keytool(
            command: "delete",
            keystore_path: "path/to/keystore.jks",
            keystore_password: "your_password",
            key_alias: "key_to_delete",
            noprompt: true
          )'
        ]
      end

      def self.category
        :code_signing
      end

      def self.is_supported?(platform)
        true
      end

      def self.output
        [
          ['KEYTOOL_OUTPUT', 'The output from the keytool command']
        ]
      end
    end
  end
end
