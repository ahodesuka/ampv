
require "gtk2"
require "ampv/mpvwidget"
require "ampv/playlist"
require "ampv/progressbarwidget"
require "ampv/version"
require "uri"

module Ampv
  class MainWindow < Gtk::Window

    MAIN_CONF  = "#{ENV["HOME"]}/.config/ampv.conf"
    INPUT_CONF = "#{ENV["HOME"]}/.mpv/input.conf"
    VIDEO_EXTS = [ ".avi", ".mkv", ".mp4", ".mpeg", ".mpg", ".ogm", ".ogv" ]
    KEY_NAMES  = {
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
    WHEEL_BUTTONS = {
      Gdk::EventScroll::UP    => 4,
      Gdk::EventScroll::DOWN  => 5,
      Gdk::EventScroll::LEFT  => 6,
      Gdk::EventScroll::RIGHT => 7
    }

    LEFT_PTR     = Gdk::Cursor.new(Gdk::Cursor::LEFT_PTR)
    BLANK_CURSOR = Gdk::Cursor.new(Gdk::Cursor::BLANK_CURSOR)

    def initialize
      load_config
      super
      set_title(PACKAGE)
      set_default_size(@config["width"], @config["height"])
      set_window_position(Gtk::Window::POS_CENTER)
      move(@config["x"], @config["y"]) unless @config["x"] == -1 and @config["y"] == -1

      Gtk::Drag.dest_set(self, Gtk::Drag::DEST_DEFAULT_ALL,
                         [ [ "text/uri-list", 0, 0 ] ],
                         Gdk::DragContext::ACTION_LINK)
      add_events(Gdk::Event::POINTER_MOTION_MASK)

      signal_connect("delete_event") { quit }
      signal_connect("scroll_event") { |w, e| handle_mouse_event(e) }
      signal_connect("button_press_event") { |w, e| handle_mouse_event(e) }
      signal_connect("key_press_event") { |w, e| handle_keyboard_event(e) }
      signal_connect("drag_data_received") { |w, dc, x, y, sd, type, time|
        handle_drop_event(sd.data, dc, time, false, true)
      }
      signal_connect("motion_notify_event") {
        window.set_cursor(LEFT_PTR)
        GLib::Source.remove(@cursor_timeout) if @cursor_timeout
        @cursor_timeout = GLib::Timeout.add(1000) {
          window.set_cursor(BLANK_CURSOR)
        } unless @mpv.is_paused
      }

      vbox = Gtk::VBox.new
      add(vbox)

      args = process_args
      print_version if args.include?("--version")
      load_bindings

      @mpv = MpvWidget.new(args, @config["scrobbler"])
      @mpv.signal_connect("file_changed") { |w, file|
        @playing = file
        @mpv.send("show_text ${media-title} 1500") if window.state.fullscreen?
        @playlist.set_selected(@playing)
        set_title(File.basename(@playing))
      }
      @mpv.signal_connect("length_changed") { |w, len|
        @length = len
        @playlist.update_length(@length)
      }
      @mpv.signal_connect("time_pos_changed") { |w, pos| @progress_bar.value = pos / @length.to_f }
      @mpv.signal_connect("stopped") {
        @progress_bar.value = 0
        next_file = @playlist.get_next
        @really_stop = next_file.nil? or @really_stop
        set_title(PACKAGE)
        if @really_stop and window.state.fullscreen?
          toggle_fullscreen
        elsif not @really_stop
          load_file(next_file, false)
        end
        @really_stop = false
      }

      vbox.pack_start(@mpv)

      @playlist = Playlist.new(@config["playlist_x"],
                               @config["playlist_y"],
                               @config["playlist_width"],
                               @config["playlist_height"],
                               @config["playlist_visible"])

      Gtk::Drag.dest_set(@playlist, Gtk::Drag::DEST_DEFAULT_ALL,
                         [ [ "text/uri-list", 0, 0 ] ],
                         Gdk::DragContext::ACTION_LINK)

      @playlist.signal_connect("open_file_chooser") { open_file_chooser }
      @playlist.signal_connect("drag_data_received") { |w, dc, x, y, sd, type, time|
        handle_drop_event(sd.data, dc, time, true, false)
      }
      @playlist.signal_connect("play_entry") { |w, file| load_file(file, false, false, false, true) }
      @playlist.signal_connect("playing_removed") { @mpv.send("stop"); @really_stop = true }

      @progress_bar = ProgressBarWidget.new(@config["bar_color"],
                                            @config["head_color"],
                                            @config["progress_bar_height"])
      @progress_bar.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      @progress_bar.signal_connect("button_press_event") { |w, e| handle_seek_event(e) }
      vbox.pack_start(@progress_bar, false)

      show_all
      @mpv.start

      argv = ARGV.join(" ")
      if not argv.empty?
        load_file(argv)
      elsif not @config["playlist"].empty?
        @config["playlist"].each { |x| load_file(x, true, true, false) }
        @playlist.set_selected(@config["playlist_selected"])
      end

      Gtk.main
    end

    def load_config
      @config = {
        "width"                  => Gdk::Screen.default.width > 1280 ? 1280 : 853,
        "height"                 => Gdk::Screen.default.width > 1280 ? 726  : 486,
        "x"                      => -1,
        "y"                      => -1,
        "fullscreen_progressbar" => false,
        "progress_bar_visible"   => true,
        "progress_bar_height"    => 6,
        "bar_color"              => "#8f5b5b",
        "head_color"             => "#c48181",
        "playlist_width"         => 360,
        "playlist_height"        => 550,
        "playlist_x"             => 0,
        "playlist_y"             => 0,
        "playlist_visible"       => true,
        "always_save_position"   => false,
        "scrobbler"              => "",
        "playlist_selected"      => "",
        "playlist"               => [ ],
      }

      if File.exists?(MAIN_CONF)
        File.readlines(MAIN_CONF).each { |line|
          key, _, val = line.partition("=")
          key = key.strip
          val = val.strip
          next unless @config.has_key?(key) and not key.start_with?("#")

          if @config[key].is_a?(Integer)
            val = val.to_i
          elsif @config[key].is_a?(TrueClass) or @config[key].is_a?(FalseClass)
            val = val == "true"
          elsif @config[key].is_a?(Array)
            val = val.split("|")
          elsif val.start_with?("#")
            begin
              c = Gdk::Color.parse(val)
            rescue
              puts("Invalid hexidecimal color for setting `#{key}': `#{val}")
              c = Gdk::Color.parse(@config[key])
            end
            val = c
          end

          @config[key] = val
        }
      end
    end

    def process_args
      args = [ ]
      ARGV.dup.each { |arg|
        if arg.start_with?("-")
          args.push(arg)
          ARGV.delete(arg)
        end
      }
      return args
    end

    def load_bindings
      @mouse_bindings = [ ]
      @key_bindings   = [ ]
      if File.exists?(INPUT_CONF)
        File.readlines(INPUT_CONF).each { |line|
          line = line.strip
          if line.start_with?("MOUSE_BTN")
            # 4 = up, 5 = down, 6 = left, 7 = right
            button, cmd = line.match(/MOUSE_BTN(\d+)(?:_DBL)?\s+(.+)$/).captures
            button = button.to_i + 1
            type   = (4..7).include?(button) ? Gdk::Event::SCROLL :
              line.include?("DBL") ? Gdk::Event::BUTTON2_PRESS : Gdk::Event::BUTTON_PRESS
            @mouse_bindings[type] = [ ] if @mouse_bindings[type].nil?
            @mouse_bindings[type][button] = cmd
          elsif not line.empty?
            key, cmd = line.match(/^([^\s]+)\s+(.+)$/).captures
            if name = KEY_NAMES[key.downcase]
              keyval = Gdk::Keyval.from_name(name)
            else
              keyval = Gdk::Keyval.from_name(key)
            end

            @key_bindings[keyval] = cmd if keyval > 0
          end
        }
      end
    end

    def load_file(file, add_to_playlist=true, do_not_play=false, auto_add=true, force_play=false)
      return if file.nil? or file.empty?
      file = File.expand_path(file) if file[0] == "~"

      if add_to_playlist
        if @playlist.count == 0 and auto_add and file !~ /^https?:\/\//
          dir     = File.directory?(file) ? file : File.dirname(file)
          entries = Dir.entries(dir).sort
          entries.delete_if { |x| x.start_with?(".") or not valid_video_file(x) }
          entries.map { |x|
            x = dir + "/" + x
            @playlist.add_file(x)
            file = x if file == dir
          }
        else
          @playlist.add_file(file)
        end
      end

      @mpv.load_file(file, force_play) unless do_not_play
    end

    def handle_mouse_event(e)
      button = e.event_type == Gdk::Event::SCROLL ? WHEEL_BUTTONS[e.direction] : e.button
      return if @mouse_bindings[e.event_type].nil?

      process_cmd(@mouse_bindings[e.event_type][button])

      return true
    end

    def handle_keyboard_event(e)
      process_cmd(@key_bindings[e.keyval])

      return true
    end

    def handle_seek_event(e)
      if e.event_type == Gdk::Event::BUTTON_PRESS and e.button == 1
        pos = e.x / allocation.width * @length.to_f
        seek("seek #{pos} absolute")
      end

      return true
    end

    def handle_drop_event(data, context, time, do_not_play, replace)
      files = URI.decode(data).gsub("file://", "").split("\r\n")
      @playlist.clear if replace

      files.each { |x|
        load_file(x, true, do_not_play) if valid_video_file(x)
      }

      Gtk::Drag.finish(context, true, true, time)
    end

    def process_cmd(cmd)
      case cmd
      when "cycle fullscreen"
        toggle_fullscreen
      when "cycle pause"
        @mpv.play_pause
      when "cycle playlist"
        @playlist.visible? ? @playlist.hide : @playlist.show
      when /seek /
        seek(cmd)
      when /add chapter/
        seek(cmd)
      when "playlist_next"
        load_file(@playlist.get_next, false)
      when "playlist_prev"
        load_file(@playlist.get_prev, false)
      when "open_file_chooser"
        open_file_chooser
      when "cycle progress_bar"
        toggle_progress_bar
      when "quit_watch_later"
        quit(true)
      when "quit"
        quit
      else
        @mpv.send(cmd) if cmd
      end
    end

    def seek(cmd)
      cmd = "no-osd " + cmd unless cmd.start_with?("no-osd") or
                               not @progress_bar.visible?
      @mpv.send(cmd)
      @mpv.send("get_property time-pos")
    end

    def toggle_fullscreen
      if window.state.fullscreen?
        @progress_bar.show unless @progress_bar_user_hidden
        unfullscreen
      else
        @progress_bar.hide unless @config["fullscreen_progressbar"]
        fullscreen
      end
    end

    def toggle_progress_bar
      if @progress_bar.visible?
        @progress_bar.hide
        @progress_bar_user_hidden = true
      else
        @progress_bar.show
        @progress_bar_user_hidden = false
      end
    end

    def valid_video_file(x)
      return (VIDEO_EXTS.include?(File.extname(x)) or
              `file -b --mime-type "#{x}"`.start_with?("video"))
    end


    def open_file_chooser
      dialog = Gtk::FileChooserDialog.new("Open File - #{PACKAGE}",
                                          self, Gtk::FileChooser::ACTION_OPEN, nil,
                                          [ Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL ],
                                          [ Gtk::Stock::OPEN,   Gtk::Dialog::RESPONSE_ACCEPT ])
      dialog.select_multiple = true
      do_not_play = @playlist.count > 0

      filter = Gtk::FileFilter.new
      filter.name = "Video Files"
      VIDEO_EXTS.each { |x| filter.add_pattern("*#{x}") }
      dialog.add_filter(filter)

      filterAll = Gtk::FileFilter.new
      filterAll.name = "All Files"
      filterAll.add_pattern("*.*")
      dialog.add_filter(filterAll)

      dialog.filenames.each { |x|
        load_file(x, true, do_not_play)
        do_not_play = true
      } if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
      dialog.destroy
    end

    def print_version
      puts("#{PACKAGE} - v#{VERSION}\n" +
           "ruby #{RUBY_VERSION}-p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE} revision #{RUBY_REVISION}) [#{RUBY_PLATFORM}]\n\n" +
          `#{MpvWidget::PATH} --version`)
      exit
    end

    def quit(watch_later=false)
      @config["x"],
      @config["y"],
      @config["width"],
      @config["height"]               = window.geometry unless window.state.fullscreen?
      @config["playlist_x"],
      @config["playlist_y"],
      @config["playlist_width"],
      @config["playlist_height"]      = @playlist.window.geometry
      @config["playlist_visible"]     = @playlist.visible?
      @config["playlist_selected"]    = @playing
      @config["playlist"]             = @playlist.get_entries.join("|")
      @config["progress_bar_visible"] = @progress_bar.visible?
      File.open(MAIN_CONF, "w") { |file| @config.each { |k, v| file.puts("#{k}=#{v}") } }

      @mpv.quit(@config["always_save_position"] ? true : watch_later)
      Gtk.main_quit
    end
  end
end

