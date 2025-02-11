platform :flutter do
  # Public lanes
  desc "Clean the flutter project"
  lane :clean do
    Dir.chdir("..") do
      # Remove build artifacts from any previous runs
      if Dir.exist?("./build")
        FileUtils.rm_rf(Dir.glob("./build/*"))
      end

      # Remove test reports from any previous runs
      if Dir.exist?("./coverage")
        FileUtils.rm_rf(Dir.glob("./coverage/*"))
      end

      # Run flutter clean to clear the workspace
      result = execute_command("flutter clean")
    end
  end

  desc "Get flutter dependencies"
  lane :pub do
    Dir.chdir("..") do
      # Run flutter pub get to install package dependencies
      result = execute_command("flutter pub get")

      # Run flutter build_runner to output generated code
      result = execute_command("flutter pub run build_runner build --delete-conflicting-outputs")
    end
  end

  desc "Run flutter unit tests with coverage report"
  lane :test do
    Dir.chdir("..") do
      # Run flutter test to execute unit tests
      result = execute_command("flutter test --coverage --reporter json")
      File.open("./coverage/results.json", "w") do |file|
        file.write(result)
      end
    end
  end

  desc "Run flutter build for all target platforms"
  lane :build do
    build_failures = []

    # Increment version patch number
    version = increment_version_patch()
    Actions.lane_context[:VERSION] = version

    Dir.chdir("..") do
      # Run flutter build to create release artifact for each platform
      begin
        build_ios
      rescue => e
        UI.error("iOS build failed: #{e}")
        build_failures.push("iOS")
      end

      begin
        build_android
      rescue => e
        UI.error("Android build failed: #{e}")
        build_failures.push("Android")
      end

      begin
        build_web
      rescue => e
        UI.error("Web build failed: #{e}")
        build_failures.push("Web")
      end
    end

    if build_failures.any?
      UI.crash!("Build(s) for the following targets failed: [#{build_failures.join(" ")}]")
    end
  end

  desc "Upload artifacts to app stores"
  lane :upload do
    upload_failures = []

    Dir.chdir("..") do
      begin
        upload_ios
      rescue => e
        UI.error("iOS upload failed: #{e}")
        upload_failures.push("iOS")
      end

      begin
        upload_android
      rescue => e
        UI.error("Android upload failed: #{e}")
        upload_failures.push("Android")
      end

      begin
        upload_web
      rescue => e
        UI.error("Web upload failed: #{e}")
        upload_failures.push("Web")
      end
    end

    if upload_failures.any?
      UI.crash!("Build(s) for the following targets failed: [#{upload_failures.join(" ")}]")
    end
  end

  # Private lanes
  desc "Build iOS app"
  private lane :build_ios do
    # Build iOS ipa
    flutter_build("ipa")
  end

  desc "Upload iOS app"
  private lane :upload_ios do
    # Upload iOS ipa
    upload_to_testflight(
      api_key: apple_api_key,
      ipa: "./build/ios/#{ENV["SCHEME"]}.ipa",
      app_platform: "ios",
      changelog: changelog,
      notify_external_testers: false
    )
  end

  desc "Build Android app"
  private lane :build_android do
    # Build Android app bundle
    flutter_build("appbundle")
  end

  desc "Upload Android app"
  private lane :upload_android do
    # Upload Android aab
    Tempfile.open(["temp", ".json"]) do |tempfile|
      tempfile.write(google_api_key)
      tempfile.flush
      supply(
        json_key: tempfile.path,
        package_name: ENV["APP_IDENTIFIER"],
        track: "internal",
        aab: "./build/app/outputs/bundle/release/app-release.aab"
      )
    end
  end

  desc "Build Web app"
  private lane :build_web do
    # Biuld web app
    flutter_build("web")
  end

  desc "Upload Web app"
  private lane :upload_web do
    # Upload web app
  end

  # Helper functions
  def flutter_build(artifact)
    version = Actions.lane_context[:VERSION]
    number = version.split(".").map { |segment| segment.rjust(3, "0") }.join.to_i
    result = execute_command("flutter build #{artifact} --release --build-name #{version} --build-number #{number}")
  end

end
