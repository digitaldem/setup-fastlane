require "fileutils"
require "open3"

module Fastlane
  module Actions
    module SharedValues
       KEYTOOL_OUTPUT = :KEYTOOL_OUTPUT
    end

    class KeytoolAction < Action
      def self.run(params)
        # Build the base command
        keytool_command = ["keytool"]
        keytool_command << "-#{params[:command]}"

        # Add optional and required parameters dynamically
        keytool_command << "-keystore" << params[:keystore_path] if params[:keystore_path]
        FileUtils.mkdir_p(File.dirname(params[:keystore_path])) if params[:keystore_path]
        keytool_command << "-storepass" << params[:keystore_password] if params[:keystore_password]
        keytool_command << "-alias" << params[:key_alias] if params[:key_alias]
        keytool_command << "-keypass" << params[:keystore_password] if params[:keystore_password]
        keytool_command << "-keyalg" << params[:key_algorithm] if params[:key_algorithm]
        keytool_command << "-keysize" << params[:key_size].to_s if params[:key_size]
        keytool_command << "-validity" << params[:validity].to_s if params[:validity]
        keytool_command << "-dname" << "\"#{params[:dname]}\"" if params[:dname]
        keytool_command << "-trustcacerts" if params[:trustcacerts]
        keytool_command << "-v" if params[:verbose]
        keytool_command << "-genkeypair" if params[:genkeypair]
        keytool_command << "-list" if params[:list]
        keytool_command << "-delete" if params[:delete]
        keytool_command << "-certreq" if params[:certreq]
        keytool_command << "-importcert" if params[:importcert]
        keytool_command << "-importkeystore" if params[:importkeystore]
        keytool_command << "-exportcert" if params[:exportcert]
        keytool_command << "-noprompt" if params[:noprompt]
        keytool_command << "-storetype" << params[:storetype] if params[:storetype]
        keytool_command << "-providername" << params[:providername] if params[:providername]
        keytool_command << "-providerclass" << params[:providerclass] if params[:providerclass]
        keytool_command << "-providerarg" << params[:providerarg] if params[:providerarg]

        # Execute the command
        cmd = keytool_command.join(" ")
        UI.command(cmd)
        output, status = Open3.capture2(cmd, err: [:child, :out])
        Actions.lane_context[SharedValues::KEYTOOL_OUTPUT] = output

        unless status.success?
          UI.user_error!("== Command Failed ==\nExit Status: #{status.exitstatus}\nOutput: #{output}")
        end
  
        # Return the exit status code
        status.exitstatus
      end

      def self.description
        "Interface with the keytool command to manage keystores and certificates for Android app signing"
      end

      def self.authors
        ["Dave"]
      end

      def self.output
        [
          ["KEYTOOL_OUTPUT", "The raw stdout/stderr output of the keytool command"]
        ]
      end
      
      def self.return_value
        "The exit status code of the keytool command"
      end

      def self.details
        "This action wraps the keytool command, allowing the use of its full set of options"
      end

      def self.available_options
        [
          # General Options
          FastlaneCore::ConfigItem.new(key: :command,
                                       description: "Keytool subcommand to run (e.g., -genkeypair, -list)",
                                       optional: false,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :keystore_path,
                                       description: "Path to the keystore file",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :keystore_password,
                                       description: "Password for the keystore",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :key_alias,
                                       description: "Alias for the key",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :key_algorithm,
                                       description: "Key algorithm (e.g., RSA)",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :key_size,
                                       description: "Key size in bits",
                                       optional: true,
                                       type: Integer),
          FastlaneCore::ConfigItem.new(key: :validity,
                                       description: "Validity period in days",
                                       optional: true,
                                       type: Integer),
          FastlaneCore::ConfigItem.new(key: :dname,
                                       description: "Distinguished Name (e.g., CN=Your Name, OU=Org Unit, etc.)",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :trustcacerts,
                                       description: "Include this flag to trust the CA certificates",
                                       optional: true,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :verbose,
                                       description: "Include this flag for verbose output",
                                       optional: true,
                                       type: Boolean),

          # Additional Commands
          FastlaneCore::ConfigItem.new(key: :genkeypair,
                                       description: "Include this flag to generate a key pair",
                                       optional: true,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :list,
                                       description: "Include this flag to list keystore entries",
                                       optional: true,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :delete,
                                       description: "Include this flag to delete a keystore entry",
                                       optional: true,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :certreq,
                                       description: "Include this flag to generate a certificate signing request",
                                       optional: true,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :importcert,
                                       description: "Include this flag to import a certificate into the keystore",
                                       optional: true,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :importkeystore,
                                       description: "Include this flag to import one keystore into another",
                                       optional: true,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :exportcert,
                                       description: "Include this flag to export a certificate",
                                       optional: true,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :noprompt,
                                       description: "Include this flag to suppress prompts",
                                       optional: true,
                                       type: Boolean),
          FastlaneCore::ConfigItem.new(key: :storetype,
                                       description: "Keystore type (e.g., JKS, PKCS12)",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :providername,
                                       description: "Provider name for the keystore",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :providerclass,
                                       description: "Provider class for the keystore",
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :providerarg,
                                       description: "Arguments for the provider class",
                                       optional: true,
                                       type: String)
        ]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
