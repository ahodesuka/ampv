module Ampv
  class InputBindings

    KeyBinding = Struct.new(:keyval, :mods, :cmd)

    INPUT_CONFIG = File.exists?("#{Dir.home}/.mpv/input.conf") ?
                      "#{Dir.home}/.mpv/input.conf" : File.expand_path("../../../input.conf", __FILE__)
    # mpv key names to gdk keyvals
    KEY_VALS = {
      "SPACE" 	 		=> Gdk::Keyval::GDK_space,
      "SHARP" 	 		=> Gdk::Keyval::GDK_numbersign,
      "ENTER" 	 		=> Gdk::Keyval::GDK_Return,
      "TAB"   	 		=> Gdk::Keyval::GDK_Tab,
      "BS"    	 		=> Gdk::Keyval::GDK_BackSpace,
      "DEL"   	 		=> Gdk::Keyval::GDK_Delete,
      "INS"   	 		=> Gdk::Keyval::GDK_Insert,
      "HOME"  	 		=> Gdk::Keyval::GDK_Home,
      "END"   	 		=> Gdk::Keyval::GDK_End,
      "PGUP"  	 		=> Gdk::Keyval::GDK_Page_Up,
      "PGDWN" 	 		=> Gdk::Keyval::GDK_Page_Down,
      "ESC"   	 		=> Gdk::Keyval::GDK_Escape,
      "PRINT" 	 		=> Gdk::Keyval::GDK_Print,
      "RIGHT" 	 		=> Gdk::Keyval::GDK_Right,
      "LEFT"  	 		=> Gdk::Keyval::GDK_Left,
      "DOWN"  	 		=> Gdk::Keyval::GDK_Down,
      "UP"       		=> Gdk::Keyval::GDK_Up,
      "KP_DEL"   		=> Gdk::Keyval::GDK_KP_Delete,
      "KP_DEC"   		=> Gdk::Keyval::GDK_KP_Decimal,
      "KP_INS"   		=> Gdk::Keyval::GDK_KP_Insert,
      "KP_ENTER" 		=> Gdk::Keyval::GDK_KP_Enter,
      "MENU"     		=> Gdk::Keyval::GDK_MenuKB,
      "PLAY"     		=> Gdk::Keyval::GDK_AudioPlay,
      "PAUSE"    		=> Gdk::Keyval::GDK_AudioPause,
      "STOP"     		=> Gdk::Keyval::GDK_AudioStop,
      "PREV"     		=> Gdk::Keyval::GDK_AudioPrev,
      "NEXT"        => Gdk::Keyval::GDK_AudioNext,
      "VOLUME_UP"   => Gdk::Keyval::GDK_AudioRaiseVolume,
      "VOLUME_DOWN" => Gdk::Keyval::GDK_AudioLowerVolume,
      "MUTE"        => Gdk::Keyval::GDK_AudioMute,
      "HOMEPAGE"    => Gdk::Keyval::GDK_HomePage,
      "WWW"         => Gdk::Keyval::GDK_WWW,
      "MAIL"        => Gdk::Keyval::GDK_Mail,
      "FAVORITES"   => Gdk::Keyval::GDK_Favorites,
      "SEARCH"      => Gdk::Keyval::GDK_Search,
      "SLEEP"       => Gdk::Keyval::GDK_Sleep,
    }

    (0..12).each { |x|
      KEY_VALS["KP#{x}"] = Gdk::Keyval.from_name("KP_#{x}") if x <= 9
      KEY_VALS["F#{x}"]  = Gdk::Keyval.from_name("F#{x}")   if x != 0
    }

    @@key_bindings   = [ ]
    @@mouse_bindings = { }

    def self.load
      if File.exists?(INPUT_CONFIG)
        File.readlines(INPUT_CONFIG).each { |line|
          line.strip!
          if line.start_with?("MOUSE_BTN")
            # 4 = up, 5 = down, 6 = left, 7 = right
            button, cmd = line.match(/MOUSE_BTN(\d+)(?:_DBL)?\s+(.+)$/).captures
            next if cmd == "ignore"
            button = button.to_i + 1
            type   = (4..7).include?(button) ? Gdk::Event::SCROLL :
              line.include?("DBL") ? Gdk::Event::BUTTON2_PRESS : Gdk::Event::BUTTON_PRESS
            @@mouse_bindings[type] = [ ] if @@mouse_bindings[type].nil?
            @@mouse_bindings[type][button] = cmd
          elsif !line.empty? and !line.start_with?("#")
            key, cmd = line.match(/^([^\s]+)\s+(.+)$/).captures
            #next if cmd == "ignore"
            if key =~ /(shift|ctrl|alt|meta)\+/i
              key.gsub!(/(shift|ctrl|alt|meta)\+/i, '<\1>')
            end
            kb = KeyBinding.new(*Gtk::Accelerator.parse(key), cmd)
            if kb.keyval == 0
              key.gsub!(/<(shift|ctrl|alt|meta)>/i, "")
              unless kb.keyval = KEY_VALS[key.upcase]
                kb.keyval = key.ord
              end
            end
            @@key_bindings << kb
          end
        }
      end
    end

    def self.key
      @@key_bindings
    end

    def self.mouse
      @@mouse_bindings
    end
  end
end
