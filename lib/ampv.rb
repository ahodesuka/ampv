require "gtk2"
require "json"
require "uri"
require "ampv/config"
require "ampv/mpvwidget"
require "ampv/playlist"
require "ampv/progressbarwidget"
require "ampv/version"

module Ampv
  class MainWindow < Gtk::Window

    INPUT_CONF    = "#{ENV["HOME"]}/.mpv/input.conf"
    VIDEO_EXTS    = [ ".avi", ".mkv", ".mp4", ".mpeg", ".mpg", ".ogm", ".ogv", ".rm", ".ts", ".wmv" ]
    WHEEL_BUTTONS = {
      Gdk::EventScroll::UP    => 4,
      Gdk::EventScroll::DOWN  => 5,
      Gdk::EventScroll::LEFT  => 6,
      Gdk::EventScroll::RIGHT => 7
    }

    LEFT_PTR     = Gdk::Cursor.new(Gdk::Cursor::LEFT_PTR)
    BLANK_CURSOR = Gdk::Cursor.new(Gdk::Cursor::BLANK_CURSOR)

    def initialize
      unless defined?(MpvWidget::PATH)
        dlg = Gtk::MessageDialog.new(nil,
                                     Gtk::Dialog::DESTROY_WITH_PARENT,
                                     Gtk::MessageDialog::ERROR,
                                     Gtk::MessageDialog::BUTTONS_CLOSE,
                                     "Unable to find mpv executable")
        dlg.set_secondary_text("Please ensure you have mpv installed in your PATH.")
        dlg.run
        dlg.destroy
        exit
      end

      args  = ARGV.reject { |x| x[0] != "-" }
      files = ARGV - args

      print_version if args.include?("--version")
      Config.load
      super

      set_title(PACKAGE)
      set_default_size(Config["width"], Config["height"])
      set_window_position(Gtk::Window::POS_CENTER)
      move(Config["x"], Config["y"]) unless Config["x"] == -1 and Config["y"] == -1

      add_events(Gdk::Event::POINTER_MOTION_MASK)
      Gtk::Drag.dest_set(self, Gtk::Drag::DEST_DEFAULT_ALL,
                         [ [ "text/uri-list", 0, 0 ] ],
                         Gdk::DragContext::ACTION_COPY)

      signal_connect("delete_event") { quit }
      signal_connect("scroll_event") { |w, e| handle_mouse_event(e) }
      signal_connect("button_press_event") { |w, e| handle_mouse_event(e) }
      signal_connect("key_press_event") { |w, e| handle_keyboard_event(e) }
      signal_connect("drag_data_received") { |w, dc, x, y, sd, type, time|
        handle_drop_event(sd.uris, false, true)
        Gtk::Drag.finish(dc, true, false, time)
      }
      signal_connect("motion_notify_event") { mouse_cursor_timeout }

      vbox          = Gtk::VBox.new
      @mpv          = MpvWidget.new(args)
      @progress_bar = ProgressBarWidget.new
      @playlist     = Playlist.new
      @ignore_stop  = false

      @mpv.signal_connect("file_changed") { |w, file|
        @playing = URI.decode(file).sub(/^file:\/\/[^\/]*/, "")
        # hacky work around when mpv catches drag and drop events.
        unless @playlist.include?(@playing)
          @playlist.clear(true)
          if (file = create_playlist(@playing)) != @playing and File.directory?(@playing)
            @playing = file
            GLib::Idle.add { @mpv.load_file(@playing); false }
            # mpv will fail to play the directory and then stop
            # ignore the next stop event so the playlist does not advance
            @ignore_stop = true
          end
        end
        @mpv.send("show_text ${media-title} 1500") if window.state.fullscreen? and !@ignore_stop
        @playlist.set_selected(@playing)
        set_title(File.basename(@playing))
      }
      @mpv.signal_connect("playing_watched") { @playlist.on_playing_watched }
      @mpv.signal_connect("length_changed") { |w, len| @playlist.update_length(@length = len) }
      @mpv.signal_connect("time_pos_changed") { |w, pos| @progress_bar.value = pos / @length.to_f }
      @mpv.signal_connect("stopped") {
        @progress_bar.value = 0
        set_title(PACKAGE)
        unless @ignore_stop
          next_file = @playlist.get_next
          @really_stop ||= next_file.nil?
          if !@really_stop
            load_file(next_file, false)
          elsif window.state.fullscreen?
            toggle_fullscreen
          end
        end
        @really_stop = @ignore_stop = false
      }

      @playlist.signal_connect("open_file_chooser") { open_file_chooser }
      @playlist.signal_connect("drag_data_received") { |w, dc, x, y, sd, type, time|
        handle_drop_event(sd.uris, true, false)
        Gtk::Drag.finish(dc, true, false, time)
      }
      @playlist.signal_connect("play_entry") { |w, file| load_file(file, false, false, false, true) }
      @playlist.signal_connect("playing_removed") { @mpv.stop; @really_stop = true }

      Gtk::Drag.dest_set(@playlist, Gtk::Drag::DEST_DEFAULT_ALL,
                         [ [ "text/uri-list", 0, 0 ] ],
                         Gdk::DragContext::ACTION_COPY)

      @progress_bar.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      @progress_bar.signal_connect("button_press_event") { |w, e| handle_seek_event(e) }

      vbox.pack_start(@mpv)
      vbox.pack_start(@progress_bar, false)
      add(vbox)
      show_all

      if !files.empty?
        if files.length > 1
          files.each_with_index { |x, i| load_file(x, true, i != 0, false) }
        else
          load_file(files[0])
        end
      elsif Config["playlist"].length > 0
        Config["playlist"].each { |x| @playlist.add_file(x["file"], x["length"], x["watched"]) }
        if Config["resume_playback"]
          @mpv.load_file(Config["playlist_selected"])
        else
          @playlist.set_selected(Config["playlist_selected"])
        end
      end

      Gtk.main
    end

  private
    def load_file(file, add_to_playlist = true, do_not_play = false, auto_add = true, force_play = false)
      file = File.expand_path(file) if file[0] == "~"
      return unless (File.directory?(file) or valid_video_file?(file))

      if add_to_playlist
        if @playlist.count == 0 and auto_add and file !~ /^https?:\/\//
          file = create_playlist(file)
        else
          @playlist.add_file(file)
        end
      end

      @mpv.load_file(file, force_play) unless do_not_play
    end

    def create_playlist(file)
      dir     = File.directory?(file) ? file : File.dirname(file)
      entries = Dir.entries(dir).sort.map { |x| "#{dir}/#{x}" }
      entries.delete_if { |x| x[0] == "." || !valid_video_file?(x) }
      entries.each { |x| @playlist.add_file(x) }
      file == dir ? entries[0] : file
    end

    def handle_mouse_event(e)
      mouse_cursor_timeout
      button = e.event_type == Gdk::Event::SCROLL ? WHEEL_BUTTONS[e.direction] : e.button
      return if Config["mouse_bindings"][e.event_type].nil?
      process_cmd(Config["mouse_bindings"][e.event_type][button])
    end

    def handle_keyboard_event(e)
      process_cmd(Config["key_bindings"][e.keyval])
    end

    def handle_seek_event(e)
      if e.event_type == Gdk::Event::BUTTON_PRESS and e.button == 1
        pos = e.x / allocation.width * @length.to_f
        seek("seek #{pos} absolute")
      end
    end

    def handle_drop_event(files, do_not_play, replace)
      @playlist.clear if replace
      files.each { |x| load_file(URI.decode(x).sub(/^file:\/\/[^\/]*/, ""), true, do_not_play) }
    end

    def mouse_cursor_timeout
      window.set_cursor(LEFT_PTR)
      GLib::Source.remove(@cursor_timeout) if @cursor_timeout
      @cursor_timeout = GLib::Timeout.add(1000) {
        window.set_cursor(BLANK_CURSOR)
      } unless @mpv.is_paused
    end

    def process_cmd(cmd)
      case cmd
      when "cycle fullscreen"
        toggle_fullscreen
      when "cycle pause"
        @mpv.play_pause
      when "stop"
        @mpv.stop
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
      true
    end

    def seek(cmd)
      cmd = "no-osd " + cmd unless cmd.start_with?("no-osd") or !@progress_bar.visible?
      @mpv.send(cmd)
      @mpv.send("get_property time-pos")
    end

    def toggle_fullscreen
      if window.state.fullscreen?
        @progress_bar.show unless @progress_bar_user_hidden
        unfullscreen
      else
        @progress_bar.hide unless Config["fullscreen_progressbar"]
        fullscreen
      end
      mouse_cursor_timeout
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

    def valid_video_file?(x)
      return (x and File.exists?(x) and !File.directory?(x) and VIDEO_EXTS.include?(File.extname(x).downcase))
    end


    def open_file_chooser
      dialog = Gtk::FileChooserDialog.new("Open File - #{PACKAGE}",
                                          self, Gtk::FileChooser::ACTION_OPEN, nil,
                                          [ Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL ],
                                          [ Gtk::Stock::OPEN,   Gtk::Dialog::RESPONSE_ACCEPT ])
      dialog.select_multiple = true

      filter = Gtk::FileFilter.new
      filter.name = "Video Files"
      VIDEO_EXTS.each { |x| filter.add_pattern("*#{x}") }
      dialog.add_filter(filter)

      filterAll = Gtk::FileFilter.new
      filterAll.name = "All Files"
      filterAll.add_pattern("*.*")
      dialog.add_filter(filterAll)

      dialog.filenames.each { |x|
        do_not_play = @playlist.count > 0
        load_file(x, true, do_not_play)
      } if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
      dialog.destroy
    end

    def print_version
      puts("#{PACKAGE} - v#{VERSION} (C) 2013-2014 ahoka\n" +
           `ruby --version` +
           `#{MpvWidget::PATH} --version`)
      exit
    end

    def quit(watch_later = false)
      Config["x"],
      Config["y"],
      Config["width"],
      Config["height"]               = window.geometry unless window.state.fullscreen?
      Config["playlist_x"],
      Config["playlist_y"],
      Config["playlist_width"],
      Config["playlist_height"]      = @playlist.window.geometry
      Config["playlist_visible"]     = @playlist.visible?
      Config["playlist_selected"]    = @playing
      Config["playlist"]             = @playlist.get_entries.to_json
      Config["resume_playback"]      = !@mpv.is_stopped && (watch_later || Config["always_save_position"])
      Config["progress_bar_visible"] = @progress_bar.visible?
      Config.save

      @mpv.quit(Config["always_save_position"] ? true : watch_later)
      Gtk.main_quit
    end
  end
end

