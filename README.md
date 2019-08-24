# bandrip
Bandcamp downloader written in Ruby

## Usage

### Command Line Interface

```sh
# download single track
$ ruby bandrip.rb https://artist-name.bandcamp.com/track/track-name

# download full album
$ ruby bandrip.rb https://artist-name.bandcamp.com/album/album-name
```

### Ruby Interface

```ruby
# download single track
Bandrip.new('artist-name-from-url', track: 'track-name-from-url')

# download full album
Bandrip.new('artist-name-from-url', album: 'album-name-from-url')
```

## TODO

Browse discography
