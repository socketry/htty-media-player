# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "htty/media/player/application"
require "htty/media/player/playlist"
require "protocol/http/request"
require "tmpdir"

describe HTTY::Media::Player::Application do
	let(:tmpdir) {Dir.mktmpdir}

	def after(*)
		FileUtils.remove_entry(tmpdir)
		super
	end

	def make_media_file(name)
		path = File.join(tmpdir, name)
		File.write(path, "fake media content")
		path
	end

	def fake_request(method, path)
		headers = Protocol::HTTP::Headers.new
		Protocol::HTTP::Request.new("http", "localhost", method, path, "HTTP/1.1", headers, nil)
	end

	let(:mp3_path) {make_media_file("track.mp3")}
	let(:mp4_path) {make_media_file("clip.mp4")}
	let(:playlist) {HTTY::Media::Player::Playlist.from_paths([mp3_path, mp4_path], cache_dir: tmpdir)}
	let(:app) {subject.new(playlist)}

	with "GET /" do
		it "returns 200 with HTML playlist" do
			response = app.call(fake_request("GET", "/"))

			expect(response.status).to be == 200
			expect(response.headers["content-type"]).to be =~ /text\/html/
		end

		it "includes both file titles in the HTML" do
			response = app.call(fake_request("GET", "/"))
			body = response.body.join

			expect(body).to be =~ /track\.mp3/
			expect(body).to be =~ /clip\.mp4/
		end
	end

	with "GET /player" do
		it "returns 200 for a valid index" do
			response = app.call(fake_request("GET", "/player?index=0"))
			expect(response.status).to be == 200
		end

		it "returns 404 for an out-of-range index" do
			response = app.call(fake_request("GET", "/player?index=99"))
			expect(response.status).to be == 404
		end

		it "renders an audio element for an mp3" do
			response = app.call(fake_request("GET", "/player?index=0"))
			body = response.body.join
			expect(body).to be =~ /<audio/
		end

		it "renders a video element for an mp4" do
			response = app.call(fake_request("GET", "/player?index=1"))
			body = response.body.join
			expect(body).to be =~ /<video/
		end

		it "includes a next-index in the player script" do
			response = app.call(fake_request("GET", "/player?index=0"))
			body = response.body.join
			expect(body).to be =~ /nextIndex.*1/
		end

		it "sets nextIndex to null on the last item" do
			response = app.call(fake_request("GET", "/player?index=1"))
			body = response.body.join
			expect(body).to be =~ /nextIndex.*null/
		end
	end

	with "GET /media" do
		it "returns 200 with correct content-type for mp3" do
			response = app.call(fake_request("GET", "/media?index=0"))
			expect(response.status).to be == 200
			expect(response.headers["content-type"]).to be == "audio/mpeg"
		end

		it "returns 200 with correct content-type for mp4" do
			response = app.call(fake_request("GET", "/media?index=1"))
			expect(response.status).to be == 200
			expect(response.headers["content-type"]).to be == "video/mp4"
		end

		it "returns 404 for an out-of-range index" do
			response = app.call(fake_request("GET", "/media?index=99"))
			expect(response.status).to be == 404
		end
	end

	with "POST /last" do
		it "updates last_index and returns 204" do
			response = app.call(fake_request("POST", "/last?index=1"))
			expect(response.status).to be == 204
			expect(playlist.last_index).to be == 1
		end

		it "clamps out-of-range values" do
			response = app.call(fake_request("POST", "/last?index=99"))
			expect(response.status).to be == 204
			expect(playlist.last_index).to be == 1
		end
	end

	with "unknown route" do
		it "returns 404" do
			response = app.call(fake_request("GET", "/nonexistent"))
			expect(response.status).to be == 404
		end
	end
end
