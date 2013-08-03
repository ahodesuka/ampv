# Ampv

A minimal GTK frontend for mpv written in ruby.

## Installation

    $ git clone https://github.com/ahodesuka/ampv.git
    $ cd ampv
    $ bundle install

You can then move the ampv executable to a directory included in your `$PATH`

## Usage

    $ ampv

or

    $ ampv "videofile"

ampv input configuration is loaded from `~/.mpv/input.conf`, and ignores all default mpv bindings.
An example input.conf is included in this repository.

