# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module HTTY
	module Media
		module Player
			# File extensions that browsers cannot play natively and require real-time
			# transcoding via ffmpeg before they can be served.
			TRANSCODE_EXTENSIONS = %w[.mkv .avi .mov].freeze

			# A streaming response body that reads output chunks from a live ffmpeg process.
			# The process writes to its own stdout; we read from the other end of that pipe.
			class TranscodeBody
				CHUNK_SIZE = 65_536

				# @parameter io [IO] The readable pipe connected to ffmpeg's stdout.
				def initialize(io)
					@io = io
				end

				# Returns the next chunk of transcoded bytes, or nil at EOF.
				def read
					return nil if @io.closed?
					chunk = @io.read(CHUNK_SIZE)
					return nil if chunk.nil? || chunk.empty?
					chunk
				rescue IOError
					nil
				end

				# Closes the pipe.  Sending EOF to the read end causes ffmpeg to receive
				# SIGPIPE on its next write and exit cleanly.
				def close
					@io.close unless @io.closed?
					Process.waitpid(@io.pid, Process::WNOHANG)
				rescue SystemCallError
					# Child already reaped or never started.
				end

				# Length is unknown for a streaming transcode.
				def length
					nil
				end
			end

			# Transcodes non-native media files to browser-compatible formats in real time
			# using ffmpeg.  The transcoded bytes stream directly from the ffmpeg child
			# process through the HTTP/2 response body — no temp file is created.
			#
			# Video is transcoded to fragmented MP4 (H.264 + AAC), which browsers can play
			# from a streaming source without needing a complete file or range support.
			# Audio is transcoded to Ogg Vorbis.
			module Transcoder
				# Whether this file requires transcoding for browser playback.
				# @parameter file [File]
				# @returns [Boolean]
				def self.needed?(file)
					TRANSCODE_EXTENSIONS.include?(::File.extname(file.path).downcase)
				end

				# Start an ffmpeg transcoding process for the given file.
				# @parameter file [File]
				# @returns [[TranscodeBody, String]] body and content-type pair
				def self.start(file)
					if file.audio?
						start_audio(file)
					else
						start_video(file)
					end
				end

				def self.start_video(file)
					# Fragmented MP4 can be streamed from a pipe; the browser does not need
					# the full moov atom upfront because frag_keyframe+empty_moov provides it
					# at the start of the stream.
					args = [
						"ffmpeg",
						"-loglevel", "quiet",
						"-i", file.path,
						"-c:v", "libx264", "-preset", "ultrafast", "-crf", "23",
						"-c:a", "aac", "-b:a", "128k",
						"-f", "mp4", "-movflags", "frag_keyframe+empty_moov",
						"pipe:1",
					]
					io = IO.popen(args, "rb")
					[TranscodeBody.new(io), "video/mp4"]
				end
				private_class_method :start_video

				def self.start_audio(file)
					args = [
						"ffmpeg",
						"-loglevel", "quiet",
						"-i", file.path,
						"-c:a", "libvorbis",
						"-f", "ogg",
						"pipe:1",
					]
					io = IO.popen(args, "rb")
					[TranscodeBody.new(io), "audio/ogg"]
				end
				private_class_method :start_audio
			end
		end
	end
end
