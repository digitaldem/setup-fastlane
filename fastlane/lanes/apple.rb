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
    specified_version = options[:version] || "0.0.1"
    build_failures = []

    # Ensure plist has ITSAppUsesNonExemptEncryption declaration
    update_plist(
      plist_path: "#{ENV["SCHEME"]}/Info.plist",
      block: proc do |plist|
        plist[:ITSAppUsesNonExemptEncryption] = false
      end
    )

    # Increment version patch number and update xcodeproj MARKETING_VERSION
    minimum_version = get_minimum_version()
    version = [Gem::Version.new(specified_version), Gem::Version.new(minimum_version)].max
    
    xcodeproj = Xcodeproj::Project.open("../#{ENV["PROJECT"]}")
    xcodeproj.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings["MARKETING_VERSION"] = version
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

    # Build macOS
    if macos
      begin
        _build_macos
      rescue StandardError => e
        UI.error("macOS build failed: #{e}")
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

    # Upload macOS
    if macos
      begin
        _upload_macos
      rescue StandardError => e
        UI.error("macOS upload failed: #{e}")
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
    # Output setup
    archive_dir = File.expand_path("../../builds/iOS", __dir__)
    FileUtils.mkdir_p(archive_dir) 
    UI.message("iOS archiving created at: #{archive_dir.inspect}")
    export_dir = File.expand_path("../../builds/iOS/export", __dir__) 
    FileUtils.mkdir_p(export_dir) 
    UI.message("iOS exporting at: #{export_dir}") 

    # XCodeBuild archive
    gym(
      project: ENV["PROJECT"],
      scheme: ENV["SCHEME"],
      configuration: "Release",
      sdk: "iphoneos",
      destination: "generic/platform=iOS",
      catalyst_platform: "ios",
      clean: true,
      skip_package_ipa: true,      
      build_path: archive_dir,
      #output_name: "#{ENV["SCHEME"]}",
      xcargs: "OTHER_CODE_SIGN_FLAGS='--keychain #{$keychains_path}/#{ENV["KEYCHAIN"]}-db' IPHONEOS_DEPLOYMENT_TARGET=17.0"
    )
    
    # Validate archive
    archive = Actions.lane_context[SharedValues::XCODEBUILD_ARCHIVE] 
    UI.crash!("gym did not return XCODEBUILD_ARCHIVE") unless archive 
    UI.crash!("gym returned an invalid XCODEBUILD_ARCHIVE #{archive.inspect}") unless archive.include?("/iOS/")
    UI.crash!("gym returned XCODEBUILD_ARCHIVE #{archive.inspect} but archive does not exist") unless File.exist?(archive)    
    UI.message("iOS archive created at: #{archive.inspect}") 

    # XCodeBuild export from archive
    with_export_options_plist("match AppStore #{ENV["APP_IDENTIFIER"]}") do |export_plist|
      execute_command("xcrun xcodebuild -exportArchive -archivePath \"#{archive}\" -exportPath \"#{export_dir}\" -exportOptionsPlist \"#{export_plist}\" OTHER_CODE_SIGN_FLAGS='--keychain #{$keychains_path}/#{ENV["KEYCHAIN"]}-db'")
      execute_command("ls -la #{export_dir}")
    end

    # Validate export
    export = File.join(export_dir, "#{ENV["SCHEME"]}.ipa")
    UI.crash!("Archive does not exist") unless File.exist?(export)    
    UI.message("iOS export created at: #{export.inspect}") 
  end

  desc "Upload iOS app to TestFlight"
  lane :_upload_ios do
    # Upload iOS ipa
    upload_to_testflight(
      api_key: get_apple_app_store_key,
      ipa: File.expand_path("../../builds/iOS/export/#{ENV["SCHEME"]}.ipa", __dir__),
      app_platform: "ios",
      changelog: $changelog,
      notify_external_testers: false
    )
  end

  desc "Build macOS app"
  lane :_build_macos do
    # Output setup
    archive_dir = File.expand_path("../../builds/macOS", __dir__)
    FileUtils.mkdir_p(archive_dir) 
    UI.message("macOS archiving created at: #{archive_dir.inspect}")
    export_dir = File.expand_path("../../builds/macOS/export", __dir__) 
    FileUtils.mkdir_p(export_dir) 
    UI.message("macOS exporting at: #{export_dir}") 
    
    # XCodeBuild archive
    gym(
      project: ENV["PROJECT"],
      scheme: ENV["SCHEME"],
      configuration: "Release",
      sdk: "macosx",
      #destination: "generic/platform=macOS,variant=Mac Catalyst",
      destination: "generic/platform=macOS",
      #catalyst_platform: "macos",
      clean: true,
      skip_package_ipa: true,
      build_path: archive_dir,
      #output_name: "#{ENV["SCHEME"]}",
      xcargs: "OTHER_CODE_SIGN_FLAGS='--keychain #{$keychains_path}/#{ENV["KEYCHAIN"]}-db' MACOSX_DEPLOYMENT_TARGET=10.15 EFFECTIVE_PLATFORM_NAME=''"
    )
    
    # Validate archive
    archive = Actions.lane_context[SharedValues::XCODEBUILD_ARCHIVE] 
    UI.crash!("gym did not return XCODEBUILD_ARCHIVE") unless archive 
    UI.crash!("gym returned an invalid XCODEBUILD_ARCHIVE #{archive.inspect}") unless archive.include?("/macOS/")
    UI.crash!("gym returned XCODEBUILD_ARCHIVE #{archive.inspect} but archive does not exist") unless Dir.exist?(archive)
    UI.message("macOS archive created at: #{archive.inspect}") 

    # XCodeBuild export from archive
    with_export_options_plist("match AppStore #{ENV["APP_IDENTIFIER"]} macos") do |export_plist|
      execute_command("xcrun xcodebuild -exportArchive -archivePath \"#{archive}\" -exportPath \"#{export_dir}\" -exportOptionsPlist \"#{export_plist}\" OTHER_CODE_SIGN_FLAGS='--keychain #{$keychains_path}/#{ENV["KEYCHAIN"]}-db'")
      execute_command("ls -la #{export_dir}")
    end

    # Validate export
    export = File.join(export_dir, "#{ENV["SCHEME"]}.pkg")
    UI.crash!("Archive does not exist") unless File.exist?(export)
    UI.message("iOS export created at: #{export.inspect}")     
  end

  desc "Upload macOS app to TestFlight"
  lane :_upload_macos do
    # Upload macOS pkg
    upload_to_testflight(
      api_key: get_apple_app_store_key,
      pkg: File.expand_path("../../builds/macOS/export/#{ENV["SCHEME"]}.pkg", __dir__),
      app_platform: "osx",
      changelog: $changelog,
      notify_external_testers: false
    )
  end

  desc "Build tvOS app"
  lane :_build_tvos do
    # Output setup
    archive_dir = File.expand_path("../../builds/tvOS", __dir__)
    FileUtils.mkdir_p(archive_dir) 
    UI.message("tvOS archiving created at: #{archive_dir.inspect}")
    export_dir = File.expand_path("../../builds/tvOS/export", __dir__) 
    FileUtils.mkdir_p(export_dir) 
    UI.message("tvOS exporting at: #{export_dir}") 

    # XCodeBuild archive
    gym(
      silent: false,
      suppress_xcode_output: false,
      disable_xcpretty: true,
      buildlog_path: File.expand_path("~/Library/Logs/gym", ENV["HOME"]),
      xcodebuild_formatter: "xcbeautify",
      
      project: ENV["PROJECT"],
      scheme: ENV["SCHEME"],
      configuration: "Release",
      sdk: "appletvos",
      destination: "generic/platform=tvOS",
      clean: true,
      skip_package_ipa: true,      
      build_path: archive_dir,
      #output_name: "#{ENV["SCHEME"]}",
      xcargs: "OTHER_CODE_SIGN_FLAGS='--keychain #{$keychains_path}/#{ENV["KEYCHAIN"]}-db' TVOS_DEPLOYMENT_TARGET=17.0"
    )

    log_path = Actions.lane_context[SharedValues::XCODEBUILD_ARCHIVE]
    UI.message("Archive: #{log_path}")
    Actions.sh("ls -la ~/Library/Logs/gym || true")
    Actions.sh("grep -R \"exportArchive\\|Generated plist file\" -n ~/Library/Logs/gym | tail -n 50 || true")
    
    # Validate archive
    archive = Actions.lane_context[SharedValues::XCODEBUILD_ARCHIVE] 
    UI.crash!("gym did not return XCODEBUILD_ARCHIVE") unless archive 
    UI.crash!("gym returned an invalid XCODEBUILD_ARCHIVE #{archive.inspect}") unless archive.include?("/tvOS/")
    UI.crash!("gym returned XCODEBUILD_ARCHIVE #{archive.inspect} but archive does not exist") unless File.exist?(archive)    
    UI.message("tvOS archive created at: #{archive.inspect}") 

    # Export from archive
    with_export_options_plist("match AppStore #{ENV["APP_IDENTIFIER"]} tvos") do |export_plist|
      execute_command("xcrun xcodebuild -exportArchive -archivePath \"#{archive}\" -exportPath \"#{export_dir}\" -exportOptionsPlist \"#{export_plist}\" OTHER_CODE_SIGN_FLAGS='--keychain #{$keychains_path}/#{ENV["KEYCHAIN"]}-db'")
      execute_command("ls -la #{export_dir}")
    end

    # Validate export
    export = File.join(export_dir, "#{ENV["SCHEME"]}.ipa")
    UI.crash!("Archive does not exist") unless File.exist?(export)    
    UI.message("tvOS export created at: #{export.inspect}")     
  end

  desc "Upload tvOS app to TestFlight"
  lane :_upload_tvos do
    # Upload tvOS ipa
    upload_to_testflight(
      api_key: get_apple_app_store_key,
      ipa: File.expand_path("../../builds/tvOS/export/#{ENV["SCHEME"]}.ipa", __dir__),
      app_platform: "appletvos",
      changelog: $changelog,
      notify_external_testers: false
    )
  end

  # Helper functions
  def select_iphone_simulator
    iphone_simulators = []
    
    # Get list of available simulators
    simctl_list = JSON.parse(Actions.sh_no_action("xcrun simctl list devices -j", log: false))
    simctl_list["devices"].each do |runtime, simulators|
      # Parse the version string from the runtime and process each simulator
      next unless runtime.include?("iOS")
      version = runtime.match(/iOS-(\d+-\d+)/)&.captures&.first&.tr('-', '.')
      simulators.each do |simulator|
        next unless simulator["name"].include?("iPhone") && simulator["isAvailable"]
        iphone_simulators.push({ "id" => simulator["udid"], "model" => simulator["name"], "version" => version })
      end
    end

    # Abort if there is no viable simulator
    if iphone_simulators.empty?
      UI.user_error!("Could not find an appropriate simulator.")
    end
    
    # Select "latest" simulator and return the device id
    device = iphone_simulators.sort_by do |iphone|
      model = 
        if iphone["model"].include?(" Pro")
          2
        elsif iphone["model"].include?(" SE")
          0
        else
          1
        end
      [Gem::Version.new(iphone["version"]), model]
    end.last
    UI.message("Testing on #{device["model"]} running iOS #{device["version"]}")

    Actions.sh_no_action("xcrun simctl boot #{device["id"]}", log: true)
    60.times do |i|
      if Actions.sh_no_action("xcrun simctl list devices | grep '#{device["id"]}' | grep 'Booted'", log: false).include?("Booted")
        break
      end
      sleep(1)
    end
    "id=#{device["id"]}"
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

  def with_export_options_plist(profile)
    Dir.mktmpdir("export-options") do |dir|
      path = File.join(dir, "exportOptions.plist")
  
      plist_hash = {
        "method" => "app-store",
        "signingStyle" => "manual",
        "compileBitcode" => true,
        "provisioningProfiles" => {
          ENV["APP_IDENTIFIER"] => profile
        }
      }
  
      plist = CFPropertyList::List.new
      plist.value = CFPropertyList.guess(plist_hash)
      File.write(path, plist.to_str(CFPropertyList::List::FORMAT_XML))
  
      yield path
    end
  end

end
