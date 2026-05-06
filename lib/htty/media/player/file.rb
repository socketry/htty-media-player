# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module HTTY
	module Media
		module Player
			AUDIO_EXTENSIONS = {
				".mp3"  => "audio/mpeg",
				".wav"  => "audio/wav",
				".ogg"  => "audio/ogg",
				".flac" => "audio/flac",
				".aac"  => "audio/aac",
				".m4a"  => "audio/mp4",
				".opus" => "audio/ogg; codecs=opus",
			}.freeze

			VIDEO_EXTENSIONS = {
				".mp4"  => "video/mp4",
				".webm" => "video/webm",
				".ogv"  => "video/ogg",
				".mov"  => "video/quicktime",
				".avi"  => "video/x-msvideo",
				".mkv"  => "video/x-matroska",
			}.freeze

			MEDIA_EXTENSIONS = AUDIO_EXTENSIONS.merge(VIDEO_EXTENSIONS).freeze

			# A single media item in the playlist.
			class File
				# @parameter path [String] Absolute path to the media file.
				# @parameter duration [Float | Nil] Duration in seconds, or nil if unknown.
				# @parameter tag_title [String | Nil] Embedded metadata title tag.
				# @parameter artist [String | Nil] Embedded artist tag.
				# @parameter album [String | Nil] Embedded album tag.
				def initialize(path, duration: nil, tag_title: nil, artist: nil, album: nil)
					@path            = ::File.expand_path(path)
					@duration        = duration
					@tag_title       = tag_title
					@artist          = artist
					@album           = album
					@metadata_loaded = false
				end

				# @attribute [String] Absolute path to the media file.
				attr_accessor :path

				# @attribute [Float | Nil] Duration in seconds.
				attr_accessor :duration

				# @attribute [String | Nil] Embedded title tag (may be nil).
				attr_accessor :tag_title

				# @attribute [String | Nil] Embedded artist tag.
				attr_accessor :artist

				# @attribute [String | Nil] Embedded album tag.
				attr_accessor :album

				# @attribute [Boolean] Whether metadata has been probed/loaded for this file.
				attr_accessor :metadata_loaded

				# The display title: embedded tag if present, otherwise the filename.
				# @returns [String]
				def title
					@tag_title || ::File.basename(@path)
				end

				# The filename, regardless of any embedded title tag.
				# @returns [String]
				def filename
					::File.basename(@path)
				end

				# The MIME content-type for this file.
				# @returns [String]
				def type
					ext = ::File.extname(@path).downcase
					MEDIA_EXTENSIONS[ext]
				end

				# Whether this file is an audio-only item.
				# @returns [Boolean]
				def audio?
					ext = ::File.extname(@path).downcase
					AUDIO_EXTENSIONS.key?(ext)
				end

				# Whether this file is a video item.
				# @returns [Boolean]
				def video?
					!audio?
				end

				# Human-readable duration label, e.g. "3:42", or nil.
				# @returns [String | Nil]
				def duration_label
					return nil unless @duration

					total = @duration.to_i
					hours   = total / 3600
					minutes = (total % 3600) / 60
					seconds = total % 60

					if hours > 0
						format("%d:%02d:%02d", hours, minutes, seconds)
					else
						format("%d:%02d", minutes, seconds)
					end
				end

				# Whether this media file exists on disk.
				# @returns [Boolean]
				def exist?
					::File.exist?(@path)
				end

				# Serialise to a plain Hash suitable for JSON.
				# @returns [Hash]
				def to_h
					{duration: @duration, tag_title: @tag_title, artist: @artist, album: @album}
				end
			end
		end
	end
end
