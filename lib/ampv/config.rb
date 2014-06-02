require "json"
require "ampv/input"

module Ampv
  class Config

    CONFIG_FILE  = "#{(ENV["XDG_CONFIG_HOME"] || "#{Dir.home}/.config")}/ampv.conf"
    MPV_CONFIG   = "#{Dir.home}/.mpv/config"
    DEFAULTS     = {
        :width                  => Gdk::Screen.default.width > 1280 ? 1280 : 853,
        :height                 => Gdk::Screen.default.width > 1280 ? 724  : 484,
        :x                      => nil,
        :y                      => nil,
        :progress_bar_visible   => true,
        :progress_bar_height    => 4,
        :bar_color              => Gdk::Color.parse("#8f5b5b"),
        :head_color             => Gdk::Color.parse("#c48181"),
        :playlist_width         => 360,
        :playlist_height        => 550,
        :playlist_x             => 0,
        :playlist_y             => 0,
        :playlist_visible       => true,
        :always_save_position   => false,
    }
    @@config = { }

    def self.load
      if File.exists?(CONFIG_FILE)
        begin
          @@config = JSON.parse(File.open(CONFIG_FILE, "r").read, :symbolize_names => true)

          [ :bar_color, :head_color ].each { |k|
            if @@config[k]
              begin
                val = @@config[k]
                @@config[k] = Gdk::Color.parse(val)
              rescue
                delete(k)
                warn("Invalid hexidecimal color: `#{val}' for #{k.to_s}")
              end
            end
          }
        rescue => e
          warn("Failed to parse config file.\n#{e.message}")
        end
      end
      InputBindings.load
    end

    def self.[](key)
      @@config.include?(key) ? @@config[key] : DEFAULTS[key]
    end

    def self.[]=(key, value)
      @@config[key] = value
    end

    def self.delete(key)
      @@config.delete(key)
    end

    def self.save
      File.write(CONFIG_FILE, JSON.pretty_generate(@@config), { :mode => "w" })
    end
  end
end
