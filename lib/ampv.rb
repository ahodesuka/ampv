require "gtk2"
require "uri"
require "ampv/config"
require "ampv/input"
require "ampv/mpvwidget"
require "ampv/playlist"
require "ampv/progressbarwidget"
require "ampv/version"

module Ampv
  class MainWindow < Gtk::Window

    VIDEO_EXTS    = [ ".avi", ".mkv", ".mp4", ".mpeg", ".mpg", ".ogm", ".ogv", ".rm", ".ts", ".wmv" ]
    WHEEL_BUTTONS = {
      Gdk::EventScroll::UP    => 4,
      Gdk::EventScroll::DOWN  => 5,
      Gdk::EventScroll::LEFT  => 6,
      Gdk::EventScroll::RIGHT => 7
    }

    def initialize
      args  = ARGV.reject { |x| x[0] != "-" }
      files = ARGV - args

      print_version if args.include?("--version")
      Config.load
      super

      set_title(PACKAGE)
      set_default_size(Config[:width], Config[:height])
      set_window_position(Gtk::Window::POS_CENTER)
      move(Config[:x], Config[:y]) if Config[:x] and Config[:y]

      add_events(Gdk::Event::POINTER_MOTION_MASK)
      Gtk::Drag.dest_set(self, Gtk::Drag::DEST_DEFAULT_ALL,
                         [ [ "text/uri-list", 0, 0 ] ],
                         Gdk::DragContext::ACTION_COPY)

      signal_connect("delete_event") { @mpv.quit(Config[:always_save_position]) }
      signal_connect("scroll_event") { |w, e| handle_mouse_event(e) }
      signal_connect("button_press_event") { |w, e| handle_mouse_event(e) }
      signal_connect("key_press_event") { |w, e| handle_keyboard_event(e) }
      signal_connect("drag_data_received") { |w, dc, x, y, sd, type, time|
        files = sd.uris.map { |f| URI.decode(f).sub(/^file:\/\/[^\/]*/, "") }
        @playlist.clear(true) unless @playlist.get_files & files == files
        load_files(files)
        present
        Gtk::Drag.finish(dc, true, false, time)
      }
      signal_connect("motion_notify_event") { mouse_cursor_timeout }

      vbox          = Gtk::VBox.new
      @mpv          = MpvWidget.new
      @progress_bar = ProgressBarWidget.new
      @playlist     = Playlist.new

      @mpv.handle.register_event(Mpv::Event::FILE_LOADED) {
        @stopped = false
        @playing = @mpv.handle.get_property("path")
        @length  = @mpv.handle.get_property("length")
        title    = @mpv.handle.get_property("media-title")

        @mpv.handle.command("show_text ${media-title} 1500") if window.state.fullscreen?
        @playlist.set_selected(@playing)
        @playlist.update_title(title)
        set_title(title)
        @prog_thread.kill if @prog_thread

        if @length
          @playlist.update_length(@length)
          @prog_thread = Thread.new { progress_update }
        end

        if @force_play
          @mpv.handle.set_property("pause" => false)
          @force_play = false
        end
      }
      @mpv.handle.register_event(Mpv::Event::TICK) {
        val = @mpv.handle.get_property("time-pos")
        @progress_bar.value = val / @length if @length and val
      }
      @mpv.handle.register_event(Mpv::Event::END_FILE) { |e|
        @progress_bar.value = 0
        set_title(PACKAGE)
        @playlist.playing_stopped
        if e.reason == 0
          @stopped = true
          if next_file = @playlist.get_next
            @mpv.load_file(next_file)
          else
            toggle_fullscreen if window.state.fullscreen?
          end
        end
      }
      @mpv.handle.register_event(Mpv::Event::SHUTDOWN) { quit }

      if args.include?("--debug")
        @mpv.handle.request_log_messages("info")
        @mpv.handle.register_event(Mpv::Event::LOG_MESSAGE) { |e|
          print(e.text)
          $stdout.flush
        }
      end

      @playlist.signal_connect("open_file_chooser") { open_file_chooser }
      @playlist.signal_connect("drag_data_received") { |w, dc, x, y, sd, type, time|
        sd.uris.each { |f| @playlist.add_file(URI.decode(f).sub(/^file:\/\/[^\/]*/, "")) }
        present
        Gtk::Drag.finish(dc, true, false, time)
      }
      @playlist.signal_connect("play_entry") { |w, file| @mpv.load_file(file); @force_play = true }
      @playlist.signal_connect("playing_removed") {
        @mpv.handle.command("stop")
      }

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
        load_files(files)
      elsif Config[:playlist].length > 0
        Config[:playlist].each { |x| @playlist.add_file(x[:file], x[:length], x[:watched]) }
        if Config[:playlist_selected]
          if Config[:resume_playback]
           @mpv.load_file(Config[:playlist_selected])
          else
            @playlist.set_selected(Config[:playlist_selected])
          end
        end
      end

      mouse_cursor_timeout
      Gtk.main
    end

  private
    def load_file(file, auto_add = true, play = true)
      if file =~ /^#{URI::regexp}$/
        uri = true
      else
        file = File.expand_path(file)
      end

      return unless File.directory?(file) or File.file?(file) or uri

      if @playlist.count == 0 and auto_add and !uri
        file = create_playlist(file)
      elsif !@playlist.include?(file)
        @playlist.add_file(file)
      end

      @mpv.load_file(file) if play
    end

    def load_files(files)
      if files.length == 1
        load_file(files[0])
      else
        files.each_with_index { |x, i|
          load_file(x, false, i == 0)
        }
      end
    end

    def create_playlist(file)
      dir     = File.directory?(file) ? file : File.dirname(file)
      entries = Dir.entries(dir).sort.map { |x| "#{dir}/#{x}" }
      entries.delete_if { |x|
        if x == file or (File.file?(x) and VIDEO_EXTS.include?(File.extname(x).downcase))
          @playlist.add_file(x)
          false
        else
          true
        end
      }
      file == dir ? entries[0] : file
    end

    def progress_update
      watched = 0
      loop {
        if watched > @length * 0.5
          system("#{Config[:scrobbler]} \"#{@playing}\"") if Config[:scrobbler]
          @playlist.on_playing_watched
          break
        end
        sleep(1)
        watched += 1 unless @mpv.handle.get_property("pause")
      }
    end

    def handle_mouse_event(e)
      button = e.event_type == Gdk::Event::SCROLL ? WHEEL_BUTTONS[e.direction] : e.button
      return if InputBindings.mouse[e.event_type].nil?
      process_cmd(InputBindings.mouse[e.event_type][button])
      mouse_cursor_timeout(true)
    end

    def handle_keyboard_event(e)
      kb = InputBindings.key.find { |x| x.keyval == e.keyval and e.state & x.mods == x.mods }
      process_cmd(kb.cmd) if kb
    end

    def handle_seek_event(e)
      if e.event_type == Gdk::Event::BUTTON_PRESS and e.button == 1
        pos = e.x / allocation.width * @length.to_f
        seek("seek #{pos} absolute")
      end
    end

    def mouse_cursor_timeout(mevent = false)
      GLib::Source.remove(@cursor_timeout) if @cursor_timeout
      window.set_cursor(nil)
      @cursor_timeout = GLib::Timeout.add(1000) {
        window.set_cursor(Gdk::Cursor.new(Gdk::Cursor::BLANK_CURSOR))
        # hacky workaround when called after a mouse event
        # without this the cursor is still shown when it should not be.
        Gdk::Display.default.warp_pointer(*Gdk::Display.default.pointer[0..2]) if mevent
        false
      }
    end

    def process_cmd(cmd)
      case cmd
      when "cycle fullscreen"
        toggle_fullscreen
      when "cycle playlist"
        @playlist.visible? ? @playlist.hide : @playlist.show
      when /seek /
        seek(cmd)
      when /add chapter/
        seek(cmd)
      when "playlist_next"
        file = @playlist.get_next
        @mpv.load_file(file) if file
      when "playlist_prev"
        file = @playlist.get_prev
        @mpv.load_file(file) if file
      when "open_file_chooser"
        open_file_chooser
      when "cycle progress_bar"
        toggle_progress_bar
      when "quit_watch_later"
        @mpv.quit(@watch_later = true)
      when "quit"
        @mpv.quit
      else
        @mpv.handle.command(cmd) if cmd
      end
      true
    end

    def seek(cmd)
      cmd = "no-osd " + cmd if !cmd.start_with?("no-osd") and @progress_bar.visible?
      @mpv.handle.command(cmd)
    end

    def toggle_fullscreen
      if window.state.fullscreen?
        @progress_bar.show unless @progress_bar_user_hidden
        unfullscreen
      else
        @progress_bar.hide unless Config[:fullscreen_progressbar]
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

      load_files(dialog.filenames) if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
      dialog.destroy
    end

    def print_version
      puts("#{PACKAGE} - v#{VERSION} (C) 2013-2014 ahoka")
      exit
    end

    def quit
      @mpv.quitting = true
      @prog_thread.kill if @prog_thread
      Config[:x],
      Config[:y],
      Config[:width],
      Config[:height]               = window.geometry unless window.state.fullscreen?
      Config[:playlist_x],
      Config[:playlist_y],
      Config[:playlist_width],
      Config[:playlist_height]      = @playlist.window.geometry
      Config[:playlist_visible]     = @playlist.visible?
      Config[:playlist_selected]    = @playing
      Config[:playlist]             = @playlist.get_entries
      Config[:resume_playback]      = @playing && !@stopped && (@watch_later || Config[:always_save_position])
      Config[:progress_bar_visible] = @progress_bar.visible?
      Config.save
      Gtk.main_quit
    end
  end
end
