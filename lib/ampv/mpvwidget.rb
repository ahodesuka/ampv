require "tmpdir"

module Ampv
  class MpvWidget < Gtk::EventBox

    type_register
    signal_new("file_changed", GLib::Signal::RUN_FIRST, nil, nil, String)
    signal_new("length_changed", GLib::Signal::RUN_FIRST, nil, nil, Integer)
    signal_new("title_changed", GLib::Signal::RUN_FIRST, nil, nil, String)
    signal_new("playing_watched", GLib::Signal::RUN_FIRST, nil, nil)
    signal_new("time_pos_changed", GLib::Signal::RUN_FIRST, nil, nil, Float)
    signal_new("stopped", GLib::Signal::RUN_FIRST, nil, nil)

    ENV["PATH"].split(":").each { |x|
      if File.executable?("#{x}/mpv")
        PATH = "#{x}/mpv"
        break
      end
    }

    attr_reader :is_paused, :is_stopped

    def initialize(args)
      if args.include?("--debug")
        args.delete("--debug")
        @debug = true
      end

      @mpv_options = args.join(" ")
      @mpv_fifo    = "#{Dir.tmpdir}/mpv.fifo." + Process.pid.to_s
      @is_paused   = true

      super()

      @widget = Gtk::DrawingArea.new
      @widget.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse("#000"))
      @widget.signal_connect("realize") { start }

      add(@widget)
    end

    def send(cmd)
      @fifo.puts(cmd)
      @fifo.flush
    end

    def load_file(file, force_play = false)
      send("loadfile \"#{file}\"")
      @force_play = force_play
    end

    def play_pause
      send("cycle pause")
      @is_paused = !@is_paused
    end

    def stop
      send("stop")
      @is_stopped = @is_paused = true
    end

    def quit(watch_later)
      send("quit" + (watch_later ? "_watch_later" : ""))
      @prog_thread.kill if @prog_thread
      @thread.join
      @fifo.close
    end

  private
    def start
      return if @thread and @thread.alive?
      system("mkfifo \"#{@mpv_fifo}\"")
      @fifo = File.open(@mpv_fifo, "w+")
      ObjectSpace.define_finalizer(self, proc { File.delete(@mpv_fifo) })

      cmd = "#{PATH} \
        --idle \
        --input-file=#{@mpv_fifo} \
        --cursor-autohide=no \
        --no-mouse-movements \
        --msglevel=all=info \
        --wid=#{@widget.window.xid} #{@mpv_options}"

      @thread = Thread.start {
        IO.popen(cmd) { |io|
          io.each { |line|
            line.chomp!
            if line.start_with?("Playing: ")
              signal_emit("file_changed", (@playing = line.partition("Playing: ")[-1]))
              send("get_property media-title")
              send("get_property length")
              send("get_property time-pos")
              send("get_property pause")
              @is_stopped = false
            elsif line.start_with?("ANS_media-title=")
              signal_emit("title_changed", line.rpartition("=")[-1])
            elsif line.start_with?("ANS_length=")
              signal_emit("length_changed", (@length = line.rpartition("=")[-1].to_i))
            elsif line.start_with?("ANS_pause=")
              @is_paused = line.rpartition("=")[-1] == "yes"
              @prog_thread.kill if @prog_thread
              @prog_thread = Thread.new { progress_update }
              play_pause if @force_play and @is_paused
            elsif line.start_with?("ANS_time-pos=")
              signal_emit("time_pos_changed", line.rpartition("=")[-1].to_f)
            elsif line == "Creating non-video VO window."
              signal_emit("stopped")
              @is_stopped = true
            end

            puts(line) if @debug and !line.start_with?("ANS_")
          }
        }
      }
    end

    def progress_update
      scrobbled = false
      watched = 0
      loop {
        send("get_property time-pos")
        unless scrobbled or watched < @length * 0.5
          system("#{Config["scrobbler"]} \"#{@playing}\"") if Config["scrobbler"]
          signal_emit("playing_watched")
          scrobbled = true
        end
        sleep(1)
        watched += 1 unless @is_paused
      }
    end

    def signal_do_file_changed(file) end
    def signal_do_length_changed(len) end
    def signal_do_title_changed(title) end
    def signal_do_playing_watched; end
    def signal_do_time_pos_changed(pos) end
    def signal_do_stopped
      @prog_thread.kill if @prog_thread
    end
  end
end

