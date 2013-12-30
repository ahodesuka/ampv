require "fifo"

module Ampv
  class MpvWidget < Gtk::EventBox

    type_register
    signal_new("file_changed", GLib::Signal::RUN_FIRST, nil, nil, String)
    signal_new("length_changed", GLib::Signal::RUN_FIRST, nil, nil, Integer)
    signal_new("time_pos_changed", GLib::Signal::RUN_FIRST, nil, nil, Float)
    signal_new("stopped", GLib::Signal::RUN_FIRST, nil, nil)

    PATH = "/usr/bin/mpv"

    attr_reader :is_paused

    def initialize(args, scrobbler)
      if args.include?("--debug")
        args.delete("--debug")
        @debug = true
      end

      @scrobbler   = scrobbler
      @mpv_path    = "/usr/bin/mpv"
      @mpv_options = args.join(" ")
      @mpv_fifo    = "/tmp/mpv.fifo." + Process.pid.to_s

      super()

      @socket = Gtk::Socket.new
      @socket.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse("#000"))

      @socket.signal_connect("plug_removed") { signal_emit("stopped"); true }
      add(@socket)
    end

    def start
      if @thread.nil?
        @fifo = Fifo.new(@mpv_fifo, :w, :nowait)

        cmd = "#{@mpv_path} \
          --identify \
          --idle \
          --input-file=#{@mpv_fifo} \
          --no-mouse-movements \
          --cursor-autohide=no \
          --msglevel=all=info \
          --wid=#{@socket.id} #{@mpv_options}"
        @thread = Thread.new { slave_reader(cmd) }
      end
    end

    def send(cmd)
      @fifo.puts(cmd) unless @fifo.nil?
    end

    def load_file(file, force_play=false)
      send("loadfile \"#{file}\"")
      @force_play = force_play
    end

    def play_pause
      send("cycle pause")
      @is_paused = @is_paused ? false : true
    end

    def quit(watch_later)
      send("quit" + (watch_later ? "_watch_later" : ""))
      @thread.join unless @thread.nil? or not @thread.alive?
      @fifo.close
      File.delete(@mpv_fifo)
    end

  private
    def slave_reader(cmd)
      @pipe = IO.popen(cmd, "a+")

      until @pipe.nil? or @pipe.closed? or @pipe.eof?
        line = @pipe.readline.chomp
        if line.include?("ID_FILENAME=")
          signal_emit("file_changed", (@playing = line.partition("ID_FILENAME=").last))
          send("get_property pause") # saved position also saves play state

          @prog_thread.kill unless @prog_thread.nil? or not @prog_thread.alive?
          @prog_thread = Thread.new { progress_update }
        elsif line.start_with?("ID_LENGTH=")
          signal_emit("length_changed", (@length = line.rpartition("=").last.to_i))
        elsif line.start_with?("ANS_pause=")
          @is_paused = line.rpartition("=").last == "yes"
          play_pause if @force_play and @is_paused
        elsif line.start_with?("ANS_time-pos=")
          signal_emit("time_pos_changed", line.rpartition("=").last.to_f)
        end

        if @debug or line.start_with?("Error")
          puts(line) unless line.start_with?("ANS_time-pos=") or
                            line.start_with?("ANS_ERROR") or
                            line.start_with?("Failed to get") or
                            line.start_with?("Command ")
        end
      end
    end

    def progress_update
      scrobbled = false
      watched = 0

      loop {
        send("get_property time-pos") unless @is_paused

        unless @scrobbler.nil? or scrobbled or watched < @length * 0.5
          system("#{@scrobbler} \"#{@playing}\"")
          scrobbled = true
        end

        sleep(1)
        watched += 1 unless @is_paused
      }
    end

    def signal_do_file_changed(file) end
    def signal_do_length_changed(len) end
    def signal_do_time_pos_changed(pos) end
    def signal_do_stopped()
      @prog_thread.kill
    end
  end
end

