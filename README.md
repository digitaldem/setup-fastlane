# **Setup Fastlane Action**

This GitHub Action sets up a Fastlane environment for mobile projects based on centralized dependencies and configurations. 
It installs Ruby, Bundler, Fastlane and additional required gems, and copies the entire `fastlane` directory (including some custom actions) into your project. 
Use this action to ensure consistent Fastlane configurations across multiple mobile repositories.

---

## **Features**

- Installs Ruby and gems from a centralized `Gemfile`.
- Copies the entire `fastlane` directory, including the `Fastfile` and some custom actions.
- Supports caching of Ruby gems for faster CI builds.
- Simplifies Fastlane setup across multiple projects.

---

## **Usage**

Add this `setup-action` to the workflow file in your app repository:

```yaml
name: Build and Deploy

on:
  push:
    branches:
      - main

jobs:
  build:
    runs-on: macos-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Fastlane Environment
        uses: digitaldem/setup-fastlane@v1

      - name: Run Fastlane
        run: bundle exec fastlane [clean / test / build / upload ]

```

---

## **Inputs**

| Input         | Description                  | Required | Default |
| ------------- | ---------------------------- | -------- | ------- |
| `ruby_version` | Ruby version to use for Fastlane | No       | `3.3`   |

---

## **Environment Variables**

Set the following GitHub Environment variables in your consumer repository:
- `APP_IDENTIFIER` App identifier (ex: com.digitaldementia.myapp)
- `KEYCHAIN` Name for the temporary keychain (ex: build.keychain)
- `PROJECT` XCode project file (ex: Runner.xcodeproj)
- `SCHEME` XCode build scheme (ex: Runner)

Set the following GitHub Secret variables in your consumer repository:
- `GIT_USER`
- `GIT_SSH_KEY`
- `SIGNING_ASSETS_GIT_URL`
- `MATCH_PASSWORD`
- `APP_STORE_KEY`
- `APP_STORE_KEY_ID`
- `APP_STORE_ISSUER_ID`
- `PLAY_STORE_KEY`

---

## **License**

MIT License.
