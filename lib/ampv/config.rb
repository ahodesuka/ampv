module Ampv
  class Config

    CONFIG_FILE  = "#{(ENV["XDG_CONFIG_HOME"] || "#{Dir.home}/.config")}/ampv.conf"
    INPUT_CONFIG = File.exists?("#{Dir.home}/.mpv/input.conf") ?
                      "#{Dir.home}/.mpv/input.conf" : File.expand_path("../../../input.conf", __FILE__)
    MPV_CONFIG   = "#{Dir.home}/.mpv/config"
    KEY_NAMES    = {
      "esc"         => "Escape",
      "space"       => "space",
      "right"       => "Right",
      "left"        => "Left",
      "up"          => "Up",
      "down"        => "Down",
      "pgup"        => "Page_Up",
      "pgdwn"       => "Page_Down",
      "home"        => "Home",
      "end"         => "End",
      "ins"         => "Insert",
      "del"         => "Delete",
    }
    DEFAULTS     = {
        "width"                  => Gdk::Screen.default.width > 1280 ? 1280 : 853,
        "height"                 => Gdk::Screen.default.width > 1280 ? 726  : 486,
        "x"                      => -1,
        "y"                      => -1,
        "fullscreen_progressbar" => false,
        "progress_bar_visible"   => true,
        "progress_bar_height"    => 6,
        "bar_color"              => Gdk::Color.parse("#8f5b5b"),
        "head_color"             => Gdk::Color.parse("#c48181"),
        "playlist_width"         => 360,
        "playlist_height"        => 550,
        "playlist_x"             => 0,
        "playlist_y"             => 0,
        "playlist_visible"       => true,
        "always_save_position"   => false,
        "resume_playback"        => false,
        "scrobbler"              => "",
        "playlist_selected"      => "",
        "playlist"               => [ ],
        "key_bindings"           => [ ],
        "mouse_bindings"         => [ ]
    }
    @@config     = { }

    def self.load
      if File.exists?(CONFIG_FILE)
        File.readlines(CONFIG_FILE).each { |line|
          key, _, val = line.partition("=")
          key.strip!
          val.strip!
          next unless DEFAULTS.has_key?(key) and key[0] != "#"

          if DEFAULTS[key].is_a?(Integer)
            val = val.to_i
          elsif DEFAULTS[key].is_a?(TrueClass) or  DEFAULTS[key].is_a?(FalseClass)
            val = val == "true"
          elsif DEFAULTS[key].is_a?(Gdk::Color)
            begin
              val = Gdk::Color.parse(val)
            rescue
              puts("Invalid hexidecimal color for setting `#{key}': `#{val}'")
              next
            end
          elsif key == "playlist"
            begin
              val = JSON.parse(val)
            rescue
              puts("Failed to parse playlist JSON array.")
              next
            end
          end

          @@config[key] = val
        }
      end

      # load input config
      self["mouse_bindings"] = [ ]
      self["key_bindings"]   = [ ]
      if File.exists?(INPUT_CONFIG)
        File.readlines(INPUT_CONFIG).each { |line|
          line.strip!
          if line.start_with?("MOUSE_BTN")
            # 4 = up, 5 = down, 6 = left, 7 = right
            button, cmd = line.match(/MOUSE_BTN(\d+)(?:_DBL)?\s+(.+)$/).captures
            button = button.to_i + 1
            type   = (4..7).include?(button) ? Gdk::Event::SCROLL :
              line.include?("DBL") ? Gdk::Event::BUTTON2_PRESS : Gdk::Event::BUTTON_PRESS
            self["mouse_bindings"][type] = [ ] if self["mouse_bindings"][type].nil?
            self["mouse_bindings"][type][button] = cmd
          elsif !line.empty?
            key, cmd = line.match(/^([^\s]+)\s+(.+)$/).captures
            if name = KEY_NAMES[key.downcase]
              keyval = Gdk::Keyval.from_name(name)
            else
              keyval = Gdk::Keyval.from_name(key)
            end

            self["key_bindings"][keyval] = cmd if keyval > 0
          end
        }
      end
    end

    def self.[](key)
      @@config[key].nil? ? DEFAULTS[key] : @@config[key]
    end

    def self.[]=(key, value)
      @@config[key] = value
    end

    def self.save
      File.open(CONFIG_FILE, "w") { |file|
        @@config.each { |k, v| file.puts("#{k}=#{v}") unless [ "key_bindings", "mouse_bindings" ].include?(k) }
      }
    end
  end
end

