# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "htty/media/player/version"

describe HTTY::Media::Player do
	it "has a version number" do
		expect(HTTY::Media::Player::VERSION).to be =~ /\d+\.\d+\.\d+/
	end
end
