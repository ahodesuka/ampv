# ampv

A minimal GTK2 frontend for [mpv](https://github.com/mpv-player/mpv) written in ruby.

[![Gem Version](https://badge.fury.io/rb/ampv.png)](https://rubygems.org/gems/ampv)

## Installation

    $ gem install ampv

Ensure you have `$(ruby -rubygems -e "puts Gem.user_dir")/bin` added to your `$PATH`.

## Screenshots
![Player Window](https://goput.it/ekdd.png)
![Playlist Window](https://goput.it/9las.png)

## Usage

    $ ampv

or

    $ ampv "videofile"

ampv input configuration is loaded from `~/.mpv/input.conf` - and ignores all default mpv bindings.<br>
An example input.conf is included in this repository.  This example config is used if there is none in the previously stated location.
mpv will retain settings in `~/.mpv/config` except for the `autofit*` and `geometry` settings.

