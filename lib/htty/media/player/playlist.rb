# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "open3"
require "shellwords"

require_relative "file"

module HTTY
	module Media
		module Player
			# An ordered collection of media files with ffprobe-backed metadata and a
			# persistent JSON cache.
			class Playlist
				CACHE_NAME = ".media.json"

				# Build a playlist by globbing a directory for all supported extensions.
				# @parameter directory [String] The directory to scan.
				# @returns [Playlist]
				def self.from_directory(directory)
					directory = ::File.expand_path(directory)
					pattern   = ::File.join(directory, "**", "*{#{MEDIA_EXTENSIONS.keys.join(",")}}")
					paths     = Dir.glob(pattern, ::File::FNM_CASEFOLD).sort
					new(paths, cache_dir: directory)
				end

				# Build a playlist from an explicit list of file paths.
				# @parameter paths [Array(String)] Ordered list of media file paths.
				# @parameter cache_dir [String] Directory in which to store `.media.json`.
				# @returns [Playlist]
				def self.from_paths(paths, cache_dir: nil)
					cache_dir ||= ::File.dirname(::File.expand_path(paths.first.to_s))
					new(paths, cache_dir: cache_dir)
				end

				# @parameter paths [Array(String)] Ordered list of media file paths.
				# @parameter cache_dir [String] Directory for the cache file.
				def initialize(paths, cache_dir:)
					@cache_path  = ::File.join(::File.expand_path(cache_dir), CACHE_NAME)
					@files       = paths.map { |p| File.new(p) }
					@last_index  = 0

					load_cache!
				end

				# @attribute [Array(File)] All items in the playlist.
				attr_reader :files

				# @attribute [Integer] Index of the last-played item.
				attr_accessor :last_index

				# @attribute [String] Path to the `.media.json` cache file.
				attr_reader :cache_path

				# Return the file at the given index, or nil.
				# @parameter index [Integer]
				# @returns [File | Nil]
				def [](index)
					@files[index]
				end

				# Total number of items.
				# @returns [Integer]
				def size
					@files.size
				end

				# Whether there is an item after the given index.
				# @parameter index [Integer]
				# @returns [Boolean]
				def next?(index)
					index + 1 < @files.size
				end

				# The next index after the given one, or nil if at the end.
				# @parameter index [Integer]
				# @returns [Integer | Nil]
				def next_index(index)
					next_i = index + 1
					next_i < @files.size ? next_i : nil
				end

				# Probe any items that are missing duration data, then save the cache.
				def load_metadata!
					changed = false

					@files.each do |file|
						next if file.duration

						duration = probe_duration(file.path)
						if duration
							file.duration = duration
							changed = true
						end
					end

					save_cache! if changed
				end

				# Persist the current state (durations + last_index) to `.media.json`.
				def save_cache!
					data = {
						last_index: @last_index,
						files: {}
					}

					@files.each do |file|
						data[:files][file.path] = file.to_h
					end

					::File.write(@cache_path, JSON.pretty_generate(data))
				rescue => error
					warn "htty-media-player: could not save cache #{@cache_path}: #{error.message}"
				end

				private

				def load_cache!
					return unless ::File.exist?(@cache_path)

					data = JSON.parse(::File.read(@cache_path), symbolize_names: true)

					@last_index = data[:last_index].to_i.clamp(0, [@files.size - 1, 0].max)

					if (file_cache = data[:files])
						@files.each do |file|
							entry = file_cache[file.path.to_sym] || file_cache[file.path]
							next unless entry

							if (d = entry[:duration] || entry["duration"])
								file.duration = d.to_f
							end
						end
					end
				rescue => error
					warn "htty-media-player: could not load cache #{@cache_path}: #{error.message}"
				end

				def probe_duration(path)
					return nil unless system("which ffprobe > /dev/null 2>&1")

					stdout, _stderr, status = Open3.capture3(
						"ffprobe", "-v", "quiet",
						"-print_format", "json",
						"-show_format",
						path
					)

					return nil unless status.success?

					data = JSON.parse(stdout)
					data.dig("format", "duration")&.to_f
				rescue
					nil
				end
			end
		end
	end
end
