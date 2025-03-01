platform :apple do
  # Public lanes
  desc "Clean derived data and intermediate files"
  lane :clean do
    Dir.chdir("..") do
      # Perform XCode clean
      output = execute_command("xcodebuild clean -project #{ENV["PROJECT"]} -scheme #{ENV["SCHEME"]}")

      # Remove build artifacts from any previous runs
      if Dir.exist?("./builds")
        FileUtils.rm_rf(Dir.glob("./builds/*"))
      end

      # Remove test reports from any previous runs
      if Dir.exist?("./test_output")
        FileUtils.rm_rf(Dir.glob("./test_output/*"))
      end
    end
  end

  desc "Run test suite and export results and coverage reports"
  lane :test do
    Dir.chdir("..") do
      # Perform XCode test
      output = execute_command("xcodebuild test -project #{ENV["PROJECT"]} -scheme #{ENV["SCHEME"]} -destination '#{select_iphone_simulator}' -resultBundlePath ./test_output/#{ENV["SCHEME"]}.xcresult -resultBundleVersion 3 -enableCodeCoverage YES")

      # Extract test results as JSON and convert to JUnit Results XML
      output = execute_command("xcrun xcresulttool get test-results tests --format json --path ./test_output/#{ENV["SCHEME"]}.xcresult")
      results = convert_results_to_junit(output)
      File.open("./test_output/#{ENV["SCHEME"]}_test_results.xml", "w") { |file| file.write(results) }

      # Extract test coverage as JSON and convert to JUnit Coverage XML
      output = execute_command("xcrun xccov view --report --json ./test_output/#{ENV["SCHEME"]}.xcresult")
      coverage = convert_coverage_to_junit(output)
      File.open("./test_output/#{ENV["SCHEME"]}_test_coverage.xml", "w") { |file| file.write(coverage) }
    end
  end

  desc "Build iOS, macOS, and tvOS apps"
  lane :build do |options|
    ios = options[:ios] ? true : false
    macos = options[:macos] ? true : false
    tvos = options[:tvos] ? true : false
    build_failures = []

    # Ensure plist has ITSAppUsesNonExemptEncryption declaration
    update_plist(
      plist_path: "#{ENV["SCHEME"]}/Info.plist",
      block: proc do |plist|
        plist[:ITSAppUsesNonExemptEncryption] = false
      end
    )

    # Increment version patch number and update xcodeproj MARKETING_VERSION
    new_version = increment_version_patch()
    xcodeproj = Xcodeproj::Project.open("../#{ENV["PROJECT"]}")
    xcodeproj.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings["MARKETING_VERSION"] = new_version
      end
    end
    xcodeproj.save

    # Build iOS
    if ios
      begin
        _build_ios
      rescue StandardError => e
        UI.error("iOS build failed: #{e}")
        build_failures.push("iOS")
      end
    end

    # Build macOS (Catalyst)
    if macos
      begin
        _build_macos
      rescue StandardError => e
        UI.error("macOS (Catalyst) build failed: #{e}")
        build_failures.push("macOS")
      end
    end

    # Build tvOS
    if tvos
      begin
        _build_tvos
      rescue StandardError => e
        UI.error("tvOS build failed: #{e}")
        build_failures.push("tvOS")
      end
    end
    
    if build_failures.any?
      UI.crash!("Build(s) for the following targets failed: [#{build_failures.join(" ")}]")
    end
  end

  desc "Upload tvOS, iOS, and macOS apps to TestFlight"
  lane :upload do |options|
    ios = options[:ios] ? true : false
    macos = options[:macos] ? true : false
    tvos = options[:tvos] ? true : false
    upload_failures = []

    # Upload iOS
    if ios
      begin
        _upload_ios
      rescue StandardError => e
        UI.error("iOS upload failed: #{e}")
        upload_failures.push("iOS")
      end
    end

    # Upload macOS (Catalyst)
    if macos
      begin
        _upload_macos
      rescue StandardError => e
        UI.error("macOS (Catalyst) upload failed: #{e}")
        upload_failures.push("macOS")
      end
    end

    # Upload tvOS
    if tvos
      begin
        _upload_tvos
      rescue StandardError => e
        UI.error("tvOS upload failed: #{e}")
        upload_failures.push("tvOS")
      end
    end
    
    if upload_failures.any?
      UI.crash!("Build(s) for the following targets failed: [#{upload_failures.join(" ")}]")
    end
  end

  # Private lanes
  desc "Build iOS app"
  lane :_build_ios do
    # Perform XCode build
    gym(
      project: ENV["PROJECT"],
      scheme: ENV["SCHEME"],
      configuration: "Release",
      sdk: "iphoneos",
      destination: "generic/platform=iOS",
      skip_package_ipa: false,
      output_directory: "./builds/iOS",
      output_name: "#{ENV["SCHEME"]}.ipa",
      xcargs: "OTHER_CODE_SIGN_FLAGS='--keychain #{$keychains_path}/#{ENV["KEYCHAIN"]}-db' IPHONEOS_DEPLOYMENT_TARGET=17.0",
      catalyst_platform: "ios",
      clean: true,
      export_method: "app-store",
      export_options: {
        provisioningProfiles: {
          ENV["APP_IDENTIFIER"] => "match AppStore #{ENV["APP_IDENTIFIER"]}"
        },
        compileBitcode: true
      }
    )
  end

  desc "Upload iOS app to TestFlight"
  lane :_upload_ios do
    # Upload iOS ipa
    upload_to_testflight(
      api_key: get_apple_app_store_key,
      ipa: "./builds/iOS/#{ENV["SCHEME"]}.ipa",
      app_platform: "ios",
      changelog: $changelog,
      notify_external_testers: false
    )
  end

  desc "Build macOS app"
  lane :_build_macos do
    # Perform XCode build
    gym(
      project: ENV["PROJECT"],
      scheme: ENV["SCHEME"],
      configuration: "Release",
      sdk: "macosx",
      destination: "generic/platform=macOS,variant=Mac Catalyst",
      skip_package_ipa: false,
      output_directory: "./builds/macOS",
      output_name: "#{ENV["SCHEME"]}",
      xcargs: "OTHER_CODE_SIGN_FLAGS='--keychain #{$keychains_path}/#{ENV["KEYCHAIN"]}-db' MACOSX_DEPLOYMENT_TARGET=10.15 EFFECTIVE_PLATFORM_NAME=''",
      catalyst_platform: "macos",
      clean: true,
      export_method: "app-store",
      export_options: {
        provisioningProfiles: {
          ENV["APP_IDENTIFIER"] => "match AppStore #{ENV["APP_IDENTIFIER"]} catalyst"
        },
        compileBitcode: false
      }
    )
  end

  desc "Upload macOS app to TestFlight"
  lane :_upload_macos do
    # Upload macOS pkg
    upload_to_testflight(
      api_key: get_apple_app_store_key,
      pkg: "./builds/macOS/#{ENV["SCHEME"]}.pkg",
      app_platform: "osx",
      changelog: $changelog,
      notify_external_testers: false
    )
  end

  desc "Build tvOS app"
  lane :_build_tvos do
    # Perform XCode build
    gym(
      project: ENV["PROJECT"],
      scheme: ENV["SCHEME"],
      configuration: "Release",
      sdk: "appletvos",
      destination: "generic/platform=tvOS",
      skip_package_ipa: false,
      output_directory: "./builds/tvOS",
      output_name: "#{ENV["SCHEME"]}.ipa",
      xcargs: "OTHER_CODE_SIGN_FLAGS='--keychain #{$keychains_path}/#{ENV["KEYCHAIN"]}-db' TVOS_DEPLOYMENT_TARGET=17.0",
      clean: true,
      export_method: "app-store",
      export_options: {
        provisioningProfiles: {
          ENV["APP_IDENTIFIER"] => "match AppStore #{ENV["APP_IDENTIFIER"]} tvos"
        },
        compileBitcode: true
      }
    )
  end

  desc "Upload tvOS app to TestFlight"
  lane :_upload_tvos do
    # Upload tvOS ipa
    upload_to_testflight(
      api_key: get_apple_app_store_key,
      ipa: "./builds/tvOS/#{ENV["SCHEME"]}.ipa",
      app_platform: "appletvos",
      changelog: $changelog,
      notify_external_testers: false
    )
  end

  # Helper functions
  def select_iphone_simulator
    # Get list of available simulators
    simulators = Actions.sh_no_action("xcrun simctl list devices", log: true)
    ios_versions = []
    iphone_models = []

    simulators.each_line do |line|
      # Match lines with the iOS version (e.g., "-- iOS 18.0 --")
      ios_versions << line.split[2] if line =~ /^-- iOS/
      # Match lines with available iPhone devices (excluding unavailable devices)
      iphone_models << line.split(" (").first.strip if line =~ /iPhone/ && !line.include?("unavailable")
    end

    latest_ios = ios_versions.max_by { |os| Gem::Version.new(os) }
    latest_model = iphone_models.max_by { |model| model.gsub(/[^0-9]/, "").to_i }

    # Abort if there is no viable simulator
    unless latest_ios && latest_model
      UI.user_error!("Could not find an appropriate simulator.")
    end

    # Return "latest" simulator string
    puts "platform=iOS Simulator,name=#{latest_model},OS=#{latest_ios}"
    "platform=iOS Simulator,name=#{latest_model},OS=#{latest_ios}"
  end

  def convert_results_to_junit(json_string)
    json = JSON.parse(json_string)

    # Create a new JUnit XML document
    doc = REXML::Document.new
    testsuites = doc.add_element("testsuites")

    # Add device information as an attribute to the testsuites element
    device = json["devices"].first
    testsuites.add_attribute("deviceName", device["deviceName"])
    testsuites.add_attribute("osVersion", device["osVersion"])
    testsuites.add_attribute("platform", device["platform"])

    # Iterate over each test plan and suite
    json["testNodes"].each do |test_plan|
      testsuite = testsuites.add_element("testsuite", {
        "name" => test_plan["name"],
        "tests" => test_plan["children"].flat_map { |bundle| bundle["children"] }.size.to_s,
        "failures" => "0",
        "errors" => "0",
      })

      test_plan["children"].each do |bundle|
        bundle["children"].each do |suite|
          suite["children"].each do |test_case|
            testcase = testsuite.add_element("testcase", {
              "name" => test_case["name"],
              "classname" => suite["name"],
              "time" => test_case["duration"].gsub("s", "")
            })

            if test_case["result"] != "Passed"
              failure = testcase.add_element("failure", {
                "message" => "Test failed"
              })
              failure.text = "Failure in #{test_case["name"]}"
            end
          end
        end
      end
    end

    # Return the XML as a string
    output = StringIO.new
    doc.write(output, 2)
    output.string
  end

  def convert_coverage_to_junit(json_string)
    json = JSON.parse(json_string)

    # Create a new JUnit XML document
    doc = REXML::Document.new
    testsuites = doc.add_element("testsuites")

    # Create a top-level test suite to encapsulate all file coverage results
    testsuite = testsuites.add_element("testsuite", {
      "name" => json["name"],
      "tests" => json["targets"][0]["files"].size.to_s,
      "failures" => "0",
      "errors" => "0"
    })

    # Loop through each file and generate a test case for its coverage
    json["targets"][0]["files"].each do |file|
      file_name = file["name"]
      file_coverage = file["lineCoverage"]

      testcase = testsuite.add_element("testcase", {
        "name" => file_name,
        "classname" => json["targets"][0]["name"],
        "time" => "0"
      })

      # Mark the file as failed if it has any uncovered lines
      if file_coverage < 1
        failure = testcase.add_element("failure", {
          "message" => "Partial coverage",
        })
        failure.text = "#{file["coveredLines"]}/#{file["executableLines"]} lines covered, #{(file_coverage * 100).round(2)}% coverage"
      end

      # Add details for each function in the file
      file["functions"].each do |function|
        func_name = function["name"]
        func_coverage = function["lineCoverage"]

        # Create a nested testcase for each function
        func_testcase = testsuite.add_element("testcase", {
          "name" => "#{file_name} - #{func_name}",
          "classname" => json["targets"][0]["name"],
          "time" => "0"
        })

        if func_coverage < 1
          func_failure = func_testcase.add_element("failure", {
            "message" => "Partial coverage in function #{func_name}"
          })
          func_failure.text = "#{function["coveredLines"]}/#{function["executableLines"]} lines covered, #{(func_coverage * 100).round(2)}% coverage"
        end
      end
    end

    # Return the XML as a string
    output = StringIO.new
    doc.write(output, 2)
    output.string
  end

end
