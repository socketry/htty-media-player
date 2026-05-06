# frozen_string_literal: true

require_relative "lib/htty/media/player/version"

Gem::Specification.new do |spec|
	spec.name = "htty-media-player"
	spec.version = HTTY::Media::Player::VERSION

	spec.summary = "A terminal media player using HTTY and HTML5."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"

	spec.homepage = "https://github.com/socketry/htty-media-player"

	spec.files = Dir.glob(["{bin,lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__)

	spec.executables = ["htty-media-player"]

	spec.required_ruby_version = ">= 3.3"

	spec.add_dependency "async-htty", "~> 0.3"
	spec.add_dependency "xrb"
end
