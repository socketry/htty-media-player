# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "htty/media/player/file"

describe HTTY::Media::Player::File do
	let(:mp3_path) {"/music/track.mp3"}
	let(:mp4_path) {"/video/clip.mp4"}

	with "an audio file" do
		let(:file) {subject.new(mp3_path, duration: 222.4)}

		it "reports the filename as title when no tag is present" do
			expect(file.title).to be == "track.mp3"
		end

		it "prefers the tag title over the filename" do
			file.tag_title = "My Song"
			expect(file.title).to be == "My Song"
		end

		it "returns the filename regardless of tag" do
			file.tag_title = "My Song"
			expect(file.filename).to be == "track.mp3"
		end

		it "detects the MIME type" do
			expect(file.type).to be == "audio/mpeg"
		end

		it "is audio" do
			expect(file).to be(:audio?)
		end

		it "is not video" do
			expect(file).not.to be(:video?)
		end

		it "formats a duration label in m:ss" do
			expect(file.duration_label).to be == "3:42"
		end
	end

	with "an audio file longer than one hour" do
		let(:file) {subject.new(mp3_path, duration: 3661.0)}

		it "formats a duration label in h:mm:ss" do
			expect(file.duration_label).to be == "1:01:01"
		end
	end

	with "a video file" do
		let(:file) {subject.new(mp4_path)}

		it "is video" do
			expect(file).to be(:video?)
		end

		it "is not audio" do
			expect(file).not.to be(:audio?)
		end

		it "detects the MIME type" do
			expect(file.type).to be == "video/mp4"
		end

		it "returns nil duration_label when duration is unknown" do
			expect(file.duration_label).to be == nil
		end
	end

	with "#to_h" do
		let(:file) {subject.new(mp3_path, duration: 99.5, tag_title: "Song", artist: "Band", album: "Record")}

		it "serialises duration and tags" do
			expect(file.to_h).to be == {duration: 99.5, tag_title: "Song", artist: "Band", album: "Record"}
		end
	end
end
