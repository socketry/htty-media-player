# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "htty/media/player/playlist"
require "tmpdir"
require "json"

describe HTTY::Media::Player::Playlist do
	let(:tmpdir) {Dir.mktmpdir}

	def after(*)
		FileUtils.remove_entry(tmpdir)
		super
	end

	def make_file(name)
		path = File.join(tmpdir, name)
		File.write(path, "")
		path
	end

	with ".from_paths" do
		it "builds a playlist from explicit paths" do
			a = make_file("a.mp3")
			b = make_file("b.mp4")
			playlist = subject.from_paths([a, b], cache_dir: tmpdir)

			expect(playlist.size).to be == 2
			expect(playlist[0].title).to be == "a.mp3"
			expect(playlist[1].title).to be == "b.mp4"
		end
	end

	with ".from_directory" do
		it "globs supported media files" do
			make_file("song.mp3")
			make_file("video.mp4")
			make_file("notes.txt")

			playlist = subject.from_directory(tmpdir)

			titles = playlist.files.map(&:title)
			expect(titles).to be(:include?, "song.mp3")
			expect(titles).to be(:include?, "video.mp4")
			expect(titles).not.to be(:include?, "notes.txt")
		end
	end

	with "#next_index" do
		let(:paths) {[make_file("a.mp3"), make_file("b.mp3"), make_file("c.mp3")]}
		let(:playlist) {subject.from_paths(paths, cache_dir: tmpdir)}

		it "returns the following index" do
			expect(playlist.next_index(0)).to be == 1
			expect(playlist.next_index(1)).to be == 2
		end

		it "returns nil at the last item" do
			expect(playlist.next_index(2)).to be == nil
		end
	end

	with "cache persistence" do
		let(:paths) {[make_file("a.mp3"), make_file("b.mp4")]}

		it "saves and reloads last_index and durations" do
			playlist = subject.from_paths(paths, cache_dir: tmpdir)
			playlist.files[0].duration = 120.0
			playlist.files[1].duration = 300.5
			playlist.last_index = 1
			playlist.save_cache!

			cache_path = File.join(tmpdir, ".media.json")
			expect(File.exist?(cache_path)).to be == true

			data = JSON.parse(File.read(cache_path))
			expect(data["last_index"]).to be == 1

			# Reload from cache
			playlist2 = subject.from_paths(paths, cache_dir: tmpdir)
			expect(playlist2.last_index).to be == 1
			expect(playlist2[0].duration).to be == 120.0
			expect(playlist2[1].duration).to be == 300.5
		end
	end
end
