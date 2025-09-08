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
  lane :build do |options|
    ios = options[:ios] ? true : false
    android = options[:android] ? true : false
    web = options[:web] ? true : false
    build_failures = []

    # Increment version patch number
    version = increment_version_patch()
    number = version.split(".").map { |segment| segment.rjust(3, "0") }.join.to_i

    Dir.chdir("..") do
      # Run flutter build to create release artifact for each platform
      if ios
        begin
          _build_ios(version: version, number: number)
        rescue StandardError => e
          UI.error("iOS build failed: #{e}")
          build_failures.push("iOS")
        end
      end

      if android
        begin
          _build_android(version: version, number: number)
        rescue StandardError => e
          UI.error("Android build failed: #{e}")
          build_failures.push("Android")
        end
      end

      if web
        begin
          _build_web(version: version, number: number)
        rescue StandardError => e
          UI.error("Web build failed: #{e}")
          build_failures.push("Web")
        end
      end
    end

    if build_failures.any?
      UI.crash!("Build(s) for the following targets failed: [#{build_failures.join(" ")}]")
    end
  end

  desc "Upload artifacts to app stores"
  lane :upload do |options|
    ios = options[:ios] ? true : false
    android = options[:android] ? true : false
    web = options[:web] ? true : false
    upload_failures = []

    # Increment version patch number
    version = increment_version_patch()
    number = version.split(".").map { |segment| segment.rjust(3, "0") }.join.to_i

    Dir.chdir("..") do
      if ios
        begin
          _upload_ios(version: version, number: number)
        rescue StandardError => e
          UI.error("iOS upload failed: #{e}")
          upload_failures.push("iOS")
        end
      end

      if android
        begin
          _upload_android(version: version, number: number)
        rescue StandardError => e
          UI.error("Android upload failed: #{e}")
          upload_failures.push("Android")
        end
      end

      if web
        begin
          _upload_web(version: version, number: number)
        rescue StandardError => e
          UI.error("Web upload failed: #{e}")
          upload_failures.push("Web")
        end
      end
    end

    if upload_failures.any?
      UI.crash!("Upload(s) for the following targets failed: [#{upload_failures.join(" ")}]")
    end
  end

  # Private lanes
  desc "Build iOS app"
  lane :_build_ios do |options|
    version = options[:version] || "0.0.1"
    number = 1  #options[:number] || 1
    
    # Build iOS ipa
    flutter_build("ipa", version, number, { "export-options-plist" => "./ios/ExportOptions.plist" })
  end

  desc "Upload iOS app"
  lane :_upload_ios do |options|
    version = options[:version] || "0.0.1"
    number = 1  #options[:number] || 1

    # Upload iOS ipa
    ipa = Dir.glob(File.join("./build/ios/ipa", "*.ipa")).max_by { |f| File.mtime(f) }&.then { |f| File.expand_path(f) }
    upload_to_testflight(
      api_key: get_apple_app_store_key(),
      ipa: ipa,
      app_platform: "ios",
      changelog: $changelog,
      notify_external_testers: false
    )
  end

  desc "Build Android app"
  lane :_build_android do |options|
    version = options[:version] || "0.0.1"
    number = options[:number] || 1

    # Build Android app bundle
    flutter_build("appbundle", version, number, nil)
  end

  desc "Upload Android app"
  lane :_upload_android do |options|
    version = options[:version] || "0.0.1"
    number = 1  #options[:number] || 1

    # Upload Android aab
    aab = Dir.glob(File.join("./build/app/outputs/bundle/release", "*.aab")).max_by { |f| File.mtime(f) }&.then { |f| File.expand_path(f) }
    Tempfile.open(["temp", ".json"]) do |tempfile|
      tempfile.write(get_google_play_store_key().to_json())
      tempfile.flush
      supply(
        json_key: tempfile.path,
        aab: aab,
        mapping: File.expand_path("build/app/outputs/mapping/release/mapping.txt", Dir.pwd),
        package_name: ENV["APP_IDENTIFIER"],
        version_name: "Version #{version} (#{number})",
        track: "internal",
        release_status: "draft",
      )
    end
  end

  desc "Build Web app"
  lane :_build_web do |options|
    version = options[:version] || "0.0.1"
    number = 1  #options[:number] || 1

    # Build web app
    flutter_build("web", version, number, nil)
  end

  desc "Upload Web app"
  lane :_upload_web do |options|
    version = options[:version] || "0.0.1"
    number = 1  #options[:number] || 1

    # Upload web app
    #TODO
  end

  # Helper functions
  def flutter_build(artifact, version, number, options)
    additional_args = options&.map { |key, value| "--#{key} #{value}" }&.join(" ") || ""
    result = execute_command("flutter build #{artifact} --release --build-name #{version} --build-number #{number} #{additional_args}")
  end

end
