# ampv

A minimal GTK2 frontend for [mpv](https://github.com/mpv-player/mpv) written in ruby.

## Installation

    $ gem install ampv

Ensure `~/.gem/ruby/**/bin` is in your `$PATH`.

## Usage

    $ ampv

or

    $ ampv "videofile"

ampv input configuration is loaded from `~/.mpv/input.conf` - and ignores all default mpv bindings.<br>
An example input.conf is included in this repository.  mpv will retain settings in `~/.mpv/config` except for the `autofit*` and `geometry` settings

