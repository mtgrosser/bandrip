# encoding: utf-8

require 'uri'
require 'net/http'
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'nokogiri'
  gem 'http-cookie'
end

class Bandrip
  USER_AGENT = 'Mozilla/5.0 (Android; Mobile; rv:40.0) Gecko/40.0 Firefox/40.0'
  MP3_REGEX = /\{\"mp3-128\"\:\"(\S+)\"\}/mi
  WAIT_TIME = 10
  
  CHARACTER_FILTER = /[\x00-\x1F\/\\:\*\?\"<>\|]/u
  UNICODE_WHITESPACE = /[[:space:]]+/u
  
  class << self
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
    raise 'No MP3 link found' unless mp3_url = MP3_REGEX.match(document.to_s).captures.first
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
   
   def http_get(url, referrer = nil)
     sleep WAIT_TIME
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

Bandrip.from_url(ARGV[0]) if $PROGRAM_NAME == __FILE__
