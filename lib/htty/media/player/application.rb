# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "protocol/http/middleware"
require "protocol/http/body/file"
require "xrb/template"
require "json"

require_relative "playlist"

module HTTY
	module Media
		module Player
			# The main Rack-style middleware for the HTTY media player.
			#
			# Routes:
			#   GET  /                  playlist view
			#   GET  /player?index=N    player view for item N
			#   GET  /media?index=N     range-aware media bytes for item N
			#   POST /last?index=N      persist last-played index, returns 204
			class Application < Protocol::HTTP::Middleware
				PLAYLIST_TEMPLATE = XRB::Template.load_file(
					::File.expand_path("views/playlist.xrb", __dir__)
				)
				PLAYER_TEMPLATE = XRB::Template.load_file(
					::File.expand_path("views/player.xrb", __dir__)
				)

				# @parameter playlist [Playlist] The playlist to serve.
				# @parameter delegate [Protocol::HTTP::Middleware] Downstream middleware.
				def initialize(playlist, delegate = Protocol::HTTP::Middleware::HelloWorld)
					super(delegate)
					@playlist = playlist
				end

				# @attribute [Playlist]
				attr_reader :playlist

				# Handle an incoming HTTP request.
				def call(request)
					path  = request.path.split("?", 2).first
					query = parse_query(request.path)
					index = query["index"]&.to_i

					case [request_method(request), path]
					when ["GET",  "/"]
						serve_playlist
					when ["GET",  "/player"]
						serve_player(index || @playlist.last_index)
					when ["GET",  "/media"]
						serve_media(request, index || @playlist.last_index)
					when ["POST", "/last"]
						update_last(index || 0)
					else
						Protocol::HTTP::Response[404, [["content-type", "text/plain"]], ["Not Found"]]
					end
				rescue => error
					Protocol::HTTP::Response[500, [["content-type", "text/plain"]], [error.message]]
				end

				private

				def serve_playlist
					html = PLAYLIST_TEMPLATE.to_string(self)
					Protocol::HTTP::Response[200, [["content-type", "text/html; charset=utf-8"]], [html]]
				end

				def serve_player(index)
					file = @playlist[index]
					unless file
						return Protocol::HTTP::Response[404, [["content-type", "text/plain"]], ["No media at index #{index}"]]
					end

					context = PlayerContext.new(@playlist, index, file)
					html    = PLAYER_TEMPLATE.to_string(context)
					Protocol::HTTP::Response[200, [["content-type", "text/html; charset=utf-8"]], [html]]
				end

				def serve_media(request, index)
					file = @playlist[index]
					unless file
						return Protocol::HTTP::Response[404, [["content-type", "text/plain"]], ["No media at index #{index}"]]
					end

					unless file.exist?
						return Protocol::HTTP::Response[404, [["content-type", "text/plain"]], ["File not found: #{file.path}"]]
					end
					if Transcoder.needed?(file)
						body, content_type = Transcoder.start(file)
						return Protocol::HTTP::Response[200, [["content-type", content_type]], body]
					end

					total_size   = ::File.size(file.path)
					range_header = header_value(request, "range")

					if range_header
						range = parse_range(range_header, total_size)
						unless range
							return Protocol::HTTP::Response[416,
								[["content-range", "bytes */#{total_size}"], ["accept-ranges", "bytes"]],
								[]]
						end

						body = head?(request) ? [] : Protocol::HTTP::Body::File.open(file.path, range)
						return Protocol::HTTP::Response[206,
							[["content-type", file.type],
							 ["content-range", "bytes #{range.begin}-#{range.end}/#{total_size}"],
							 ["accept-ranges", "bytes"]],
							body]
					end

					body = head?(request) ? [] : Protocol::HTTP::Body::File.open(file.path)
					Protocol::HTTP::Response[200,
						[["content-type", file.type],
						 ["content-length", total_size.to_s],
						 ["accept-ranges", "bytes"]],
						body]
				end

				def update_last(index)
					@playlist.last_index = index.clamp(0, [@playlist.size - 1, 0].max)
					@playlist.save_cache!
					Protocol::HTTP::Response[204, [], []]
				end

				# Helpers

				def request_method(request)
					(request.respond_to?(:method) ? request.method : "GET").to_s.upcase
				end

				def head?(request)
					request_method(request) == "HEAD"
				end

				def header_value(request, name)
					headers = request.headers
					return nil unless headers

					value = if headers.respond_to?(:[])
						headers[name] || headers[name.downcase]
					elsif headers.respond_to?(:to_h)
						h = headers.to_h
						h[name] || h[name.downcase]
					end

					value.is_a?(Array) ? value.first : value
				end

				def parse_query(path)
					_, qs = path.split("?", 2)
					return {} unless qs

					qs.split("&").each_with_object({}) do |pair, h|
						k, v = pair.split("=", 2)
						h[k] = v
					end
				end

				def parse_range(range_header, total_size)
					raw = range_header.to_s.strip
					return nil unless raw.start_with?("bytes=")

					first = raw.delete_prefix("bytes=").split(",", 2).first&.strip
					match = /\A(\d*)-(\d*)\z/.match(first.to_s)
					return nil unless match

					s, e = match[1], match[2]

					if s.empty?
						suffix = e.to_i
						return nil if suffix <= 0
						start = [total_size - suffix, 0].max
						return start..(total_size - 1)
					end

					start  = s.to_i
					return nil if start >= total_size
					finish = e.empty? ? total_size - 1 : [e.to_i, total_size - 1].min
					return nil if finish < start
					start..finish
				end
			end

			# Thin view-model passed to the player template.
			PlayerContext = Struct.new(:playlist, :index, :file)
		end
	end
end
