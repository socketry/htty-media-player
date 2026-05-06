# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# gem "async-htty", path: "../async-htty"
# gem "protocol-htty", path: "../protocol-htty"
# gem "protocol-http2", path: "../protocol-http2"

group :maintenance, optional: true do
	gem "bake-gem"
	gem "bake-releases"
end
