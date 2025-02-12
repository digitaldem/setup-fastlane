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
      puts Dir.pwd
      # Run flutter build to create release artifact for each platform
      begin
        _build_ios
      rescue => e
        UI.error("iOS build failed: #{e}")
        build_failures.push("iOS")
      end

      begin
        _build_android
      rescue => e
        UI.error("Android build failed: #{e}")
        build_failures.push("Android")
      end

      begin
        _build_web
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
      dir_path = "./"
      Dir.entries(dir_path).each { |file| puts file }

      dir_path = "./build"
      Dir.entries(dir_path).each { |file| puts file }

      dir_path = "./build/ios"
      Dir.entries(dir_path).each { |file| puts file }

      dir_path = "./build/app"
      Dir.entries(dir_path).each { |file| puts file }

      dir_path = "./build/app/outputs"
      Dir.entries(dir_path).each { |file| puts file }

      dir_path = "./build/app/outputs/bundle"
      Dir.entries(dir_path).each { |file| puts file }

      dir_path = "./build/app/outputs/bundle/release"
      Dir.entries(dir_path).each { |file| puts file }

      begin
        _upload_ios
      rescue => e
        UI.error("iOS upload failed: #{e}")
        upload_failures.push("iOS")
      end

      begin
        _upload_android
      rescue => e
        UI.error("Android upload failed: #{e}")
        upload_failures.push("Android")
      end

      begin
        _upload_web
      rescue => e
        UI.error("Web upload failed: #{e}")
        upload_failures.push("Web")
      end
    end

    if upload_failures.any?
      UI.crash!("Upload(s) for the following targets failed: [#{upload_failures.join(" ")}]")
    end
  end

  # Private lanes
  desc "Build iOS app"
  lane :_build_ios do
    # Build iOS ipa
    flutter_build("ipa")
  end

  desc "Upload iOS app"
  lane :_upload_ios do
    # Upload iOS ipa
    upload_to_testflight(
      api_key: get_apple_app_store_key(),
      ipa: "./build/ios/#{ENV["SCHEME"]}.ipa",
      app_platform: "ios",
      changelog: $changelog,
      notify_external_testers: false
    )
  end

  desc "Build Android app"
  lane :_build_android do
    # Build Android app bundle
    flutter_build("appbundle")
  end

  desc "Upload Android app"
  lane :_upload_android do
    # Upload Android aab
    Tempfile.open(["temp", ".json"]) do |tempfile|
      tempfile.write(get_google_play_store_key().to_json())
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
  lane :_build_web do
    # Biuld web app
    flutter_build("web")
  end

  desc "Upload Web app"
  lane :_upload_web do
    # Upload web app
  end

  # Helper functions
  def flutter_build(artifact)
    version = Actions.lane_context[:VERSION]
    number = version.split(".").map { |segment| segment.rjust(3, "0") }.join.to_i
    result = execute_command("flutter build #{artifact} --release --build-name #{version} --build-number #{number}")
  end

end
