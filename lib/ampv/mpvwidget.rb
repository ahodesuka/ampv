require "tmpdir"
begin
  require "mpv"
rescue LoadError
  dlg = Gtk::MessageDialog.new(nil,
                               Gtk::Dialog::DESTROY_WITH_PARENT,
                               Gtk::MessageDialog::ERROR,
                               Gtk::MessageDialog::BUTTONS_CLOSE,
                               "Unable to load ruby mpv bindings")
  dlg.set_secondary_text("Please ensure you have installed mpv and the mpv gem.")
  dlg.run
  dlg.destroy
  exit
end

module Ampv
  class MpvWidget < Gtk::EventBox

    attr_reader :handle
    attr_writer :quitting

    def initialize
      super

      @quitting = false
      @handle = Mpv::Handle.create
      begin
        @handle.load_config_file(Config::MPV_CONFIG) if File.file?(Config::MPV_CONFIG)
      rescue Mpv::OptionError
        puts("failed to parse config file")
      end
      @handle.set_option({ "cursor-autohide" => "no",
                           "input-cursor" => false })

      @widget = Gtk::DrawingArea.new
      @widget.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse("#000"))
      @widget.signal_connect("realize") {
        @handle.set_option({ "wid" => @widget.window.xid })
        @handle.wakeup_callback {
          while !@quitting and (e = @handle.wait_event(0)).type != Mpv::Event::NONE
            @handle.process_event(e)
          end
        }
        @handle.init
      }

      add(@widget)
    end

    def load_file(file)
      @handle.commandv("loadfile", file)
    end

    def quit(watch_later)
      @handle.command("quit" + (watch_later ? "_watch_later" : ""))
    end
  end
end
