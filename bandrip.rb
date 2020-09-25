#!/usr/bin/env ruby

# bandrip.rb v0.2.0
# 2020-09-25

require 'uri'
require 'net/http'
require 'json'
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'nokogiri'
  gem 'http-cookie'
end

class Bandrip
  VERSION = '0.2.0'
  USER_AGENT = 'Mozilla/5.0 (Android; Mobile; rv:40.0) Gecko/40.0 Firefox/40.0'
  WAIT_TIME = 10
  
  CHARACTER_FILTER = /[\x00-\x1F\/\\:\*\?\"<>\|]/u
  UNICODE_WHITESPACE = /[[:space:]]+/u
  
  class << self
    def usage
      puts <<~USAGE
        Usage: ruby bandrip.rb URL
        
        Single track URL: https://artist-name.bandcamp.com/track/track-name
        Full album URL:   https://artist-name.bandcamp.com/album/album-name
        
      USAGE
    end
  
    def from_url(url)
      uri = URI(url)
      raise ArgumentError, "not a valid Bandcamp URL" unless uri.host.end_with?('.bandcamp.com')
      artist = uri.host[0..-14]
      if uri.path.start_with?('/track/')
        track = uri.path[7..-1]
      elsif uri.path.start_with?('/album/')
        album = uri.path[7..-1]
      elsif ['/', '/music', ''].include?(uri.path)
        # browse releases
      else
        raise ArgumentError, "not a valid Bandcamp URL"
      end
      new(artist, track: track, album: album)
    end
  end
  
  def initialize(artist, track: nil, album: nil)
    @artist = artist
    if artist && track
      download_track(artist, track)
    elsif artist && album
      download_album(artist, album)
    elsif artist
      browse_artist(artist)
    else
      raise ArgumentError, 'Insufficient arguments, artist is required'
    end
  end
  
  private

  def cookie_jar
    @cookie_jar ||= HTTP::CookieJar.new
  end
  
  def download_track(artist, track, number: nil, overwrite: false)
    url = "https://#{artist}.bandcamp.com/track/#{track}"
    puts "Getting track info from #{url}"
    document = Nokogiri::HTML(http_get(url))
    artist_name = parse_artist_name(document)
    track_name = parse_track_name(document)
    filename = sanitize_filename("#{artist_name} - #{track_name}.mp3")
    number = number.to_i
    filename = "#{'%02d' % number} #{filename}" if number > 0
    track_data = JSON.parse(document.at_css('script[data-tralbum]')['data-tralbum'])
    mp3_url = track_data['trackinfo'].first.dig('file', 'mp3-128')
    raise 'No MP3 link found' unless mp3_url && mp3_url.start_with?('https://')
    print "  #{filename} ... "
    if File.exist?(filename)
      puts "already exists, skipping!"
    elsif data = http_get(mp3_url, url)
      File.binwrite(filename, data)
      puts "done (#{'%0.2f' % (data.size / 0x100000.to_f)} MB)"
    else
      puts "error!"
    end
   end
   
   def download_album(artist, album)
     url = "https://#{artist}.bandcamp.com/album/#{album}"
     puts "Getting album info from #{url}"
     document = Nokogiri::HTML(http_get(url))
     document.css("#track_table tr[itemtype='http://www.schema.org/MusicRecording']").each do |tr|
       number = tr['rel'].to_s.sub('tracknum=', '').to_i
       if link = tr.at_css(".title a[itemprop='url']")['href'] and link.start_with?('/track/')
         download_track(artist, link[7..-1], number: number)
       end
     end
   end
   
   def sanitize_filename(filename)
     filename.gsub(CHARACTER_FILTER, '').gsub(UNICODE_WHITESPACE, ' ')[0..250]
   end
   
   def parse_artist_name(document)
     document.at_css("#name-section .albumTitle span[itemprop='byArtist']").text.strip
   end
   
   def parse_track_name(document)
     document.at_css('#name-section .trackTitle').text.strip
   end

   def sleep_with_info(seconds)
     print " "
     seconds.times do
       print "."
       sleep 1
     end
     print " "
   end
   
   def http_get(url, referrer = nil)
     sleep_with_info WAIT_TIME
     uri = URI.parse(url)
     http = Net::HTTP.new(uri.host, uri.port)
     http.use_ssl = true
     http.set_debug_output $stdout if ENV['DEBUG']
     request = Net::HTTP::Get.new(uri.request_uri)
     request['User-Agent'] = USER_AGENT
     request['Accept'] = '*/*'
     request['Referer'] = referrer if referrer
     request['Cookie'] = cookies_for_uri(uri)
     response = http.request(request)
     return false unless response.is_a?(Net::HTTPSuccess)
     cookie_jar.parse(response['Set-Cookie'], uri) if response['Set-Cookie']
     response.body
   end
   
   def cookies_for_uri(uri)
     HTTP::Cookie.cookie_value(cookie_jar.cookies(uri))
   end
end

if $PROGRAM_NAME == __FILE__
  begin
    arg = ARGV[0]
    if arg.nil? || arg == '' || arg == '--help'
      Bandrip.usage
      exit(1)
    elsif arg == '--version'
      puts "bandrip.rb v#{Bandrip::VERSION}\n"
      exit(0)
    else
      Bandrip.from_url(ARGV[0])
    end
  rescue => e
    puts "Error: #{e.message}"
    puts "Check bandrip.rb --help for usage\n"
    exit(1)
  end
end
