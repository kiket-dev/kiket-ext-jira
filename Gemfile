# frozen_string_literal: true

source "https://rubygems.org"

ruby "~> 3.4"

# Kiket SDK for extension development
gem "kiket-sdk", github: "kiket-dev/kiket-ruby-sdk", branch: "main"

# Jira API client
gem "faraday", "~> 2.9"
gem "faraday-multipart", "~> 1.0"

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "rack-test", "~> 2.1"
  gem "webmock", "~> 3.23"
  gem "vcr", "~> 6.2"
  gem "rubocop", "~> 1.69", require: false
end
