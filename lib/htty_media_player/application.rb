# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "protocol/http/middleware"
require "protocol/http/body/file"
require "xrb/template"

require_relative "version"

# @namespace
module HTTYMediaPlayer
	AUDIO_TYPES = {
		".mp3"  => "audio/mpeg",
		".wav"  => "audio/wav",
		".ogg"  => "audio/ogg",
		".flac" => "audio/flac",
		".aac"  => "audio/aac",
		".m4a"  => "audio/mp4",
		".opus" => "audio/ogg; codecs=opus",
	}.freeze

	VIDEO_TYPES = {
		".mp4"  => "video/mp4",
		".webm" => "video/webm",
		".ogv"  => "video/ogg",
		".mov"  => "video/quicktime",
		".avi"  => "video/x-msvideo",
		".mkv"  => "video/x-matroska",
	}.freeze

	MEDIA_TYPES = AUDIO_TYPES.merge(VIDEO_TYPES).freeze

	# Detect the MIME type from a file extension.
	# @parameter path [String] The file path.
	# @returns [String | Nil] The MIME type, or nil if unknown.
	def self.media_type(path)
		ext = File.extname(path).downcase
		MEDIA_TYPES[ext]
	end

	# Whether the given path is an audio file.
	# @parameter path [String] The file path.
	# @returns [Boolean]
	def self.audio?(path)
		ext = File.extname(path).downcase
		AUDIO_TYPES.key?(ext)
	end

	# The main application middleware for the HTTY media player.
	#
	# Serves an HTML5 player at `/` and the media file at `/media`.
	class Application < Protocol::HTTP::Middleware
		TEMPLATE = XRB::Template.load_file(File.expand_path("player.xrb", __dir__))

		class << self
			attr_accessor :media_path
		end

		# Initialize middleware with either an explicit media path or delegate-first form.
		# This supports both direct usage and Lively's middleware builder.
		# @parameter path_or_delegate [String | Protocol::HTTP::Middleware] Media path or downstream delegate.
		# @parameter delegate [Protocol::HTTP::Middleware]
		def initialize(path_or_delegate = nil, delegate = Protocol::HTTP::Middleware::HelloWorld)
			if path_or_delegate.is_a?(String)
				path = path_or_delegate
			else
				delegate = path_or_delegate if path_or_delegate
				path = self.class.media_path
			end

			super(delegate)

			unless path
				raise ArgumentError, "No media file specified. Set HTTYMediaPlayer::Application.media_path or pass a path to .new"
			end

			@path = File.expand_path(path)
			@type = HTTYMediaPlayer.media_type(@path) or raise ArgumentError, "Unsupported media type: #{File.extname(@path)}"
			@audio = HTTYMediaPlayer.audio?(@path)
			@title = File.basename(@path)
		end

		# @attribute [String] Absolute path to the media file.
		attr :path

		# @attribute [String] MIME type of the media file.
		attr :type

		# @attribute [String] Display title (filename).
		attr :title

		# Whether the media file is audio-only.
		# @returns [Boolean]
		def audio?
			@audio
		end

		# Handle an incoming HTTP request.
		# @parameter request [Protocol::HTTP::Request]
		# @returns [Protocol::HTTP::Response]
		def call(request)
			unless request && request.respond_to?(:path)
				return Protocol::HTTP::Response[400, [["content-type", "text/plain; charset=utf-8"]], ["Bad Request\n"]]
			end

			response = case request.path
			when "/media"
				serve_media(request)
			else
				serve_player(request)
			end

			response
		rescue => error
			internal_error_response(error)
		end

		private

		def internal_error_response(error)
			Protocol::HTTP::Response[500, [["content-type", "text/plain; charset=utf-8"]], [error.message]]
		end

		def serve_player(request)
			html = TEMPLATE.to_string(self)
			headers = [["content-type", "text/html; charset=utf-8"]]
			body = request_method(request) == "HEAD" ? [] : [html]

			Protocol::HTTP::Response[200, headers, body]
		end

		def serve_media(request)
			unless File.exist?(@path)
				return Protocol::HTTP::Response[404, [], ["File not found"]]
			end

			total_size = File.size(@path)
			range_header = header_value(request, "range")

			if range_header
				range = parse_range(range_header, total_size)

				unless range
					return Protocol::HTTP::Response[416, [["content-range", "bytes */#{total_size}"], ["accept-ranges", "bytes"]], []]
				end

				# range_size = range.end - range.begin + 1
				body = request_method(request) == "HEAD" ? [] : Protocol::HTTP::Body::File.open(@path, range)
				headers = [
					["content-type", @type],
					["content-range", "bytes #{range.begin}-#{range.end}/#{total_size}"],
					# ["content-length", range_size.to_s],
					["accept-ranges", "bytes"],
				]

				return Protocol::HTTP::Response[206, headers, body]
			end

			headers = [
				["content-type", @type],
				["content-length", total_size.to_s],
				["accept-ranges", "bytes"],
			]

			body = request_method(request) == "HEAD" ? [] : Protocol::HTTP::Body::File.open(@path)

			Protocol::HTTP::Response[200, headers, body]
		end

		def request_method(request)
			request.respond_to?(:method) ? request.method.to_s : "GET"
		end

		def header_value(request, name)
			headers = request.headers
			return nil unless headers

			if headers.respond_to?(:[])
				value = headers[name] || headers[name.downcase] || headers[name.to_sym]
				return value.first if value.is_a?(Array)
				return value
			end

			if headers.respond_to?(:to_h)
				value = headers.to_h[name] || headers.to_h[name.downcase] || headers.to_h[name.to_sym]
				return value.first if value.is_a?(Array)
				return value
			end

			nil
		end

		def parse_range(range_header, total_size)
			raw_header = range_header.to_s.strip
			return nil unless raw_header.start_with?("bytes=")

			# Chromium/Electron can send multi-range values (e.g. "bytes=0-0,-1").
			# We serve the first range to keep playback robust.
			first_range = raw_header.delete_prefix("bytes=").split(",", 2).first&.strip
			match = /\A(\d*)-(\d*)\z/.match(first_range.to_s)
			return nil unless match

			start_text = match[1]
			finish_text = match[2]

			if start_text.empty?
				suffix_length = finish_text.to_i
				return nil if suffix_length <= 0

				start_index = [total_size - suffix_length, 0].max
				return (start_index..(total_size - 1))
			end

			start_index = start_text.to_i
			return nil if start_index >= total_size

			finish_index = finish_text.empty? ? (total_size - 1) : finish_text.to_i
			finish_index = total_size - 1 if finish_index >= total_size
			return nil if finish_index < start_index

			(start_index..finish_index)
		end
	end
end
